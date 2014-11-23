import ceylon.collection {
    LinkedList,
    HashMap,
    unmodifiableMap
}
import ceylon.io {
    Socket,
    SocketConnector,
    SocketAddress,
    newSocketConnector,
    newSslSocketConnector
}
import java.util.concurrent.locks {
    ReentrantLock
}

shared class UnsupportedSchemeException(scheme, cause = null)
        extends Exception("Scheme '``scheme``' is not supported.", cause) {
    shared String scheme;
    Throwable? cause;
}

Map<String,SocketConnector(SocketAddress)> createDefaultSchemeConnectors() {
    value map = HashMap<String,SocketConnector(SocketAddress)> {
        entries = [
            "http"->newSocketConnector,
            "https"->newSslSocketConnector
        ];
    };
    return unmodifiableMap(map);
}
shared Map<String,SocketConnector(SocketAddress)> defaultSchemeConnectors = createDefaultSchemeConnectors();

"Provides [[Socket]] pooling, keyed on scheme, host and port. When the number
 of pools is equal to [[maximumPools]] and a new pool must be created, an
 existing pool (the pool that was requested the longest time ago, LRU) will be
 closed."
shared class PoolManager(maximumPools = 5,
    maximumConnectionsPerPool = 5,
    softPools = true,
    connectors = defaultSchemeConnectors) {
    "The pool count where LRU will be applied before creating a new pool."
    shared Integer maximumPools;
    "Passed to the [[Pool]] instances, see [[Pool.maximumConnections]]."
    shared Integer maximumConnectionsPerPool;
    "Passed to the [[Pool]] instances, see [[Pool.soft]]."
    shared Boolean softPools;
    "Entries defining the supported schemes and which connection functions to
     call for them."
    shared Map<String,SocketConnector(SocketAddress)> connectors;
    
    ReentrantLock poolsLock = ReentrantLock();
    value pools = HashMap<[String, String, Integer],Pool>();
    
    "Return the [[Pool]] for the parameters, creating a new one if required."
    throws (`class UnsupportedSchemeException`, "When [[scheme]] is not one of
                                                 the schemes defined in
                                                 [[connectors]].")
    shared Pool poolFor(String scheme, String host, Integer port) {
        try {
            poolsLock.lock();
            value key = [scheme, host, port];
            Pool? pool = pools.get(key);
            if (exists pool) {
                // Use HashMap's linked ordering to keep track of LRU (as Least Recently Added)
                // A plain put won't update the linked ordering
                pools.remove(key);
                pools.put(key, pool);
                return pool;
            } else {
                if (pools.size >= maximumPools, exists first = pools.first) {
                    pools.remove(first.key);
                }
                value connectorCreator = connectors.get(scheme);
                if (exists connectorCreator) {
                    value socketAddress = SocketAddress(host, port);
                    value newPool = Pool {
                        connectorCreator;
                        socketAddress;
                        maximumConnectionsPerPool;
                        softPools;
                    };
                    pools.put(key, newPool);
                    return newPool;
                } else {
                    throw UnsupportedSchemeException(scheme);
                }
            }
        } finally {
            poolsLock.unlock();
        }
    }
    
    "Close all of the pools. Any active sockets within each pool will be closed
     as soon as their leases are returned, rather than immediately."
    shared void close() {
        try {
            poolsLock.lock();
            for (pool in pools.items) {
                pool.close();
            }
            pools.clear();
        } finally {
            poolsLock.unlock();
        }
    }
}

shared class PoolExhaustedException(cause = null)
        extends Exception("All sockets are leased", cause) {
    Throwable? cause;
}

"A pool of Sockets created using a constant [[SocketAddress]] and
 [[SocketConnector]].
 
 When used concurrently, the connection pool will grow to meet demand (see
 [[maximumConnections]]). When used sequentially, there will be at most one
 connection in the pool."
shared class Pool(connectorCreator, target, maximumConnections = 5, soft = true) {
    "Used to create a new [[Socket]] for [[target]] when one is required."
    shared SocketConnector(SocketAddress) connectorCreator;
    "Passed to [[connectorCreator]] when creating a [[Socket]]."
    shared SocketAddress target;
    "The upper bound on how many connections will be kept open persistently.
     The number of active connections at any one time may exceed this value if
     [[soft]] is true."
    shared Integer maximumConnections;
    "If true, create a temporary connection instead of throwing an exception
     when [[idleConnections]] is zero, [[leasedConnections]] equals
     [[maximumConnections]] and a connection lease is requested. This temporary
     connection will be discarded instead of being returned to the pool when
     the lease is returned."
    shared Boolean soft;
    
    SocketConnector connector = connectorCreator(target);
    
    ReentrantLock connnectionsLock = ReentrantLock();
    
    variable Boolean closed = false;
    LinkedList<Socket> leasedConnections = LinkedList<Socket>();
    LinkedList<Socket> idleConnections = LinkedList<Socket>();
    
    "Lease a [[Socket]] from the pool. You must call [[yield]] with the same
     socket when you are finished with it.
     
     If [[close]] was called previously, only temporary connections may be
     created, and only if [[soft]] is true."
    shared Socket borrow() {
        try {
            connnectionsLock.lock();
            if (exists top = idleConnections.pop()) {
                leasedConnections.push(top);
                return top;
            } else if (!closed && leasedConnections.size < maximumConnections) {
                // ^^ In this condition, idleConnections is known to be of zero
                // size because it has no top.
                Socket socket = connector.connect();
                leasedConnections.push(socket);
                return socket;
            } else if (soft) {
                return connector.connect();
            } else {
                throw PoolExhaustedException();
            }
        } finally {
            connnectionsLock.unlock();
        }
    }
    
    "Return a [[borrowed]] [[Socket]] to the pool.
     
     If [[close]] was called previously, or if the socket is temporary (see
     [[soft]]) the socket will be closed instead."
    shared void yield(Socket borrowed) {
        try {
            connnectionsLock.lock();
            if (closed) {
                leasedConnections.remove(borrowed);
                borrowed.close();
            } else {
                Boolean wasLeased = leasedConnections.removeFirst(borrowed);
                if (wasLeased) {
                    idleConnections.push(borrowed);
                } else {
                    borrowed.close();
                }
            }
        } finally {
            connnectionsLock.unlock();
        }
    }
    
    "Basically the only reliable way to detect if a TCP connection is dead is
     to attempt to use it. This method allows you to return a [[borrowed]]
     [[Socket]] if it doesn't work. A replacement [[Socket]] will be returned."
    shared Socket exchange(Socket borrowed) {
        try {
            connnectionsLock.lock();
            borrowed.close();
            leasedConnections.remove(borrowed);
            return borrow();
        } finally {
            connnectionsLock.unlock();
        }
    }
    
    "Close all sockets in the pool. Sockets with active leases will be closed
     when their lease is returned, other sockets will be closed immediately."
    shared void close() {
        try {
            connnectionsLock.lock();
            for (socket in idleConnections) {
                socket.close();
            }
            idleConnections.clear();
            closed = true;
        } finally {
            connnectionsLock.unlock();
        }
    }
}

import ceylon.collection {
    LinkedList,
    Stack,
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
                // TODO update LRU Socket
                return pool;
            } else {
                if (pools.size >= maximumPools) {
                    // TODO close+remove LRU Socket
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
            for (Pool pool in pools.items) {
                pool.close();
            }
            pools.clear();
        } finally {
            poolsLock.unlock();
        }
    }
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
     when [[activeConnections]] equals [[maximumConnections]] and a connection
     lease is requested. This temporary connection will be discarded instead of
     being returned to the pool when the lease is returned."
    shared Boolean soft;
    
    SocketConnector connector = connectorCreator(target);
    
    ReentrantLock connnectionsLock = ReentrantLock();
    
    Stack<Socket> activeConnections = LinkedList<Socket>(); // TODO required, or implicit in leases?
    Stack<Socket> idleConnections = LinkedList<Socket>();
    
    // TODO
    
    "Close all sockets in the pool. Sockets with active leases will be closed
     when their lease is returned, other sockets will be closed immediately."
    shared void close() {
        Socket x = nothing;
        // TODO
    }
}

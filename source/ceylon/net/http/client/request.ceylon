import ceylon.collection {
    unmodifiableMap,
    HashMap
}
import ceylon.io {
    FileDescriptor,
    Socket
}
import ceylon.net.http {
    Message,
    Method,
    getMethod=get,
    postMethod=post
}
import ceylon.net.uri {
    Uri,
    parse
}

void send(FileDescriptor reciever, Message outgoing) {
}

Message receive(FileDescriptor sender) {
    Message incoming = nothing;
    
    return incoming;
}

shared class UnknownSchemePortException(scheme, cause = null)
        extends Exception("The default port for '``scheme``' is not known.", cause) {
    shared String scheme;
    Throwable? cause;
}

shared class MissingHostException(uri, cause = null)
        extends Exception("The URI '``uri``' is missing a host.", cause) {
    shared Uri uri;
    Throwable? cause;
}

shared class MissingSchemeException(uri, cause = null)
        extends Exception("The URI '``uri``' is missing a scheme.", cause) {
    shared Uri uri;
    Throwable? cause;
}

Map<String,Integer> createDefaultSchemePorts() {
    value map = HashMap<String,Integer> {
        entries = ["http"->80, "https"->443];
    };
    return unmodifiableMap(map);
}
shared Map<String,Integer> defaultSchemePorts = createDefaultSchemePorts();

PoolManager defaultPoolManager = PoolManager();

throws (`class UnknownSchemePortException`, "When the [[uri]] doesn't specify a
                                             port value, and the [[uri]] scheme
                                             is not in [[defaultSchemePorts]]")
throws (`class MissingSchemeException`, "When the parsed [[uri]] lacks a scheme
                                         definition.")
throws (`class MissingHostException`, "When the parsed [[uri]] lacks a host
                                       definition.")
Message request(method, uri, poolManager = defaultPoolManager, schemePorts = defaultSchemePorts) {
    "HTTP method to use for the request."
    Method method;
    "URI to use. The scheme must be supported by [[poolManager]] and in
     [[defaultSchemePorts]] if [[uri]] doesn't specify a port value."
    Uri|String uri;
    "Used to get the [[Socket]] required for the request."
    PoolManager poolManager;
    "Default ports for schemes. Used when [[uri]] doesn't specify a port value."
    Map<String,Integer> schemePorts;
    
    Uri parsedUri;
    switch (uri)
    case (is Uri) {
        parsedUri = uri;
    }
    case (is String) {
        parsedUri = parse(uri);
    }
    
    if (exists String host = parsedUri.authority.host) {
        if (exists String scheme = parsedUri.scheme) {
            Integer port;
            if (exists p = parsedUri.authority.port) {
                port = p;
            } else if (exists p = schemePorts[scheme]) {
                port = p;
            } else {
                throw UnknownSchemePortException(scheme);
            }
            
            Pool pool = poolManager.poolFor(scheme, host, port);
            Socket socket = pool.borrow();
            
            value request = Message(nothing);
            send(socket, request);
            Message response = receive(socket);
            
            pool.yield(socket);
            // TODO how to handle a streaming response body? Would have to return the lease later after it is done being read.
            
            return response;
        } else {
            throw MissingSchemeException(parsedUri);
        }
    } else {
        throw MissingHostException(parsedUri);
    }
}

shared class Client(poolManager = defaultPoolManager, schemePorts = defaultSchemePorts) {
    "Used to get the [[Socket]]s required for the requests."
    PoolManager poolManager;
    "Default ports for schemes. Used when a request URI doesn't specify a port value."
    shared Map<String,Integer> schemePorts;
    
    shared Message post(uri) {
        Uri|String uri;
        return nothing;
    }
    
    // TODO move request into this class
}

Client defaultClient = Client();

Message post(Uri|String uri) => defaultClient.post(uri);

// TODO change return to Message subtype Response, offer followRedirect param, store any redirects in attribute of Response
Message get(uri) {
    Uri|String uri;
    return request(getMethod, uri);
}

{Message+} getFollowingRedirects(Uri|String uri) {
    //return request(getMethod, uri);
    return nothing; // TODO
}

import ceylon.collection {
    unmodifiableMap,
    HashMap
}
import ceylon.io {
    FileDescriptor,
    Socket
}
import ceylon.io.buffer {
    ByteBuffer
}
import ceylon.io.charset {
    Charset
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

import java.io {
    IOException
}

// TODO add superclass to group these exceptions

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

shared alias Headers => Map<String,String|{String*}?>;
shared alias Parameters => Map<String,String?>;
shared alias Body => Parameters|FileDescriptor|ByteBuffer(Charset?)|String(Charset)|ByteBuffer|String;
shared alias ChunkReceiver => Boolean(String)|Boolean(ByteBuffer, Charset?)|FileDescriptor;

"For sending HTTP messages to servers and receiving replies."
shared class Client(poolManager = PoolManager(), schemePorts = defaultSchemePorts) {
    "Used to get the [[Socket]]s required for the requests."
    PoolManager poolManager;
    "Default ports for schemes. Used when a request URI doesn't specify a port value."
    shared Map<String,Integer> schemePorts;
    
    "Clean up any persistent resources."
    shared void close() {
        poolManager.close();
    }
    
    "Make a request."
    throws (`class UnknownSchemePortException`, "When the [[uri]] doesn't specify a
                                                 port value, and the [[uri]] scheme
                                                 is not in [[defaultSchemePorts]]")
    throws (`class MissingSchemeException`, "When the parsed [[uri]] lacks a scheme
                                             definition.")
    throws (`class MissingHostException`, "When the parsed [[uri]] lacks a host
                                           definition.")
    shared Message request(method,
        uri,
        parameters = emptyMap,
        headers = emptyMap,
        body = null,
        bodyCharset = null,
        chunkReceiver = null,
        maxRedirects = 10) {
        "HTTP method to use for the request."
        Method method;
        "URI to use. The scheme must be supported by [[poolManager]], and in
         [[defaultSchemePorts]] if [[uri]] doesn't specify a port value."
        Uri|String uri;
        "Parameters to include with the request. They will be appended to the
         [[uri]]'s query parameters."
        Parameters parameters;
        "Headers to include with the request. They will be encoded with
         [[ceylon.io.charset::utf8]], which degrades to ASCII. Note that some
         servers may only accept ASCII header characters, so be cautious when
         including unicode characters.
         
         Header names are case insensitive (`Host` == `host`), and headers with
         duplicate names will be merged into a single header with a comma
         seperated value. For more information about duplicately named headers
         see [RFC 7230 §3.2.2]
         (https://tools.ietf.org/rfcmarkup?doc=7230#section-3.2.2).
         
         These default headers will be provided if you do not specify them:
         - `Host` = the host part of the [[uri]]
         - `Accept` = `*/*`
         - `Accept-Charset` = `UTF-8`
         - `User-Agent` = `Ceylon/1.2`
         
         For the `Content-Type` header:
         - if [[body]] is [[null]], the header will not be provided.
         - if the header is specified and a type name is present in its value,
         it will be preserved.
         - if the header is unspecified or if a type name is missing, it will
         be determined from the [[body]] type.
         `application/x-www-form-urlencoded` for [[Parameters]], `text/plain`
         for [[String]], and `application/octet-stream` for [[ByteBuffer]] or
         [[FileDescriptor]].
         - if a charset parameter is present in the header value, it will be
         preserved.
         - if the header is unspecified or if a charset parameter is missing,
         and the body must be encoded, it will be set to `UTF-8`.
         
         The charset parameter of the `Content-Type` header will be parsed
         and used to encode the message body if required. Its value must be one
         of the supported [[ceylon.io.charset::charsets]].
         
         The `Content-Length` and `Transfer-Encoding` headers should not be set
         by the user, and will be overriden as required to create a compliant
         HTTP message."
        Headers headers;
        "Data to include in the request body. Usually this is [[null]] for
         [safe](https://tools.ietf.org/html/rfc7231#page-22) methods (GET,
         HEAD, etc.), but it does not have to be.
         
         Non-binary values will be encoded with the charset parameter of the
         `Content-Type` header, or the value of [[bodyCharset]], if it exists.
         
         [[FileDescriptor]]s will be read in manageable pieces and sent using
         chunked transfer encoding. Similarly, each returned piece from a body
         function will be sent as chunks, until [[null]] is returned."
        Body? body;
        "The charset of the [[body]]. This will overwrite any charset parameter of
         the `Content-Type` header in [[headers]]."
        Charset|String? bodyCharset;
        "If this exists, the body chunks of the response from the server will be
         sent to [[chunkReceiver]] instead of being buffered and returned with
         the [[Response]].
         
         Using this is strongly recommended if you expect the server will
         return a large response to the request."
        ChunkReceiver? chunkReceiver;
        "If the response status code is in the [300 series]
         (https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#3xx_Redirection)
         then the redirect(s) will be followed up to the depth specified here.
         To disable redirect following, set this to 0."
        Integer maxRedirects;
        // TODO argument ideas: lazy (relating to response body reading), authentication, timeouts
        // TODO Sockets have to be modified to add timeout support: https://technfun.wordpress.com/2009/01/29/networking-in-java-non-blocking-nio-blocking-nio-and-io/
        
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
                [ByteBuffer, Anything(FileDescriptor)] message = buildMessage {
                    method;
                    host;
                    parsedUri.pathPart;
                    parsedUri.queryPart;
                    parameters;
                    headers;
                    body;
                    bodyCharset;
                };
                try {
                    variable Exception? error = null;
                    // The maximum number of potentially stale connections.
                    // Attempt n+1 times, so we should get a fresh connection
                    // at the end. Throw if it still fails.
                    for (i in 0..pool.idleConnectionsSize+1) {
                        try {
                            // Write the prefix first as it's easy to reset it if writing fails
                            socket.writeFully(message[0]);
                            break;
                        } catch (IOException e) {
                            message[0].position = 0;
                            pool.exchange(socket);
                            if (exists x = error) {
                                e.addSuppressed(x);
                            }
                            error = e;
                        }
                    } else {
                        throw error else Exception("Unable to send message.");
                    }
                    // Write the body after we're fairly sure the socket is ok
                    message[1](socket);
                    
                    Message response = receive(socket, chunkReceiver);
                    
                    // TODO process redirects if flag is true.
                    // TODO Probably won't be able to resend any body, which is ok for 303 (force GET) but maybe throw exception for non-303 redirect with non-resendable body?
                    // TODO change return to Message subtype Response, store any redirects in [Response*] attribute of Response
                    
                    // TODO how to handle a streaming response body? Would have to return the lease later after it is done being read.
                    // TODO ^^^^ have parameter with a chunk callback or a stream to write the chunks into?
                    
                    return response;
                } finally {
                    pool.yield(socket);
                }
            } else {
                throw MissingSchemeException(parsedUri);
            }
        } else {
            throw MissingHostException(parsedUri);
        }
    }
    
    shared Message get(uri,
        parameters = emptyMap,
        headers = emptyMap,
        body = null,
        bodyCharset = null,
        chunkReceiver = null,
        maxRedirects = 10) {
        Uri|String uri;
        Parameters parameters;
        Headers headers;
        Body? body;
        Charset|String? bodyCharset;
        ChunkReceiver? chunkReceiver;
        Integer maxRedirects;
        return request(getMethod, uri, parameters, headers, body, bodyCharset, chunkReceiver, maxRedirects);
    }
    
    shared Message post(uri,
        parameters = emptyMap,
        headers = emptyMap,
        body = null,
        bodyCharset = null,
        chunkReceiver = null,
        maxRedirects = 10) {
        Uri|String uri;
        Parameters parameters;
        Headers headers;
        Body? body;
        Charset|String? bodyCharset;
        ChunkReceiver? chunkReceiver;
        Integer maxRedirects;
        return request(postMethod, uri, parameters, headers, body, bodyCharset, chunkReceiver, maxRedirects);
    }
    
    // TODO ...
}

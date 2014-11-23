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
    Charset,
    utf8
}
import ceylon.net.http {
    Message,
    Method,
    getMethod=get,
    postMethod=post,
    Header
}
import ceylon.net.uri {
    Uri,
    parse,
    Parameter
}

shared String terminator = "\r\n";

shared void externaliseParameters(StringBuilder builder, {Parameter*} parameters) {
    variable Boolean addPrefix = false;
    for (parameter in parameters) {
        if (addPrefix) {
            builder.append("&");
        }
        addPrefix = true;
        builder.append(parameter.toRepresentation(false));
    }
}

shared void send(reciever,
    method,
    uri,
    parameters = empty,
    headers = empty,
    data = null) {
    FileDescriptor reciever;
    Method method;
    "URI to apply. Only the host, path and query portions will be used."
    Uri uri;
    {Parameter*} parameters;
    {Header*} headers;
    FileDescriptor|ByteBuffer|String? data;
    
    // message prefix
    value builder = StringBuilder();
    
    // method
    builder.append(method.string)
        .append(" ");
    
    // path
    String path = uri.pathPart;
    if (path.empty) {
        builder.append("/");
    } else {
        builder.append(path);
    }
    Boolean queryParamsAdded;
    if (exists query = uri.queryPart) {
        builder.append("?")
            .append(query);
        queryParamsAdded = true;
    } else {
        queryParamsAdded = false;
    }
    if (!parameters.empty && method == get) {
        if (!queryParamsAdded) {
            builder.append("?");
        } else {
            builder.append("&");
        }
        externaliseParameters(builder, parameters);
    }
    
    // version
    builder.append(" ")
        .append("HTTP/1.1")
        .append(terminator);
    
    // add content type header
    //if (exists contentTypeValue, !getHeader("Content-Type") exists) {
    //    headers.add(contentType(contentTypeValue, bodyCharset));
    //}
    // add length header
    //if (bodySize != 0 && !getHeader("Content-Length") exists) {
    //    headers.add(contentLength(bodySize.string));
    //}
    Integer? bodySize;
    if (is FileDescriptor data) {
        bodySize = null;
    } else if (is ByteBuffer data) {
        bodySize = data.available;
    } else if (is String data) {
        bodySize = data.size;
    } else {
        bodySize = 0;
    }
    
    // headers
    Charset bodyCharset = nothing;
    // TODO defaults
    // TODO make sure Content-Type is handled as documented, extract/default the charset from the value
    // TODO drop Content-Length if FileDescriptor data, otherwise include with bodySize if exists
    // TODO the "values" for header looks like it needs to be rewritten, there's only one value, and only one header with a case-insensitive name (?)
    for (header in headers) {
        for (val in header.values) {
            builder.append(header.name)
                .append(": ")
                .append(val)
                .append(terminator);
        }
    }
    builder.append(terminator);
    
    // Write the header early so that any socket issues are thrown before we touch the body.
    reciever.writeFully(utf8.encode(builder.string));
    
    if (!parameters.empty && method == post) {
        value paramBuilder = StringBuilder();
        externaliseParameters(paramBuilder, parameters);
        reciever.writeFully(bodyCharset.encode(paramBuilder.string));
    } else if (is String s = data) {
        reciever.writeFully(bodyCharset.encode(s));
    } else if (is ByteBuffer b = data) {
        reciever.writeFully(b);
    } else if (is FileDescriptor f = data) {
        // Transfer-Encoding: chunked header should already be set
        f.readFully(void(ByteBuffer buffer) {
                Integer length = buffer.available;
                // Can't be zero length, as that is specified as the terminating chunk
                if (length > 0) {
                    String lengthHex = formatInteger(length, 16);
                    reciever.writeFully(utf8.encode(lengthHex + terminator));
                    reciever.writeFully(buffer);
                    reciever.writeFully(utf8.encode(terminator));
                }
            });
        // Terminating zero-length chunk
        reciever.writeFully(utf8.encode("0" + terminator + terminator));
    }
    // else null: write nothing
}

shared Message receive(FileDescriptor sender) {
    Message incoming = nothing;
    
    return incoming;
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
        parameters = empty,
        headers = empty,
        data = null,
        maxRedirects = 10) {
        "HTTP method to use for the request."
        Method method;
        "URI to use. The scheme must be supported by [[poolManager]] and in
         [[defaultSchemePorts]] if [[uri]] doesn't specify a port value."
        Uri|String uri;
        "Parameters to include with the request. If [[method]] is get, then
         they will be appended to the [[uri]]'s query parameters. If [[method]]
         is post, then they will be used as the request body, see [[data]]."
        {Parameter*} parameters;
        "Headers to include with the request. They will be encoded with
         [[utf8]], which degrades to ASCII. Note that some servers may only
         accept ASCII header characters, so be cautious when including unicode
         characters. Header keys are case insensitive (`Host` == `host`).
         
         These default headers will be provided if you do not specify a value
         for them:
         - `Host` = the host part of the [[uri]]
         - `Accept` = `*/*`
         - `Accept-Charset` = `UTF-8`
         - `User-Agent` = `Ceylon/1.2`
         
         The `Content-Type` header may be set/manipulated in certain scenarios:
         - if [[parameters]] is not [[empty]], and [[method]] is post, the type
         name will be set to `application/x-www-form-urlencoded`.
         - if the header is not present, and [[data]] is a [[ByteBuffer]] or
         [[FileDescriptor]], the type name will be set to
         `application/octet-stream`.
         - if the header is not present, and [[data]] is a [[String]], the type
         name will be set to `text/plain`.
         - if the header is present, and the type name isn't
         `application/octet-stream`, and the header's value parameter `charset`
         is not set, it will be set to `UTF-8`.
         
         The `charset` parameter of the `Content-Type` header will be parsed
         and used to encode the message body (only if there is one, see
         [[data]]). Its value must be one of the supported
         [[ceylon.io.charset::charsets]]."
        {Header*} headers;
        "Data to include in the request body. Usually this is [[null]] for
         idempotent methods (GET, HEAD, etc.), but it does not have to be.
         
         If [[parameters]] is not empty, and [[method]] is post, then the
         parameters will be used instead of this value. [[String]] values will
         be encoded with the charset parameter of the `Content-Type` header,
         see [[headers]].
         
         [[FileDescriptor]]s will be read in manageable pieces and sent using
         chunked transfer encoding."
        FileDescriptor|ByteBuffer|String? data;
        "If the response status code is in the [300 series]
         (https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#3xx_Redirection)
         then the redirect(s) will be followed up to the depth specified here.
         To disable redirect following, set this to 0."
        Integer maxRedirects;
        // TODO argument ideas: lazy (relating to response body reading), authentication, timeouts
        
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
                
                // TODO try/catch for write issues? Proably only way to reliably detect if the socket is still open?
                // TODO ^^^^ would have to add something to the Pool class to expire a socket and get a new lease?
                send(socket, method, parsedUri, parameters, headers, data);
                Message response = receive(socket);
                
                // TODO process redirects if flag is true
                // TODO change return to Message subtype Response, store any redirects in [Response*] attribute of Response
                
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
    
    shared Message get(uri,
        parameters = empty,
        headers = empty,
        data = null,
        maxRedirects = 10) {
        Uri|String uri;
        {Parameter*} parameters;
        {Header*} headers;
        FileDescriptor|ByteBuffer|String? data;
        Integer maxRedirects;
        return request(getMethod, uri, parameters, headers, data, maxRedirects);
    }
    
    shared Message post(uri,
        parameters = empty,
        headers = empty,
        data = null,
        maxRedirects = 10) {
        Uri|String uri;
        {Parameter*} parameters;
        {Header*} headers;
        FileDescriptor|ByteBuffer|String? data;
        Integer maxRedirects;
        return request(postMethod, uri, parameters, headers, data, maxRedirects);
    }
    
    // TODO ...
}

Client defaultClient = Client();

// TODO update param lists
shared Message(Uri|String, {Parameter*}, {Header*}, FileDescriptor|ByteBuffer|String?, Integer) get = defaultClient.get;
shared Message post(Uri|String uri) => defaultClient.post(uri);
// TODO ...

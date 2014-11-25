import ceylon.collection {
    unmodifiableMap,
    HashMap,
    LinkedList
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
    Header,
    contentTypeFormUrlEncoded
}
import ceylon.net.uri {
    Uri,
    parse,
    Parameter
}
import java.io {
    IOException
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
    host,
    path,
    query,
    parameters = empty,
    headers = empty,
    data = null) {
    FileDescriptor reciever;
    Method method;
    String host;
    String path;
    String? query;
    {Parameter*} parameters;
    {Header*} headers;
    FileDescriptor|ByteBuffer|String? data;
    
    // message prefix
    value builder = StringBuilder();
    
    // method
    builder.append(method.string)
        .append(" ");
    
    // path
    if (path.empty) {
        builder.append("/");
    } else {
        builder.append(path);
    }
    Boolean queryParamsAdded;
    if (exists q = query) {
        builder.append("?")
            .append(q);
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
    
    String? postParameters;
    if (!parameters.empty && method == postMethod) {
        value paramBuilder = StringBuilder();
        externaliseParameters(paramBuilder, parameters);
        postParameters = paramBuilder.string;
    } else {
        postParameters = null;
    }
    
    // headers
    // Header semantics are a bit odd, so it seems cleanest to do late processing on them like this
    value processedHeaders = HashMap<String,LinkedList<String>>();
    for (header in headers) {
        // Combine headers with same name based on comma seperated value interpretation:
        // http://tools.ietf.org/rfcmarkup?doc=7230#section-3.2.2
        if (exists values = processedHeaders.get(header.name.lowercased)) {
            values.addAll(header.values);
        } else {
            processedHeaders.put(header.name.lowercased, LinkedList<String>(header.values));
        }
    }
    for (defaultName->defaultValue in { "host"->host,
        "accept"->"*/*",
        "accept-charset"->"UTF-8",
        "user-agent"->"Ceylon/1.2" }) {
        if (!processedHeaders.defines(defaultName)) {
            processedHeaders.put(defaultName, LinkedList<String> { defaultValue });
        }
    }
    // TODO make sure Content-Type is handled as documented, extract/default the charset from the value
    Charset bodyCharset = nothing;
    String contentTypeName;
    String contentTypeCharset;
    //The `Content-Type` header may be set/manipulated in certain scenarios:
    //        - if [[parameters]] is not [[empty]], and [[method]] is post, the type
    //name will be set to `application/x-www-form-urlencoded`.
    //        - if the header is not present, and [[data]] is a [[ByteBuffer]] or
    //[[FileDescriptor]], the type name will be set to
    //`application/octet-stream`.
    //        - if the header is not present, and [[data]] is a [[String]], the type
    //name will be set to `text/plain`.
    //        - if the header is present, and the type name isn't
    //         `application/octet-stream`, and the header's value parameter `charset`
    //is not set, it will be set to `UTF-8`.
    if (exists postParameters) {
        contentTypeName = contentTypeFormUrlEncoded;
        // TODO charset from header param if available, default utf-8
    } else if (exists values = processedHeaders.get("content-type"), exists val = values.last) {
        // Content-Type := type "/" subtype *[";" parameter]
        String[] params = [for (p in val.split((ch) => ch == ';')) p];
        if (nonempty params) {
            contentTypeName = params.first;
            for (param in params.spanFrom(1)) {
                String paramName = nothing;
                String paramVal = nothing;
                if (nothing) {
                    contentTypeCharset = paramVal;
                    break;
                }
            } else {
                contentTypeCharset = "UTF-8";
            }
        } else {
            if (data is FileDescriptor || data is ByteBuffer) {
                contentTypeName = "application/octet-stream";
            } else if (data is String) {
                contentTypeName = "text/plain";
            } else {
                // TODO null, no data, therefore do not include content-type header
            }
        }
    }
    
    String contentTypeValue = "``contentTypeName``;charset=``contentTypeCharset``";
    processedHeaders.put("content-type", LinkedList<String> { contentTypeValue });
    
    FileDescriptor|ByteBuffer? body;
    Integer? bodySize;
    if (exists postParameters) {
        value buffer = bodyCharset.encode(postParameters);
        bodySize = buffer.available;
        body = buffer;
    } else if (is FileDescriptor data) {
        body = data;
        bodySize = null;
    } else if (is ByteBuffer data) {
        body = data;
        bodySize = data.available;
    } else if (is String data) {
        value buffer = bodyCharset.encode(data);
        bodySize = buffer.available;
        body = buffer;
    } else {
        body = null;
        bodySize = 0;
    }
    
    if (exists bodySize) {
        processedHeaders.put("content-length", LinkedList<String> { bodySize.string });
    } else {
        processedHeaders.remove("content-length");
        processedHeaders.put("transfer-encoding", LinkedList<String> { "chunked" });
    }
    
    for (headerName->headerValues in processedHeaders) {
        builder.append(headerName);
        if (headerValues.empty) {
            builder.append(";");
        } else {
            builder.append(": ");
            variable Boolean addPrefix = false;
            for (val in headerValues) {
                if (addPrefix) {
                    builder.append(",");
                }
                addPrefix = true;
                builder.append(val);
            }
        }
        builder.append(terminator);
    }
    builder.append(terminator);
    
    // TODO return builder string before attempting write, so it can be easily retried without losing stream data?
    // Write the header early so that any socket issues are thrown before we touch the body.
    reciever.writeFully(utf8.encode(builder.string));
    
    if (is FileDescriptor body) {
        // Transfer-Encoding: chunked header should already be set
        body.readFully(void(ByteBuffer buffer) {
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
    } else if (is ByteBuffer body) {
        reciever.writeFully(body);
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
                try {
                    variable Exception? error = null;
                    // The maximum number of potentially stale connections is
                    // the connection pool size. Attempt n+1 times, so we
                    // should get a fresh connection at the end. Throw if it
                    // still fails.
                    for (i in 0..pool.maximumConnections) {
                        try {
                            send(socket, method, host, parsedUri.pathPart, parsedUri.queryPart, parameters, headers, data);
                            break;
                        } catch (IOException e) { // TODO is there a more specific exception?
                            pool.exchange(socket);
                            error = e;
                        }
                    } else {
                        throw error else Exception("Unable to send message.");
                    }
                    
                    // TODO probably need a timeout on the receive, attempt retransmission with exchanged socket?
                    // TODO ^^^ on retransmit, will need to handle fd/buffer reset. Is that possible?
                    // TODO it may not be desirable to retransmit on a timeout (two generals' problem), as request may not be indempotent, even for usually indempotent methods. Just remove the socket and throw timeoutexception
                    Message response = receive(socket);
                    
                    // TODO process redirects if flag is true
                    // TODO change return to Message subtype Response, store any redirects in [Response*] attribute of Response
                    
                    // TODO how to handle a streaming response body? Would have to return the lease later after it is done being read.
                    // TODO yield in a finally block
                    
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

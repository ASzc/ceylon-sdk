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
    utf8,
    getCharset
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

shared void writeBody(receiver, body) {
    FileDescriptor receiver;
    FileDescriptor|ByteBuffer? body;
    
    if (is FileDescriptor body) {
        // Transfer-Encoding: chunked header should already be set
        body.readFully(void(ByteBuffer buffer) {
                Integer length = buffer.available;
                // Can't be zero length, as that is specified as the terminating chunk
                if (length > 0) {
                    String lengthHex = formatInteger(length, 16);
                    receiver.writeFully(utf8.encode(lengthHex + terminator));
                    receiver.writeFully(buffer);
                    receiver.writeFully(utf8.encode(terminator));
                }
            });
        // Terminating zero-length chunk
        receiver.writeFully(utf8.encode("0" + terminator + terminator));
    } else if (is ByteBuffer body) {
        receiver.writeFully(body);
    }
    // else null: write nothing
}

shared [ByteBuffer, FileDescriptor|ByteBuffer?] buildMessage(
    method,
    host,
    path,
    query,
    parameters = empty,
    headers = empty,
    data = null) {
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
    
    // https://tools.ietf.org/html/rfc7231#section-3.1.1.5
    String? defaultTypeName;
    String? defaultTypeCharset;
    if (postParameters exists) {
        defaultTypeName = "application/x-www-form-urlencoded";
        defaultTypeCharset = "UTF-8";
    } else if (data is FileDescriptor) {
        defaultTypeName = "application/octet-stream";
        defaultTypeCharset = null;
    } else if (data is ByteBuffer) {
        defaultTypeName = "application/octet-stream";
        defaultTypeCharset = null;
    } else if (data is String) {
        defaultTypeName = "text/plain";
        defaultTypeCharset = "UTF-8";
    } else {
        defaultTypeName = null;
        defaultTypeCharset = null;
    }
    Charset? bodyCharset;
    if (exists defaultTypeName) {
        String contentTypeName;
        String? contentTypeCharset;
        
        if (exists values = processedHeaders.get("content-type"),
            exists val = values.last,
            nonempty typeNameAndParams = [for (p in val.split((ch) => ch == ';')) p]) {
            contentTypeName = typeNameAndParams.first;
            String[] params = typeNameAndParams.spanFrom(1);
            if (exists charsetParam = params.findLast((elem) => elem.trimmed.startsWith("charset=")),
                exists charsetParamValue = charsetParam.split((ch) => ch == '=').getFromFirst(1)) {
                contentTypeCharset = charsetParamValue.trimmed;
            } else {
                contentTypeCharset = defaultTypeCharset;
            }
        } else {
            contentTypeName = defaultTypeName;
            contentTypeCharset = defaultTypeCharset;
        }
        
        String contentTypeValue;
        if (exists contentTypeCharset) {
            contentTypeValue = "``contentTypeName``; charset=``contentTypeCharset``";
            bodyCharset = getCharset(contentTypeCharset);
        } else {
            contentTypeValue = contentTypeName;
            bodyCharset = null;
        }
        processedHeaders.put("content-type", LinkedList<String> { contentTypeValue });
    } else {
        bodyCharset = null;
    }
    
    FileDescriptor|ByteBuffer? body;
    Integer? bodySize;
    if (exists postParameters) {
        assert (exists bodyCharset);
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
        assert (exists bodyCharset);
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
    
    return [utf8.encode(builder.string), body];
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
         
         For the `Content-Type` header:
         - if [[data]] is the body, and it is null, the header will not be set.
         - if a type name is present in the header value, it will be preserved.
         - if a type name is missing, it will be determined from the body (see
         [[data]]). If [[parameters]] is the body, the type name will be set to
         `application/x-www-form-urlencoded`. If [[data]] is the body,
         [[String]] defaults to `text/plain`, [[ByteBuffer]] or
         [[FileDescriptor]] defaults to `application/octet-stream`.
         - if a charset parameter is present in the header value, it will be
         preserved.
         - if a charset parameter is missing, and the body must be encoded
         (see [[data]]), the charset parameter will be defaulted to `UTF-8`.
         
         The charset parameter of the `Content-Type` header will be parsed
         and used to encode the message body if required. Its value must be one
         of the supported [[ceylon.io.charset::charsets]].
         
         The `Content-Length` and `Transfer-Encoding` headers should not be set
         by the user, and will be overriden as required to create a compliant
         HTTP message."
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
                [ByteBuffer, FileDescriptor|ByteBuffer?] message = buildMessage {
                    method;
                    host;
                    parsedUri.pathPart;
                    parsedUri.queryPart;
                    parameters;
                    headers;
                    data;
                };
                try {
                    variable Exception? error = null;
                    // The maximum number of potentially stale connections is
                    // the connection pool size. Attempt n+1 times, so we
                    // should get a fresh connection at the end. Throw if it
                    // still fails.
                    for (i in 0..pool.maximumConnections) {
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
                    writeBody(socket, message[1]);
                    
                    Message response = receive(socket);
                    
                    // TODO process redirects if flag is true
                    // TODO change return to Message subtype Response, store any redirects in [Response*] attribute of Response
                    
                    // TODO how to handle a streaming response body? Would have to return the lease later after it is done being read.
                    
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

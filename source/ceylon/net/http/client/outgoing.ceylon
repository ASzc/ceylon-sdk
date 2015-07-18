import ceylon.collection {
    LinkedList,
    HashMap
}
import ceylon.io {
    FileDescriptor
}
import ceylon.io.buffer {
    ByteBuffer
}
import ceylon.io.charset {
    utf8,
    getCharset,
    Charset
}
import ceylon.net.http {
    Method,
    Header,
    postMethod=post,
    capitaliseHeaderName
}
import ceylon.net.uri {
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
    parameters = emptyMap,
    headers = emptyMap,
    data = null) {
    Method method;
    String host;
    String path;
    String? query;
    Parameters parameters;
    Headers headers;
    Body data;
    
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
        if (!headerValues.empty) {
            builder.append(capitaliseHeaderName(headerName));
            builder.append(": ");
            variable Boolean addPrefix = false;
            for (val in headerValues) {
                if (addPrefix) {
                    builder.append(",");
                }
                addPrefix = true;
                builder.append(val);
            }
            builder.append(terminator);
        }
    }
    builder.append(terminator);
    
    return [utf8.encode(builder.string), body];
}

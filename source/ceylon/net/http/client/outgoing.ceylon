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
    capitaliseHeaderName
}
import ceylon.net.uri {
    percentEncoder
}

shared String terminator = "\r\n";

shared void externaliseParameters(StringBuilder builder, Parameters parameters) {
    variable Boolean addPrefix = false;
    for (name->val in parameters) {
        if (addPrefix) {
            builder.append("&");
        }
        addPrefix = true;
        
        builder.append(percentEncoder.encodePathSegmentParamName(name));
        builder.append("=")
            .append(percentEncoder.encodePathSegmentParamValue(val));
    }
}

void writeChunk(Anything(ByteBuffer) output, ByteBuffer chunk) {
    // Transfer-Encoding: chunked header should already be set
    Integer length = chunk.available;
    // Can't be zero length, as that is specified as the termination chunk
    if (length > 0) {
        String lengthHex = formatInteger(length, 16);
        output(utf8.encode(lengthHex + terminator));
        output(chunk);
        output(utf8.encode(terminator));
    }
}

void writeTerminationChunk(Anything(ByteBuffer) output) {
    output(utf8.encode("0" + terminator + terminator));
}

shared void noopBodyWriter(FileDescriptor|Anything(ByteBuffer) output) {
}

shared void binaryBodyWriter(FileDescriptor|ByteBuffer body)(FileDescriptor|Anything(ByteBuffer) output) {
    Anything(ByteBuffer) outputFunc;
    if (is FileDescriptor output) {
        outputFunc = output.writeFully;
    } else {
        outputFunc = output;
    }
    
    if (is FileDescriptor body) {
        body.readFully(void(ByteBuffer chunk) {
                writeChunk(outputFunc, chunk);
            });
        writeTerminationChunk(outputFunc);
    } else {
        outputFunc(body);
    }
}

shared void callbackBodyWriter(ByteBuffer(Charset?) body, Charset? charset)(FileDescriptor|Anything(ByteBuffer) output) {
    Anything(ByteBuffer) outputFunc;
    if (is FileDescriptor output) {
        outputFunc = output.writeFully;
    } else {
        outputFunc = output;
    }
    
    variable ByteBuffer chunk = body(charset);
    while (chunk.available > 0) {
        writeChunk(outputFunc, chunk);
        chunk = body(charset);
    }
    writeTerminationChunk(outputFunc);
}

shared void encodingCallbackBodyWriter(String(Charset) body, Charset charset)(FileDescriptor|Anything(ByteBuffer) output) {
    Anything(ByteBuffer) outputFunc;
    if (is FileDescriptor output) {
        outputFunc = output.writeFully;
    } else {
        outputFunc = output;
    }
    
    variable String chunkText = body(charset);
    while (!chunkText.empty) {
        ByteBuffer chunk = charset.encode(chunkText);
        writeChunk(outputFunc, chunk);
        chunkText = body(charset);
    }
    writeTerminationChunk(outputFunc);
}

shared [ByteBuffer, Anything(FileDescriptor|Anything(ByteBuffer))] buildMessage(
    method,
    host,
    path,
    query,
    parameters = emptyMap,
    headers = emptyMap,
    body = null,
    bodyCharset = null) {
    Method method;
    String host;
    String path;
    String? query;
    Parameters parameters;
    Headers headers;
    Body? body;
    Charset|String? bodyCharset;
    
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
    if (!parameters.empty) {
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
    
    // Process Headers
    // Header semantics are a bit odd, so it seems cleanest to do late processing on them like this
    value processedHeaders = HashMap<String,LinkedList<String>>();
    for (rawName->val in headers) {
        String name = capitaliseHeaderName(rawName);
        
        // Combine headers with same name based on comma seperated value interpretation:
        // http://tools.ietf.org/rfcmarkup?doc=7230#section-3.2.2
        if (exists values = processedHeaders.get(name)) {
            switch (val)
            case (is {String*}) {
                values.addAll(val);
            }
            case (is String) {
                values.addAll { val };
            }
        } else {
            switch (val)
            case (is {String*}) {
                processedHeaders.put(name, LinkedList<String>(val));
            }
            case (is String) {
                processedHeaders.put(name, LinkedList<String> { val });
            }
        }
    }
    // Add default Headers
    for (defaultName->defaultValue in { "Host"->host,
        "Accept"->"*/*",
        "Accept-Charset"->"UTF-8",
        "User-Agent"->"Ceylon/1.2" }) {
        if (!processedHeaders.defines(defaultName)) {
            processedHeaders.put(defaultName, LinkedList<String> { defaultValue });
        }
    }
    
    // Charset handling
    Charset? parsedBodyCharset;
    switch (bodyCharset)
    case (is Charset) {
        parsedBodyCharset = bodyCharset;
    }
    case (is String) {
        parsedBodyCharset = getCharset(bodyCharset);
    }
    case (null) {
        parsedBodyCharset = null;
    }
    
    // Read Content-Type, resolve type and charset
    String contentTypeName;
    Charset? contentTypeCharset;
    if (exists values = processedHeaders.get("Content-Type"),
        exists val = values.last) {
        // Store Content-Type type name
        {String+} typeNameAndParams = val.split((ch) => ch == ';');
        contentTypeName = typeNameAndParams.first;
        
        // Read any available parameters of Content-Type
        {String*} params = typeNameAndParams.rest;
        if (exists charsetParam = params.findLast((elem) => elem.trimmed.startsWith("charset=")),
            exists charsetParamValue = charsetParam.split((ch) => ch == '=').getFromFirst(1)) {
            contentTypeCharset = getCharset(charsetParamValue.trimmed) else utf8;
        } else {
            if (body is Parameters) {
                contentTypeCharset = parsedBodyCharset else utf8;
            } else if (body is String(Charset?)) {
                contentTypeCharset = parsedBodyCharset else utf8;
            } else if (body is String) {
                contentTypeCharset = parsedBodyCharset else utf8;
            } else {
                contentTypeCharset = parsedBodyCharset;
            }
        }
    } else {
        if (body is Parameters) {
            contentTypeName = "application/x-www-form-urlencoded";
            contentTypeCharset = parsedBodyCharset else utf8;
        } else if (body is String(Charset?)) {
            contentTypeName = "text/plain";
            contentTypeCharset = parsedBodyCharset else utf8;
        } else if (body is String) {
            contentTypeName = "text/plain";
            contentTypeCharset = parsedBodyCharset else utf8;
        } else {
            contentTypeName = "application/octet-stream";
            contentTypeCharset = parsedBodyCharset;
        }
    }
    
    // (Over)write Content-Type if there is a body
    if (!body is Null) {
        String contentTypeValue;
        if (exists contentTypeCharset) {
            contentTypeValue = "``contentTypeName``; charset=``contentTypeCharset.name``";
        } else {
            contentTypeValue = contentTypeName;
        }
        processedHeaders.put("Content-Type", LinkedList<String> { contentTypeValue });
    }
    
    // Prepare body writer
    // Need to do this now, since body length may be needed for the headers
    Anything(FileDescriptor|Anything(ByteBuffer)) bodyWriter;
    Integer? bodySize;
    
    if (is Parameters body) {
        assert (exists contentTypeCharset);
        
        StringBuilder paramBuilder = StringBuilder();
        externaliseParameters(paramBuilder, body);
        // Encode now, since we need to specify byte length
        ByteBuffer buffer = contentTypeCharset.encode(paramBuilder.string);
        
        bodyWriter = binaryBodyWriter(buffer);
        bodySize = buffer.available;
    } else if (is String body) {
        assert (exists contentTypeCharset);
        
        // Encode now, since we need to specify byte length
        ByteBuffer buffer = contentTypeCharset.encode(body);
        
        bodyWriter = binaryBodyWriter(buffer);
        bodySize = buffer.available;
    } else if (is String(Charset) body) {
        assert (exists contentTypeCharset);
        
        // Strings will be encoded for each chunk
        bodyWriter = encodingCallbackBodyWriter(body, contentTypeCharset);
        bodySize = null;
    } else if (is ByteBuffer body) {
        bodyWriter = binaryBodyWriter(body);
        bodySize = body.available;
    } else if (is ByteBuffer(Charset?) body) {
        bodyWriter = callbackBodyWriter(body, contentTypeCharset);
        bodySize = null;
    } else if (is FileDescriptor body) {
        bodyWriter = binaryBodyWriter(body);
        bodySize = null;
    } else {
        bodyWriter = noopBodyWriter;
        bodySize = 0;
    }
    
    if (exists bodySize) {
        processedHeaders.put("Content-Length", LinkedList<String> { bodySize.string });
        processedHeaders.remove("Transfer-Encoding");
    } else {
        processedHeaders.remove("Content-Length");
        processedHeaders.put("Transfer-Encoding", LinkedList<String> { "chunked" });
    }
    
    // Write headers
    for (headerName->headerValues in processedHeaders) {
        // It's up to the user to ensure RFC 7230 is respected regarding repeated header names
        // https://tools.ietf.org/rfcmarkup?doc=7230#section-3.2.2
        for (val in headerValues) {
            builder.append(headerName);
            builder.append(": ");
            builder.append(val);
            builder.append(terminator);
        }
    }
    builder.append(terminator);
    
    ByteBuffer messagePreamble = utf8.encode(builder.string);
    
    return [messagePreamble, bodyWriter];
}

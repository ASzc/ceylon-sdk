import ceylon.collection {
    LinkedList,
    MutableList
}
import ceylon.io.charset {
    Charset
}

shared String capitaliseHeaderName(String headerName) {
    value builder = StringBuilder();
    variable Boolean addPrefix = false;
    for (part in headerName.split((a) => a == '-')) {
        if (addPrefix) {
            builder.append("-");
        }
        addPrefix = true;
        if (exists first = part.first) {
            builder.appendCharacter(first.uppercased);
            String remainder = part.spanFrom(1).lowercased;
            builder.append(remainder);
        }
    }
    return builder.string;
}

// TODO make name always conform to capitaliseHeaderName?
// TODO convert to immutable
"Represents an HTTP Header"
by("Stéphane Épardaud")
shared class Header(name, String* initialValues) {
    
    "Header name"
    shared String name;
    
    "Header value"
    shared MutableList<String> values = LinkedList<String>();
    
    for(val in initialValues) {
        values.add(val);
    }
}

shared Header contentType(String contentType, Charset? charset = null) {
    String headerValue;
    if (exists charset) {
        headerValue = "``contentType``; charset=``charset.name``";
    } else {
        headerValue = contentType;
    }
    return Header("Content-Type", headerValue);
}

shared Header contentLength(String contentLength) 
        => Header("Content-Length", contentLength);

Header allowHeaders({Method*} methods) {
    StringBuilder sb = StringBuilder();
    for (i -> method in methods.indexed) {
        if (i > 0) {
            sb.append(", ");
        }
        sb.append(method.string);
    }
    return Header("Allow", sb.string);
}
shared Header allow({Method*} methods = empty) 
        => allowHeaders(methods);

shared String contentTypeFormUrlEncoded 
        = "application/x-www-form-urlencoded";

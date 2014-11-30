import ceylon.collection {
    HashMap,
    HashSet,
    LinkedList
}
import ceylon.io {
    FileDescriptor
}
import ceylon.io.buffer {
    newByteBuffer
}
import ceylon.io.charset {
    utf8
}
import ceylon.io.readers {
    FileDescriptorReader
}
import ceylon.net.http {
    Message
}

shared class ParseException(String? description = null, Throwable? cause = null)
        extends Exception(description, cause) {
}

String formatCharSet(Set<Integer> set) {
    value builder = StringBuilder();
    builder.append("{");
    variable Boolean addPrefix = false;
    for (element in set) {
        if (addPrefix) {
            builder.append(", ");
        }
        builder.append("#");
        builder.append(formatInteger(element, 16));
    }
    builder.append("}");
    return builder.string;
}

String formatActual(Integer? actual) {
    if (exists actual) {
        return "#``formatInteger(actual, 16)``";
    } else {
        return "EOF";
    }
}

shared class OutOfSequenceCharacter(actual, expected, expectedIn, cause = null)
        extends ParseException("Got ``formatActual(actual)`` when expecting #``formatInteger(expected, 16)`` in ``expectedIn``.", cause) {
    shared Integer? actual;
    shared Integer expected;
    shared String expectedIn;
    Throwable? cause;
}

shared class UnexpectedCharacter(actual, expectedIn, cause = null)
        extends ParseException("Got ``formatActual(actual)`` when expecting one of ``formatCharSet(expectedIn)``.", cause) {
    shared Integer? actual;
    shared Set<Integer> expectedIn;
    Throwable? cause;
}

// ABNF character sets https://tools.ietf.org/rfcmarkup?doc=5234#appendix-B.1
Set<Integer> ctl = HashSet<Integer> { elements = (#00..#1F).chain({ #7F }); };
Set<Integer> digit = HashSet<Integer> { elements = #30..#39; };
Set<Integer> hexDigit = HashSet<Integer> { elements = (#30..#39).chain(#61..#66).chain(#41..#46); };

alias Expected => String|Set<Integer>;

by ("Alex Szczuczko", "Stéphane Épardaud")
shared Response receive(FileDescriptor sender) {
    value reader = FileDescriptorReader(sender);
    
    "Message must be parsed with ASCII for security reasons, as per [RFC 7230]
     (https://tools.ietf.org/rfcmarkup?doc=7230#section-3). However, UTF-8
     decoding is ok when not using it for element deliniation."
    value decoder = utf8.Decoder();
    
    Integer status;
    String reason;
    Integer major;
    Integer minor;
    // TODO construct Header list from map afterwards
    value headers = HashMap<String,LinkedList<String>>();
    
    variable Integer byte = 0; // TODO required?
    value buffer = newByteBuffer(1024);
    
    void expect(Expected expected) {
        switch (expected)
        case (is String) {
            for (char in expected) {
                Integer charInt = char.integer;
                Integer read;
                if (exists b = reader.readByte()) {
                    read = b.signed;
                } else {
                    throw OutOfSequenceCharacter(null, charInt, expected);
                }
                if (read != charInt) {
                    throw OutOfSequenceCharacter(read, charInt, expected);
                }
            }
        }
        case (is Set<Integer>) {
            Integer read;
            if (exists b = reader.readByte()) {
                read = b.signed;
            } else {
                throw UnexpectedCharacter(null, expected);
            }
            if (!read in expected) {
                throw UnexpectedCharacter(read, expected);
            }
        }
    }
    
    
    //reader.readByte();
    
    // TODO status line
    // TODO HTTP version
    expect("HTTP/");
    //major = parseDigit();
    //readChar('.');
    //minor = parseDigit();
    
    // TODO status
    // TODO reason
    
    // TODO headers
    
    Response incoming = nothing;
    return incoming;
}

// TODO handle lazy yielding of the socket
shared class Response() extends Message(nothing) {
    shared Integer code = nothing;
    // TODO include redirect [Response*] history here
}

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

String formatCharSet(Set<Byte> set) {
    value builder = StringBuilder();
    builder.append("{");
    variable Boolean addPrefix = false;
    for (element in set) {
        if (addPrefix) {
            builder.append(", ");
        }
        builder.append("#");
        builder.append(formatInteger(element.signed, 16));
    }
    builder.append("}");
    return builder.string;
}

String formatActual(Byte? actual) {
    if (exists actual) {
        return "#``formatInteger(actual.signed, 16)``";
    } else {
        return "EOF";
    }
}

shared class OutOfSequenceCharacter(actual, expected, expectedIn, cause = null)
        extends ParseException("Got ``formatActual(actual)`` when expecting #``formatInteger(expected.signed, 16)`` in ``expectedIn``.", cause) {
    shared Byte? actual;
    shared Byte expected;
    shared {Byte*} expectedIn;
    Throwable? cause;
}

shared class UnexpectedCharacter(actual, expectedIn, cause = null)
        extends ParseException("Got ``formatActual(actual)`` when expecting one of ``formatCharSet(expectedIn)``.", cause) {
    shared Byte? actual;
    shared Set<Byte> expectedIn;
    Throwable? cause;
}

// ABNF character sets https://tools.ietf.org/rfcmarkup?doc=5234#appendix-B.1
// Controls
Set<Byte> ctl = HashSet<Byte> { for (c in (#00..#1F).chain({ #7F })) c.byte };
// 0 - 9
Set<Byte> digit = HashSet<Byte> { for (c in (#30..#39)) c.byte };
// 0 - 9 | a-f | A-F
Set<Byte> hexDigit = HashSet<Byte> { for (c in (#30..#39).chain(#61..#66).chain(#41..#46)) c.byte };

// HTTP keywords
Byte[] statusHttp = [for (c in "HTTP/") c.integer.byte];
Byte versionPoint = '.'.integer.byte;
Byte space = ' '.integer.byte;
Byte cr = '\r'.integer.byte;
Byte lr = '\n'.integer.byte;

by ("Alex Szczuczko", "Stéphane Épardaud")
shared Response receive(FileDescriptor sender) {
    value reader = FileDescriptorReader(sender);
    
    "Message must be parsed with ASCII for security reasons, as per [RFC 7230]
     (https://tools.ietf.org/rfcmarkup?doc=7230#section-3). However, UTF-8
     decoding is ok when not using it for element deliniation."
    value decoder = utf8.Decoder();
    
    void expectBytes({Byte*} expected) {
        for (char in expected) {
            if (exists b = reader.readByte()) {
                if (b != char) {
                    throw OutOfSequenceCharacter(b, char, expected);
                }
            } else {
                throw OutOfSequenceCharacter(null, char, expected);
            }
        }
    }
    
    Byte expectByteIn(Set<Byte> expected) {
        if (exists b = reader.readByte()) {
            if (!b in expected) {
                throw UnexpectedCharacter(b, expected);
            }
            return b;
        } else {
            throw UnexpectedCharacter(null, expected);
        }
    }
    
    Integer expectDigit() {
        return expectByteIn(digit).signed - #30; // '0'
    }
    
    value buffer = newByteBuffer(1024);
    void pushToBuffer(Byte byte) {
        // grow the buffer if required
        if (!buffer.hasAvailable) {
            buffer.resize(buffer.capacity + 1024, true);
        }
        // save the byte
        buffer.putByte(byte);
    }
    String readString(Byte terminatedBy) {
        Byte read() {
            if (exists b = reader.readByte()) {
                return b;
            } else {
                throw ParseException("Premature EOF while reading string");
            }
        }
        buffer.clear();
        variable Byte byte = read();
        while (byte != terminatedBy) {
            pushToBuffer(byte);
            byte = read();
        }
        buffer.flip();
        decoder.decode(buffer);
        return decoder.consume();
    }
    
    // Status line, ex: HTTP/1.1 200 OK\r\n
    // HTTP version, ex: HTTP/1.1
    expectBytes(statusHttp);
    Integer major = expectDigit();
    expectBytes { versionPoint };
    Integer minor = expectDigit();
    expectBytes { space };
    // Status code, ex: 200
    Integer status = expectDigit() * 100 + expectDigit() * 10 + expectDigit();
    expectBytes { space };
    // Reason phrase, ex: OK
    String reason = readString(cr);
    // \r already read by readString(), read the \n still present
    expectBytes { lr };
    
    // TODO headers
    
    // TODO construct Header list from map afterwards
    value headers = HashMap<String,LinkedList<String>>();
    
    Response incoming = nothing;
    return incoming;
}

// TODO handle lazy yielding of the socket
shared class Response() extends Message(nothing) {
    shared Integer code = nothing;
    // TODO include redirect [Response*] history here
}

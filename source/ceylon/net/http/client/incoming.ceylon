import ceylon.collection {
    HashMap,
    HashSet,
    LinkedList,
    unmodifiableMap
}
import ceylon.io {
    FileDescriptor
}
import ceylon.io.buffer {
    newByteBuffer,
    ByteBuffer
}
import ceylon.io.charset {
    utf8
}
import ceylon.io.readers {
    FileDescriptorReader,
    Reader
}
import ceylon.net.http {
    Message,
    Header,
    capitaliseHeaderName
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
Byte lf = '\n'.integer.byte;
Byte headerSep = ':'.integer.byte;

// ((0 * 10 + 3) * 10 + 2) * 10 + 1 = 321
Integer base10accumulator(Integer partial, Byte element) {
    // #30 == '0'
    return 10 * partial + (element.signed - #30);
}

Integer base16accumulator(Integer partial, Byte element) {
    return nothing; // TODO
}

by ("Alex Szczuczko", "Stéphane Épardaud")
shared Response receive(FileDescriptor sender) {
    value reader = FileDescriptorReader(sender);
    
    //
    // "Expect", either wholly known values, or known length
    //
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
    Integer expectNumerical(expected, length, accumulator) {
        Set<Byte> expected;
        Integer length;
        Integer(Integer, Byte) accumulator;
        
        return { for (i in 0:length) expectByteIn(expected) }.fold(0)(accumulator);
    }
    
    //
    // "Read", unknown length values
    //
    "Message must be parsed with ASCII for security reasons, as per [RFC 7230]
     (https://tools.ietf.org/rfcmarkup?doc=7230#section-3). However, UTF-8
     decoding is ok when not using it for element deliniation."
    value decoder = utf8.Decoder();
    value buffer = newByteBuffer(1024);
    void pushToBuffer(Byte byte) {
        // grow the buffer if required
        if (!buffer.hasAvailable) {
            buffer.resize(buffer.capacity + 1024, true);
        }
        // save the byte
        buffer.putByte(byte);
    }
    Byte read() {
        if (exists b = reader.readByte()) {
            return b;
        } else {
            throw ParseException("Premature EOF while reading sequence");
        }
    }
    [String, Byte] readString({Byte*} terminatedBy) {
        buffer.clear();
        variable Byte byte = read();
        while (!byte in terminatedBy) {
            pushToBuffer(byte);
            byte = read();
        }
        buffer.flip();
        decoder.decode(buffer);
        return [decoder.consume(), byte];
    }
    Integer readNumerical(terminatedBy, expected, accumulator) {
        Byte terminatedBy;
        Set<Byte> expected;
        Integer(Integer, Byte) accumulator;
        
        buffer.clear();
        variable Byte byte = read();
        while (!byte == terminatedBy) {
            pushToBuffer(byte);
            byte = read();
        }
        buffer.flip();
        return buffer.fold(0)(accumulator);
    }
    
    // Status line, ex: HTTP/1.1 200 OK\r\n
    // HTTP version, ex: HTTP/1.1
    expectBytes(statusHttp);
    Integer major = expectNumerical(digit, 1, base10accumulator);
    expectBytes { versionPoint };
    Integer minor = expectNumerical(digit, 1, base10accumulator);
    expectBytes { space };
    // Status code, ex: 200
    // Integer status = expectDigit() * 100 + expectDigit() * 10 + expectDigit();
    Integer status = expectNumerical(digit, 3, base10accumulator);
    expectBytes { space };
    // Reason phrase, ex: OK
    String reason = readString { cr }[0];
    // \r already read by readString(), read the \n still present
    expectBytes { lf };
    
    // Headers, ex: Content-Type: text/html; charset=UTF-8\r\n
    value headerMap = HashMap<String,LinkedList<String>>();
    while (true) {
        value nameOrTerm = readString { headerSep, cr };
        // Header Field Name, ex: Content-Type
        String name = nameOrTerm[0].trimmed.lowercased;
        // If termChar is cr, then we expect name to be blank, ex: \r\n\r\n
        Byte termChar = nameOrTerm[1];
        // End of headers?
        if (termChar == cr) {
            if (name.empty) {
                // \r already read by readString(), read the \n still present
                expectBytes { lf };
                break;
            } else {
                // TODO throw exception, unexpected value between terminators
            }
        } else {
            if (name.empty) {
                // TODO throw exception, blank header name
            }
        }
        // Header Field Value, ex: text/html; charset=UTF-8
        // Comma seperated, as per RFC
        {String*} newValues = readString { cr }[0].split((ch) => ch == ',').map((element) => element.trimmed);
        // Combine headers with same name based on comma seperated value interpretation:
        // http://tools.ietf.org/rfcmarkup?doc=7230#section-3.2.2
        if (exists values = headerMap.get(name)) {
            values.addAll(newValues);
        } else {
            headerMap.put(name, LinkedList<String>(newValues));
        }
    }
    
    // TODO call capitaliseHeaderName
    value headers = unmodifiableMap(headerMap);
    
    value body = BodyReader {
        sender;
        nothing;
        nothing;
        nothing;
        readNumerical;
        expectBytes;
    };
    
    Response incoming = nothing;
    return incoming;
}

shared class BodyReader(sender, yield, lazy, size, readNumerical, expectBytes) extends Reader() {
    FileDescriptor sender;
    "Function to call when done reading the body"
    Anything(FileDescriptor) yield;
    "If true, wait to read the body until [[read]] is called."
    shared Boolean lazy;
    "Null implies chunked transfer"
    shared Integer? size;
    Integer(Byte, Set<Byte>, Integer(Integer, Byte)) readNumerical;
    Anything({Byte*}) expectBytes;
    
    ByteBuffer eagerRead() {
        ByteBuffer body;
        if (exists size) {
            // TODO Socket timeout is required to recover from size being greater than the actual body size.
            ByteBuffer b = newByteBuffer(size);
            Integer bytesRead = sender.read(b);
            if (size != bytesRead) {
                // TODO throw exception, body size didn't match (smaller?)
            }
            body = b;
        } else {
            ByteBuffer b = newByteBuffer(0);
            while (true) {
                Integer chunkLength = readNumerical(cr, hexDigit, base16accumulator);
                expectBytes({ lf });
                if (chunkLength == 0) {
                    expectBytes({ cr, lf });
                    break;
                }
                b.resize(b.capacity + chunkLength, true);
                Integer bytesRead = sender.read(b);
                if (chunkLength != bytesRead) {
                    // TODO throw exception, chunk size didn't match (smaller?)
                }
            }
            body = b;
        }
        yield(sender);
        body.flip();
        return body;
    }
    
    ByteBuffer? body;
    if (lazy) {
        body = null;
    } else {
        body = eagerRead();
    }
    
    ByteBuffer? readChunk() {
        return nothing;
    }
    
    variable ByteBuffer? latestChunk = null;
    Integer lazyRead(ByteBuffer buffer) {
        if (exists size) {
            Integer available = buffer.available;
            Integer amountRead = sender.read(buffer);
            if (amountRead < available) {
                yield(sender);
            }
            return amountRead;
        } else {
            // TODO chunked transfer encoding
            // TODO transfer up to requestedAmount
            while (buffer.available > 0) {
                if (exists lc = latestChunk) {
                    Integer requestedBytes = buffer.available;
                    Integer leftoverBytes = lc.available;
                    
                    Integer transferAmount = min { leftoverBytes, requestedBytes };
                    for (i in 0:transferAmount) {
                        buffer.put(lc.get());
                    }
                    
                    if (leftoverBytes <= requestedBytes) {
                        latestChunk = null;
                    }
                }
                
                if (!latestChunk exists) {
                    ByteBuffer? newChunk = readChunk();
                    if (exists newChunk) {
                        latestChunk = newChunk;
                    } else {
                        // TODO need to return -1 if nothing read
                        break;
                    }
                }
            }
            
            // TODO when done reading, yield sender
            return nothing;
        }
    }
    
    shared actual Integer read(ByteBuffer buffer) {
        if (exists body) {
            // TODO 
            return nothing;
        } else {
            return lazyRead(buffer);
        }
    }
}

shared class Response() extends Message(nothing) {
    shared Integer code = nothing;
    // TODO include redirect [Response*] history here
}

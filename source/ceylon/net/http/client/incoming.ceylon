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
    utf8,
    Charset,
    getCharset
}
import ceylon.io.readers {
    FileDescriptorReader,
    Reader
}
import ceylon.net.http {
    Message,
    capitaliseHeaderName,
    Method,
    getMethod=get
}
import ceylon.net.uri {
    Uri,
    parse,
    InvalidUriException
}
import java.lang {
    Thread
}

//
// Resend
//

shared class ResendMods(
    method = null,
    uri = null,
    parameters = null,
    headers = null,
    body = null,
    bodyCharset = null) {
    shared Method? method;
    shared Uri? uri;
    shared Parameters? parameters;
    shared Headers? headers;
    shared Body? body;
    shared Charset? bodyCharset;
}

shared abstract class ReceiveResult() of Complete | Resend {}
shared class Complete(response, body) extends ReceiveResult() {
    shared ProtoResponse response;
    shared ByteBuffer body;
}
shared class Resend(response, mods) extends ReceiveResult() {
    shared ProtoResponse response;
    shared ResendMods mods;
}

shared class RetryException() extends Exception() {}
shared class AttemptsExhaustedException() extends RetryException() {}
shared class RedirectDepthException() extends RetryException() {}

shared alias ProtoCallback => ResendMods?(ProtoResponse);

"Resend based on the response HTTP status code."
shared ProtoCallback retryOnStatus(statuses, max_attempts = 5, backoff_factor = 0) {
    Integer[] statuses;
    Integer max_attempts;
    Integer backoff_factor;
    
    variable Integer attempts = 0;
    
    ResendMods? f(ProtoResponse response) {
        attempts++;
        if (attempts > max_attempts) {
            throw AttemptsExhaustedException();
        } else if (response.status in statuses) {
            if (backoff_factor > 0) {
                Thread.sleep(backoff_factor * (2 ^ (attempts - 1)));
            }
            return ResendMods();
        } else {
            return null;
        }
    }
    return f;
}
ProtoCallback retryOnServerError() => retryOnStatus(500..599);
ProtoCallback retryOnError() => retryOnStatus(400..599);

Uri? parseLocation(ProtoResponse response) {
    if (exists locs = response.headers.get("Location"), exists loc = locs.first) {
        try {
            return parse(loc);
        } catch (InvalidUriException e) {
        }
    }
    return null;
}

"Follow server specified redirects as defined in [RFC 7231 §6.4]
 (https://tools.ietf.org/html/rfc7231#section-6.4) and [RFC 7538]
 (https://tools.ietf.org/html/rfc7538#section-3)."
shared ProtoCallback followRedirects(max_depth = 10) {
    Integer max_depth;
    
    variable Integer depth = 0;
    
    ResendMods? f(ProtoResponse response) {
        depth++;
        if (depth > max_depth) {
            throw RedirectDepthException();
        } else if (exists loc = parseLocation(response)) {
            if (response.status == 301) {
                return ResendMods { uri = loc; };
            } else if (response.status == 302) {
                return ResendMods { uri = loc; };
            } else if (response.status == 303) {
                return ResendMods {
                    method = getMethod;
                    uri = loc;
                    body = null;
                };
            } else if (response.status == 307) {
                return ResendMods { uri = loc; };
            } else if (response.status == 308) {
                return ResendMods { uri = loc; };
            }
        }
        return null;
    }
    return f;
}

// TODO need basic auth functions: a simple one for setting the Authorization header blind (no resend required),
// TODO and a preambleCallback that can handle WWW-Authenticate realms (user/pass per realm), but requires a resend

shared String basicAuthHeader(String user, String pass) {
    // TODO
    return nothing;
}

shared ResendMods? realmAwareBasicAuth(Map<String,[String, String]> credentials)(response) {
    ProtoResponse response;
    // TODO 
    return nothing;
}


//
// Parse
//

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
    return 10*partial + (element.signed - '0'.integer);
}

Integer base16accumulator(Integer partial, Byte element) {
    // Num/upperalpha/loweralpha are not contiguous in ascii
    Integer digit;
    if ('0'.integer <= element.signed <= '9'.integer) {
        digit = element.signed - '0'.integer;
    } else if ('A'.integer <= element.signed <= 'F'.integer) {
        digit = 10 + element.signed - 'A'.integer;
    } else if ('a'.integer <= element.signed <= 'f'.integer) {
        digit = 10 + element.signed - 'a'.integer;
    } else {
        throw ParseException("Non-hexadecimal digit ``element`` encountered");
    }
    return 16*partial + digit; // TODO
}

//
// Receive
//

by ("Alex Szczuczko", "Stéphane Épardaud")
shared ReceiveResult receive(readByte, readBuf, close, protoCallbacks, chunkReceiver) {
    Byte?() readByte;
    Integer(ByteBuffer) readBuf;
    Anything() close;
    {ProtoCallback*} protoCallbacks;
    ChunkReceiver? chunkReceiver;
    
    //
    // "Expect", either wholly known values, or known length
    //
    void expectBytes({Byte*} expected) {
        for (char in expected) {
            if (exists b = readByte()) {
                if (b != char) {
                    throw OutOfSequenceCharacter(b, char, expected);
                }
            } else {
                throw OutOfSequenceCharacter(null, char, expected);
            }
        }
    }
    Byte expectByteIn(Set<Byte> expected) {
        if (exists b = readByte()) {
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
        if (exists b = readByte()) {
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
        String name = capitaliseHeaderName(nameOrTerm[0].trimmed);
        // If termChar is cr, then we expect name to be blank, ex: \r\n\r\n
        Byte termChar = nameOrTerm[1];
        // End of headers?
        if (termChar == cr) {
            if (name.empty) {
                // \r already read by readString(), read the \n still present
                expectBytes { lf };
                break;
            } else {
                throw ParseException("Unexpected value between terminator characters");
            }
        } else {
            if (name.empty) {
                throw ParseException("Blank header name");
            }
        }
        // Header Field Value, ex: text/html; charset=UTF-8
        // TODO is splitting on commas safe for all headers?
        {String*} newValues = readString { cr }[0].split((ch) => ch == ',').map((element) => element.trimmed);
        if (exists values = headerMap.get(name)) {
            // Duplicated header names are addressed in RFC 7230
            // https://tools.ietf.org/rfcmarkup?doc=7230#section-3.2.2
            values.addAll(newValues);
        } else {
            headerMap.put(name, LinkedList<String>(newValues));
        }
    }
    value headers = unmodifiableMap(headerMap);
    
    value proto = ProtoResponse {
        major = major;
        minor = minor;
        status = status;
        reason = reason;
        headers = headers;
    };
    
    void drain(Integer limit = 2 ^ 20) {
        // Finish reading otherwise socket can't be reused
        if (exists bodySize = proto.bodySize) {
            ByteBuffer buf = newByteBuffer(min { bodySize, limit });
            if (readBuf(buf) == limit) {
                close();
            }
            // otherwise we've read the entire body, socket is safe to reuse
        } else {
            // TODO read chunks, close if total reaches limit
        }
    }
    
    try {
        for (callback in protoCallbacks) {
            if (exists rm = callback(proto)) {
                drain();
                return Resend(proto, rm);
            }
        }
    } catch (Exception e) {
        drain();
        throw;
    }
    
    ByteBuffer body;
    // TODO Socket read timeout is required to recover from bodySize being greater than the actual body size.
    if (exists bodySize = proto.bodySize) {
        variable Integer bytesRead = 0;
        // Known size body (no Chunked Transfer Encoding)
        if (exists chunkReceiver) {
            // Simulate chunk(s) of at most 4 MiB
            ByteBuffer buf = newByteBuffer(min { bodySize, 4 * (2 ^ 20) });
            readBuf(buf);
            while (buf.available == 0) {
                bytesRead += buf.capacity;
                buf.flip();
                if (is Boolean(String) chunkReceiver) {
                    Charset charset = proto.bodyCharset;
                    String chunkString = charset.decode(buf);
                    chunkReceiver(chunkString);
                } else if (is Boolean(ByteBuffer, Charset?) chunkReceiver) {
                    chunkReceiver(buf, proto.bodyCharset);
                } else {
                    chunkReceiver.writeFully(buf);
                }
                readBuf(buf);
            }
            bytesRead += buf.capacity-buf.available;
            body = newByteBuffer(0);
        } else {
            // Read entire body into a single buffer
            ByteBuffer buf = newByteBuffer(bodySize);
            bytesRead = readBuf(buf);
            buf.flip();
            body = buf;
        }
        if (bodySize != bytesRead) {
            throw ParseException("Premature EOF while reading body");
        }
    } else {
        // Unknown size body (Chunked Transfer Encoding)
        if (exists chunkReceiver) {
            // Read chunks as they come and pass them on
            ByteBuffer buf = newByteBuffer(0);
            while (true) {
                Integer chunkLength = readNumerical(cr, hexDigit, base16accumulator);
                expectBytes({ lf });
                if (chunkLength == 0) {
                    expectBytes({ cr, lf });
                    break;
                }
                buf.resize(chunkLength, true);
                Integer bytesRead = readBuf(buf);
                if (chunkLength != bytesRead) {
                    throw ParseException("Premature EOF while reading body chunk");
                }
                buf.flip();
                if (is Boolean(String) chunkReceiver) {
                    Charset charset = proto.bodyCharset;
                    String chunkString = charset.decode(buf);
                    chunkReceiver(chunkString);
                } else if (is Boolean(ByteBuffer, Charset?) chunkReceiver) {
                    chunkReceiver(buf, proto.bodyCharset);
                } else {
                    chunkReceiver.writeFully(buf);
                }
            }
            body = newByteBuffer(0);
        } else {
            // Read chunks as they come, combine into a single buffer
            ByteBuffer buf = newByteBuffer(0);
            while (true) {
                Integer chunkLength = readNumerical(cr, hexDigit, base16accumulator);
                expectBytes({ lf });
                if (chunkLength == 0) {
                    expectBytes({ cr, lf });
                    break;
                }
                buf.resize(buf.capacity + chunkLength, true);
                Integer bytesRead = readBuf(buf);
                if (chunkLength != bytesRead) {
                    throw ParseException("Premature EOF while reading body chunk");
                }
            }
            buf.flip();
            body = buf;
        }
    }
    
    return Complete(proto, body);
}

//
// Response
//

"A HTTP response with a complete preamble, but no body"
shared class ProtoResponse(major, minor, status, reason, headers) {
    shared Integer major;
    shared Integer minor;
    shared Integer status;
    shared String reason;
    shared Map<String,LinkedList<String>> headers;
    
    // https://tools.ietf.org/html/rfc7230#section-3.3.3
    shared Integer? bodySize;
    if (exists encs = headers.get("Transfer-Encoding"),
        exists enc = encs.last,
        enc == "chunked") {
        bodySize = null;
    } else if (exists lengths = headers.get("Content-Length"),
        exists lenStr = lengths.last,
        exists len = parseInteger(lenStr)) {
        bodySize = len;
    } else {
        bodySize = 0;
    }
    
    // https://tools.ietf.org/html/rfc2045#section-5
    // TODO probably need a seperate MIME parsing library in future
    shared Charset bodyCharset;
    if (exists cts = headers.get("Content-Type"),
        exists ctStr = cts.last,
        exists start = ctStr.firstInclusion("charset=")) {
        String charsetName;
        if (exists end = ctStr.firstInclusion(" ", start)) {
            charsetName = ctStr.span(start, end);
        } else {
            charsetName = ctStr.spanFrom(start);
        }
        bodyCharset = getCharset(charsetName) else utf8;
    } else {
        bodyCharset = utf8;
    }
}

"A complete HTTP response"
shared class Response(major, minor, status, reason, fullHeaders, body, resends) {
    Integer major;
    Integer minor;
    shared Integer status;
    shared String reason;
    shared Map<String,List<String>> fullHeaders;
    "Will be empty if the body has been sent to a chunkReceiver instead of being buffered."
    shared ByteBuffer body;
    shared List<Resend> resends;
    
    shared [Integer, Integer] http_version = [major, minor];
    shared Integer bodySize = body.capacity;
    // TODO "view" of fullHeaders with only one value (first?), see Map.patch for impl. example
    shared Map<String,String> headers = nothing;
    
    // TODO lazy JsonValue, parse from body transparently.
    shared Anything bodyJson => nothing;
    // TODO lazy, parse from body transparently
    shared String bodyText => nothing;
    // TODO lazy, parse from body transparently
    shared Parameters bodyParameters => nothing;
}

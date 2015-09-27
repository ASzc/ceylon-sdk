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
    Charset
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
    shared Body? body;
}
shared class Resend(response, modifications) extends ReceiveResult() {
    shared ProtoResponse response;
    shared ResendMods? modifications;
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

shared ResendMods? realmAwareBasicAuth(credentials)(response) {
    Map<String,[String, String]> credentials;
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
    // #30 == '0'
    return 10*partial + (element.signed - #30);
}

Integer base16accumulator(Integer partial, Byte element) {
    return nothing; // TODO
}

//
// Receive
//

by ("Alex Szczuczko", "Stéphane Épardaud")
shared ReceiveResult receive(sender, protoCallbacks, chunkReceiver) {
    FileDescriptor sender;
    {ProtoCallback*} protoCallbacks;
    ChunkReceiver? chunkReceiver;
    
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
                // TODO throw exception, unexpected value between terminators
            }
        } else {
            if (name.empty) {
                // TODO throw exception, blank header name
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
    
    
    void drain() {
        // TODO drain / finish reading otherwise socket can't be reused
        // TODO intelligent behaviour: attempt to Drain for some small number of bytes (<1MB?), if still there, Close
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
    
    // TODO read body
    
    return Complete(proto, nothing);
}

// TODO incorporate BodyReader into recieve, doesn't need to be seperate anymore
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
    
    shared Integer? bodySize = nothing; //TODO get from headers
}

// TODO probably don't need a Message superclass?
shared class Response() extends Message(nothing) {
    shared Integer code = nothing;
    // TODO include redirect [Response*] history here
}

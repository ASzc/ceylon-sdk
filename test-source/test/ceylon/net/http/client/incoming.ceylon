import ceylon.test {
    test,
    assertTrue,
    assertEquals
}
import ceylon.net.http.client {
    ProtoCallback,
    ChunkReceiver,
    receive,
    ReceiveResult,
    Complete
}
import ceylon.io.charset {
    Charset,
    utf8,
    utf16
}
import ceylon.io.buffer {
    ByteBuffer,
    newByteBufferWithData
}

shared class ReceiveTest() {
    ReceiveResult simulate(
        responsePre,
        responseBody = null,
        responseBodyCharset = utf8,
        protoCallbacks = empty,
        chunkReceiver = null,
        expectClose = false) {
        String responsePre;
        String? responseBody;
        Charset responseBodyCharset;
        {ProtoCallback*} protoCallbacks;
        ChunkReceiver? chunkReceiver;
        Boolean expectClose;
        
        ByteBuffer buf;
        ByteBuffer preambleBuf = utf8.encode(responsePre.replace("\n", "\r\n"));
        if (exists responseBody) {
            ByteBuffer bodyBuf = responseBodyCharset.encode(responseBody.replace("\n", "\r\n"));
            buf = newByteBufferWithData(*preambleBuf.chain(bodyBuf));
        } else {
            buf = preambleBuf;
        }
        
        Byte? readByte() {
            if (buf.hasAvailable) {
                return buf.get();
            } else {
                return null;
            }
        }
        Integer readBuf(ByteBuffer otherBuf) {
            variable Integer count = 0;
            while (otherBuf.hasAvailable && buf.hasAvailable) {
                otherBuf.put(buf.get());
                count++;
            }
            return count;
        }
        void close() {
            assertTrue(expectClose, "Closed when expecting no close");
        }
        
        return receive {
            readByte = readByte;
            readBuf = readBuf;
            close = close;
            protoCallbacks = protoCallbacks;
            chunkReceiver = chunkReceiver;
        };
    }
    
    test
    shared void nobody() {
        value result = simulate("""HTTP/1.1 200 OK
                                   Content-Length: 0
                                   
                                   """);
        assert (is Complete result);
        assertEquals(result.body.capacity, 0);
        assertEquals(result.response.bodySize, 0);
        
        assertEquals(result.response.major, 1);
        assertEquals(result.response.minor, 1);
        assertEquals(result.response.status, 200);
        assertEquals(result.response.reason, "OK");
        
        assertEquals(result.response.headers.size, 1);
    }
    
    test
    shared void text_utf8_buffered() {
        value result = simulate("""HTTP/1.1 200 OK
                                   Content-Type: text/plain; charset=UTF-8
                                   Content-Length: 87
                                   
                                   ᚠᛇᚻ᛫ᛒᛦᚦ᛫ᚠᚱᚩᚠᚢᚱ᛫ᚠᛁᚱᚪ᛫ᚷᛖᚻᚹᛦᛚᚳᚢᛗ""");
        assert (is Complete result);
        assertEquals(result.body.capacity, 87);
        assertEquals(result.response.bodySize, 87);
        assertEquals(utf8.decode(result.body), "ᚠᛇᚻ᛫ᛒᛦᚦ᛫ᚠᚱᚩᚠᚢᚱ᛫ᚠᛁᚱᚪ᛫ᚷᛖᚻᚹᛦᛚᚳᚢᛗ");
        
        assertEquals(result.response.major, 1);
        assertEquals(result.response.minor, 1);
        assertEquals(result.response.status, 200);
        assertEquals(result.response.reason, "OK");
        
        assertEquals(result.response.headers.size, 2);
    }
    
    test
    shared void text_utf16_buffered() {
        value result = simulate {
            responsePre = """HTTP/1.1 200 OK
                             Content-Type: text/plain; charset=UTF-16
                             Content-Length: 58
                             
                             """;
            responseBody = "ᚠᛇᚻ᛫ᛒᛦᚦ᛫ᚠᚱᚩᚠᚢᚱ᛫ᚠᛁᚱᚪ᛫ᚷᛖᚻᚹᛦᛚᚳᚢᛗ";
            responseBodyCharset = utf16;
        };
        assert (is Complete result);
        assertEquals(result.body.capacity, 58);
        assertEquals(result.response.bodySize, 58);
        assertEquals(utf16.decode(result.body), "ᚠᛇᚻ᛫ᛒᛦᚦ᛫ᚠᚱᚩᚠᚢᚱ᛫ᚠᛁᚱᚪ᛫ᚷᛖᚻᚹᛦᛚᚳᚢᛗ");
        
        assertEquals(result.response.major, 1);
        assertEquals(result.response.minor, 1);
        assertEquals(result.response.status, 200);
        assertEquals(result.response.reason, "OK");
        
        assertEquals(result.response.headers.size, 2);
    }
}

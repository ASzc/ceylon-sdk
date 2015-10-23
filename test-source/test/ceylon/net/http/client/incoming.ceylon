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
    ByteBuffer
}

shared class ReceiveTest() {
    ReceiveResult simulate(
        responseText,
        charset = utf8,
        protoCallbacks = empty,
        chunkReceiver = null,
        expectClose = false) {
        String responseText;
        Charset charset;
        {ProtoCallback*} protoCallbacks;
        ChunkReceiver? chunkReceiver;
        Boolean expectClose;
        
        ByteBuffer buf = charset.encode(responseText.replace("\n", "\r\n"));
        
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
                buf.put(buf.get());
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
        value result = simulate ("""HTTP/1.1 200 OK
                                    Content-Length: 0
                                    
                                    """);
        assert (is Complete result);
        assertEquals(result.body.capacity, 0);
        assertEquals(result.response.bodySize, 0);
    }
    
    test
    shared void text_utf8_buffered() {
        value result = simulate ("""HTTP/1.1 200 OK
                                    Content-Type: text/plain; charset=UTF-8
                                    Content-Length: 87
                                    
                                    ᚠᛇᚻ᛫ᛒᛦᚦ᛫ᚠᚱᚩᚠᚢᚱ᛫ᚠᛁᚱᚪ᛫ᚷᛖᚻᚹᛦᛚᚳᚢᛗ""");
        assert (is Complete result);
        assertEquals(result.body.capacity, 87);
        assertEquals(result.response.bodySize, 87);
        assertEquals(utf8.decode(result.body), "ᚠᛇᚻ᛫ᛒᛦᚦ᛫ᚠᚱᚩᚠᚢᚱ᛫ᚠᛁᚱᚪ᛫ᚷᛖᚻᚹᛦᛚᚳᚢᛗ");
    }
    
    test
    shared void text_utf16_buffered() {
        value result = simulate {
            responseText = """HTTP/1.1 200 OK
                              Content-Type: text/plain; charset=UTF-16
                              Content-Length: 58
                              
                              ᚠᛇᚻ᛫ᛒᛦᚦ᛫ᚠᚱᚩᚠᚢᚱ᛫ᚠᛁᚱᚪ᛫ᚷᛖᚻᚹᛦᛚᚳᚢᛗ""";
        };
        assert (is Complete result);
        assertEquals(result.body.capacity, 58);
        assertEquals(result.response.bodySize, 58);
        assertEquals(utf16.decode(result.body), "ᚠᛇᚻ᛫ᛒᛦᚦ᛫ᚠᚱᚩᚠᚢᚱ᛫ᚠᛁᚱᚪ᛫ᚷᛖᚻᚹᛦᛚᚳᚢᛗ");
    }
}

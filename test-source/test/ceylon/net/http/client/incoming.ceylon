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
    newByteBuffer
}

shared class ReceiveTest() {
    ReceiveResult simulate(
        responseParts,
        protoCallbacks = empty,
        chunkReceiver = null,
        expectClose = false) {
        {String|[String, Charset]*} responseParts;
        {ProtoCallback*} protoCallbacks;
        ChunkReceiver? chunkReceiver;
        Boolean expectClose;
        
        ByteBuffer buf = newByteBuffer(0);
        for (responsePart in responseParts) {
            String text;
            Charset charset;
            if (is String responsePart) {
                text = responsePart;
                charset = utf8;
            } else {
                text = responsePart[0];
                charset = responsePart[1];
            }
            ByteBuffer partBuf = charset.encode(text.replace("\n", "\r\n"));
            buf.resize(buf.capacity + partBuf.available, true);
            for (b in partBuf) {
                buf.put(b);
            }
        }
        buf.flip();
        
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
        
        value result = receive {
            readByte = readByte;
            readBuf = readBuf;
            close = close;
            protoCallbacks = protoCallbacks;
            chunkReceiver = chunkReceiver;
        };
        
        assertEquals(buf.available, 0, "Some response bytes were left unread");
        
        return result;
    }
    
    test
    shared void nobody_200() {
        value result = simulate { """HTTP/1.1 200 OK
                                     Content-Length: 0
                                     
                                     """ };
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
    shared void nobody_302() {
        value result = simulate { """HTTP/1.0 302 Found
                                     Location: /foo
                                     
                                     """ };
        assert (is Complete result);
        assertEquals(result.body.capacity, 0);
        assertEquals(result.response.bodySize, 0);
        
        assertEquals(result.response.major, 1);
        assertEquals(result.response.minor, 0);
        assertEquals(result.response.status, 302);
        assertEquals(result.response.reason, "Found");
        
        assertEquals(result.response.headers.size, 1);
    }
    
    test
    shared void text_utf8_buffered_unchunked() {
        value result = simulate { """HTTP/1.1 200 OK
                                     Content-Type: text/plain; charset=UTF-8
                                     Content-Length: 87
                                     
                                     ᚠᛇᚻ᛫ᛒᛦᚦ᛫ᚠᚱᚩᚠᚢᚱ᛫ᚠᛁᚱᚪ᛫ᚷᛖᚻᚹᛦᛚᚳᚢᛗ""" };
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
    shared void text_utf16_buffered_unchunked() {
        value result = simulate {
            """HTTP/1.1 200 OK
               Content-Type: text/plain; charset=UTF-16
               Content-Length: 58
               
               """,
            ["ᚠᛇᚻ᛫ᛒᛦᚦ᛫ᚠᚱᚩᚠᚢᚱ᛫ᚠᛁᚱᚪ᛫ᚷᛖᚻᚹᛦᛚᚳᚢᛗ", utf16]
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
    
    test
    shared void text_buffered_chunked() {
        value result = simulate {
            """HTTP/1.1 200 OK
               Content-Type: text/plain; charset=UTF-8
               Transfer-Encoding: chunked
               
               """,
            // printf '%x\n' "$(printf 'ᚠᛇᚻ᛫ᛒᛦᚦ᛫' | wc -c)"
            "18\n",
            "ᚠᛇᚻ᛫ᛒᛦᚦ᛫\n",
            "21\n",
            "ᚠᚱᚩᚠᚢᚱ᛫ᚠᛁᚱᚪ\n",
            "3\n",
            "᛫\n",
            "1b\n",
            "ᚷᛖᚻᚹᛦᛚᚳᚢᛗ\n\n"
        };
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
    shared void text_unbuffered_unchunked() {
        // TODO checkReciever with Content-Length response
    }
    
    test
    shared void text_unbuffered_chunked() {
        // TODO checkReciever with T-E: chunked response
    }
}

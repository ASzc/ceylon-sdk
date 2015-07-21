import ceylon.collection {
    HashMap
}
import ceylon.io.buffer {
    ByteBuffer,
    newByteBuffer
}
import ceylon.io.charset {
    utf8,
    utf16
}
import ceylon.net.http {
    get,
    post
}
import ceylon.net.http.client {
    buildMessage
}
import ceylon.test {
    test,
    assertEquals
}

ByteBuffer collectChunks(Anything(Anything(ByteBuffer)) producer) {
    ByteBuffer gather = newByteBuffer(0);
    
    void collect(ByteBuffer chunk) {
        gather.resize(gather.capacity + chunk.available, true);
        while (chunk.hasAvailable) {
            gather.put(chunk.get());
        }
    }
    producer(collect);
    
    gather.flip();
    return gather;
}

shared class BuildMessageTest() {
    test
    shared void minimalGet() {
        value message = buildMessage {
            get;
            "example.com";
            "/";
            null;
            emptyMap;
            emptyMap;
        };
        assertEquals {
            utf8.decode(message[0]);
            """GET / HTTP/1.1
               Host: example.com
               Accept: */*
               Accept-Charset: UTF-8
               User-Agent: Ceylon/1.2
               Content-Length: 0
               
               """.replace("\n", "\r\n");
            "Preamble";
        };
        assertEquals {
            utf8.decode(collectChunks(message[1]));
            "";
            "Body";
        };
    }
    
    test
    shared void stringGetUtf8() {
        value message = buildMessage {
            get;
            "example.com";
            "/";
            null;
            emptyMap;
            emptyMap;
            body = "ᚠᛇᚻ᛫ᛒᛦᚦ᛫ᚠᚱᚩᚠᚢᚱ᛫ᚠᛁᚱᚪ᛫ᚷᛖᚻᚹᛦᛚᚳᚢᛗ";
        };
        assertEquals {
            utf8.decode(message[0]);
            """GET / HTTP/1.1
               Host: example.com
               Accept: */*
               Accept-Charset: UTF-8
               User-Agent: Ceylon/1.2
               Content-Type: text/plain; charset=UTF-8
               Content-Length: 87
               
               """.replace("\n", "\r\n");
            "Preamble";
        };
        assertEquals {
            utf8.decode(collectChunks(message[1]));
            "ᚠᛇᚻ᛫ᛒᛦᚦ᛫ᚠᚱᚩᚠᚢᚱ᛫ᚠᛁᚱᚪ᛫ᚷᛖᚻᚹᛦᛚᚳᚢᛗ";
            "Body";
        };
    }
    
    test
    shared void stringGetUtf16() {
        value message = buildMessage {
            get;
            "example.com";
            "/";
            null;
            emptyMap;
            HashMap<String,String> { "content-type"->"text/plain; charset=utf-16" };
            body = "ᚠᛇᚻ᛫ᛒᛦᚦ᛫ᚠᚱᚩᚠᚢᚱ᛫ᚠᛁᚱᚪ᛫ᚷᛖᚻᚹᛦᛚᚳᚢᛗ";
        };
        assertEquals {
            utf8.decode(message[0]);
            """GET / HTTP/1.1
               Content-Type: text/plain; charset=UTF-16
               Host: example.com
               Accept: */*
               Accept-Charset: UTF-8
               User-Agent: Ceylon/1.2
               Content-Length: 58
               
               """.replace("\n", "\r\n");
            "Preamble";
        };
        assertEquals {
            utf16.decode(collectChunks(message[1]));
            "ᚠᛇᚻ᛫ᛒᛦᚦ᛫ᚠᚱᚩᚠᚢᚱ᛫ᚠᛁᚱᚪ᛫ᚷᛖᚻᚹᛦᛚᚳᚢᛗ";
            "Body";
        };
    }
    
    test
    shared void stringPost() {
        value message = buildMessage {
            post;
            "example.com";
            "/";
            null;
            emptyMap;
            emptyMap;
            body = "testing 123";
        };
        assertEquals {
            utf8.decode(message[0]);
            """POST / HTTP/1.1
               Host: example.com
               Accept: */*
               Accept-Charset: UTF-8
               User-Agent: Ceylon/1.2
               Content-Type: text/plain; charset=UTF-8
               Content-Length: 11
               
               """.replace("\n", "\r\n");
            "Preamble";
        };
        assertEquals {
            utf8.decode(collectChunks(message[1]));
            "testing 123";
            "Body";
        };
    }
}

import ceylon.io.charset {
    utf8,
    utf16
}
import ceylon.net.http {
    get,
    post,
    contentType
}
import ceylon.net.http.client {
    buildMessage
}
import ceylon.test {
    test,
    assertNull,
    assertEquals
}
import ceylon.io.buffer {
    ByteBuffer
}

shared class BuildMessageTest() {
    test
    shared void minimalGet() {
        value message = buildMessage {
            get;
            "example.com";
            "/";
            null;
            {};
            {};
        };
        assertEquals {
            utf8.decode(message[0]);
            """GET / HTTP/1.1
               Host: example.com
               Accept: */*
               Accept-Charset: UTF-8
               User-Agent: Ceylon/1.2
               
               """.replace("\n", "\r\n");
            "Prefix";
        };
        assertNull(message[1], "Body");
    }
    
    test
    shared void stringGetUtf8() {
        value message = buildMessage {
            get;
            "example.com";
            "/";
            null;
            {};
            {};
            data = "ᚠᛇᚻ᛫ᛒᛦᚦ᛫ᚠᚱᚩᚠᚢᚱ᛫ᚠᛁᚱᚪ᛫ᚷᛖᚻᚹᛦᛚᚳᚢᛗ";
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
            "Prefix";
        };
        assert (is ByteBuffer body = message[1]);
        assertEquals(utf8.decode(body), "ᚠᛇᚻ᛫ᛒᛦᚦ᛫ᚠᚱᚩᚠᚢᚱ᛫ᚠᛁᚱᚪ᛫ᚷᛖᚻᚹᛦᛚᚳᚢᛗ", "Body");
    }
    
    test
    shared void stringGetUtf16() {
        value message = buildMessage {
            get;
            "example.com";
            "/";
            null;
            {};
            { contentType("text/plain", utf16) };
            data = "ᚠᛇᚻ᛫ᛒᛦᚦ᛫ᚠᚱᚩᚠᚢᚱ᛫ᚠᛁᚱᚪ᛫ᚷᛖᚻᚹᛦᛚᚳᚢᛗ";
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
            "Prefix";
        };
        assert (is ByteBuffer body = message[1]);
        assertEquals(utf16.decode(body), "ᚠᛇᚻ᛫ᛒᛦᚦ᛫ᚠᚱᚩᚠᚢᚱ᛫ᚠᛁᚱᚪ᛫ᚷᛖᚻᚹᛦᛚᚳᚢᛗ", "Body");
    }
    
    test
    shared void stringPost() {
        value message = buildMessage {
            post;
            "example.com";
            "/";
            null;
            {};
            {};
            data = "testing 123";
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
            "Prefix";
        };
        assert (is ByteBuffer body = message[1]);
        assertEquals(utf8.decode(body), "testing 123", "Body");
    }
}

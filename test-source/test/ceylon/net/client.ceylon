import ceylon.io.charset {
    utf8
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
    assertNull,
    assertEquals
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
    shared void stringGet() {
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
        assertEquals(message[1], "ᚠᛇᚻ᛫ᛒᛦᚦ᛫ᚠᚱᚩᚠᚢᚱ᛫ᚠᛁᚱᚪ᛫ᚷᛖᚻᚹᛦᛚᚳᚢᛗ", "Body");
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
        assertEquals(message[1], "testing 123", "Body");
    }
}

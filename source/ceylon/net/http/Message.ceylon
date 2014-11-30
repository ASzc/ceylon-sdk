import ceylon.io.buffer {
    ByteBuffer
}
import ceylon.net.uri {
    Parameter
}
import ceylon.io.charset {
    Charset
}

"Represents an HTTP Message"
by ("Alex Szczuczko")
shared class Message(String|ByteBuffer initBodyThing) { // TODO accept body as sequence for chunked encoding?
    shared String topLine = nothing; // TODO type?
    
    shared String version => nothing;
    shared String path = nothing; // TODO, Uri vs Path+Query...
    
    shared List<Header> headers = nothing;
    shared List<Parameter> parameters => nothing;
    
    shared String contents {
        // TODO if headers contains Content-Type of application/x-www-form-urlencoded, text, else null???
        
        return nothing;
    }
    shared Charset bodyCharset = nothing;
    shared ByteBuffer body {
        switch (initBodyThing)
        case (is String) {
            return bodyCharset.encode(initBodyThing);
        }
        case (is ByteBuffer) {
            return initBodyThing;
        }
    }
    shared String text {
        switch (initBodyThing)
        case (is String) {
            return initBodyThing;
        }
        case (is ByteBuffer) {
            return bodyCharset.decode(initBodyThing);
        }
    }
}

// TODO might need this server side, but not client
class Request() {
    shared Method method = nothing;
}

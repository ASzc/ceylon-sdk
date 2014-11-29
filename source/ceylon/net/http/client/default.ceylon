import ceylon.io {
    FileDescriptor
}
import ceylon.io.buffer {
    ByteBuffer
}
import ceylon.net.http {
    Header,
    Message
}
import ceylon.net.uri {
    Uri,
    Parameter
}

Client defaultClient = Client();

// TODO update param lists
shared Message(Uri|String, {Parameter*}, {Header*}, FileDescriptor|ByteBuffer|String?, Integer) get = defaultClient.get;
shared Message post(Uri|String uri) => defaultClient.post(uri);
// TODO ...

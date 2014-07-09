import ceylon.net.http { Method }
"Asynchronous web endpoint. Endpoint is executed 
 asynchronously. End of request processing must be 
 signaled by calling `complete()`."
by("Matej Lazar")
shared class AsynchronousEndpoint(Matcher path, service, {Method*} acceptMethod) 
        extends HttpEndpoint(path, acceptMethod) {
    
    shared void service(Request request, Response response,
            void complete());
    
}
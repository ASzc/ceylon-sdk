doc "Writes text to a `File`."
see (File)
shared interface Writer satisfies Closeable {
    
    doc "Write text to the file."
    shared formal void write(String string);
    
    doc "Write a line of text to the file."
    shared formal void writeLine(String line);
    
    doc "Flush all written text to the underlying
         file system."
    shared formal void flush();
    
    doc "Destroy this `Writer`. Called 
         automatically by `close()`."
    see (close)
    shared formal void destroy();
    
    shared actual void open() {}
    
    shared actual void close(Exception? exception) =>
            destroy();
    
}
doc "This module allows you to read and write to streams, such as files, sockets and pipes.
     
     It also defines character sets, for encoding and decoding bytes to strings, as well
     as buffers of bytes and characters for input/output.
     
     See the `ceylon.io` package for usage examples."
by "Stéphane Épardaud"
license "Apache Software License"
module ceylon.io '0.5' {
    import ceylon.language '0.5';
    shared import ceylon.file '0.5';
    import ceylon.collection '0.5';
    import java.base '7';
}

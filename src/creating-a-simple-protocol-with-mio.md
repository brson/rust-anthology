---
layout: post
title: "Creating A Simple Protocol When Using Rust and mio"
tags:
- rustlang
- mio
status: publish
type: post
published: true
---

This post is going to walk through establishing a simple protocol when using mio.

Let us first talk about why a protocol is needed. There are two common network protocols in use today: UDP and TCP. UDP is a message oriented protocol that delivers the message in one chunk. The downside to UDP is that there is no guarantee of message delivery because UDP does not handle packet loss. Many people want to protect against packet loss so they choose TCP instead. TCP is a stream oriented protocol. Data is sent byte by byte. A "message" may come one byte at a time, in multi-byte chunks or all at once. The only thing we can count on with TCP is that the bytes will arrive in the same order they were sent. And here is the reason we need a higher level protocol: It is task of the receiving socket to determine when it has enough data to make any sense of it.

I have seen two basic approaches to building a higher level protocol. The HTTP standard uses both, so let us look at how it works. An HTTP request is split into two parts: a header section and a body section. The header section contains meta information, mostly in the form of headers, used to precisely describe the request. We do not know ahead of time how long a header is or how many headers a request sends. However, HTTP uses `\r\n` to signal the end of the header. Within the header section is the _Content-Length_ header that specifies how many bytes the body section is. So one approach is to use a marker, such as `\r\n`, to signal the end of the message. Another approach is to explicitly specify how many bytes to read. HTTP also has a [chunked transfer encoding][chunked transfer encoding] option in in HTTP 1.1 that combines both of these approaches to read the body section.

There are some really powerful tools for building protocols, such as [capnproto][capnproto]. I wanted something very simple that I could implement. I decided to tell the receiver how many bytes of data they should be expecting. To do this, I use the first 64 bits to specify how many bytes I am sending over the wire. My custom protocol is not _discoverable_. Both the sender and receiver have to agree ahead of time on this protocol and implement it.

The basic strategy for receiving is as follows:

   1. Read the first 64 bits from the socket.
   1. Convert those bits into a `u64` type and determine the length of the message.
   1. Read `message_length` bytes from the socket.

Either of the reads can receieve `WouldBlock` which, [we know][previous post on WouldBlock], means we have to try again later. This is not a problem for our first read of the 64 bytes. However, if we receive `WouldBlock` during the second read then we have to remember to not try and read the first 64 bytes from the socket when we try again. This means we have to keep some state around reads. We need to keep track of two peices of information. The first is whether or not we are in the middle of reading. The second is if we are in the middle of reading then we need to keep track of how many bytes the message is. I added `read_continuation: Option<u64>` to my `Connection` struct to capture this.

Here is how we read the message length:

```rust
fn read_message_length(&mut self) -> io::Result<Option<u64>> {
    if let Some(n) = self.read_continuation {
        return Ok(Some(n));
    }

    let mut buf = [0u8; 8];

    let bytes = match self.sock.try_read(&mut buf) {
        Ok(None) => {
            return Ok(None);
        },
        Ok(Some(n)) => n,
        Err(e) => {
            return Err(e);
        }
    };

    if bytes < 8 {
        warn!("Found message length of {} bytes", bytes);
        return Err(Error::new(ErrorKind::InvalidData, "Invalid message length"));
    }

    let msg_len = BigEndian::read_u64(buf.as_ref());
    Ok(Some(msg_len))
}

```

The function starts out by checking if we are in the middle of a read. If we are in the middle of a read, we already know the message length and can just return it immediately. Otherwise, I try to read 8 bytes from the socket. The `try_read` function is provided by [mio][mio-try_read] and will return `Ok(None)` on `WouldBlock`. If the read fails or less than 8 bytes were received, we return an error that will cause this connection to be reset. Finally, I use the [byteorder][byteorder] crate to convert the bytes into a `u64` that will tell us how long the message is.


```rust
pub fn readable(&mut self) -> io::Result<Option<Vec<u8>>> {

    let msg_len = match try!(self.read_message_length()) {
        None => { return Ok(None); },
        Some(n) => n,
    };

    debug!("Expected message length: {}", msg_len);
    let mut recv_buf : Vec<u8> = Vec::with_capacity(msg_len as usize);

    // resolve "multiple applicable items in scope [E0034]" error
    let sock_ref = <TcpStream as Read>::by_ref(&mut self.sock);

    match sock_ref.take(msg_len as u64).try_read_buf(&mut recv_buf) {
        Ok(None) => {
            debug!("CONN : read encountered WouldBlock");

            // We are being forced to try again, but we already read the two bytes off of
            // the wire that determined the length. We need to store the message length
            // so we can resume next time we get readable.
            self.read_continuation = Some(msg_len as u64);
            Ok(None)
        },
        Ok(Some(n)) => {
            debug!("CONN : we read {} bytes", n);

            if n < msg_len as usize {
                return Err(Error::new(ErrorKind::InvalidData, "Did not read enough bytes"));
            }

            self.read_continuation = None;

            Ok(Some(recv_buf))
        },
        Err(e) => {
            error!("Failed to read buffer for token {:?}, error: {}", self.token, e);
            Err(e)
        }
    }
}
```

Our `readable` function starts out by determining the length of the message and then creates a vector with a capacity that is at least message length. I would have preferred a fixed slice, but I do not know of a way to create that slice dynamically. Then we need to read at _most_ `msg_len` bytes from the socket. We can do this using the `take` function. This starts to look a bit messy due to some Rust issues. If we just call `self.sock.by_ref()` Rust is not able to determine which `by_ref` function to use. The error message looks something like:

```
src/connection.rs:76:25: 76:33 error: multiple applicable items in scope [E0034]
src/connection.rs:76         match self.sock.by_ref().take(msg_len as u64).try_read_buf(&mut recv_buf) {
                                             ^~~~~~~~
src/connection.rs:76:25: 76:33 help: run `rustc --explain E0034` to see a detailed explanation
src/connection.rs:76:25: 76:33 note: candidate #1 is defined in an impl of the trait `std::io::Read` for the type `&mut _`
src/connection.rs:76         match self.sock.by_ref().take(msg_len as u64).try_read_buf(&mut recv_buf) {
                                             ^~~~~~~~
src/connection.rs:76:25: 76:33 note: candidate #2 is defined in an impl of the trait `std::io::Write` for the type `&mut _`
src/connection.rs:76         match self.sock.by_ref().take(msg_len as u64).try_read_buf(&mut recv_buf) {
                                             ^~~~~~~~
src/connection.rs:76:25: 76:33 note: candidate #3 is defined in an impl of the trait `core::iter::Iterator` for the type `&mut _`
src/connection.rs:76         match self.sock.by_ref().take(msg_len as u64).try_read_buf(&mut recv_buf) {
                                             ^~~~~~~~
src/connection.rs:76:25: 76:33 note: candidate #4 is defined in an impl of the trait `std::io::Read` for the type `mio::net::tcp::TcpStream`
src/connection.rs:76         match self.sock.by_ref().take(msg_len as u64).try_read_buf(&mut recv_buf) {
                                             ^~~~~~~~
src/connection.rs:76:25: 76:33 note: candidate #5 is defined in an impl of the trait `std::io::Write` for the type `mio::net::tcp::TcpStream`
src/connection.rs:76         match self.sock.by_ref().take(msg_len as u64).try_read_buf(&mut recv_buf) {
```

In order to resolve this, we need to use [Universal Function Call Syntax][UFCS], also called UFCS. Using UFCS, we can be explicit about which `by_ref` function we want. We can then use that reference to `take` at _most_ `msg_len` bytes from the socket. Now we just need to handle the the different responses from the socket. If `try_read` returns `None` (meaning `WouldBlock`), then we need to store the length of the message in `self.read_continuation` so we can try again later. If we successfully read from the socket, we set `self.read_continuation` to `None` so the next readable event will know to first determine the message length.

I have tested this a fair bit and find it works well. The fact that mob echos every received message to every connected socket causes messages to naturally coalecse. Knowing the message length ahead of time helps separate the messages out. The write strategy is similar to the read strategy that I will not go over it here. The working code is located on the [on github][protocol-branch], so please use that as a reference for the write strategy if you are curious. Having a basic protocol like this is exiciting as it will set us up to handle sending or receiving json, xml or other data format later on.

## Related

   * [Creating A Multi-echo Server using Rust and mio][related post]


[chunked transfer encoding]: https://en.wikipedia.org/wiki/Chunked_transfer_encoding
[capnproto]: https://capnproto.org/
[previous post on WouldBlock]: /2015/07/12/my-basic-understanding-of-mio-and-async-io.html#i-would-block-you
[mio-try_read]: https://github.com/carllerche/mio/blob/272fb3d06e8f7134c9611e1877b3ff71642ced67/src/io.rs#L57
[byteorder]: https://crates.io/crates/byteorder
[UFCS]: https://doc.rust-lang.org/book/ufcs.html
[protocol-branch]: https://github.com/hjr3/mob/tree/protocol-blog-post
[related post]: /2015/07/12/my-basic-understanding-of-mio-and-async-io.html

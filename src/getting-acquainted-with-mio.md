---
layout: post
title: "Getting Acquainted with MIO"
author: "Andrew Hobden"
tags:
 - Raft
 - Rust
 - CSC466
 - CSC462
---

One of my next goals in my [Raft](http://hoverbear.org/tag/raft/) project is to tame the `tick()` with [`mio`](https://github.com/carllerche/mio). In this post, we'll explore what it is, what it can do, and why it matters. First things first: What is MIO?

> MIO is a lightweight IO library for Rust with a focus on adding as little overhead as possible over the OS abstractions.

Now you're probably thinking... "So what? We have plenty of shiny stuff in the new `std::io`..." and you're right! But hold off on judgement until you read this:

> Features
>
> * Event loop backed by `epoll`, `kqueue`.
> * Zero allocations at runtime
> * Non-blocking TCP, UDP and Unix domain sockets
> * High performance timer system
> * Thread safe message channel for cross thread communication


Okay, here it's starting to get interesting. `epoll`, and `kqueue` are event notification interfaces available in Linux, and the BSDs (Darwin included). Zero allocations are great for performance, and non-blocking sockets are insanely useful for network applications.

For a Raft context, the ability to use evented timers is applicable for heartbeats and election timings.

If you've used `node.js`, `io.js`, or Python's Twisted framework event loops might be familiar to you. *Yes I know callback hell sucks!* Fear not, this is Rust, not some scruffy loosely-typed, garbage-collected, non-blocking language!

## The General Idea

MIO works off this general concept:

* Make a thread for the `EventLoop`.
* Register interest with `IOHandle`s.
* Supply the loop with a `Handler`.
* Run your code.

## Hello, World

The following program is a nice, simple example of what MIO looks like:

    extern crate mio;
    use mio::*;
    use std::fmt::Debug;

    fn main() {
        // Create an event loop
        let mut event_loop = EventLoop::<(), String>::new().unwrap();
        let sender = event_loop.channel();
        sender.send("Hello".to_string()).unwrap();
        // Start it
        event_loop.run(&mut BearHandler).unwrap();
    }

    struct BearHandler;

    impl<T, M: Send + Debug> Handler<T, M> for BearHandler {
        /// A message has been delivered
        fn notify(&mut self, _reactor: &mut EventLoop<T, M>, msg: M) {
            println!("{:?}", msg);
        }
    }

A **lot** is going on here. Let's take a closer look.

    EventLoop::<(), String>::new();

This creates a new `EventLoop`. The Event loop uses `T` tokens of type `()`, and channels that consume and pass `M: Send` of type `String`. You can use anything that implements `Send` for messages.

	event_loop.channel();

This gives us a channel to send `String`s. When we `send()` later our `BearHandler` wakes up and invokes `notify`.

From there, `notify` prints out the message. In a real application, this is where your business logic would be to determine what to do with the message.

## Getting a Handle(r)

A Handler can implement some or all of the following functions:

    pub trait Handler<T: Token, M: Send> {
        /// A registered IoHandle has available data to read
        fn readable(&mut self, reactor: &mut EventLoop<T, M>, hint: ReadHint, token: T);
        /// A registered IoHandle is available to write to
        fn writable(&mut self, reactor: &mut EventLoop<T, M>, token: T);
        /// A registered timer has expired
        fn timeout(&mut self, reactor: &mut EventLoop<T, M>, token: T);
        /// A message has been delivered
        fn notify(&mut self, reactor: &mut EventLoop<T, M>, msg: M);
        /// A signal has been delivered to the process
        fn signal(&mut self, reactor: &mut EventLoop<T, M>, info: mio::SigInfo);
    }

So this is a lot more then just sending some `String`s around! Did you doubt me?

What's really cool is your `Handler` can have a data backing since it's just a trait that you can implement yourself! Let's do that now:

    extern crate mio;
    use mio::*;

    fn main() {
        // Create an event loop
        let mut event_loop = EventLoop::<(), u64>::new().unwrap();
        let sender = event_loop.channel();
        for i in 0.. 5 {
            sender.send(i).unwrap();
        }
        // Start it
        event_loop.run(&mut BearHandler(0)).unwrap();
    }

    struct BearHandler(u64);

    impl<T> Handler<T, u64> for BearHandler {
        fn notify(&mut self, _reactor: &mut EventLoop<T, u64>, msg: u64) {
            self.0 += msg;
            println!("Message: {}, Total: {}", msg, self.0);
        }
    }

Output:

    Message: 0, Total: 0
    Message: 1, Total: 1
    Message: 2, Total: 3
    Message: 3, Total: 6
    Message: 4, Total: 10

In this case, our `BearHandler` was a humble `u64` tuple which we mutated, but you could easily make this a more complicated `struct`.

## Registered Interest

Just sending messages isn't particularly interesting, let's wire up some new interests.

Alright, so let's take our humble little `BearHandler` and build it into a bit of a state mutation game:

* Each time a timer fire (every 250ms) send a UDP packet to some socket.
* Each time that socket gets hit decrement a `count` by 1.
* Each time on the channel increment it by that much.

First, we'll modify the `BearHandler` to reflect these changes. First, we'll make it a proper `struct` and let it store a pair of sockets as well as it's `count`.

Second, we'll implement the `readable`, `timeout`, and `notify`. Note in the `readable` we take care to drain the socket. Also, note how the `timeout` doesn't need to reset itself, we can clear it with [`clear_timeout`](https://carllerche.github.io/mio/mio/struct.EventLoop.html#method.clear_timeout) if we want.

    impl Handler<Token, u64> for BearHandler {
        fn readable(&mut self, _reactor: &mut EventLoop<Token, u64>, _token: Token, _hint: ReadHint) {
            let mut buffer = buf::RingBuf::new(1024);
            // Drain socket, otherwise infinite loop!
            net::TryRecv::recv_from(&self.listener, &mut buffer.writer()).unwrap();
            self.count -= 1;
            println!("Decremented, Total: {}", self.count);
        }
        fn timeout(&mut self, reactor: &mut EventLoop<Token, u64>, _token: Token) {
            self.sender.send_to(&[0], "127.0.0.1:12345").unwrap();
            // Reset
            reactor.timeout(TIMEOUT, Duration::milliseconds(250)).unwrap();
            println!("Timeout");
        }

        fn notify(&mut self, _reactor: &mut EventLoop<Token, u64>, msg: u64) {
            self.count += msg;
            println!("Increment by: {}, Total: {}", msg, self.count);
        }
    }

Next, registering the various events, we'll use some of MIO's `mio::net` items:

    const LISTENER: Token = Token(0);
    const TIMEOUT:  Token = Token(1);
    fn main() {
        // Create an event loop
        let mut event_loop = EventLoop::<Token, u64>::new().unwrap();
        // Register Interest
        let listener = UdpSocket::bind("127.0.0.1:12345").unwrap();
        event_loop.register(&listener, LISTENER).unwrap(); // Token lets us distinguish.
        // Increments
        let incrementer = event_loop.channel();
        for i in 0.. 5 {
            incrementer.send(i).unwrap();
        }
        // Decrements
        event_loop.timeout(TIMEOUT, Duration::milliseconds(250)).unwrap();
        // Start it
        let sender = UdpSocket::bind("127.0.0.1:12346").unwrap();
        event_loop.run(&mut BearHandler {
            count: 0,
            listener: listener,
            sender: sender
        }).unwrap();
    }

Output:

    Increment by: 0, Total: 0
    Increment by: 1, Total: 1
    Increment by: 2, Total: 3
    Increment by: 3, Total: 6
    Increment by: 4, Total: 10
    Timeout
    Decremented, Total: 9
    Timeout
    Decremented, Total: 8
    Timeout
    Decremented, Total: 7
    Timeout
    Decremented, Total: 6
    Timeout
    Decremented, Total: 5
    Timeout
    Decremented, Total: 4
    Timeout
    Decremented, Total: 3
    Timeout
    Decremented, Total: 2
    Timeout
    Decremented, Total: 1
    Timeout
    Decremented, Total: 0


> By the way, in our examples MIO will take over the main thread and block. In a normal application you'll want to kick it off into a new thread when you `start()` it.

## Learn More

* I found Wycats' [`mio-book`](https://github.com/wycats/mio-book) repo very useful.
* As always, the [docs](https://carllerche.github.io/mio/mio/index.html) were a great help.
* This post is [**discussed on Reddit**](https://www.reddit.com/r/rust/comments/2xvtll/getting_acquainted_with_mio/).
* This post is also [**discussed on Hacker News**](https://news.ycombinator.com/item?id=9143255)!

## Help Out!

We're tracking progress on integrating MIO into Raft with [this issue](https://github.com/Hoverbear/raft/issues/6). Feel free to weigh in or help out!

> A **huge** thanks to [**@danburkert**](https://github.com/Hoverbear/raft/commits/master?author=danburkert) for their contributions this week!

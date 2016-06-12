---
layout: default
title: Some notes on Send and Sync
description: >
    The `Send` and `Sync` traits in Rust are cool, here are two edge-ish cases.
comments:
    users: "http://users.rust-lang.org/t/some-notes-on-send-and-sync/400"
    r_rust: "http://www.reddit.com/r/rust/comments/2wjwcl/some_notes_on_send_and_sync/"
---

If you've been in the `#rust-internals` IRC channel recently, you
may've caught a madman raving about how much they like Rust:

{% highlight irc linenos %}
...
[15:50:03] <huon> I love this language
...
[20:02:07] <huon> did you know: Rust is awesome.
...
{% endhighlight %}

I was (and still am) losing my mind over how well `Sync` and `Send`
interact with everything, especially now that
[the implementation](https://github.com/rust-lang/rust/pull/22319) for
[RFC 458](https://github.com/rust-lang/rfcs/pull/458) has landed.

I'm aiming to write down a few edge cases and slight subtleties here
that Aaron Turon, Niko Matsakis and I have realised; so that we (and
others) don't have to keep rediscovering them. So, unfortunately, this
short(ish) article isn't aiming to describe entirely why I'm so keen
on them, but...

## The traits

... I'm sure I can write something.

Rust aims to be a language with really good support for concurrency;
and there's two parts to it: ownership & lifetimes, and the traits
[`Send`][send] & [`Sync`][sync] (the docs for these aren't great at
the moment, especially since the latest set of improvements landed so
recently).

[send]: http://doc.rust-lang.org/nightly/std/marker/trait.Send.html
[sync]: http://doc.rust-lang.org/nightly/std/marker/trait.Sync.html

These traits capture and control the two most common ways a piece of
data be accessed and thrown around by threads, dictating whether it is
safe to transfer ownership or pass a reference into another
thread.

The traits are "marker traits", meaning they have no methods and don't
inherently provide any functionality. They serve as markers of certain
invariants that types implementing them are expected to fulfill
(they're `unsafe` to implement manually for this reason: the
programmer has to ensure the invariants are upheld). Specifically, the
working definitions we have from them now are:

- If `T: Send`, then passing by-value a value of type `T` into
  another thread will not lead to data races (or other unsafety)
- If `T: Sync`, then passing a reference `&T` to a value of type `T`
  into another thread will not lead to data races (or other unsafety)
  (aka, `T: Sync` implies `&T: Send`)

That is, `Sync` is related to how a type works when shared across
multiple threads at once, and `Send` talks about how a type behaves as
it crosses a task boundary. (These definitions are pretty vague, but
the core team is definitely very interested in firming up and
formalising them to be able to prove useful concrete things.)

These two traits enable a lot of useful concurrency and parallel
patterns to be expressed while guaranteeing memory safety. Basic
examples include message passing and shared memory, both immutable &
mutable (e.g. with enforced atomic instructions, or protected by
locks). But more advanced things are easily possible too, with safety
falling automatically out of the type system and the design of the
standard library, e.g. manipulating (reading and writing) data stored
directly on another thread's stack and mutating disjoint pieces of a
vector in parallel with no locking necessary.

(It's worth mentioning that Rust only guarantees memory safety and,
particularly, freedom from data races, it doesn't guarantee freedom
from other concurrence/parallelism issues, such as dead locks, and
non-data-race race conditions.)

I have a very basic little library, [`simple_parallel`][sp-docs]
([source][sp-source]), that is trying to experiment with these
ideas. The examples there show off a few of the things mentioned
above, and compile today. I think its pretty cool what Rust can do.

[sp-docs]: http://huonw.github.io/simple_parallel/simple_parallel/
[sp-source]: https://github.com/huonw/simple_parallel

Anyway, there'll probably be lots more said about this later by me and
by others. Now, I'll stop distracting myself and get on to the actual
notes I wanted to write down.

## `Sync + Copy` ⇒ `Send`

That is, if a type `T` implements both `Sync` and `Copy`, then it can
also implement `Send` (conversely, a type is only allowed to be both
`Sync` and `Copy` if it is also `Send`).

Proof:
{% highlight rust linenos %}
// we start with some `T` on the main thread
let x: T = ...;

thread::scoped(|| {
    // and transfer a reference to a subthread (safe, since T: Sync)
    let y: &T = &x;

    // now use `T: Copy` to duplicate the data out, meaning we've
    // transferred `x` by-value into this new thread
    let z: T = *y;

})
{% endhighlight %}

The transfer happened only using `Sync + Copy` and so must be safe (if
it wasn't safe `T` isn't allowed to implement `Sync`), hence it is
legal for `T` to implement `Send`.

This might not seem so interesting, since it *is* just a specific case
of the definition of `Sync` ("can copy out of `&`" is a fundamental
property of our `T: Copy` type, and so has to be considered when
considering the thread safety of `&T`), but it is a little
subtle.

Also, needing to consider this case at all probably won't come up for
many types; one is most likely to encounter types that are not `Send`
when storing pointers to shared memory&mdash;such as `Rc`&mdash;and
most such types are not `Copy` since they have to manage their
memory&mdash;such as `Rc` again. The two most prominent examples are
`&` (which has safety ensured by `Sync` and static analysis in the
compiler: lifetimes) and a hypothetical `Gc<T>` pointer. I guess we'll
just have to take care for `Gc`.

## `&mut T: Send` when `T: Send`

We want to work out when it is safe to transfer a mutable reference
`&mut T` between threads. For the shared reference `&T` it is easy:
replacing `&T` with `U` in the definition of `Sync` gives the
definition of `Send` (up to alpha renaming), so `&T: Send` when `T:
Sync`, which can be
[expressed in code](https://github.com/rust-lang/rust/blob/522d09dfecbeca1595f25ac58c6d0178bbd21d7d/src/libcore/marker.rs#L388)
as

{% highlight rust linenos %}
unsafe impl<'a, T: Sync> Send for &'a T {
{% endhighlight %}

For `&mut`, you might suspect that thread-safety might depend on
`Sync` in some way since that trait is so important for the other
reference type, but, you'd be wrong. It is another example of the
dramatic semantic difference between `&mut` and `&` despite the
syntactic similarities.

The mutable reference type has the guarantee that it is globally
unaliased, so if a thread has access to a piece of data via a `&mut`,
then it is the only thread in the whole program that can legally read
from/write to that data. In particular, there's no sharing and there
cannot be several threads concurrently accessing that memory at the
same time, hence the sharing-related guarantees of `Sync` don't
guarantee thread-safety for `&mut`. (RFC 458 describes this as `&mut`
linearizing access to its contents.)

Thinking about this, it seems like transferring a `&mut T` between
threads might *almost* be safe for any `T`. The thinking might be that
`Send` describes "passing by-value" between threads, and this passing
changes fundamental properties of the program, such as where/when
destructors are run; on the other hand, passing a `&mut T` is passing
by reference so doesn't change such things, and a `&mut` has unique
access, so the whole set-up is basically the same as running on the
original thread. For example, passing a `&mut T` around doesn't change
where/when the destructor of the `T` is run: it is still run when it
goes out of scope, on the main thread.

Unfortunately...

{% highlight rust linenos %}
// we start with some `T` on the main thread
let x: T = ...;
// wrap it up
let mut packet: Option<T> = Some(x);

thread::scoped(|| {
    // and transfer just a mutable reference to the other thread
    let y: &mut Option<T> = &mut packet;

    // and then steal the `T` out!
    let z: T = y.take().unwrap();
})
{% endhighlight %}

That code transfers the `T` between two threads by just transferring a
`&mut Option<T>`. Hence, if it is illegal to transfer a `T` between
threads, by-value, it must also be illegal to transfer `&mut
Option<T>` because we can use that to construct a `T` transfer. In
pseudo-code, if `T: !Send`, then `&mut Option<T>: !Send` (using
"negative bounds", meaning `T` does not implement `Send`).

Of course, this isn't a failing of `Option` itself, its just a type
that makes for a direct example. One could also create one `T` in each
thread, and use `std::mem::swap` to exchange their places, causing
both `T`s to transfer by-value between threads (double the
unsafety!!).

The general rule is that transferring a `&mut T` between threads is
guaranteed to be safe if `T: Send`, so `&mut T` behaves *very* much
like `T` with relation to concurrency. (It is *theoretically* possible
to have types for which sending a `&mut T` is safe, but sending a
plain `T` is not, meaning `&mut T: Send` but not `T: Send`, so the
relationship is not "if and only if", as wrongerontheinternet pointed
out on /r/rust.)

{% include comments.html c=page.comments %}

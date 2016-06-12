---
layout: post
title: "Fearless Concurrency with Rust"
author: Aaron Turon
description: "Rust's vision for concurrency"
---

The Rust project was initiated to solve two thorny problems:

* How do you do safe systems programming?
* How do you make concurrency painless?

Initially these problems seemed orthogonal, but to our amazement, the
solution turned out to be identical: **the same tools that make Rust
safe also help you tackle concurrency head-on**.

Memory safety bugs and concurrency bugs often come down to code
accessing data when it shouldn't. Rust's secret weapon is *ownership*,
a discipline for access control that systems programmers try to
follow, but that Rust's compiler checks statically for you.

For memory safety, this means you can program without a garbage
collector *and* without fear of segfaults, because Rust will catch
your mistakes.

For concurrency, this means you can choose from a wide variety of
paradigms (message passing, shared state, lock-free, purely
functional), and Rust will help you avoid common pitfalls.

Here's a taste of concurrency in Rust:

* A [channel][mpsc] transfers ownership of the messages sent along it,
  so you can send a pointer from one thread to another without fear of
  the threads later racing for access through that pointer. **Rust's
  channels enforce thread isolation.**

* A [lock][mutex] knows what data it protects, and Rust guarantees
  that the data can only be accessed when the lock is held. State is
  never accidentally shared. **"Lock data, not code" is enforced in
  Rust.**

* Every data type knows whether it can safely be [sent][send] between
  or [accessed][sync] by multiple threads, and Rust enforces this safe
  usage; there are no data races, even for lock-free data structures.
  **Thread safety isn't just documentation; it's law.**

* You can even [share stack frames][scoped] between threads, and Rust
  will statically ensure that the frames remain active while other
  threads are using them. **Even the most daring forms of sharing are
  guaranteed safe in Rust**.

All of these benefits come out of Rust's ownership model, and in fact
locks, channels, lock-free data structures and so on are defined in
libraries, not the core language. That means that Rust's approach to
concurrency is *open ended*: new libraries can embrace new paradigms
and catch new bugs, just by adding APIs that use Rust's ownership
features.

The goal of this post is to give you some idea of how that's done.

### Background: ownership

> We'll start with an overview of Rust's ownership and borrowing
systems. If you're already familiar with these, you can skip the two
"background" sections and jump straight into concurrency. If you want
a deeper introduction, I can't recommend
[Yehuda Katz's post](http://blog.skylight.io/rust-means-never-having-to-close-a-socket/)
highly enough. And
[the Rust book](http://doc.rust-lang.org/book/ownership.html) has all
the details.

In Rust, every value has an "owning scope," and passing or returning a
value means transferring ownership ("moving" it) to a new
scope. Values that are still owned when a scope ends are automatically
destroyed at that point.

Let's look at some simple examples. Suppose we create a vector and
push some elements onto it:

~~~~rust
fn make_vec() {
    let mut vec = Vec::new(); // owned by make_vec's scope
    vec.push(0);
    vec.push(1);
    // scope ends, `vec` is destroyed
}
~~~~

The scope that creates a value also initially owns it. In this case,
the body of `make_vec` is the owning scope for `vec`. The owner can do
anything it likes with `vec`, including mutating it by pushing. At the
end of the scope, `vec` is still owned, so it is automatically
deallocated.

Things get more interesting if the vector is returned or passed around:

~~~~rust
fn make_vec() -> Vec<i32> {
    let mut vec = Vec::new();
    vec.push(0);
    vec.push(1);
    vec // transfer ownership to the caller
}

fn print_vec(vec: Vec<i32>) {
    // the `vec` parameter is part of this scope, so it's owned by `print_vec`

    for i in vec.iter() {
        println!("{}", i)
    }

    // now, `vec` is deallocated
}

fn use_vec() {
    let vec = make_vec(); // take ownership of the vector
    print_vec(vec);       // pass ownership to `print_vec`
}
~~~~

Now, just before `make_vec`'s scope ends, `vec` is moved out by
returning it; it is not destroyed. A caller like `use_vec` then
receives ownership of the vector.

On the other hand, the `print_vec` function takes a `vec` parameter,
and ownership of the vector is transferred *to* it by its
caller. Since `print_vec` does not transfer the ownership any further,
at the end of its scope the vector is destroyed.

Once ownership has been given away, a value can no longer be used. For
example, consider this variant of `use_vec`:

~~~~rust
fn use_vec() {
    let vec = make_vec();  // take ownership of the vector
    print_vec(vec);        // pass ownership to `print_vec`

    for i in vec.iter() {  // continue using `vec`
        println!("{}", i * 2)
    }
}
~~~~

If you feed this version to the compiler, you'll get an  error:

~~~~
error: use of moved value: `vec`

for i in vec.iter() {
         ^~~
~~~~

The compiler is saying `vec` is no longer available; ownership has
been transferred elsewhere. And that's very good, because the vector
has already been deallocated at this point!

Disaster averted.

### Background: borrowing

The story so far isn't totally satisfying, because it's not our intent
for `print_vec` to destroy the vector it was given. What we really
want is to grant `print_vec` *temporary* access to the vector, and
then continue using the vector afterwards.

This is where *borrowing* comes in. If you have access to a value in
Rust, you can lend out that access to the functions you call. **Rust
will check that these leases do not outlive the object being
borrowed**.

To borrow a value, you make a *reference* to it (a kind of pointer),
using the `&` operator:

~~~~rust
fn print_vec(vec: &Vec<i32>) {
    // the `vec` parameter is borrowed for this scope

    for i in vec.iter() {
        println!("{}", i)
    }

    // now, the borrow ends
}

fn use_vec() {
    let vec = make_vec();  // take ownership of the vector
    print_vec(&vec);       // lend access to `print_vec`
    for i in vec.iter() {  // continue using `vec`
        println!("{}", i * 2)
    }
    // vec is destroyed here
}
~~~~

Now `print_vec` takes a reference to a vector, and `use_vec` lends out
the vector by writing `&vec`. Since borrows are temporary, `use_vec`
retains ownership of the vector; it can continue using it after the
call to `print_vec` returns (and its lease on `vec` has expired).

Each reference is valid for a limited scope, which the compiler will
automatically determine. References come in two flavors:

* Immutable references `&T`, which allow sharing but not mutation.
  There can be multiple `&T` references to the same value
  simultaneously, but the value cannot be mutated while those
  references are active.

* Mutable references `&mut T`, which allow mutation but not sharing.
  If there is an `&mut T` reference to a value, there can be no other
  active references at that time, but the value can be mutated.

Rust checks these rules at compile time; borrowing has no runtime
overhead.

Why have two kinds of references? Consider a function like:

~~~~rust
fn push_all(from: &Vec<i32>, to: &mut Vec<i32>) {
    for i in from.iter() {
        to.push(*i);
    }
}
~~~~

This function iterates over each element of one vector, pushing it
onto another. The iterator keeps a pointer into the vector at the
current and final positions, stepping one toward the other.

What if we called this function with the same vector for both arguments?

~~~~rust
push_all(&vec, &mut vec)
~~~~

This would spell disaster! As we're pushing elements onto the vector,
it will occasionally need to resize, allocating a new hunk of memory
and copying its elements over to it. The iterator would be left with a
dangling pointer into the old memory, leading to memory unsafety (with
attendant segfaults or worse).

Fortunately, Rust ensures that **whenever a mutable borrow is active,
no other borrows of the object are active**, producing the message:

~~~~
error: cannot borrow `vec` as mutable because it is also borrowed as immutable
push_all(&vec, &mut vec);
                    ^~~
~~~~

Disaster averted.

### Message passing

Now that we've covered the basic ownership story in Rust, let's see
what it means for concurrency.

Concurrent programming comes in many styles, but a particularly simple
one is message passing, where threads or actors communicate by sending
each other messages.  Proponents of the style emphasize the way that
it ties together sharing and communication:

> Do not communicate by sharing memory; instead, share memory by
> communicating.
>
> --[Effective Go](http://golang.org/doc/effective_go.html)

**Rust's ownership makes it easy to turn that advice into a
compiler-checked rule**. Consider the following channel API
([channels in Rust's standard library][mpsc] are a bit different):

~~~~rust
fn send<T: Send>(chan: &Channel<T>, t: T);
fn recv<T: Send>(chan: &Channel<T>) -> T;
~~~~

Channels are generic over the type of data they transmit (the `<T:
Send>` part of the API). The `Send` part means that `T` must be
considered safe to send between threads; we'll come back to that later
in the post, but for now it's enough to know that `Vec<i32>` is
`Send`.

As always in Rust, passing in a `T` to the `send` function means
transferring ownership of it. This fact has profound consequences: it
means that code like the following will generate a compiler error.

~~~~rust
// Suppose chan: Channel<Vec<i32>>

let mut vec = Vec::new();
// do some computation
send(&chan, vec);
print_vec(&vec);
~~~~

Here, the thread creates a vector, sends it to another thread, and
then continues using it. The thread receiving the vector could mutate
it as this thread continues running, so the call to `print_vec` could
lead to race condition or, for that matter, a use-after-free bug.

Instead, the Rust compiler will produce an error message on the call
to `print_vec`:

~~~~
Error: use of moved value `vec`
~~~~

Disaster averted.

### Locks

Another way to deal with concurrency is by having threads communicate
through passive, shared state.

Shared-state concurrency has a bad rap. It's easy to forget to acquire
a lock, or otherwise mutate the wrong data at the wrong time, with
disastrous results -- so easy that many eschew the style altogether.

Rust's take is that:

1. Shared-state concurrency is nevertheless a fundamental programming
style, needed for systems code, for maximal performance, and for
implementing other styles of concurrency.

2. The problem is really about *accidentally* shared state.

Rust aims to give you the tools to conquer shared-state concurrency
directly, whether you're using locking or lock-free techniques.

In Rust, threads are "isolated" from each other automatically, due to
ownership. Writes can only happen when the thread has mutable access,
either by owning the data, or by having a mutable borrow of it. Either
way, **the thread is guaranteed to be the only one with access at the
time**.  To see how this plays out, let's look at locks.

Remember that mutable borrows cannot occur simultaneously with other
borrows. Locks provide the same guarantee ("mutual exclusion") through
synchronization at runtime. That leads to a locking API that hooks
directly into Rust's ownership system.

Here is a simplified version (the [standard library's][mutex]
is more ergonomic):

~~~~rust
// create a new mutex
fn mutex<T: Send>(t: T) -> Mutex<T>;

// acquire the lock
fn lock<T: Send>(mutex: &Mutex<T>) -> MutexGuard<T>;

// access the data protected by the lock
fn access<T: Send>(guard: &mut MutexGuard<T>) -> &mut T;
~~~~

This lock API is unusual in several respects.

First, the `Mutex` type is generic over a type `T` of **the data
protected by the lock**. When you create a `Mutex`, you transfer
ownership of that data *into* the mutex, immediately giving up access
to it. (Locks are unlocked when they are first created.)

Later, you can `lock` to block the thread until the lock is
acquired. This function, too, is unusual in providing a return value,
`MutexGuard<T>`. The `MutexGuard` automatically releases the lock when
it is destroyed; there is no separate `unlock` function.

The only way to access the lock is through the `access` function,
which turns a mutable borrow of the guard into a mutable borrow of the
data (with a shorter lease):

~~~~rust
fn use_lock(mutex: &Mutex<Vec<i32>>) {
    // acquire the lock, taking ownership of a guard;
    // the lock is held for the rest of the scope
    let mut guard = lock(mutex);

    // access the data by mutably borrowing the guard
    let vec = access(&mut guard);

    // vec has type `&mut Vec<i32>`
    vec.push(3);

    // lock automatically released here, when `guard` is destroyed
}
~~~~

There are two key ingredients here:

* The mutable reference returned by `access` cannot outlive the
  `MutexGuard` it is borrowing from.

* The lock is only released when the `MutexGuard` is destroyed.

The result is that **Rust enforces locking discipline: it will not let
you access lock-protected data except when holding the lock**. Any
attempt to do otherwise will generate a compiler error. For example,
consider the following buggy "refactoring":

~~~~rust
fn use_lock(mutex: &Mutex<Vec<i32>>) {
    let vec = {
        // acquire the lock
        let mut guard = lock(mutex);

        // attempt to return a borrow of the data
        access(&mut guard)

        // guard is destroyed here, releasing the lock
    };

    // attempt to access the data outside of the lock.
    vec.push(3);
}
~~~~

Rust will generate an error pinpointing the problem:

~~~~
error: `guard` does not live long enough
access(&mut guard)
            ^~~~~
~~~~

Disaster averted.

### Thread safety and "Send"

It's typical to distinguish some data types as "thread safe" and
others not. Thread safe data structures use enough internal
synchronization to be safely used by multiple threads concurrently.

For example, Rust ships with two kinds of "smart pointers" for
reference counting:

* `Rc<T>` provides reference counting via normal reads/writes. It is
  not thread safe.

* `Arc<T>` provides reference counting via *atomic* operations. It is
  thread safe.

The hardware atomic operations used by `Arc` are more expensive than
the vanilla operations used by `Rc`, so it's advantageous to use `Rc`
rather than `Arc`. On the other hand, it's critical that an `Rc<T>`
never migrate from one thread to another, because that could lead to
race conditions that corrupt the count.

Usually, the only recourse is careful documentation; most languages
make no *semantic* distinction between thread-safe and thread-unsafe
types.

In Rust, the world is divided into two kinds of data types: those that
are [`Send`][send], meaning they can be safely moved from one thread to
another, and those that are `!Send`, meaning that it may not be safe
to do so. If all of a type's components are `Send`, so is that type --
which covers most types. Certain base types are not inherently
thread-safe, though, so it's also possible to explicitly mark a type
like `Arc` as `Send`, saying to the compiler: "Trust me; I've verified
the necessary synchronization here."

Naturally, `Arc` is `Send`, and `Rc` is not.

We already saw that the `Channel` and `Mutex` APIs work only with
`Send` data. Since they are the point at which data crosses thread
boundaries, they are also the point of enforcement for `Send`.

Putting this all together, Rust programmers can reap the benefits of
`Rc` and other thread-*unsafe* types with confidence, knowing that if
they ever do accidentally try to send one to another thread, the Rust
compiler will say:

~~~~
`Rc<Vec<i32>>` cannot be sent between threads safely
~~~~

Disaster averted.

### Sharing the stack: "scoped"

_Note: The API mentioned here is an old one which has been moved out of
the standard library. You can find equivalent functionality in
[`crossbeam`][crossbeam-crate] ([documentation for `scope()`][crossbeam-doc])
and [`scoped_threadpool`][scoped-threadpool-crate]
([documentation for `scoped()`][scoped-threadpool-doc])_

So far, all the patterns we've seen involve creating data structures
on the heap that get shared between threads. But what if we wanted to
start some threads that make use of data living in our stack frame?
That could be dangerous:

~~~~rust
fn parent() {
    let mut vec = Vec::new();
    // fill the vector
    thread::spawn(|| {
        print_vec(&vec)
    })
}
~~~~

The child thread takes a reference to `vec`, which in turn resides in
the stack frame of `parent`. When `parent` exits, the stack frame is
popped, but the child thread is none the wiser. Oops!

To rule out such memory unsafety, Rust's basic thread spawning API
looks a bit like this:

~~~~rust
fn spawn<F>(f: F) where F: 'static, ...
~~~~

The `'static` constraint is a way of saying, roughly, that no borrowed
data is permitted in the closure.  It means that a function like
`parent` above will generate an error:

~~~~
error: `vec` does not live long enough
~~~~

essentially catching the possibility of `parent`'s stack frame
popping. Disaster averted.

But there is another way to guarantee safety: ensure that the parent
stack frame stays put until the child thread is done. This is the
pattern of *fork-join* programming, often used for divide-and-conquer
parallel algorithms. Rust supports it by providing a
["scoped"][scoped] variant of thread spawning:

~~~~rust
fn scoped<'a, F>(f: F) -> JoinGuard<'a> where F: 'a, ...
~~~~

There are two key differences from the `spawn` API above:

* The use a parameter `'a`, rather than `'static`. This parameter
  represents a scope that encompasses all the borrows within the
  closure, `f`.

* The return value, a `JoinGuard`. As its name suggests, `JoinGuard`
  ensures that the parent thread joins (waits on) its child, by
  performing an implicit join in its destructor (if one hasn't happened
  explicitly already).

Including `'a` in `JoinGuard` ensures that the `JoinGuard` **cannot
escape the scope of any data borrowed by the closure**.  In other
words, Rust guarantees that the parent thread waits for the child to
finish before popping any stack frames the child might have access to.

Thus by adjusting our previous example, we can fix the bug and satisfy
the compiler:

~~~~rust
fn parent() {
    let mut vec = Vec::new();
    // fill the vector
    let guard = thread::scoped(|| {
        print_vec(&vec)
    });
    // guard destroyed here, implicitly joining
}
~~~~

So in Rust, you can freely borrow stack data into child threads,
confident that the compiler will check for sufficient synchronization.

### Data races

At this point, we've seen enough to venture a strong statement about
Rust's approach to concurrency: **the compiler prevents all *data races*.**

> A data race is any unsynchronized, concurrent access to data
> involving a write.

Synchronization here includes things as low-level as atomic
instructions. Essentially, this is a way of saying that you cannot
accidentally "share state" between threads; all (mutating) access to
state has to be mediated by *some* form of synchronization.

Data races are just one (very important) kind of race condition, but
by preventing them, Rust often helps you prevent other, more subtle
races as well. For example, it's often important that updates to
different locations appear to take place *atomically*: other threads
see either all of the updates, or none of them. In Rust, having `&mut`
access to the relevant locations at the same time **guarantees
atomicity of updates to them**, since no other thread could possibly
have concurrent read access.

It's worth pausing for a moment to think about this guarantee in the
broader landscape of languages. Many languages provide memory safety
through garbage collection. But garbage collection doesn't give you
any help in preventing data races.

Rust instead uses ownership and borrowing to provide its two key value
propositions:

* Memory safety without garbage collection.
* Concurrency without data races.

### The future

When Rust first began, it baked channels directly into the language,
taking a very opinionated stance on concurrency.

In today's Rust, concurrency is *entirely* a library affair;
everything described in this post, including `Send`, is defined in the
standard library, and could be defined in an external library instead.

And that's very exciting, because it means that Rust's concurrency
story can endlessly evolve, growing to encompass new paradigms and
catch new classes of bugs. Libraries like [syncbox][syncbox] and
[simple_parallel][simple_parallel] are taking some of the first steps,
and we expect to invest heavily in this space in the next few
months. Stay tuned!

[mpsc]: http://static.rust-lang.org/doc/master/std/sync/mpsc/index.html
[mutex]: http://static.rust-lang.org/doc/master/std/sync/struct.Mutex.html
[send]: http://static.rust-lang.org/doc/master/std/marker/trait.Send.html
[sync]: http://static.rust-lang.org/doc/master/std/marker/trait.Sync.html
[scoped]: http://static.rust-lang.org/doc/master/std/thread/fn.scoped.html
[syncbox]: https://github.com/carllerche/syncbox
[simple_parallel]: https://github.com/huonw/simple_parallel
[crossbeam-crate]: https://crates.io/crates/crossbeam
[crossbeam-doc]: http://aturon.github.io/crossbeam-doc/crossbeam/fn.scope.html
[scoped-threadpool-crate]: https://crates.io/crates/scoped_threadpool
[scoped-threadpool-doc]: http://kimundi.github.io/scoped-threadpool-rs/scoped_threadpool/index.html#examples:

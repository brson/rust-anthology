# How Rust Achieves Thread Safety

_In every talk I have given till now, the question "how does Rust achieve thread safety?"
has invariably come up[^1]. I usually just give an overview, but this provides a more comprehensive
explanation for those who are interested_

See also: [Huon's blog post on the same topic][huon-send]

[huon-send]: http://huonw.github.io/blog/2015/02/some-notes-on-send-and-sync/
[^1]: So much that I added bonus slides about thread safety to the end of my deck, and of course I ended up using them at the talk I gave recently

In my [previous post][post-prev] I touched a bit on the [`Copy`][copy] trait. There are other such
"marker" traits in the standard library, and the ones relevant to this discussion are [`Send`][send]
and [`Sync`][sync]. I recommend reading that post if you're not familiar with Rust wrapper types
like [`RefCell`][refcell] and [`Rc`][rc], since I'll be using them as examples throughout this post;
but the concepts explained here are largely independent.

For the purposes of this post, I'll restrict thread safety to mean no data races or cross-thread
dangling pointers. Rust doesn't aim to solve race conditions. However, there are projects which
utilize the type system to provide some form of extra safety, for example [rust-
sessions](https://github.com/Munksgaard/rust-sessions) attempts to provide protocol safety using
session types.

These traits are auto-implemented using a feature called "opt in builtin traits". So, for example,
if struct `Foo` contains only [`Sync`][sync] fields, it will also be [`Sync`][sync], unless we
explicitly opt out using `impl !Sync for Foo {}`. Similarly, if struct `Foo` contains at least one
non-[`Sync`][sync] type, it will not be [`Sync`][sync] either, unless it explicitly opts in (`unsafe
impl Sync for Foo {}`)

This means that, for example, a [`Sender`][sender] for a [`Send`][send] type is itself
[`Send`][send], but a [`Sender`][sender] for a non-`Send` type will not be [`Send`][send]. This
pattern is quite powerful; it lets one use channels with non-threadsafe data in a single-threaded
context without requiring a separate "single threaded" channel abstraction.

At the same time, structs like [`Rc`][rc] and [`RefCell`][refcell] which contain
[`Send`][send]/[`Sync`][sync] fields have explicitly opted out of one or more of these because the
invariants they rely on do not hold in threaded situations.

It's actually possible to design your own library with comparable thread safety guarantees outside
of the compiler &mdash; while these marker traits are specially treated by the compiler, the special
treatment is not necessary for their working. Any two opt-in builtin traits could be used here.

[post-prev]: http://manishearth.github.io/blog/2015/05/27/wrapper-types-in-rust-choosing-your-guarantees/
[send]: http://doc.rust-lang.org/std/marker/trait.Send.html
[sync]: http://doc.rust-lang.org/std/marker/trait.Sync.html
[copy]: http://doc.rust-lang.org/std/marker/trait.Copy.html

[`Send`][send] and [`Sync`][sync] have slightly differing meanings, but are very intertwined.

[`Send`][send] types can be moved between threads without an issue. It answers the question
"if this variable were moved to another thread, would it still be valid for use?".
Most objects which completely own their contained data qualify here. Notably, [`Rc`][rc] doesn't
(since it is shared ownership). Another exception is [`LocalKey`][localkey], which
_does_ own its data but isn't valid from other threads. Borrowed data does qualify to be `Send`, but
in most cases it can't be sent across threads due to a constraint that will be touched upon later.

Even though types like [`RefCell`][refcell] use non-atomic reference counting, it can be sent safely
between threads because this is a transfer of _ownership_ (a move). Sending a [`RefCell`][refcell] to another thread
will be a move and will make it unusable from the original thread; so this is fine.


[localkey]: https://doc.rust-lang.org/nightly/std/thread/struct.LocalKey.html


[`Sync`][sync], on the other hand, is about synchronous access. It answers the question: "if
multiple threads were all trying to access this data, would it be safe?". Types like
[`Mutex`][mutex] and other lock/atomic based types implement this, along with primitive types.
Things containing pointers generally are not [`Sync`][sync].

`Sync` is sort of a crutch to `Send`; it helps make other types [`Send`][send] when sharing is
involved. For example, `&T` and [`Arc<T>`][arc] are only [`Send`][send] when the inner data is [`Sync`][sync] (there's an additional
[`Send`][send] bound in the case of [`Arc<T>`][arc]). In words, stuff that has shared/borrowed ownership can be sent
to another thread if the shared/borrowed data is synchronous-safe.

[`RefCell`][refcell], while [`Send`][send], is not [`Sync`][sync] because of the non atomic reference counting.

Bringing it together, the gatekeeper for all this is [`thread::spawn()`][spawn]. It has the signature

```rust
pub fn spawn<F, T>(f: F) -> JoinHandle<T> where F: FnOnce() -> T, F: Send + 'static, T: Send + 'static
```

Admittedly, this is confusing/noisy, partially because it's allowed to return a value, and also because
it returns a handle from which we can block on a thread join. We can conjure a simpler `spawn` API for our needs though:


```rust
pub fn spawn<F>(f: F) where F: FnOnce(), F: Send + 'static
```

which can be called like:

```rust
let mut x = vec![1,2,3,4];

// `move` instructs the closure to move out of its environment
thread::spawn(move || {
   x.push(1);

});

// x is not accessible here since it was moved

```

In words, `spawn()` will take a callable (usually a closure) that will be called once, and contains
data which is [`Send`][send] and `'static`. Here, `'static` just means that there is no borrowed
data contained in the closure. This is the aforementioned constraint that prevents the sharing of
borrowed data across threads; without it we would be able to send a borrowed pointer to a thread that
could easily outlive the borrow, causing safety issues.

There's a slight nuance here about the closures &mdash; closures can capture outer variables,
but by default they do so by-reference (hence the `move` keyword). They autoimplement `Send`
and [`Sync`][sync] depending on their capture clauses. For more on their internal representation,
see [huon's post][huon-closure]. In this case, `x` was captured by-move; i.e. as [`Vec<T>`][vec]
(instead of being similar to `&Vec<T>` or something), so the closure itself can be `Send`.
Without the `move` keyword, the closure would not be `'static' since it contains borrowed
content.

Since the closure inherits the `Send`/`Sync`/`'static`-ness of its captured data, a closure
capturing data of the correct type will satisfy the `F: Send+'static` bound.

Some examples of things that are allowed and not allowed by this function (for the type of `x`):


 - [`Vec<T>`][vec], [`Box<T>`][box] are allowed because they are [`Send`][send] and `'static` (when the inner type is of the same kind)
 - `&T` isn't allowed because it's not `'static`. This is good, because borrows should have a statically-known lifetime. Sending a borrowed pointer to a thread may lead to a use after free, or otherwise break aliasing rules.
 - [`Rc<T>`][rc] isn't [`Send`][send], so it isn't allowed. We could have some other [`Rc<T>`][rc]s hanging around, and end up with a data race on the refcount.
 - `Arc<Vec<u32>>` is allowed ([`Vec<T>`][vec] is [`Send`][send] and [`Sync`][sync] if the inner type is); we can't cause a safety violation here. Iterator invalidation requires mutation, and [`Arc<T>`][arc] doesn't provide this by default.
 - `Arc<Cell<T>>` isn't allowed. [`Cell<T>`][cell] provides copying-based internal mutability, and isn't [`Sync`][sync] (so the `Arc<Cell<T>>` isn't [`Send`][send]). If this were allowed, we could have cases where larger structs are getting written to from different threads simultaneously resulting in some random mishmash of the two. In other words, a data race. 
 - `Arc<Mutex<T>>` or `Arc<RwLock<T>>` are allowed (for `Send` `T`). The inner types use threadsafe locks and provide lock-based internal mutability. They can guarantee that only one thread is writing to them at any point in time. For this reason, the mutexes are [`Sync`][sync] regardless of the inner `T` (as long as it is `Send`), and [`Sync`][sync] types can be shared safely with wrappers like [`Arc`][arc]. From the point of view of the inner type, it's only being accessed by one thread at a time (slightly more complex in the case of [`RwLock`][rwlock]), so it doesn't need to know about the threads involved. There can't be data races when `Sync` types like these are involved.


As mentioned before, you can in fact create a [`Sender`][sender]/[`Receiver`][receiver] pair of non-`Send` objects. This sounds a bit
counterintuitive &mdash; shouldn't we be only sending values which are `Send`? However, [`Sender<T>`][sender] is only
`Send` if `T` is `Send`; so even if we can use a [`Sender`][sender] of a non-`Send` type, we cannot send it to another thread,
so it cannot be used to violate thread safety.


There is also a way to utilize the `Send`-ness of `&T` (which is not `'static`) for some [`Sync`][sync] `T`, namely [`thread::scoped`][scoped].
This function does not have the `'static` bound, but it instead has an RAII guard which forces a join before the borrow ends. This
allows for easy fork-join parallelism without necessarily needing a [`Mutex`][mutex].
Sadly, there [are][peaches] [problems][more-peaches] which crop up when this interacts with [`Rc`][rc] cycles, so the API
is currently unstable and will be redesigned. This is not a problem with the language design or the design of `Send`/`Sync`,
rather it is a perfect storm of small design inconsistencies in the libraries.


<small>Discuss: [HN](https://news.ycombinator.com/item?id=9628131), [Reddit](https://www.reddit.com/r/rust/comments/37s5x2/how_rust_achieves_thread_safety/)</small>

[spawn]: http://doc.rust-lang.org/std/thread/fn.spawn.html
[huon-closure]: http://huonw.github.io/blog/2015/05/finding-closure-in-rust/
[scoped]: http://doc.rust-lang.org/std/thread/fn.scoped.html
[peaches]: http://cglab.ca/~abeinges/blah/everyone-peaches/
[more-peaches]: http://smallcultfollowing.com/babysteps/blog/2015/04/29/on-reference-counting-and-leaks/

[rc]: https://doc.rust-lang.org/std/rc/struct.Rc.html
[vec]: https://doc.rust-lang.org/std/vec/struct.Vec.html
[arc]: https://doc.rust-lang.org/std/sync/struct.Arc.html
[refcell]: https://doc.rust-lang.org/std/cell/struct.RefCell.html
[cell]: https://doc.rust-lang.org/std/cell/struct.Cell.html
[sender]: http://doc.rust-lang.org/std/sync/mpsc/struct.Sender.html
[receiver]: http://doc.rust-lang.org/std/sync/mpsc/struct.Receiver.html
[mutex]: http://doc.rust-lang.org/std/sync/struct.Mutex.html
[rwlock]: http://doc.rust-lang.org/std/sync/struct.RwLock.html
[box]: http://doc.rust-lang.org/std/boxed/struct.Box.html

> [_Originally published 2015-05-30_](https://manishearth.github.io/blog/2015/05/30/how-rust-achieves-thread-safety/)
>
> _License: TBD_

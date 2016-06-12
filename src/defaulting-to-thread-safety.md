---
layout: default
title: "Defaulting to Thread-Safety: Closures and Concurrency"

description: >
    Rust can model properties of aggregate types with certain trait
    tricks, which makes closures and concurrent APIs interact well.

comments:
    r_rust: "http://www.reddit.com/r/rust/comments/37e6w2/defaulting_to_threadsafety_closures_and/"
    users: "https://users.rust-lang.org/t/defaulting-to-thread-safety-closures-and-concurrency/1583"
---

Rust has some powerful tricks to model properties of aggregate types
via unsafe traits with default and negative implementations. These
features motivated by offering flexible concurrency/parallelism, and
allow powerful closure-based APIs without losing any thread-safety (or
memory-safety) guarantees at all.

I realised that [my recent post][closures] on the low-level details of
closures missed an important aspect: how they interact with
threading. This post builds on the struct desugaring in that one, the
general concepts in [*Fearless Concurrency with Rust*][fearless] and
the discussion of "markers" in
[*Abstraction without overhead*][abstraction]. (I suppose I should
link [*Some notes on Send and Sync*][snosas] too.)

[closures]: {% post_url 2015-05-08-finding-closure-in-rust %}
[fearless]: http://blog.rust-lang.org/2015/04/10/Fearless-Concurrency.html
[abstraction]: http://blog.rust-lang.org/2015/05/11/traits.html
[snosas]: {% post_url 2015-02-20-some-notes-on-send-and-sync %}

## Threads

Spawning a thread in Rust is easy:

{% highlight rust linenos %}
use std::thread;

fn main() {
    let s = "from the parent";
    thread::spawn(move || {
        println!("child prints a string {}", s);
    });

    thread::sleep_ms(10);
}
{% endhighlight %}

As one might hope, this prints `child prints a string from the
parent`. Like C, an binary exits once the main thread is finished, so
I've inserted a sleep to (usually) ensure that the child thread is
spawned and prints before the main thread dies. (It could also call
[`join`][join] on the return value of `spawn` to block, but there's an
example below that the `join` strategy complicates, so `sleep_ms` it
is.)

[join]: https://doc.rust-lang.org/std/thread/struct.JoinHandle.html#method.join

It's one of Rust's key guarantees that this is ensured to be
thread-safe, statically. The standard library ensures there's no way to
pass references between threads that get invalidated and even there's
no way to mutate things without using atomics or locks (among other
assurances).

This all works automatically with closures without too much magic,
despite closures being very magic... how?

## Trait bounds

The signature of [`spawn`][spawn] is

[spawn]: http://doc.rust-lang.org/std/thread/fn.spawn.html

{% highlight rust linenos %}
pub fn spawn<F, T>(f: F) -> JoinHandle<T>
    where
        F: Send + 'static + FnOnce() -> T,
        T: Send + 'static
{% endhighlight %}

<div class="join"></div>

In words, `spawn` is a generic function with one argument and two type
parameters:

- the type `F` can be any function/closure that returns a `T`
  (`FnOnce() -> T`), can be safely transferred between threads
  (`Send`) and contains no short-lived references (`'static`),
- the type `T` can be any type at all, as long as it can be transferred
  between threads and doesn't contain short-lived references.

The [`JoinHandle<T>`][jh] allows for retrieving the `T` that `f`
returns, via its [`join` method][join].

[jh]: http://doc.rust-lang.org/std/thread/struct.JoinHandle.html
[join]: http://doc.rust-lang.org/std/thread/struct.JoinHandle.html#method.join

Why each bound on `F`? Well, `f` needs to be a function/callable of some
sort, so we need one of the `Fn*` closure traits, and `spawn` will
just run the closure on a new thread, and run it exactly once, so
using [`FnOnce`][fo] gives callers of `spawn` the most power.

[fo]: http://doc.rust-lang.org/std/ops/trait.FnOnce.html
[fn]: http://doc.rust-lang.org/std/ops/trait.Fn.html

The closure is run on a new thread independent of the parent. There's
absolutely no guarantees or relationships between how long the new
thread runs for, and how long the stack frames of the parent last, so
the new thread cannot have any references to the parent's stack. This
is the `'static` requirement: only data that can live for arbitrary
long can be passed via the new closure.

The last bound is [`Send`][send]: the closure is executed on a new thread, so
it definitely needs to be safe to transfer to that new thread. This is
what `Send` guarantees.

[send]: http://doc.rust-lang.org/std/marker/trait.Send.html
[sync]: http://doc.rust-lang.org/std/marker/trait.Sync.html

The return type `T` can be anything, as long as it can be transferred
from the child thread back to the parent (`Send`) and as long as it is
also independent of any stack frames (`'static`).

This all sounds fine and dandy. But there's one hitch: the `Send`
trait is defined entirely[^almost] in the standard library. The
compiler doesn't know anything about it. But, somehow, even the purely
compiler-internal types constructed for closures can implement it.

[^almost]: They're currently still "lang-items" (i.e. known to the
           compiler), but Niko Matsakis tells me "it's because compiler
           needs refactoring", i.e. an implementation detail.

## Witchcraft?

The main protagonist here is OIBIT.

Ok, fine, it's really default impls, but OIBIT is more fun to say.

Previously, `Send` was a super-special compiler built-in trait with
powers unseen by human eyes. Then, everything changed when the
[opt-in built-in traits (OIBIT)][oibit] nation attacked. This
introduced the concept of [a "default impl"][default] for marker
traits (traits that don't contain any items). A *default
implementation* for `Trait` means that `Trait` will automatically be
implemented by aggregate types where all (if any) the other types they
contain also implement `Trait`.

Syntactically, it looks like:

{% highlight rust linenos %}
impl Trait for .. {}
{% endhighlight %}

In terms of functionality, suppose `u8` and `String` implement `Trait`
but `i16` doesn't,

{% highlight rust linenos %}
// implement `Trait`
enum Good { A, B }
struct Excellent;
struct Wonderful { x: u8, y: String }
type Splendid = Option<u8>;
type Brilliant = (u8, String);

// don't implement `Trait`
enum Bad {
    X(i16),
    Y(u8)
}
struct Poor { x: i16 }
type Subpar = Option<i16>;
type Underwhelming = (String, i16);
{% endhighlight %}

This rule applies to closures too: if a closure only captures things
that implement `Trait`, it is a struct similar to `Wonderful`, so the
(implicit) closure type implements `Trait` too.

The `Send` trait has one of these nifty default implementations, so
benefits from all that machinery, and it's how closures can be used
with `Send`. To demonstrate specifically:

{% highlight rust linenos %}
use std::rc::Rc;

// can only be used with `Send` types.
fn check_send<T: Send>(_: T) {}

let x: i32 = 1;
let vec: Vec<Option<String>> = vec![None, None, None];

let f = move || {
    let _ = (x, vec); // make sure they're captured
};
check_send(f);

let pointer: Rc<i32> = Rc::new(1);
let g = move || {
    let _ = pointer; // make sure it is captured
};
check_send(g);
{% endhighlight %}

This fails to compile, but in a particular way:

{% highlight text linenos %}
...:18:1: 18:11 error: the trait `core::marker::Send` is not implemented for the type `alloc::rc::Rc<i32>` [E0277]
...:18 check_send(g);
       ^~~~~~~~~~
...:18:1: 18:11 note: `alloc::rc::Rc<i32>` cannot be sent between threads safely
...:18 check_send(g);
       ^~~~~~~~~~
{% endhighlight %}

Both `i32` and `Vec<Option<String>>` are `Send` so the `f` closure is
`Send` and `check_send(f)` compiles fine. On the other hand,
`Rc` is not `Send`,
so `g` doesn't get the default implementation.

The [`Rc` type][rc] is a reference counted pointer where reference count
adjustments happen non-atomically. This means that manipulating them
from multiple threads will be a data-race: undefined behaviour. An
`Rc` handle can't transfer between threads due to this risk, and this
is statically guaranteed since the type doesn't implement `Send`. (The
[`Arc` type][arc] is a thread-safe version, using atomic reference
counting.)

[rc]: http://doc.rust-lang.org/std/rc/
[arc]: http://doc.rust-lang.org/std/sync/struct.Arc.html
[oibit]: https://github.com/rust-lang/rfcs/blob/master/text/0019-opt-in-builtin-traits.md
[default]: https://github.com/rust-lang/rfcs/blob/master/text/0019-opt-in-builtin-traits.md#default-and-negative-impls

### Opting out or in

It's nice that `Send` is automatically implemented for a type when the
contents are entirely `Send`, but this isn't always perfect: it is
possible to use `unsafe` code make a thread-unsafe type, even if it
is composed entirely of primitives. Similarly, it is possible to have
a type composed of non-`Send` internals which is actually thread-safe,
by imposing extra constraints on how it manipulates data.

Hence, two important parts of the OIBIT proposal are making it
possible to fill in a "gap" that the default impl doesn't cover, and
also forcibly opt out of the default implementation. The former is
so interesting: itcan be performed with normal `impl`, as one would
write for the trait if it didn't have default implementation.

On the other hand, the opt-out is new and different, it is done via
*negative implementations*: to opt out of `Trait`, implement `!Trait`.
For example, the thread-unsafe `Rc<T>` type has

{% highlight rust linenos %}
impl<T> !Send for Rc<T> {}
{% endhighlight %}

Having to opt-out might seem error-prone, but the only way a type with
individually-thread-safe contents can be thread unsafe in aggregate is
if there is some `unsafe` code somewhere. Considering thread-safety is
an important part of writing `unsafe` code in Rust, and if you're
building safe abstractions, you need to be careful to have the right
trait implementations.

However, it's not as scary as it sounds. Safety is still the
(sometimes conservative) default in the *vast* majority[^vast] of
low-level cases. The standard library has negative implementations of
`Send` for the raw pointer types `*const T` and `*mut T`, so data
structures containing them need to explicitly opt *in* if they are in
fact thread-safe. (`Rc` actually falls into this category, so the
implementation above isn't strictly required.)

[^vast]: There's only 3 negative implementations (approximated by
         matches for `/\bimpl.*!/`) in my `projects` folder, which
         contains 100-200 Rust libraries over 1.3 million lines,
         written by me and others, mainly others. All three are for
         `Send`'s sibling [`Sync`][sync] which uses exactly the same
         default/negative impl set-up, and, in fact, one of them is on
         a type that is already not `Sync` (it has non-`Sync`
         contents).

    (That said, there's always the possibility that there *should* be
    a lot more negative impls, and there's a large number of broken
    libraries in the ecosystem... however, this would surprise me greatly.)

There's one slight hole here: the type of a closure is unnameable, so
there's no way to opt-out of a defaulted trait like `Send`. That is, a
closure could capture only `Send` types, but use `unsafe` code to be
thread unsafe. This is somewhat unfortunate, but closures are not
designed to be the abstraction boundary for safety. I'd personally try
to wrap the unsafety up into a real type with the correct trait
(un)implementations to help the compiler help me as much as
possible. Also, as I said above, this rarely happens, due to the
negative implementations in the standard library; I imagine the the
most common way that isn't necessarily caught by that is calling
non-reentrant FFI function, but wrapping C libraries in a safe
interface is [a nice idea][safe].

[safe]: http://blog.rust-lang.org/2015/04/24/Rust-Once-Run-Everywhere.html#safe-abstractions

Anyway, returning to the opt in mechanism, what is stopping us from wrapping a
thread-unsafe type (non-`Send`) in a new struct and implementing
`Send` for it? Something like

{% highlight rust linenos %}
use std::rc::Rc;

struct Trick {
    x: Rc<i32>
}
impl Send for Trick {}
{% endhighlight %}

If this worked (spoilers: it doesn't), we've "asserted" that `Trick`
is thread-safe despite it containing a thread-unsafe type, *without*
mentioning `unsafe` anywhere. This would introduce a very real risk of
undefined behaviour via data races.

### Unsafe traits

Fortunately, the compiler spits out an error:

{% highlight text linenos %}
...:6:1: 6:23 error: the trait `core::marker::Send` requires an `unsafe impl` declaration [E0200]
...:6 impl Send for Trick {}
      ^~~~~~~~~~~~~~~~~~~~~~
{% endhighlight %}

Ah! So it's telling us that `unsafe` is in fact required. This version
of the `impl` compiles:

{% highlight rust linenos %}
unsafe impl Send for Trick {}
{% endhighlight %}

This is because `Send` is [declared][send-decl] as `unsafe`:

[send-decl]: https://github.com/rust-lang/rust/blob/7cb9914fceaeaa6a39add43d3da15bb6e1d191f6/src/libcore/marker.rs#L38

{% highlight rust linenos %}
pub unsafe trait Send {
{% endhighlight %}

An *unsafe trait* is unsafe to implement, but not to use. It is
designed to allow representing classes of types with absolute
guarantees, that users of the trait can rely on even if it risks
memory unsafety: it is up to the implementers to ensure they satisfy
the requirements. It's not unsafe to *not* implement an unsafe trait,
so negative implementations don't need `unsafe`.

The guarantee for `Send` is thread-safety: a type should only
implement `Send` if it is absolutely sure.

### ⚠⚠⚠

Unsafe traits are great and libraries should definitely use them where
they make sense. However, the OIBIT functionality (default and
negative implementations) are still unstable and hence only usable
with a nightly compiler behind the `optin_builtin_traits`
feature. There's some details around them that are unclear from the
RFC and even the implementation, especially how they interact with
primitives, so I could imagine some tweaks/breaking changes in future.

Unfortunately, this means that the only way to opt-out of a defaulted
trait with a stable compiler is to store a non-implementing type. The
slickest way is to use [`PhantomData<T>`][phantom], which is a
zero-sized type (so no runtime effect) that behaves as if it stores
its type argument. For opting out of `Send`, a field of type
`PhantomData<*const ()>` works. (However, as discussed above, this is
rarely needed for `Send` and `Sync`, which are the only two defaulted
traits one can possibly use on a stable compiler.)

[phantom]: http://doc.rust-lang.org/std/marker/struct.PhantomData.html

{% include image.html src="unstable-small.jpg" link="https://www.flickr.com/photos/tm-tm/2634203419/" %}

## Calling Concurrently

We've been focusing on `Send` above, but there's another trait that's
important for thread-safety: [`Sync`][sync]. This trait represents
values that are safe to be *accessed* by multiple threads at once,
that is, sharing.

It is sometimes useful to call a single function on multiple threads,
like a parallel map, so it would be pretty great if this was
possible...

Just like `Send`, `Sync` is a defaulted trait, and so works well with
closures too. A closure that only captures thread-shareable values
(like a string) is also thread-shareable:

{% highlight rust linenos %}
use std::sync::Arc;
use std::thread;

fn upto<F>(n: usize, func: F)
    where F: Send + 'static + Fn(usize) + Sync
{
    let func = Arc::new(func);
    for i in 0..n {
        let f = func.clone();
        thread::spawn(move || f(i));
    }
}

fn main() {
    let message = "hello";
    upto(10, |i| println!("thread #{}: {}", i, message));

    // as above, don't let `main` finish
    thread::sleep_ms(100);
}
{% endhighlight %}

<div class="join"></div>

The output sometimes looks like:

{% highlight text linenos %}
thread #0: hello
thread #7: hello
thread #2: hello
thread #9: hello
thread #1: hello
thread #4: hello
thread #3: hello
thread #6: hello
thread #8: hello
thread #5: hello
{% endhighlight %}

The `Send` and `'static` bounds are "boring", they're just required
due to the implementation details of using `spawn` and `Arc`, it's the
`Fn` and `Sync` bounds that are fundamental to this behaviour.

We're calling the function from multiple threads at once, which means
accessing the closure's environment concurrently, so the `Sync` bound
is necessary to guarantee safety. Also, by nature, sharing across
threads means we've only got access to the closure via an `&`
reference, so we need to be able to call it via that sort of reference
and [`Fn`][fn] is exactly the right trait for
it. ([*Finding Closure in Rust*][closures] looks at the three closure
traits more closely.)


{% include comments.html c=page.comments %}

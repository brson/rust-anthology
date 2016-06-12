---
layout: default
title: What does Rust's “unsafe” mean?
description: >
    Exploring Rust's escape hatch for writing low-level code that the
    powerful type system of Rust cannot guarantee to be safe.
comments:
    r_rust: "http://www.reddit.com/r/rust/comments/2bhwgc/what_does_rusts_unsafe_mean/"
    r_programming: "http://www.reddit.com/r/programming/comments/2bhwhl/what_does_rusts_unsafe_mean/"
    # hn: "https://news.ycombinator.com/item?id=8288572"
---

[Rust](http://rust-lang.org/) is an in-development[^version] systems
programming language with a strong focus on no-overhead memory
safety. This is achieved through a powerful type system (with
similarities to Haskell), and careful tracking of ownership and
pointers, guaranteeing safety. However, this is too restrictive for a
low-level systems language, an escape hatch is occasionally
required. Enter the `unsafe` keyword.

[^version]: The code in this post compiles with `rustc 0.12.0-pre-nightly (aa0e35bc6 2014-07-22 00:26:21 +0000)`.

## Poking holes in memory safety

Rust aims to be memory safe, so that, by default, code cannot crash
(or be exploited) due to dangling pointers or iterator
invalidation. However, there are things that cannot fit into the type
system, for example, it is not possible to get the raw interactions
with the operating system and system libraries (like memory allocators
and thread spawning) to be truly safe. Detailed human knowledge about
how to use them safely is required to be encoded at some point, and
this is not easily checkable by a compiler: mistakes can be made.

Other memory safe languages (e.g. managed ones like Python or Haskell)
have all this knowledge encoded in the implementations of their
underlying virtual machines/runtime systems, usually written in
C. Rust doesn't have a heavy-weight VM or runtime, but still needs to
provide (preferably safe) interfaces in some manner.

Rust fills these holes with the `unsafe` keyword, which opts in to
possibly dangerous behaviour; like calling into the operating system
and external libraries via
[the foreign function interface (FFI)](http://doc.rust-lang.org/master/guide-ffi.html),
or handling possibly-invalid machine pointers directly.

Rust uses `unsafe` to build all the abstractions seen in the standard
library: the vast majority of it is written in Rust, including
fundamental types like
[the reference counted `Rc`](http://doc.rust-lang.org/master/std/rc/struct.Rc.html),
[the dynamic vector `Vec`](http://doc.rust-lang.org/master/std/vec/struct.Vec.html),
and
[`HashMap`](http://doc.rust-lang.org/master/std/collections/hashmap/struct.HashMap.html),
with only
[a few small C shims](https://github.com/rust-lang/rust/tree/82ec1aef293ddc5c6373bd7f5ec323fafbdf7901/src/rt)
and some external non-Rust libraries like jemalloc and libuv.

## `unsafe`

There are two ways in which one can opt-in to these possibly dangerous
behaviours: with an `unsafe` block, or with an `unsafe` function.

{% highlight rust linenos %}
// calling some C functions imported via FFI:

unsafe fn foo() {
    some_c_function();
}
fn bar() {
    unsafe {
        another_c_function();
    }
}
fn baz() {
    // illegal, not inside an `unsafe` context
    // yet_another_c_function();
}
{% endhighlight %}

Being inside an `unsafe` context allows one to (not necessarily
complete):

1. call functions marked `unsafe` (this includes FFI functions)
2. dereference raw pointers (the `*const` and `*mut` types), which can
  possibly be `NULL`, or otherwise invalid
3. access a mutable global variable
4. use inline assembly

All of these can easily cause large problems. For example, a shared
reference `&T` is a machine pointer, but it *must* always point to a
valid value of type `T`; all four of the above can cause this to be
violated:

1. There is an `unsafe` function
  [`std::mem::transmute`](http://doc.rust-lang.org/master/std/mem/fn.transmute.html)
  which takes the bytes of its argument and pretends they are of any
  type one wants, thus, one can create an invalid `&` pointer by
  reinterpreting an integer: `transmute::<uint, &Vec<int>>(0)`.

2. A raw pointer `p: *const T` can legally be `NULL`. The
  "rereferencing" operation `&*p` creates a reference `&T` pointing to
  `p`s data, a no-op at runtime, since `*const T` and `&T` are both
  just a single pointer under the hood. If `p` is `NULL` this allows
  one to create a `NULL` `&T`: invalid!

3. If one has `static mut X: Option<i64> = Some(1234);`, one can use
  pattern matching to get a reference `r: &i64` pointing to the `1234`
  integer, but another thread can overwrite `X` with `None`, leaving
  `r` dangling.

4. Inline assembly can set arbitrary registers to arbitrary values,
   including setting a register meant to be holding a `&T` to zero.

## What does `unsafe` really mean?

An `unsafe` context is the programmer telling the compiler that the
code is guaranteed to be safe due to invariants impossible to express
in the type system, and that it satisfies
[the invariants that Rust itself imposes](http://doc.rust-lang.org/nightly/reference.html#behavior-considered-undefined).

These invariants are assumed to never be broken, even inside `unsafe`
code blocks, and the compiler compiles and optimises with this
assumption. Thus, breaking any of those invariants is
[undefined behaviour](https://en.wikipedia.org/wiki/Undefined_behaviour)[^ub-llvm]
and can leave a program doing "anything", even making
[demons fly out your nose](http://www.catb.org/jargon/html/N/nasal-demons.html).

[^ub-llvm]: ["What Every C Programmer Should Know About Undefined Behaviour"](http://blog.llvm.org/2011/05/what-every-c-programmer-should-know.html)
            is a series of articles highlighting how insidious undefined behaviour
            can be, leading to subtly (or not so subtly) broken programs.

That is, an `unsafe` context is not a free pass to mutate anything and
everything, nor is it a free pass to mangle pointers and alias
references: all the normal rules of Rust still apply, the compiler is
just giving the programmer more power, at the expense of leaving it up
to the programmer to ensure everything is safe.

A non-`unsafe` function using `unsafe` internally *should* be
implemented to be safe to call; that is, there is no circumstance or
set of arguments that can make the function violate
[any invariants](http://doc.rust-lang.org/nightly/reference.html#behavior-considered-undefined). If
there are such circumstances, it should be marked `unsafe`.

This rule is most important for public, exported functions; private
functions are guaranteed to only be called in a limited set of
configurations (since all calls are in the crate/module in which it is
defined), so the author has more flexibility about what sort of safety
guarantees they give. However, marking possibly-dangerous things
`unsafe` helps the compiler help the programmer do the right thing, so
is encouraged even for private items.


### Case study: `Vec`

The `Vec<T>` type is
[defined](https://github.com/rust-lang/rust/blob/82ec1aef293ddc5c6373bd7f5ec323fafbdf7901/src/libcollections/vec.rs#L55-L59)
as:

{% highlight rust linenos %}
pub struct Vec<T> {
    len: uint,
    cap: uint,
    ptr: *mut T
}
{% endhighlight %}

There are (at least) two invariants here:

1. `ptr` holds an allocation with enough space for `cap` values of type `T`
2. That allocation holds `len` valid values of type `T` (i.e. the
   first `len` out of `cap` of the `T`s are valid, implying `len <=
   cap`)


It's not feasible to express these in Rust's type system, so they are
guaranteed by a careful implementation. The implementation is then
forced to use `unsafe` to assuage the compiler's doubts about certain
operations. The compiler does not and cannot understand the invariants
stated above, and so cannot be sure that
[creating a slice view into the vector](https://github.com/rust-lang/rust/blob/82ec1aef293ddc5c6373bd7f5ec323fafbdf7901/src/libcollections/vec.rs#L1430)
is safe. It is implemented like so:


{% highlight rust linenos %}
fn as_slice<'a>(&'a self) -> &'a [T] {
    unsafe { mem::transmute(Slice { data: self.as_ptr(), len: self.len }) }
}
{% endhighlight %}

And you can see that it could easily be unsafe e.g. if one
accidentally wrote `self.cap` instead of `self.len`, the resulting
slice would be too long and the last elements of it would be
uninitialised data. The compiler can't verify that this is correct,
and so assumes the worst, disallowing it without the explicit opt-in.


Another thing to note is these `Vec` invariants are required to always
hold or else `Vec` will be allowing incorrect behaviour to happen via
the safe methods it exposes (e.g. if someone could increase `len`
without initialising the elements appropriately, the `as_slice` method
above would be broken).

Unfortunately, it's not possible to get the Rust compiler to directly
enforce them, so the `Vec` API has to be careful to guarantee that
they can't be violated; part of this is keeping the fields private, so
they cannot be directly changed, another part is being careful to mark
the `unsafe` parts of the API as `unsafe`, e.g.
[the `set_len` method](http://doc.rust-lang.org/master/collections/vec/struct.Vec.html#method.set_len)
can directly change the `len` field.

### Case study: `malloc`

The C function `malloc` is described by my man page as the following:

> The `malloc()` function allocates size bytes and returns a pointer to the
> allocated memory.  The memory is not initialized.  If size is  0,  then
> `malloc()`  returns either `NULL`, or a unique pointer value that can later
> be successfully passed to `free()`.
>
> The `malloc()` and `calloc()` functions return a pointer to  the  allocated
> memory,  which  is  suitably  aligned for any built-in type.  On error,
> these functions return `NULL`.  [...].


The `libc` crate predefines most of the common symbols from the `libc`
on various platforms, including `libc::malloc`. Let's write a safe
program that creates memory for, stores and prints an 8-byte `i64`
integer, carefully justifying why we know more than the compiler, and
thus why each `unsafe` is safe (in a perfect world all `unsafe` blocks
would be justified/proved correct).

{% highlight rust linenos %}
extern crate libc;
use std::ptr;

fn main() {
    let pointer: *mut i64 = unsafe {
        // rustc doesn't know what `malloc` does, and so doesn't know
        // that calling it with argument 8 is always safe; but we do,
        // so we override the compiler's concern with
        // `unsafe`. (`malloc` returns a `*mut libc::c_void` so we
        // need to cast it to the type we want.)
        libc::malloc(8) as *mut i64
    };

    // we know that the only failure condition is the pointer being
    // NULL, in any other circumstance the pointer points to a valid
    // memory allocation of at least 8 bytes.
    if pointer.is_null() {
        println!("could not allocate");
    } else {
        // here, the only thing missing is initialisation, the memory
        // is valid but uninitialised, so lets fix that. Since it is
        // not initialised, we have to be careful to avoid running
        // destructors on the old memory; via `std::ptr::write`.
        unsafe {
            // allocation is valid, and the memory is uninitialised,
            // so this is safe and correct.
            ptr::write(pointer, 1234i64);
        }

        // now `pointer` is looking at initialised, valid memory, so
        // it is valid to read from it, and to obtain a reference to
        // it.
        let data: &i64 = unsafe { &*pointer };
        println!("The data is {}", *data);
        // prints: The data is 1234
    }

    // (leaking memory is not `unsafe`.)
}
{% endhighlight %}

(Keen eyes will note that `i64` doesn't have a destructor and so the
[`ptr::write`](http://doc.rust-lang.org/master/std/ptr/fn.write.html)
call isn't strictly required, but it's good practice.)


## FAQ: Why isn't `unsafe` viral?

One *might* expect a function containing an `unsafe` block to be
`unsafe` to call, that is, `unsafe`ty infects everything it touches,
similar to how Haskell forces one to mark all impure calculations with
the `IO` type.

However, this is not the case, `unsafe` is just an implementation
detail; if a safe function uses `unsafe` internally, it just means the
author has been forced to step around the type system, but still
exposes a safe interface.

More pragmatically, if `unsafe` were viral, every Rust program ever
would be entirely `unsafe`, since the whole standard library is
written in Rust, built on top of `unsafe` internals.

## Conclusion

The `unsafe` marker is a way to step around Rust's type system; by
telling `rustc` that there are external conditions/invariants that
guarantee correctness: the compiler steps back and locally leaves the
programmer to verify that
[various properties](http://doc.rust-lang.org/reference.html#behavior-considered-undefined)
hold. This allows Rust to write very low-level code like C, but still
be memory safe by default, by forcing programmers to opt-in to the
risky behaviour.

The
["Writing Safe Unsafe and Low-Level Code"](http://doc.rust-lang.org/master/guide-unsafe.html)
provides guidance and tips about using `unsafe` correctly.

{% include comments.html c=page.comments %}

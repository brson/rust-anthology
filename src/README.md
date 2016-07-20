# Rust Anthology

TODO: intro, historical context,
      [Authors](authors.html),
      [Additional reading](additional-reading.html)

## Ownership and Borrowing

[__Where Rust Really Shines__] ★ [Manish Goregaokar].
A tale of hacking that illustrates how Rust's strong type system and
memory safety makes it simple to modify difficult code. Don't
understand how this pointer is accessed? That's fine. The compiler
won't let you do anything bogus, and it's going to guide you to the
correct solution.

[__Where Rust Really Shines__]: where-rust-really-shines.html

[__The Problem With Single-threaded Shared Mutability__] ★ [Manish Goregaokar].
In Rust, `&mut T` is a mutable reference, but it might be better
considered an _unaliased_ reference, guaranteeing that there are no
other live pointers to that data, and no other code will access
it. The only way to write memory in Rust (without atomics) is through
an unaliased reference. This provides clear benefits in multithreaded
programs, where simultaneous access to data can result in bogus
data. But isn't this too strict for single-threaded programs? Actually,
mutable references solve subtle problems for those too.

[__The Problem With Single-threaded Shared Mutability__]: the-problem-with-shared-mutability.html

## Concurrency

[__Fearless Concurrency with Rust__] ★ [Aaron Turon]
Memory safety bugs and concurrency bugs often come down to code
accessing data when it shouldn't. And the same feature that makes Rust
memory safe - ownership - also let the compiler statically prevent
common errors with conncurrent code.

[__Fearless Concurrency with Rust__]: fearless-concurrency.html


## The Rust Language

[__Finding Closure in Rust__] ★ [Huon Wilson].
Closures are functions that can directly use variables from their
enclosing scope. They are a powerful tool in Rust, and come in several
forms, reflecting Rust's ownership-based design. This chapter covers
all the details, including the `Fn`, `FnMut`, and `FnOnce` traits,
captures and the `move` keyword.

[__Finding Closure in Rust__]: finding-closure-in-rust.html

[__Rust's Built-in Traits, the When, How & Why__] ★ [Llogiq].
Traits make all kinds of magic happen in Rust, from operator
overloading, to thread-safety. Traits are shared vocabulary between
Rust types, so the standard library defines a bunch of them, and you
need to know them. Unravel the mystery of `PartialEq`, `Eq`,
`PartialOrd`, `Ord`, `Add`, `Sub` and other operators, `Index`,
`IndexMut`, the closure types `Fn`, `FnMut`, `FnOnce`, formatting with
`Display` and `Debug`, `Copy` and `Clone`, `Drop`, `Default`, `Error`,
`Hash`, `Iterator`, `From`, `Into`, the pointer conversions `Deref`,
`DerefMut`, `AsRef`, `AsMut`, `Borrow`, `BorrowMut`, `ToOwned`,
and thread-safety markers `Send`, `Sync`.

[__Rust's Built-in Traits, the When, How & Why__]: rusts-built-in-traits.html

## Rust in Practice

TODO


[Aaron Turon]: authors.html#Aaron%20Turon
[Alexis Beingessner]: authors.html#Alexis%20Beingessner
[Andrew Hobden]: authors.html#Andrew%20Hobden
[Felix S. Klock II]: authors.html#Felix%20S.%20Klock%20II
[Herman J. Radtke III]: authors.html#Herman%20J.%20Radtke%20III
[Huon Wilson]: authors.html#Huon%20Wilson
[Llogiq]: authors.html#Llogiq
[Manish Goregaokar]: authors.html#Manish%20aGoregaokar

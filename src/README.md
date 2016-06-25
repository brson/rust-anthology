# Rust Anthology

## Ownership and Borrowing

[__Where Rust Really Shines__] ★ [Manish Goregaokar]. A tale of
hacking that illustrates how Rust's strong type system and memory
safety makes it simple to modify difficult code. Don't understand how
this pointer is accessed? That's fine. The compiler won't let you do
anything bogus, and it's going to guide you to the correct solution.

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

[__Fearless Concurrency with Rust__]: fearless-concurrency.html

[__Abstraction Without Overhead__] ★ [Aaron Turon]

[__Abstraction Without Overhead__]: abstraction-without-overhead.html

[__Defaulting to Thread-safety__] ★ [Huon Wilson]

[__Defaulting to Thread-safety__]: defaulting-to-thread-safety.html

[__How Rust Achieves Thread Safety__] ★ [Manish Goregaokar]

[__How Rust Achieves Thread Safety__]: how-rust-achieves-thread-safety.html

[__Some Notes on Send and Sync__] ★ [Huon Wilson]

[__Some Notes on Send and Sync__]: some-notes-on-send-and-sync.html

[__Comparing k-NN in Rust__] ★ [Huon Wilson]

[__Comparing k-NN in Rust__]: comparing-knn-in-rust.html

[__`simple_parallel`: Revisiting k-NN__] ★ [Huon Wilson]

[__`simple_parallel`: Revisiting k-NN__]: simple-parallel-revisiting-knn.md

## The Rust Language

[__Finding Closure in Rust__] ★ [Huon Wilson]. Closures are functions
that can directly use variables from their enclosing scope. They are a
powerful tool in Rust, and come in several forms, reflecting Rust's
ownership-based design. This chapter covers all the details, including
the `Fn`, `FnMut`, and `FnOnce` traits, captures and the `move` keyword.

[__Finding Closure in Rust__]: finding-closure-in-rust.html

[__Enums, `match`, Mutations and Moves__] ★ [Felix S. Klock II]

[__Enums, `match`, Mutations and Moves__]: enums-match-mutation-and-moves.html

[__Reading Rust Function Signatures__] ★ [Andrew Hobden]

[__Reading Rust Function Signatures__]: reading-rust-function-signatures.html

[__Memory Leaks are Memory Safe__] ★ [Huon Wilson]

[__Memory Leaks are Memory Safe__]: memory-leaks-are-memory-safe.html

[__Myths and Legends About Integer Overflow in Rust__] ★ [Huon Wilson]

[__Myths and Legends About Integer Overflow in Rust__]: myths-and-legends-about-integer-overflow-in-rust.html

[__What Does Rust's `unsafe` Mean?__] ★ [Huon Wilson]

[__What Does Rust's `unsafe` Mean?__]: what-does-rusts-unsafe-mean.html

[__Peeking Inside Trait Objects__] ★ [Huon Wilson]

[__Peeking Inside Trait Objects__]: peeking-inside-trait-objects.html

[__The `Sized` Trait__] ★ [Huon Wilson]

[__The `Sized` Trait__]: the-sized-trait.html

[__Object Safety__] ★ [Huon Wilson]

[__Object Safety__]: object-safety.html

[__Where `Self` meets `Sized`: Revisiting Object Safety__] ★ [Huon Wilson]

[__Where `Self` meets `Sized`: Revisiting Object Safety__]: where-self-meets-sized-revisiting-object-safety.html

[__Rust's Built-in Traits, the When, How & Why__] ★ [Llogiq]

Traits make all kinds of magic happen in Rust, from operator
overloading, to thread-safety. Traits are shared vocabulary between
Rust types, so the standard library defines a bunch of them, and you
need to know them. Unravel the mystery of `PartialEq`, `Eq`,
`PartialOrd`, `Ord`, `Add`, `Sub` and other operators, `Index`, `IndexMut`,
the closure types `Fn`, `FnMut`, `FnOnce`, formatting with `Display` and `Debug`,
`Copy` and `Clone`, `Drop`, `Default`, `Error`, `Hash`, `Iterator`,
`From`, `Into`, `Deref`, `DerefMut`, `AsRef`, `AsMut`, `Borrow`,
`BorrowMut`, `ToOwned`, `Send`, `Sync`.

[__Rust's Built-in Traits, the When, How & Why__]: rusts-built-in-traits.html

## Rust in Practice

[__Working With C Unions in Rust FFI__] ★ [Herman J. Radtke III]

[__Working With C Unions in Rust FFI__]: unions-rust-ffi.html

[__Terminal Window Size With Rust FFI__] ★ [Herman J. Radtke III]

[__Terminal Window Size With Rust FFI__]: terminal-window-size-with-rust-ffi.html

[__Getting Acquainted with `mio`__] ★ [Andrew Hobden]

[__Getting Acquainted with `mio`__]: getting-acquainted-with-mio.html

[__My Basic Understanding of `mio` and Async I/O__] ★ [Herman J. Radtke III]

[__My Basic Understanding of `mio` and Async I/O__]: my-basic-understanding-of-mio-and-async-io.html

[__Creating a Simple Protocol With `mio`__] ★ [Herman J. Radtke III]

[__Creating a Simple Protocol With `mio`__]: creating-a-simple-protocol-with-mio.html

[__Managing Connection State With `mio`__] ★ [Herman J. Radtke III]

[__Managing Connection State With `mio`__]: managing-connection-state-with-mio.html

[__Get Data From A URL In Rust__] ★ [Herman J. Radtke III]

[__Get Data From A URL In Rust__]: get-data-from-a-url.html

[__Effectively Using Iterators in Rust__] ★ [Herman J. Radtke III]

[__Effectively Using Iterators in Rust__]: effectively-using-iterators.html

[__`String` vs. `&str` in Rust Functions__] ★ [Herman J. Radtke III]

[__`String` vs. `&str` in Rust Functions__]: string-vs-str-in-rust-functions.html

[__Creating a Rust Function That Accepts `String` or `&str`__] ★ [Herman J. Radtke III]

[__Creating a Rust Function That Accepts `String` or `&str`__]: creating-a-rust-function-that-accepts-string-or-str.html

[__Creating a Rust Function That Returns `String` or `&str`__] ★ [Herman J. Radtke III]

[__Creating a Rust Function That Returns `String` or `&str`__]: creating-a-rust-function-that-returns-string-or-str.html

[__Understanding Over Guesswork__] ★ [Andrew Hobden]

[__Understanding Over Guesswork__]: understanding-over-guesswork.html

[__Rust, Lifetimes, and Collections__] ★ [Alexis Beingessner]

[__Rust, Lifetimes, and Collections__]: rust-lifetimes-and-collections.html

[__Rust, Generics, and Collections__] ★ [Alexis Beingessner]

[__Rust, Generics, and Collections__]: rust-generics-and-collections.html

[__Rust Collections Case Study: BTreeMap__] ★ [Alexis Beingessner]

[__Rust Collections Case Study: BTreeMap__]: rust-btree-case.html

[__Pre-pooping Your Pants With Rust__] ★ [Alexis Beingessner]

[__Pre-pooping Your Pants With Rust__]: everyone-poops.html

[__The Many Kinds of Code Reuse in Rust__] ★ [Alexis Beingessner]

[__The Many Kinds of Code Reuse in Rust__]: rust-reuse-and-recycle.html

# Candidates

[__Strategies for Solving "cannot move out of" Borrowing Errors__] ★ [Herman J. Radtke III]

[__Strategies for Solving "cannot move out of" Borrowing Errors__]: strategies-for-solving-cannot-move-out-of-borrowing-errors.html

[Aaron Turon]: authors.html#Aaron%20Turon
[Alexis Beingessner]: authors.html#Alexis%20Beingessner
[Andrew Hobden]: authors.html#Andrew%20Hobden
[Felix S. Klock II]: authors.html#Felix%20S.%20Klock%20II
[Herman J. Radtke III]: authors.html#Herman%20J.%20Radtke%20III
[Huon Wilson]: authors.html#Huon%20Wilson
[Llogiq]: authors.html#Llogiq
[Manish Goregaokar]: authors.html#Manish%20aGoregaokar

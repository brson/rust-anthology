# Rust Anthology 1

_This is a work in progress draft_.

TODO: 1 paragraph intro.

Something, something [about the authors](authors.html).

## Why Rust?

[__Understanding Over Guesswork__](understanding-over-guesswork.html)
★ [Andrew Hobden].
Some bugs are just that &mdash; a one off. A wayward moth that just
happens to be innocently fluttering through the wrong relay at the
wrong time. But some kinds of bugs aren't like that. Instead, they
have risen to superstar status, plaguing veterans and newcomers alike.
But what if these aren't bugs at all? What if they are actual
deficiencies in safety and robustness offered by the C programming
language as a consequence of the degree to which guesswork is
introduced? This chapter, a proposal to teach an operating systems
course in Rust at the University of Victoria, shows why Rust
is a superior language for writing reliable systems software.


## Ownership

[__Where Rust Really Shines__](where-rust-really-shines.html)
★ [Manish Goregaokar].
A tale of hacking that illustrates how Rust's strong type system and
memory safety makes it simple to modify difficult code. Don't
understand how this pointer is accessed? That's fine. The compiler
won't let you do anything bogus, and it's going to guide you to the
correct solution.


[__The Problem With Single-threaded Shared Mutability__](the-problem-with-shared-mutability.html)
★ [Manish Goregaokar].
In Rust, `&mut T` is a mutable reference, but it might be better
considered an _unaliased_ reference, guaranteeing that there are no
other live pointers to that data, and no other code will access
it. The only way to write memory in Rust (without atomics) is through
an unaliased reference. This provides clear benefits in multithreaded
programs, where simultaneous access to data can result in bogus
data. But isn't this too strict for single-threaded programs? Actually,
mutable references solve subtle problems for those too.


## Concurrency

[__Fearless Concurrency with Rust__](fearless-concurrency.html)
★ [Aaron Turon].
Memory safety bugs and concurrency bugs often come down to code
accessing data when it shouldn't. And the same feature that makes Rust
memory safe - ownership - also let the compiler statically prevent
common errors with conncurrent code.


[__How Rust Achieves Thread Safety__](how-rust-achieves-thread-safety.html)
★ [Manish Goregaokar].
Ownership is the secret, unifying, sauce of Rust. Among other things
it creates a simple conceptual framework for reasoning about
concurrency. But under the hood there are mysterious things afoot in
the type system to make it all work. Two simple traits are telling the
compiler everything it needs to know about concurrency: `Send` and
`Sync`. This is their story.


## Traits

[__Abstraction Without Overhead__](abstraction-without-overhead.html)
★ [Aaron Turon].
The cornerstone of the Rust design philosophy is to enable "zero-cost abstractions".
That is, the high-level abstractions in Rust optimize into the best low-level
code you could write by hand. And Rust, perhaps more than any other language,
comes close to achieving this ideal. This is how.


[__All About Trait Objects__](all-about-trait-objects.html)
★ [Huon Wilson].
One of the most powerful parts of the Rust programming language is the trait
system. They form the basis of Rust generics via polymorphic functions and
types, and as so-called "trait objects", they allow for dynamic polymorphism and
heterogeneous uses of types. This chapter motivates trait objects and takes a
peek under the hood to see how they are implemented at runtime; then explains
the important advanced concepts of dynamically sized types and the `Sized`
trait; finally, it explains in which situations traits can be used as trait
objects, what is known as "object safety".


## The Rust Language

[__Rust's Built-in Traits, the When, How & Why__](rusts-built-in-traits.html)
★ [Andre Bogus].
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


[__Finding Closure in Rust__](finding-closure-in-rust.html)
★ [Huon Wilson].
Closures are functions that can directly use variables from their
enclosing scope. They are a powerful tool in Rust, and come in several
forms, reflecting Rust's ownership-based design. This chapter covers
all the details, including the `Fn`, `FnMut`, and `FnOnce` traits,
captures and the `move` keyword.


## Unsafe Rust

## Rust in Practice

## The Rust Toolbox

## Async I/O

## Rust Culture

[Aaron Turon]: authors.html#Aaron%20Turon
[Alexis Beingessner]: authors.html#Alexis%20Beingessner
[Andre Bogus]: authors.html#Andre%20Bogus
[Andrew Hobden]: authors.html#Andrew%20Hobden
[Felix S. Klock II]: authors.html#Felix%20S.%20Klock%20II
[Herman J. Radtke III]: authors.html#Herman%20J.%20Radtke%20III
[Huon Wilson]: authors.html#Huon%20Wilson
[Manish Goregaokar]: authors.html#Manish%20Goregaokar

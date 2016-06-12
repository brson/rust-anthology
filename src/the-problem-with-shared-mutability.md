---
layout: post
title: "The problem with single-threaded shared mutability"
date: 2015-05-17 16:56:59 +0530
comments: true
categories: rust mozilla programming
---

This is a post that I've been meaning to write for a while now; and the release of Rust 1.0 gives
me the perfect impetus to go ahead and do it.

Whilst this post discusses a choice made in the design of Rust; and uses examples in Rust; the principles discussed
here apply to other languages for the most part. I'll also try to make the post easy to understand for those without
a Rust background; please let me know if some code or terminology needs to be explained.


What I'm going to discuss here is the choice made in Rust to disallow having multiple mutable aliases
to the same data (or a mutable alias when there are active immutable aliases),
**even from the same thread**. In essence, it disallows one from doing things like:


```rust
let mut x = Vec::new();
{
    let ptr = &mut x; // Take a mutable reference to `x`
    ptr.push(1); // Allowed
    let y = x[0]; // Not allowed (will not compile): as long as `ptr` is active,
                  // x cannot be read from ...
    x.push(1);    // .. or written to
}


// alternatively,

let mut x = Vec::new();
x.push(1); // Allowed
{
    let ptr = &x; // Create an immutable reference
    let y = ptr[0]; // Allowed, nobody can mutate
    let y = x[0]; // Similarly allowed
    x.push(1); // Not allowed (will not compile): as long as `ptr` is active,
               // `x` is frozen for mutation
}

```

This is essentially the "Read-Write lock" (RWLock) pattern, except it's not being used in a
threaded context, and the "locks" are done via static analysis (compile time "borrow checking").


Newcomers to the language have the recurring question as to why this exists. [Ownership semantics][book-ownership]
and immutable [borrows][book-borrow] can be grasped because there are concrete examples from languages like C++ of
problems that these concepts prevent. It makes sense that having only one "owner" and then multiple "borrowers" who
are statically guaranteed to not stick around longer than the owner will prevent things like use-after-free.

But what could possibly be wrong with having multiple handles for mutating an object? Why do we need an RWLock pattern? [^0]



[book-ownership]: http://doc.rust-lang.org/nightly/book/ownership.html
[book-borrow]: http://doc.rust-lang.org/nightly/book/references-and-borrowing.html
[^0]: Hereafter referred to as "The Question"

## It causes memory unsafety

This issue is specific to Rust, and I promise that this will be the only Rust-specific answer.


[Rust enums][book-enums] provide a form of algebraic data types. A Rust enum is allowed to "contain" data,
for example you can have the enum

```rust
enum StringOrInt {
    Str(String),
    Int(i64)
}
```

which gives us a type that can either be a variant `Str`, with an associated string, or a variant `Int`[^1], with an associated integer.


With such an enum, we could cause a segfault like so:

```rust
let x = Str("Hi!".to_string()); // Create an instance of the `Str` variant with associated string "Hi!"
let y = &mut x; // Create a mutable alias to x

if let Str(ref insides) = x { // If x is a `Str`, assign its inner data to the variable `insides`
    *y = Int(1); // Set `*y` to `Int(1), therefore setting `x` to `Int(1)` too
    println!("x says: {}", insides); // Uh oh!
}
```

Here, we invalidated the `insides` reference because setting `x` to `Int(1)` meant that there is no longer a string inside it.
However, `insides` is still a reference to a `String`, and the generated assembly would try to dereference the memory location where
the pointer to the allocated string _was_, and probably end up trying to dereference `1` or some nearby data instead, and cause a segfault.

Okay, so far so good. We know that for Rust-style enums to work safely in Rust, we need the RWLock pattern. But are there any other
reasons we need the RWLock pattern? Not many languages have such enums, so this shouldn't really be a problem for them.

[book-enums]: http://doc.rust-lang.org/nightly/book/enums.html
[^1]: Note: `Str` and `Int` are variant names which I chose; they are not keywords. Additionally, I'm using "associated foo" loosely here; Rust *does* have a distinct concept of "associated data" but it's not relevant to this post.


## Iterator invalidation

Ah, the example that is brought up almost every time the question above is asked. While I've been quite guilty of
using this example often myself (and feel that it is a very appropriate example that can be quickly explained),
I also find it to be a bit of a cop-out, for reasons which I will explain below. This is partly why I'm writing
this post in the first place; a better idea of the answer to The Question should be available for those who want
to dig deeper.

Iterator invalidation involves using tools like iterators whilst modifying the underlying dataset somehow.

For example,


```rust

let buf = vec![1,2,3,4];

for i in &buf {
    buf.push(i);
}
```

Firstly, this will loop infinitely (if it compiled, which it doesn't, because Rust prevents this). The
equivalent C++ example would be [this one][stackoverflow-iter], which I [use][slides-iter] at every opportunity.

What's happening in both code snippets is that the iterator is really just a pointer to the vector and an index.
It doesn't contain a snapshot of the original vector; so pushing to the original vector will make the iterator iterate for
longer. Pushing once per iteration will obviously make it iterate forever.

The infinite loop isn't even the real problem here. The real problem is that after a while, we could get a segmentation fault.
Internally, vectors have a certain amount of allocated space to work with. If the vector is grown past this space,
a new, larger allocation may need to be done (freeing the old one), since vectors must use contiguous memory.

This means that when the vector overflows its capacity, it will reallocate, invalidating the reference stored in the
iterator, and causing use-after-free.

Of course, there is a trivial solution in this case &mdash; store a reference to the `Vec`/`vector` object inside
the iterator instead of just the pointer to the vector on the heap. This leads to some extra indirection or a larger
stack size for the iterator (depending on how you implement it), but overall will prevent the memory unsafety.


This would still cause problems with more complex situations involving multidimensional vectors, however.




[stackoverflow-iter]: http://stackoverflow.com/questions/5638323/modifying-a-data-structure-while-iterating-over-it
[slides-iter]: http://manishearth.github.io/Presentations/Rust/#/1/2


## "It's effectively threaded"

> Aliasing with mutability in a sufficiently complex, single-threaded program is effectively the same thing as
> accessing data shared across multiple threads without a lock

(The above is my paraphrasing of someone else's quote; but I can't find the original or remember who made it)

Let's step back a bit and figure out why we need locks in multithreaded programs. The way caches and memory work;
we'll never need to worry about two processes writing to the same memory location simultaneously and coming up with
a hybrid value, or a read happening halfway through a write.

What we do need to worry about is the rug being pulled out underneath our feet. A bunch of related reads/writes
would have been written with some invariants in mind, and arbitrary reads/writes possibly happening between them
would invalidate those invariants. For example, a bit of code might first read the length of a vector, and then go ahead
and iterate through it with a regular for loop bounded on the length.
The invariant assumed here is the length of the vector. If `pop()` was called on the vector in some other thread, this invariant could be
invalidated after the read to `length` but before the reads elsewhere, possibly causing a segfault or use-after-free in the last iteration.

However, we can have a situation similar to this (in spirit) in single threaded code. Consider the following:


```rust
let x = some_big_thing();
let len = x.some_vec.len();
for i in 0..len {
    x.do_something_complicated(x.some_vec[i]);
}
```

We have the same invariant here; but can we be sure that `x.do_something_complicated()` doesn't modify `x.some_vec` for
some reason? In a complicated codebase, where `do_something_complicated()` itself calls a lot of other functions which may
also modify `x`, this can be hard to audit.

Of course, the above example is a simplification and contrived; but it doesn't seem unreasonable to assume that such
bugs can happen in large codebases &mdash; where many methods being called have side effects which may not always be evident.

Which means that in large codebases we have almost the same problem as threaded ones. It's very hard to maintain invariants
when one is not completely sure of what each line of code is doing. It's possible to become sure of this by reading through the code
(which takes a while), but further modifications may also have to do the same. It's impractical to do this all the time and eventually
bugs will start cropping up.


On the other hand, having a static guarantee that this can't happen is great. And when the code is too convoluted for
a static guarantee (or you just want to avoid the borrow checker), a single-threaded RWlock-esque type called [RefCell][refcell]
is available in Rust. It's a type providing interior mutability and behaves like a runtime version of the borrow checker.
Similar wrappers can be written in other languages.

Edit: In case of many primitives like simple integers, the problems with shared mutability turn out to not be a major issue.
For these, we have a type called [Cell][cell] which lets these be mutated and shared simultaenously. This works on all `Copy`
types; i.e. types which only need to be copied on the stack to be copied. (Unlike types involving pointers or other indirection)

This sort of bug is a good source of reentrancy problems too.




[refcell]: https://doc.rust-lang.org/core/cell/struct.RefCell.html
[cell]: http://doc.rust-lang.org/nightly/std/cell/struct.Cell.html

## Safe abstractions

In particular, the issue in the previous section makes it hard to write safe abstractions, especially with generic code.
While this problem is clearer in the case of Rust (where abstractions are expected to be safe and preferably low-cost),
this isn't unique to any language.

Every method you expose has a contract that is expected to be followed. Many times, a contract is handled by type safety itself,
or you may have some error-based model to throw out uncontractual data (for example, division by zero).

But, as an API (can be either internal or exposed) gets more complicated, so does the contract. It's not always possible to verify that the contract is being violated
at runtime either, for example many cases of iterator invalidation are hard to prevent in nontrivial code even with asserts.

It's easy to create a method and add documentation "the first two arguments should not point to the same memory".
But if this method is used by other methods, the contract can change to much more complicated things that are harder to express
or check. When generics get involved, it only gets worse; you sometimes have no way of forcing that there are no shared mutable aliases,
or of expressing what isn't allowed in the documentation. Nor will it be easy for an API consumer to enforce this.

This makes it harder and harder to write safe, generic abstractions. Such abstractions rely on invariants, and these invariants can often
be broken by the problems in the previous section. It's not always easy to enforce these invariants, and such abstractions will either
be misused or not written in the first place, opting for a heavier option. Generally one sees that such abstractions or patterns are avoided
altogether, even though they may provide a performance boost, because they are risky and hard to maintain. Even if the present version of
the code is correct, someone may change something in the future breaking the invariants again.

[My previous post](http://manishearth.github.io/blog/2015/05/03/where-rust-really-shines/) outlines a situation where Rust was able to choose
the lighter path in a situation where getting the same guarantees would be hard in C++.

Note that this is a wider problem than just with mutable aliasing. Rust has this problem too, but not when it comes to mutable aliasing.
Mutable aliasing is important to fix however, because we can make a lot of assumptions about our program when there are no mutable aliases.
Namely, by looking at a line of code we can know what happened wrt the locals. If there is the possibility of mutable aliasing out there; there's the
possibility that other locals were modified too. A very simple example is:

```rust
fn look_ma_no_temp_var_l33t_interview_swap(&mut x, &mut y) {
    *x = *x + *y;
    *y = *x - *y;
    *x = *x - *y;
}
// or
fn look_ma_no_temp_var_rockstar_interview_swap(&mut x, &mut y) {
    *x = *x ^ *y;
    *y = *x ^ *y;
    *x = *x ^ *y;
}
```

In both cases, when the two references are the same[^2], instead of swapping, the two variables get set to zero.
A user (internal to your library, or an API consumer) would expect `swap()` to not change anything when fed equal
references, but this is doing something totally different. This assumption could get used in a program; for example instead
of skipping the passes in an array sort where the slot is being compared with itself, one might just go ahead with it
because `swap()` won't change anything there anyway; but it does, and suddenly your sort function fills everything with
zeroes. This could be solved by documenting the precondition and using asserts, but the documentation gets harder and harder
as `swap()` is used in the guts of other methods.

Of course, the example above was contrived. It's well known that those `swap()` implementations have that precondition,
and shouldn't be used in such cases. Also, in most swap algorithms it's trivial to ignore cases when you're comparing
an element with itself, generally done by bounds checking.

But the example is a simplified sketch of the problem at hand.

In Rust, since this is statically checked, one doesn't worry much about these problems, and
robust APIs can be designed since knowing when something won't be mutated can help simplify
invariants.

[^2]: Note that this isn't possible in Rust due to the borrow checker.

## Wrapping up


Aliasing that doesn't fit the RWLock pattern is dangerous. If you're using a language like
Rust, you don't need to worry. If you're using a language like C++, it can cause memory unsafety,
so be very careful. If you're using a language like Java or Go, while it can't cause memory unsafety,
it will cause problems in complex bits of code.


This doesn't mean that this problem should force you to switch to Rust, either. If you feel that you
can avoid writing APIs where this happens, that is a valid way to go around it. This problem is much
rarer in languages with a GC, so you might be able to avoid it altogether without much effort. It's
also okay to use runtime checks and asserts to maintain your invariants; performance isn't everything.

But this _is_ an issue in programming; and make sure you think of it when designing your code.

<small>Discuss: [HN](https://news.ycombinator.com/item?id=9560158), [Reddit](http://www.reddit.com/r/rust/comments/369jnx/the_problem_with_singlethreaded_shared_mutability/)</small>
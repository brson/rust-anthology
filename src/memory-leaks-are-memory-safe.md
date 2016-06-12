---
title: Memory Leaks are Memory Safe
layout: default

description: >
    Memory unsafety and memory leaks are distinct concepts, despite
    their names. Languages that are merely memory safe (both Rust and
    GC-reliant managed ones) have no guarantee of preventing memory leaks.

comments:
    r_rust: "https://www.reddit.com/r/rust/comments/4dgvvh/memory_leaks_are_memory_safe_huon_on_the_internet/"
    users: "https://users.rust-lang.org/t/memory-leaks-are-memory-safe/5288?u=huon"
--    r_programming: ""
--    hn: ""
---


[*Memory unsafety*][ms] and [*memory leaks*][ml] are arguably the two
categories of bugs that have received the most attention for
prevention and mitigation. As their names suggest, they are in the
same part of "bug space", however they are in some ways diametric
opposites, and solving one does not solve the other. The widespread
use of memory-safe managed languages hammers this point home: they
avoid some memory unsafety by presenting a "leak everything" model to
programmers.

Put simply: **memory unsafety is doing something with invalid data,
a memory leak is *not* doing something with valid data**. In table
form:


[ms]: https://en.wikipedia.org/wiki/Memory_safety
[ml]: https://en.wikipedia.org/wiki/Memory_leak


|| Valid data | Invalid data |
|---------------|-------------|---------------|
| Used           | 👍 | Memory unsafety |
| Not used            | Memory leak | 👍 |

The best programs lie in the 👍 cells only: they manipulate valid
things, and don't manipulate invalid ones. Passable programs might
also have some valid data that they don't use (leak memory), but bad
ones will try to use invalid data.

When a language, such as Rust, advertises itself as memory *safe*, it
isn't saying anything about whether memory *leaks* are impossible.


## Consequences

The most important difference between memory unsafety and memory leaks
in practice is the scope of their possible results, with one easily
very serious, and the other usually just annoying.

Memory safety is a key building block in any other form of
safety/program correctness. If a program is not memory safe, there are
very few guarantees about its behaviour, due to the possibility of
memory corruption. A malicious party interacting with a memory unsafe
program may be able to exploit the unsafety to
[read private keys straight out of a server's memory][heartbleed] or
to execute arbitrary code on someone else's computer.

[heartbleed]: https://en.wikipedia.org/wiki/Heartbleed

On the other hand, a memory leak will generally, at worst, lead to a
denial-of-service, where a useful program is killed due to using too
much memory (and, as it grows to this stage, the computer may be
rendered essentially inoperable due to memory pressure). This also can
be caused by a malicious attacker, but the damage is usually very much
more controlled. Of course, a denial-of-service can be extremely
annoying, and there are places where this is a critical problem, but
memory unsafety would generally be equally problematic---more likely,
more problematic. (Additionally, given memory unsafety's inherent lack
of control, a problem there could easily lead to a denial-of-service
similar/identical to that which a memory leak can cause.)

Given this, most programming languages choose to tolerate memory leaks
(they allow data not be deallocated/cleaned up after the last time it
is used), but not memory unsafety. That is, most "memory safe
languages" guarantee all programs written in them have no
unsafety[^optin], and they only try---usually, try hard---to help
programmers avoid leaks, but without making a hard promise.

[^optin]: More specifically, programming languages will guarantee that
    one can only get unsafety by explicitly opting in to it, in some
    form, such as via Python's `ctypes` module, or Rust's `unsafe`
    keyword.

## `delete free`

There are a few different ways to get memory unsafety, but there's one
category (from the Wikipedia article) that stands out when we're
discussing memory management:

> - **Dynamic memory errors** - incorrect management of dynamic memory and pointers:
>   - **Dangling pointer** - a pointer storing the address of an object that has been deleted.
>   - **Double free** - repeated calls to free may prematurely free a new object at the same address. If the exact address has not been reused, other corruption may occur, especially in allocators that use free lists.
>   - **Invalid free** - passing an invalid address to free can corrupt the heap.
>   - **Null pointer accesses** will cause an exception or program termination in most environments, but can cause corruption in operating system kernels or systems without memory protection, or when use of the null pointer involves a large or negative offset.

In that list, only null pointer accesses aren't caused by deallocating
memory---calling the `free` function to mark an allocation as
unused/return it to the operating system---incorrectly. And thus, one
way to be guaranteed to avoid three quarters of those possibilities is
to just never call `free`: if memory is never released, it is
impossible to suffer from the problems caused by releasing it. In
terms of the table above, removing `free` is removing the "Invalid
data" column: all data is always valid.

Of course, just disallowing `free` has some downsides[^lockfree], particularly
making it very annoying to write programs that don't eventually use
all available memory. However, computers are infallible in ways humans
are not, so maybe we could allow them to call `free`...

[^lockfree]: It also has some upsides beyond just less memory
    unsafety: if one is OK without `free`, it becomes much easier to
    write programs where the lifetime of data is unclear, which makes
    many concurrent algorithms easier to write. That said, there are
    schemes for writing such code when manual `free`s are required,
    such as [hazard pointers][hazard] and the simpler
    [epoch-based memory reclamation][epoch].

[hazard]: https://en.wikipedia.org/wiki/Hazard_pointer
[epoch]: http://aturon.github.io/blog/2015/08/27/epoch/


## Optimising leaks

A large fraction of modern code is written in languages designed to be
memory safe, languages like Java, Javascript, Python and Ruby. They
have no explicit `free`, and so automatically manage memory (hence
"managed language") via a *garbage collector* built into the runtime
systems shipped with the languages' compilers and interpreters.

At its core[^layers], garbage collection is a way to make it feasible
to expose a programming model where all allocations leak. Letting a
garbage collector manage every allocation theoretically allows
programs (and programmers) to pretend that memory is infinite, not
needing to carefully track when memory isn't needed any more: programs
do whatever they want, and the GC will automatically and dynamically
free chunks of memory that are guaranteed to be unneeded, ensuring the
program's memory use remains under control. Almost all garbage
collectors determine neededness conservatively by finding things no longer
accessible from the main program (the garbage collector itself needs
to keep track of/have access to all allocations).

[^layers]: It's worth noting that the detailed knowledge of memory
    layout required for a top-flight garbage collectors lends itself
    to other tricks, such as allocations usually being a cheap pointer
    bump with a generational GC, and the ability for a moving GC to
    shift data around, improving cache locality (especially useful
    given the generally pointer-heavy nature of most managed
    languages). However, these tricks are orthogonal to both memory
    safety and memory leaks.

In practice, the programmer has to think about non-infinite
memory and its consequences a little more often than never, but memory
unsafety concerns *are* removed, as desired. High-performance code
often has to chose particular coding patterns to work-around
deficiencies with garbage collectors (such as object pools to avoid
touching the GC in tight loops), and one can accidentally create
[chains of references][llp] that keep large trees of data
unnecessarily alive.

However, even in the face of practical concerns, the point stands:
without `free`, there's no scope for some types of memory unsafety.

<!--(Due credit: I think I first heard an idea along the lines "GC is an
optimisation for leaking" from
[Alexis Beingessner](https://twitter.com/Gankro).)-->

[llp]: https://en.wikipedia.org/wiki/Lapsed_listener_problem

## Less leaky abstractions

Given my status, I'd be remiss to mention an alternative to the
leak-everything managed paradigm: instead using a technique that
crosses out the whole "Invalid data" column, one can be more precise
and cross out only the "Memory unsafety" cell. The [Rust programming language][rust] does this.

Rust doesn't have C-style manual memory management, but rather
RAII/scope-based resource management similar to C++, allowing types to
have destructors for automatic clean-up. It does not literally have a
`free` function users must remember to call (removing most of the
"manual"), but the [`drop`][drop] function serves the role of explicit
`free`, allowing one to explicitly cause the destructor to be run on a
value, thus invalidating it. In contrast to both C and C++, the
language prevents use of such data at compile time to avoid memory
unsafety.

[drop]: http://doc.rust-lang.org/std/mem/fn.drop.html

However, a programming model that's not "leak everything" doesn't mean
it is "leak nothing": the revised table for Rust (and anything
similar) still has its memory leak cell.

|| Valid data | Invalid data |
|---------------|-------------|---------------|
| Used           | 👍 | Impossible |
| Not used            | Memory leak | 👍 |

I'm not including this section because I think it's a great promotion
of Rust (being allowed to have invalid data that one can't use doesn't
exactly sound world-shaking[^moves]...), but because that is the hole
which this article is filling. The similarity of the phrases "memory
leak" and "memory safety" regularly tricks people who have read "Rust
is memory safe" into thinking Rust is (just) preventing memory leaks,
leading to legitimate doubts about what Rust offers instead of, say,
modern C++ in the space of low-level systems languages.  **Rust
disallows memory unsafety, but memory leaks are possible**.

[^moves]: It's pretty useful, in that it allows move semantics to
    work, but that's an article for another time, perhaps.

### `std::mem::forget`

Finally, returning to the title, Rust has the [`forget`][forget]
function, which throws away a value without actually running the
destructor while still marking it invalid as if freed normally, thus
possibly leaking memory. For a long time, this was marked as `unsafe`,
that is, Rust was implicitly including memory leaks as something the
programmer must opt-in to, like the risk of memory unsafety. However,
this was not correct in practice, as things like reference cycles and
thread deadlock could cause memory to leak. Rust [decided][safe] to
make `forget` safe, focusing its guarantees on just preventing memory
unsafety and instead making only best-effort attempts
towards preventing memory leaks (like essentially all other
languages, memory safe and otherwise).

[rust]: https://www.rust-lang.org/
[forget]: https://doc.rust-lang.org/std/mem/fn.forget.html
[safe]: https://github.com/rust-lang/rfcs/blob/master/text/1066-safe-mem-forget.md

### Not all is lost!

Like modern C++, the efforts Rust makes are pretty good, with
RAII/scope-based resource management (specifically destructors) being
a powerful tool for managing memory and [beyond][locks] (and
[beyonder][socket]), especially when combined with Rust's
move-by-default semantics. The point about not being a guarantee is
that (a) it's not trivial to make a useful *formal* definition of
memory leak (at the very least, usefulness varies depending on the
context), and (b) there are relatively rare edge-cases that seem to be
impossible to statically prevent without non-trivial cost. The
[wash-up][leaking] in Rust's standard library is all values have to be
*memory safe* to leak, but they can still consider being leaked
incorrect. In other words, one may get unwanted behaviour if a value
is leaked, but the consequences will be more far controlled than a
segfault or memory corruption.

[leaking]: http://doc.rust-lang.org/stable/nomicon/leaking.html
[locks]: http://blog.rust-lang.org/2015/04/10/Fearless-Concurrency.html#locks
[socket]: http://blog.skylight.io/rust-means-never-having-to-close-a-socket/

{% include comments.html c=page.comments %}

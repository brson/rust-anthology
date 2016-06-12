---
layout: default
title: Myths and Legends about Integer Overflow in Rust

description: >
    Integer overflow detection/handling in Rust is sometimes misunderstood.

comments:
    users: "https://users.rust-lang.org/t/myths-and-legends-about-integer-overflow-in-rust/5612"
    r_rust: "https://www.reddit.com/r/rust/comments/4gz93u/myths_and_legends_about_integer_overflow_in_rust/"
#    r_programming: "https://www.reddit.com/r/programming/comments/4gz996/myths_and_legends_about_integer_overflow_in_rust/"
#    hn: "https://news.ycombinator.com/item?id=11595398"
---

The primitive integer types supported by CPUs are finite
approximations to the infinite set of integers we're all used to. This
approximation breaks down and some computations will give results that
don't match real integers, like `255_u8 + 1 == 0`. Often, this
mismatch is something the programmer didn't think about, and thus can
easily result in bugs.

Rust is a programming language designed to protect against bugs; it
does focus on outlawing the most insidious class of them---memory
unsafety---but it also likes to assist the programmer in avoiding
others: [memory leaks][ml], [ignoring errors][mu], and, in this case,
[integer overflow][io].

[qr]: https://en.wikipedia.org/wiki/Quotient_ring
[mu]: https://doc.rust-lang.org/std/result/#results-must-be-used
[ml]: {% post_url 2016-04-04-memory-leaks-are-memory-safe %}#not-all-is-lost
[io]: https://en.wikipedia.org/wiki/Integer_overflow

## Overflow in Rust

The status of detecting and avoiding overflow in Rust changed several
times in the lead up to the 1.0.0 release last year. That fluid
situation means there's still quite a bit of confusion about exactly
how overflow is handled and mitigated, and what the consequences are.

Before 1.0.0-alpha, overflow was handled by wrapping, giving the
result one would expect from a two's complement representation (as
most modern CPUs use). However, this was thought to be suboptimal:
unexpected and unintended overflow is a common source of bugs. It is
particularly bad in C and C++ due to signed overflow being undefined,
and the lack of protection against memory safety violations---overflow
can easily cascade into memory corruption---but it is still
problematic in more defensive languages like Rust: there are numerous
examples of overflows, they've cropped up in many video games (in
[their economies][diablo], in [health bars][hearthstone], and more),
[binary search][binary] and even [aircraft][boeing]. More prosaically,
code like `max(x - y, z)` turns up semiregularly, and it can give
wildly wrong results when the numbers are unsigned and `x - y`
overflows through 0. Thus, there was a push to make Rust more
defensive about integer overflows.

[binary]: http://googleresearch.blogspot.com.au/2006/06/extra-extra-read-all-about-it-nearly.html
[diablo]: http://www.gamasutra.com/blogs/MaxWoolf/20130508/191959/Diablo_III_Economy_Broken_by_an_Integer_Overflow_Bug.php
[hearthstone]: http://www.codeproject.com/Articles/802368/Integer-Overflow-in-Hearthstone
[boeing]: http://www.nytimes.com/2015/05/01/business/faa-orders-fix-for-possible-power-loss-in-boeing-787.html?_r=0

The current status in Rust was decided in [RFC 560][rfc560]:

- in debug mode, arithmetic (`+`, `-`, etc.) on signed and unsigned primitive integers
is **checked for overflow**, panicking if it occurs, and,
- in release mode, overflow is not checked and is **specified to wrap
  as two's complement**.

These[^unconditional] overflow checks can be manually disabled or
enabled independently of the compilation mode both globally and at a
per-operation level.

[^unconditional]: There are some unconditional and uncontrollable
    overflow checks for arithmetic: `x / 0`, and [`MIN / -1`][mindiv] (for
    signed integer types), and similarly for `%`. These computations
    are actually undefined behaviour in C and LLVM (which is the
    historical reason for why rustc has them unconditional), although,
    it seems to me that Rust could theoretically consider the
    latter a normal overflow and return `MIN` when the checks are off.

[mindiv]: http://blog.regehr.org/archives/887

By checking for overflow in some modes, overflow bugs in Rust code are
hopefully found earlier. Furthermore, code that actually wants
wrapping behaviour is explicit about this requirement, meaning fewer
false positives for both future static analyses and for code that
enables overflow checking in all modes.

[rfc560]: https://github.com/rust-lang/rfcs/blob/master/text/0560-integer-overflow.md

## Myth: overflow is undefined

One way to allow compilers to catch overflow is to make it
*undefined*, that is, there's absolutely no guarantees about behaviour
when overflow occurs and hence it is legal to panic instead of trying
to return something. However, Rust's core goal is ensuring memory
safety, and leaving things *undefined* ---in the sense of C undefined
behaviour---is in direct contradiction to this. For one, a variable
that is undefined does not have to have a consistent value from use to
use:

{% highlight rust linenos %}
// pseudo-Rust
let x = undefined;

let y = x;
let z = x;
assert_eq!(y, z); // this could fail
{% endhighlight %}

This has disastrous consequences for things that rely on checking a
value for safety, like indexing an array with bounds checks `foo[x]`:

{% highlight rust linenos %}
let x = undefined;

// let y = foo[x]; is equivalent to

let y = if x < foo.len() {
    unsafe { *foo.get_unchecked(x) }
} else {
    panic!("index out of bounds")
};
{% endhighlight %}

If the value of `x` isn't consistent from the `x < foo.len()`
comparison to the actual access of the array, there's no guarantee the
access will be in-bounds: the comparison might be `0 < foo.len()`,
while the index might be `foo.get_unchecked(123456789)`. Problematic!

Therefore, unlike signed integers in C, integer overflow cannot be
undefined in Rust. In other words, compilers must assume that overflow
may happen (unless they can prove otherwise). This has a
possibly unintuitive consequence that `x + 1 > x` is not always true,
something C compilers *do* assume is true if `x` is signed.

"But what about performance?" I hear you ask. It is true that
undefined behaviour drives optimisations by allowing the compiler to
make assumptions, and hence removing this ability could impact
speed. Overflow of signed integers being undefined is particularly
useful in C because such integers are often used as the induction
variables on loops, and hence the ability to make assumptions allows
more precise analysis of loop trip counts: `for (int i = 0; i < n;
i++)` will repeat `n` times, as `n` can be assumed to not be
negative. Rust sidesteps much of this by using unsigned integers for
indexing (`0..n` will always be `n` steps), and also by allowing easy
custom iterators, which can be used to loop directly over data
structures like `for x in some_array { ... }`. These iterators can
exploit guarantees about the data structures internally without having
to expose undefined behaviour to the user.

Another thing Rust misses compared to C is optimising `x * 2 / 2` to
just `x`, when `x` is signed. In this case, there's no built-in
feature for getting the optimisation (beyond just writing `x` instead
of the complicated arithmetic of course), however in my experience,
expressions like that most often occur with `x` known at compile time,
and hence the whole expression can be constant-folded.

## Myth: overflow is unspecified

Similar to leaving the result of overflow undefined, it could be left
just unspecified, meaning the compiler must assume it could happen,
but is allowed to make the operation return any particular result (or
not return at all). Indeed, [the first version][first] of
[RFC 560][rfc560] for checking integer overflow, proposed:

> Change this to define them, on overflow, as either returning an
> unspecified result, or task panic, depending on whether the overflow
> is checked.
>
> [...]
>
> - In theory, the implementation returns an unspecified result. In practice, however, this will most likely be the same as the wraparound result. Implementations should avoid needlessly exacerbating program errors with additional unpredictability or surprising behavior.
> - Most importantly: this is not undefined behavior in the C sense. Only the result of the operation is left unspecified, as opposed to the entire program's meaning, as in C. The programmer would not be allowed to rely on a specific, or any, result being returned on overflow, but the compiler would also not be allowed to assume that overflow won't happen and optimize based on this assumption.

[rfc560]: https://github.com/rust-lang/rfcs/pull/560
[first]: https://github.com/nikomatsakis/rfcs/blob/630dd70a51c0c7e166be78cd3bc8f1247664db28/text/0000-integer-overflow.md#semantics-of-overflow-with-the-built-in-types
[last]: https://github.com/rust-lang/rfcs/blob/master/text/0560-integer-overflow.md#arithmetic-operations-with-error-conditions

There was a lot of discussion about the RFC and about the
"unspecified" result of arithmetic, meaning that `127_i8 + 1` could
theoretically return `-128` (per two's complement) or `0` or `127`, or
anything else. This idea took hold in the community... and then it was
changed.

With strong encouragement from a few people, the RFC was tightened up
to actually specify the result: arithmetic on primitives that
overflows either doesn't return (e.g. it panics), or returns the
wrapped result one would expect from two's complement. [It][last] now says:

> The operations +, -, *, can underflow and overflow. When checking is
> enabled this will panic. When checking is disabled this will two's
> complement wrap.

Specifying the result is a defensive measure: errors are more likely
to cancel out when overflow isn't caught. An expression like `x - y +
z` is evaluated like `(x - y) + z` and hence the subtraction could
overflow (e.g. `x = 0` and `y = 1` both unsigned), but as long as `z`
is large enough (`z >= 1` in that example), the result will be what
one expects from true integers.

The change happened towards the end of the 160 comment long RFC
discussion and so it was easy for people to miss, making it easy for
people to still think the result is unspecified.

## Myth: the programmer has no control of overflow handling

One of the main objections to adding overflow checking was the
existance of programs/algorithms that *want* two's complement
overflow, such as hashing algorithms, certain data structures (ring
buffers, particularly) and even image codecs. For these algorithms,
using `+` in debug mode would be incorrect: the code would panic even
though it was executing as intended. Additionally, some more
security-minded domains wish to have overflow checks on in all modes
by default.

The RFC and the standard library provide *four*
sets of methods beyond the pure operators:

- [`wrapping_add`][wa], [`wrapping_sub`][ws], ...
- [`saturating_add`][sa], [`saturating_sub`][ss], ...
- [`overflowing_add`][oa], [`overflowing_sub`][os], ..
- [`checked_add`][ca], [`checked_sub`][cs], ...

These should cover all bases of "don't want overflow to panic in some
modes":

- `wrapping_...` returns the straight two's complement result,
- `saturating_...` returns the largest/smallest value (as appropriate) of
the type when overflow occurs,
- `overflowing_...` returns the two's
complement result along with a boolean indicating if overflow occured,
and
- `checked_...` returns an `Option` that's `None` when overflow
occurs.

All of these can be implemented in terms of `overflowing_...`, but the
standard library is trying to make it easy for programmers to do the
right thing in the most common cases.

Code that truly wants two's complement wrapping can be written like
`x.wrapping_sub(y).wrapping_add(z)`. This works, but clearly can get a
little verbose, verbosity that can be reduced in some cases via the
standard library's [`Wrapping`][w] wrapper type.

The current state isn't necessarily the final state of overflow
checking: the RFC even mentioned some [future directions][fd]. Rust
could introduce operators like Swift's wrapping `&+` in future,
something that was not done initially because Rust tries to be
conservative and reasonably minimal, as well as hypothetically having
scoped disabling of overflow checking (e.g. a single function could be
explicitly marked, and its internals would thus be unchecked in all
modes). There's interest in the latter particularly, from some of
Rust's keenest (potential) users [Servo][servoo] and [Gecko][oxi].

[servoo]: https://github.com/rust-lang/cargo/issues/2262
[oxi]: https://wiki.mozilla.org/Oxidation#Rust_.2F_Cargo_nice-to-haves

For code that wants overflow checking everywhere, one can either use
`checked_add` pervasively (annoying!), or explicitly enable
them. Although they are tied to debug assertions by default, overflow
checks can be turned on by passing `-C debug-assertions=on` to rustc,
or setting the `debug-assertions` field of a
[cargo profile][profile]. There's also work on having them able to be
activated independently of other debug assertions (rustc currently has
the unstable `-Z force-overflow-checks` flag).

[wa]: http://doc.rust-lang.org/std/primitive.i32.html#method.wrapping_add
[sa]: http://doc.rust-lang.org/std/primitive.i32.html#method.saturating_add
[oa]: http://doc.rust-lang.org/std/primitive.i32.html#method.overflowing_add
[ca]: http://doc.rust-lang.org/std/primitive.i32.html#method.checked_add
[ws]: http://doc.rust-lang.org/std/primitive.i32.html#method.wrapping_sub
[ss]: http://doc.rust-lang.org/std/primitive.i32.html#method.saturating_sub
[os]: http://doc.rust-lang.org/std/primitive.i32.html#method.overflowing_sub
[cs]: http://doc.rust-lang.org/std/primitive.i32.html#method.checked_sub
[w]: http://doc.rust-lang.org/std/num/struct.Wrapping.html
[fd]: https://github.com/rust-lang/rfcs/blob/master/text/0560-integer-overflow.md#alternatives-and-possible-future-directions
[profile]: http://doc.crates.io/manifest.html#the-profile-sections

## Myth: the approach to overflow checks makes code slow

Rust aims to be as fast as possible, and the design of the current
overflow checking approach took various performance considerations
seriously. Performance is one of the main motivations for checks being
disabled in release builds by default, and indeed means that there's
no speed penalty to the way in which Rust helps mitigate/flag
integer overflow bugs during development.

It's an unfortunate reality that checking for overflow requires more
code and more instructions:

{% highlight rust linenos %}
#[no_mangle]
pub fn unchecked(x: i32, y: i32) -> i32 {
    x.wrapping_add(y)
}

#[no_mangle]
pub fn checked(x: i32, y: i32) -> i32 {
    x + y
}
{% endhighlight %}

With `-O -Z force-overflow-checks`, on x86[^arm], this compiles to (with some
editing for clarity):

[^arm]: On 32-bit ARM, LLVM [currently decides][llvmbug] to emit a
    chain of redundant comparisons and register manipulations, so the
    penalty is even higher!

[llvmbug]: https://llvm.org/bugs/show_bug.cgi?id=27571

{% highlight asm linenos %}
unchecked:
	leal (%rdi,%rsi), %eax
	retq

checked:
	pushq	%rax
	addl	%esi, %edi
	jo	.overflow_occurred
	movl	%edi, %eax
	popq	%rcx
	retq
.overflow_occurred:
	leaq	panic_loc2994(%rip), %rdi
	callq	_ZN9panicking5panic20h4265c0105caa1121SaME@PLT
{% endhighlight %}

It is definitely annoying that there are all[^extra] those extra
instructions, as is the fact that implementations are forced to use
`add` rather than having the option to use `lea`[^lea]. However, an
even bigger performance hit is how overflow checks inhibit other
optimisations, both because the checks themselves serialise code
(inhibiting things like loop unrolling/reordering and vectorisation)
and because the panic/stack unwinding forces the compiler to
[be more conservative][conservative].

[^extra]: There's more instructions in the function version than there
          would be when `checked` is inlined (as it should be): the
          `pushq`/`pop`/`movl` register management wouldn't be
          necessary. Also, even without inlining I believe the
          `pushq`/`popq` stack management isn't necessary, but
          unfortunately the published Rust binaries <s>don't use a new
          enough version of LLVM to get its new <a
          href="http://reviews.llvm.org/D9210">"shrink wrapping"
          optimisation pass</a></s> use a version of LLVM that
          contains [a bug in its "shrink-wrapping" pass][shrinkwrap]
          (thanks for [the correction][eli], Eli Friedman).

[shrinkwrap]: https://llvm.org/bugs/show_bug.cgi?id=25614
[eli]: https://users.rust-lang.org/t/myths-and-legends-about-integer-overflow-in-rust/5612/2?u=huon

[^lea]: On x86, it can be extremely useful to be able to use `lea`
    (load effective address) for arithmetic: it can do relatively
    complicated computations, and is usually computed in a different
    part of the CPU and its pipeline than `add`, allowing exploiting
    more instruction-level parallelism. The x86 ISA allows
    dereferencing complicated pointer computations: the most general
    form is `A(r1, r2, B)` (in AT&T syntax), which is equal to `r1 +
    B * r2 + A` for registers `r1` and `r2` and constants `A` and
    `B`. Normally these are used directly in memory instructions like
    `mov` (e.g. `let y = array_of_u32[x];` could compile to something
    along the lines of `mov (array_of_u32.as_ptr(), x, 4), y` ,
    because each element is of size 4), but `lea` allows just doing
    the arithmetic without hitting memory.  All-in-all, being able to
    use `lea` for arithmetic is quite nice. The downside is of course
    `lea` doesn't integrate directly with overflow detection: it
    doesn't set the CPU flags that signal it.

All these considerations explain why overflow checks are not enabled
in release mode, where usually getting the highest performance
possible is desirable.

That said, even when the checks are enabled in release mode, the
performance hit can be reduced like with bounds checked arrays.  For
one, compilers can do range analysis/inductive proofs to deduce that
certain overflow checks are sure to never fail; indeed,
[significant][1] [effort][swiftroc] has been [devoted][llvmo] to [the topic][gcco]. Additionally,
the significant pain caused by using panics can be reduced by
application authors [converting panics into aborts][p->a], if it's
appropriate for their domain.

The integer overflow RFC gives itself some room for optimisation too:
it [allows "delayed panics"][delayed], meaning a Rust implementation
is allowed to perform a sequence of operations like `a + b + c + d`
and only panic once at the end if any intermediate overflow occurred,
instead of having to separately check for overflow (and panic) in `tmp
= a + b` and then in `tmp + c` etc. No known implementation actually
does this yet, but they could.

[delayed]: https://github.com/rust-lang/rfcs/blob/master/text/0560-integer-overflow.md#delayed-panics

[conservative]: http://danluu.com/integer-overflow/
[p->a]: https://github.com/rust-lang/rfcs/blob/master/text/1513-less-unwinding.md
[1]: http://blog.regehr.org/archives/1384
[swiftroc]: https://github.com/apple/swift/blob/16b3d6c8d5b2d610cdfd72898f6ab384e632b69b/lib/SILOptimizer/Transforms/RedundantOverflowCheckRemoval.cpp
[llvmo]: https://github.com/llvm-mirror/llvm/blob/8b47c17a53d683f313eaaa93c4a53de26d8fcba5/lib/Transforms/InstCombine/InstCombineAddSub.cpp#L893-L987
[gcco]: https://github.com/gcc-mirror/gcc/blob/fd3211e13bbbb6882f477aa75a36eb0ccdec485f/gcc/tree-vrp.c#L9792-L9884

## Myth: the checks find no bugs

All the design/discussion/implementation of this scheme for handling
integer overflow would be wasted if it didn't actually find any bugs
in practice. I personally have had quite a few bugs found nearly as I
write them, with expressions like `cmp::max(x - y, z)` (they never hit
the internet, so no links for them), especially when combined with
testing infrastructure like [`quickcheck`][qc].

[qc]: https://crates.io/crates/quickcheck

The overflow checks have found bugs through out the ecosystem; for instance, (not exhaustive!)

- [the standard library][iter]
- [the compiler][compiler]
- [the built-in benchmark harness][bench]
- [Servo][servo1]
- [`image`][image]
- [`url`][url]
- [`webrender`][wr]

[iter]: https://github.com/rust-lang/rust/pull/22532#issuecomment-75168901
[compiler]: https://github.com/rust-lang/rust/pull/31281
[bench]: https://github.com/rust-lang/rust/pull/23127
[image]: https://github.com/PistonDevelopers/image/pull/412
[url]: https://github.com/servo/rust-url/issues/124
[wr]: https://github.com/servo/webrender/pull/243
[servo1]: https://github.com/servo/servo/issues/6040


Beyond Rust, there's a lot of evidence for the dangers of integer overflow and
desire for detecting/protecting against them. It was on the
[CWE/SANS list of top 25 errors in 2011][list], languages like Swift
will unconditionally check for overflow, and others like Python 3 and
Haskell will avoid overflow entirely by default, via arbitrary
precision integers. Furthermore, in C, several compilers have options
to both make signed overflow defined as two's complement wrapping
(`-fwrapv`) and to catch it when it does happen
(`-fsanitize=signed-integer-overflow`).

[list]: http://cwe.mitre.org/top25/

*Thanks to [Nicole Mazzuca][ubsan], [James Miller][aatch],
  [Scott Olson][scott], and 👻👻👻 for reading and giving feedback on
  this post.*

[aatch]: https://github.com/Aatch
[scott]: https://github.com/tsion
[ubsan]: https://github.com/ubsan

{% include comments.html c=page.comments %}

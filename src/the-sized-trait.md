---
layout: default
title: The Sized Trait
description: "A short summary of the Sized trait and dynamically sized types in Rust."

comments:
    r_rust: http://www.reddit.com/r/rust/comments/2s2gee/the_sized_trait/
---

An important piece in my story about trait objects in
[Rust](http://rust-lang.org)[^version] is [the `Sized` trait][sized],
so I'm slotting in this short post between
[my discussion of low-level details][previouspost] and
[the post on "object safety"][nextpost].

{% include trait-objects.html n=1 %}


[^version]: Per the [previous post][previouspost], this post is
            designed to reflect the state of Rust at version: `rustc
            1.0.0-nightly (44a287e6e 2015-01-08 17:03:40 -0800)`.

[previouspost]: {% post_url 2015-01-10-peeking-inside-trait-objects %}
[nextpost]: {% post_url 2015-01-13-object-safety %}

`Sized` is a (very) special compiler built-in trait that is
automatically implemented or not based on the sizedness of a type. A
type is considered sized if the precise size of a value of type is
known and fixed at compile time once the real types of the type
parameters are known (i.e. after completing monomorphisation). For
example,

- `u8` is one byte,
- `Vec<T>` is either 12 or 24 bytes (platforms with 32 and 64 bit
  pointers respectively), independent of `T`,
- pointers like `&T` are sized too, on 64-bit platforms `&T` is either
  8 or 16 bytes, for sized `T` and unsized `T` respectively. This may
  seems like the size isn't known, but the sizedness of `T` is always
  known at compile time, so the precise one of those options is also
  known.

Types for which the size is not known are called
[dynamically sized types (DSTs)][dst], and there's two classes of
examples in current Rust[^virtual]: `[T]` and `Trait`. A slice[^str]
`[T]` is unsized because it represents an unknown-at-compile-time
number of `T`s contiguous in memory. A `Trait` is unsized because it
represents a value of any type that implements `Trait` and these have
wildly different sizes; I discussed this
[in the previous post too][whypointers]. Unsized values must always
appear behind a pointer at runtime, like `&[T]` or `Box<Trait>`, and
have the information required to compute their size and other relevant
properties (the length for `[T]`, the vtable for `Trait`) stored next
to that pointer.

[^virtual]: There is the possibility that Rust will gain some form of
            ["inheritance"][inherit], and Niko points out to me that
            `Sized` may play an important role there too: certain
            types (e.g. "base classes" in an conventional inheritance
            scheme)  make sense to be unsized.

[inherit]: http://discuss.rust-lang.org/t/summary-of-efficient-inheritance-rfcs/494

[^str]: The unsized string type `str` is usually considered a slice,
        since it is just a `[u8]` with the guarantee that the bytes
        are valid UTF-8.



Sized types are more flexible, since the compiler knows how to
manipulate them directly: passing them directly into functions, moving
them about in memory. Putting an unsized type behind a pointer
effectively makes it sized. A `Box` trait object, like `Box<Trait>`,
is the closest one can get to handling a trait object as a normal
value; the `Box` ensures sizedness (at the expense of an allocation)
without fundamentally changing the ownership semantics of a normal
value.

## `?Sized`

The `Sized` trait gets some special syntax for use in bounds, at the
moment: `?Sized`. Such a bound is necessary because `Sized` is
special: it is a default bound for type parameters in most positions,
and so one needs some way to opt-in to a parameter not necessarily
being sized.

{% highlight rust linenos %}
fn foo<T>() {} // can only be used with sized T

fn bar<T: ?Sized>() {} // can be used with both sized and unsized T
{% endhighlight %}

This bound is particularly special because adding the `?Sized` bound
to a parameter `T` increases the number of types that can be used for
`T`, whereas every other trait bound reduces it.

This unusual decision was chosen because of the increased flexibility
of sized types, and some data (which I now can't find in the issue
tracker) which indicated that most type parameters needed to be
sized. That is, not having these defaults would result in many
instances of `T: Sized` bounds in the standard library and elsewhere.

However, I believe this data did not consider using some form of
inference (like lifetime elision) to try to guess when sizedness was
likely to be needed, and some data Niko has been collecting apparently
implies that such inference may make removing this special case
significantly more palatable. (It may or may not be so palatable so as
to be worth the breaking change...)

[sized]: https://doc.rust-lang.org/nightly/std/marker/trait.Sized.html
[whypointers]: {% post_url 2015-01-10-peeking-inside-trait-objects %}#why-pointers
[dst]: http://smallcultfollowing.com/babysteps/blog/2014/01/05/dst-take-5/

{% include comments.html c=page.comments %}

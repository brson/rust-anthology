---
layout: default
title: Object Safety

description: >
    An overview of so-called "object safety" in Rust, and why it is necessary for trait objects.

comments:
    r_rust: http://www.reddit.com/r/rust/comments/2s2okp/object_safety/
---

A trait object in [Rust](http://rust-lang.org)[^version] can only be
constructed out of traits that satisfy certain restrictions, which are
collectively called "object safety". This object safety can appear to
be a needless restriction at first, I'll try to give a deeper
understanding into why it exists and related compiler behaviour.


[^version]: [As usual][previouspost], this post is designed to reflect
            the state of Rust at version `rustc 1.0.0-nightly
            (44a287e6e 2015-01-08 17:03:40 -0800)`.


[previouspost]: {% post_url 2015-01-10-peeking-inside-trait-objects %}
[sizedpost]: {% post_url 2015-01-12-the-sized-trait %}

{% include trait-objects.html n=2 %}

This is the second (and a half) in a short series of articles on trait
objects. The first
one---[Peeking inside Trait Objects][previouspost]---set the scene by
looking into the low-level implementation details of trait objects,
and the
first-and-a-half-th---[an interlude about `Sized`][sizedpost]---looked
at the special `Sized` trait. I strongly recommended at least glancing
over it to be familiar with trait objects, vtables and `Sized`,
since this post builds on those concepts.

## Motivation

The notion of object safety was introduced in [RFC 255][rfc255], with
the motivation that one should be able to use the dynamic trait object
types `Foo` (as a type) in more places where a "static" `Foo` (as a
trait) generic is expected. In a sense, it is bringing the two uses of
traits---static dispatch and dynamic dispatch---closer together,
reducing special handling in the language.

The high-level behaviour/restriction imposed by that RFC is: a trait
object---`&Foo`, `&mut Foo`, etc.---can only be made out of a trait
`Foo` if `Foo` is object safe. This section will focus on borrowed `&`
trait objects, but what is said applies to any.

Let's look at an example of the things object safety enables: if we
have a trait `Foo` and a function like

{% highlight rust linenos %}
fn func<T: Foo + ?Sized>(x: &T) { ... }
{% endhighlight %}

It would be nice to be able to call it like `func(object)` where
`object: &Foo`; that is, take `T` to be the dynamically sized type
`Foo`. As you might guess from the context, it is not possible to
do this without some notion of object safety: the arbitrary piece of
code `...` can do bad (uncontrolled) things.

Take it on faith (for a few paragraphs) that calling a generic method
is one example of something that can't be done on a trait object. So,
let's define a trait and a function like:

{% highlight rust linenos %}
trait Bad {
    fn generic_method<A>(&self, value: A);
}

fn func<T: Bad + ?Sized>(x: &T) {
    x.generic_method("foo"); // A = &str
    x.generic_method(1_u8); // A = u8
}
{% endhighlight %}

The function `func` *can't* be called like `foo(obj)` where `obj` is a
trait object `&Bad` because the generic method calls are
illegal. There's a possible approaches here, like

1. have signatures like `<T: Foo + ?Sized>(x: &T)` not work with `T =
  Foo` by default, for any trait `Foo`,
2. check the body of the function to see if it is legal to have `T =
   Bad` when we ask for that, or
3. ensure that we can never pass a `&Bad` into `func`.

Approach 1 is what existed before object safety, and is what object
safety was designed to solve. Approach 2 violates Rust's goal of
needing to know only the signatures of any function/method called to
type-check a program. That is, if one satisfies the signature one can
call it, unlike C++, there's no need to type-check internal code of
each the actual instantiation of a generic because the signatures
guarantee that the internals will be legal.

Approach 3 is the one that Rust takes via object safety, by ensuring
that it is impossible to ever encounter a scenario in which a function
with signature `fn func<T: Foo + ?Sized>(x: &T)` that does bad things,
could have `T == Foo`. That is, make it so that the only way that a
`&Foo` can be created is if there's no way that `func` can misbehave.

Object safety and those sort of function signatures apply particularly
to UFCS (uniform function call syntax), which allows one to call
methods as normal, generic function scoped under the type/trait in
which they are defined, for example, the UFCS function
`Bad::generic_method` from the trait above effectively has signature:

{% highlight rust linenos %}
fn Bad::generic_method<Self: Bad + ?Sized, A>(self: &Self, x: A)
{% endhighlight %}

If `fn method(&self)` comes from a trait `Foo`, `x.method()` can
always be rewritten to `Foo::method(x)` (modulo auto-deref and
auto-ref, which possibly add an `&` and/or some number of `*`s),
however, without object safety, it may not be possible to write
`trait_object.method()` as `Foo::method(trait_object)`. Object safety
guarantees this transformation is always valid---making UFCS and
method calls essentially equivalent---by outlawing creating a trait
object in situations where it would be invalid.

[rfc255]: https://github.com/rust-lang/rfcs/blob/master/text/0255-object-safety.md
[rfc428]: https://github.com/rust-lang/rfcs/issues/428
[rfc546]: https://github.com/rust-lang/rfcs/blob/master/text/0546-Self-not-sized-by-default.md
[pr20341]: https://github.com/rust-lang/rust/pull/20341

## How it works

After [RFC 546][rfc546] and [PR 20341][pr20341], making trait objects
automatically work with those sort of generic functions is achieved by
effectively having the compiler implicitly create an implementation of
`Foo` (as a trait) for `Foo` (as a type). Each method of the trait is
implemented to call into the corresponding method in the vtable. In
the explicit notation of [my previous post][previouspost], the
situation might look something like:

{% highlight rust linenos %}
trait Foo {
    fn method1(&self);
    fn method2(&mut self, x: i32, y: String) -> usize;
}

// autogenerated impl
impl<'a> Foo for Foo+'a {
    fn method1(&self) {
        // `self` is an `&Foo` trait object.

        // load the right function pointer and call it with the opaque data pointer
        (self.vtable.method1)(self.data)
    }
    fn method2(&mut self, x: i32, y: String) -> usize {
        // `self` is an `&mut Foo` trait object

        // as above, passing along the other arguments
        (self.vtable.method2)(self.data, x, y)
    }
}
{% endhighlight %}

To be clear: the `.vtable` and `.data` notation doesn't work directly
on trait objects, so that code has no hope of compiling, I am just
being explicit about actual behaviour.


## Object safety

The rules for object safety were set-out in that initial
[RFC 255][rfc255], with two missed cases identified and resolved in
[RFC 428][rfc428] and [RFC 546][rfc546]. At the time of writing, the
possible ways to be object-unsafe are described
[by two enums][object-unsafe]:

[object-unsafe]: https://github.com/rust-lang/rust/blob/2127e0d56d85ff48aafce90ab762650e46370b63/src/librustc/middle/traits/object_safety.rs#L30-L52

{% highlight rust linenos %}
pub enum ObjectSafetyViolation<'tcx> {
    /// Self : Sized declared on the trait
    SizedSelf,

    /// Method has someting illegal
    Method(Rc<ty::Method<'tcx>>, MethodViolationCode),
}

/// Reasons a method might not be object-safe.
#[derive(Copy,Clone,Show)]
pub enum MethodViolationCode {
    /// e.g., `fn(self)`
    ByValueSelf,

    /// e.g., `fn foo()`
    StaticMethod,

    /// e.g., `fn foo(&self, x: Self)` or `fn foo(&self) -> Self`
    ReferencesSelf,

    /// e.g., `fn foo<A>()`
    Generic,
}
{% endhighlight %}

Let's go through each case.

*Update 2015-05-06*: [RFC 817][rfc817] added more precise control
  over object safety via `where` clauses, see
  [*Where Self Meets Sized: Revisiting Object Safety*][whereselfsized].

[rfc817]: https://github.com/rust-lang/rfcs/pull/817
[whereselfsized]: {% post_url 2015-05-06-where-self-meets-sized-revisiting-object-safety %}

### Sized `Self`

{% highlight rust linenos %}
trait Foo: Sized {
    fn method(&self);
}
{% endhighlight %}

The trait `Foo` inherits from `Sized`, requiring the `Self` type to be
sized, and hence writing `impl Foo for Foo` is illegal: the type `Foo`
is not sized and doesn't implement `Sized`. Traits default to `Self`
being possibly-unsized---effectively a bound `Self: ?Sized`---to make
more traits object safe by default.

### By-value `self`

*Update 2015-05-06*: this is no longer object unsafe, but it is
  impossible to call such methods on possibly-unsized types, including
  trait objects. That is, one can define traits with `self` methods,
  but one is statically disallowed from call those methods on trait
  objects (and on generics that could be trait objects).

{% highlight rust linenos %}
trait Foo {
    fn method(self);
}
{% endhighlight %}

At the moment[^change-is-in-the-air], it's not possible to use trait
objects by-value anywhere, due to the lack of sizedness. If one were
to write an `impl Foo for Foo`, the signature of `method` would mean
`self` has type `Foo`: a by-value unsized type, illegal!

[^change-is-in-the-air]: There is desire to remove/relax this
                         restriction for function parameters, and
                         especially `self`, to allow them to be
                         unsized types. Niko's ["Purging proc"][pp]
                         describes the problem and the necessity for
                         [the `Invoke` trait][invoke] as a work-around
                         for the `FnOnce` trait.

### Static method

{% highlight rust linenos %}
trait Foo {
    fn func() -> i32;
}
{% endhighlight %}

There's no way to provide a sensible implementation of `func` as a
static method on the type `Foo`:

{% highlight rust linenos %}
impl<'a> Foo for Foo+'a {
    fn func() -> i32 {
        // what goes here??
    }
}
{% endhighlight %}

The compiler can't just conjure up some `i32`---the chosen value may
make no sense in context---and it can't call some other type's
`Foo::func` method---which type would it choose? The whole scenario
makes no sense.

### References `Self`

There's two fundamental ways in which this can happen, as an argument
or as a return value, in either case a reference to the `Self` type
means that it must match the type of the `self` value, the true type
of which is unknown at compile time. For example:

{% highlight rust linenos %}
trait Foo {
    fn method(&self, other: &Self);
}
{% endhighlight %}

The types of the two arguments have to match, but this can't be
guaranteed with a trait object: the erased types of two separate
`&Foo` values may not match:

{% highlight rust linenos %}
impl<'a> Foo for Foo+'a {
    fn method(&self, other: &(Foo+'a))
        (self.vtable.method)(self.data, /* what goes here? */)
    }
}
{% endhighlight %}

(Using the explicit-but-invalid notation as above.)

One can't use `other.data` because the `method` entry of `self.vtable`
is assuming that both pointers point to the same, specific type
(whatever type the vtable is specialised for), but there's absolutely
no guarantee `other.data` points to matching data. There's also not
necessarily a (reliable) way to detect a mismatch, and no way the
compiler can know a correct way to handle a mismatch even if it can be
detected.

### Generic method

{% highlight rust linenos %}
trait Foo {
    fn method<A>(&self, a: A);
}
{% endhighlight %}

As discussed briefly in [the first post][previouspost], generic
functions in Rust are monomorphised, that is, a copy of the function
is created for each type used as a generic parameter. An attempted
implementation might look like

{% highlight rust linenos %}
impl<'a> Foo for Foo+'a {
    fn method<A>(&self, a: A) {
        (self.vtable./* ... huh ???*/)(self.data, a: A)
    }
}
{% endhighlight %}

The vtable is a static struct of function pointers, somehow we have to
select a function pointer from it that will work with the arbitrary
type `A`. To have any hope of doing this, one would have[^alternative]
to pregenerate code for every type that could possibly be used for `A`
and then fill in the `huh` above to select the right one. This would
be effectively implicitly adding a whole series of methods to the
trait:

{% highlight rust linenos %}
trait Foo {
    fn method_u8(&self);     // A = u8
    fn method_i8(&self);     // A = i8
    fn method_String(&self); // A = String
    fn method_unit(&self);   // A = ()
    // ...
}
{% endhighlight %}

and each one would need an entry in the vtable struct. If it is even
possible, this would be some serious bloat, especially as I imagine
most possibilities wouldn't be used.

For the more fundamental question of "is it possible", the answer is
rarely: it only works if the number of possible types that can be used
with the generic parameters is finite and completely known, so that a
complete list can be written. I think the only circumstance in which
this occurs is if all the parameters have to be bounded by some
private trait (the example above fails, since `A` is unbounded and so
can be used with every type ever, including ones that aren't even
defined in scope).


[^alternative]: Strictly speaking I suppose one could do some type of
                runtime codegen/JITing, but that's not really
                something Rust wants to build into the language, as it
                would require Rust programs to essentially carry
                around a compiler.

[pp]: http://smallcultfollowing.com/babysteps/blog/2014/11/26/purging-proc/
[invoke]: http://doc.rust-lang.org/nightly/std/thunk/trait.Invoke.html

{% include comments.html c=page.comments %}

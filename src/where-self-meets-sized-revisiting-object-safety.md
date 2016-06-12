---
layout: default
title: "Where Self Meets Sized: Revisiting Object Safety"

description: >
    Rust's `where Self: Sized` now offers new flexibility for writing
    object-safe traits.

comments:
  users: "https://users.rust-lang.org/t/where-self-meets-sized-revisting-object-safety/1249"
  r_rust: "http://www.reddit.com/r/rust/comments/351pil/where_self_meets_sized_revisiting_object_safety/"
---

The concept of object safety in Rust was recently refined to be more
flexible in an important way: the checks can be disabled for specific
methods by using `where` clauses to restrict them to only work when
`Self: Sized`.

[rfc]: https://github.com/rust-lang/rfcs/pull/817
[trait-objects]: {% post_url 2015-01-10-peeking-inside-trait-objects %}
[sized]: {% post_url 2015-01-12-the-sized-trait %}
[object-safety]: {% post_url 2015-01-13-object-safety %}

{% include trait-objects.html n=3 %}

This post is a rather belated fourth entry in my series on trait
objects and object safety:
[*Peeking inside Trait Objects*][trait-objects],
[*The Sized Trait*][sized] and [*Object Safety*][object-safety]. It's
been long enough that a refresher is definitely in order, although this
isn't complete coverage of the details.

## Recap

Rust offers open sets of types, type erasure and dynamic dispatch via
[trait objects][trait-objects]. However, to ensure a uniform handling
of trait objects and non-trait objects in generic code, there are
certain restrictions about exactly which traits can be used to create
objects: this is [object safety][object-safety].

A trait is object safe only if the compiler can automatically
implement it for itself, by implementing each method as a dynamic
function call through the vtable stored in a trait object.

{% highlight rust linenos %}
trait Foo {
    fn method_a(&self) -> u8;

    fn method_b(&self, x: f32) -> String;
}

// automatically inserted by the compiler
impl<'a> Foo for Foo+'a {
    fn method_a(&self) -> u8 {
         // dynamic dispatch to `method_a` of erased type
         self.method_a()
    }
    fn method_b(&self, x: f32) -> String {
         // as above
         self.method_b(x)
    }
}
{% endhighlight %}

Without the object safety rules one can write functions with type
signatures satisfied by trait objects, where the internals make it
impossible to actually use with trait objects. However, Rust tries to ensure
that this can't happen---code should only need to know the signatures
of anything it calls, not the internals---and hence object safety.

These rules outlaw creating trait objects of, for example, traits with
generic methods:

{% highlight rust linenos %}
trait Bar {
    fn bad<T>(&self, x: T);
}

impl Bar for u8 {
    fn bad<T>(&self, _: T) {}
}

fn main() {
    &1_u8 as &Bar;
}

/*
...:10:5: 10:7 error: cannot convert to a trait object because trait `Bar` is not object-safe [E0038]
...:10     &1 as &Bar;
           ^~
...:10:5: 10:7 note: method `bad` has generic type parameters
...:10     &1 as &Bar;
           ^~
*/
{% endhighlight %}

Trait object values always appear behind a pointer, like `&SomeTrait`
or `Box<AnotherTrait>`, since the trait value "`SomeTrait`" itself
doesn't have size known at compile time. This property is captured via
the [`Sized` trait][sized], which is implemented for types like `i32`,
or simple `struct`s and `enum`s, but not for unsized slices `[T]`, or
the plain trait types `SomeTrait`.


## Iterating on the design

One impact of introducing object safety was that the design of several
traits had to change. The most noticeable ones were `Iterator`, and
the IO traits `Read` and `Write` (although they were probably `Reader`
and `Writer` at that point).

Focusing on the former, before object safety it was defined
something[^associated-type] like:

[^associated-type]: I'm using an associated type for `Item` here, but
                    I believe it was probably still a generic
                    parameter `trait Iterator<Item> { ...` at this
                    point, and the `IntoIterator` trait didn't
                    exist. However it doesn't matter: the exact same
                    problems existed, just with different syntax.

{% highlight rust linenos %}
trait Iterator {
    type Item;

    fn next(&mut self) -> Option<Self::Item>;
    fn size_hint(&self) -> (usize, Option<usize>) { /* ... */ }

    // ... methods methods methods ...

    fn zip<U>(self, other: U) -> Zip<Self, U::IntoIter>
        where U: IntoIterator
    { /* ... */ }

    fn map<B, F>(self, f: F) -> Map<Self, F>
        where F: FnMut(Self::Item) -> B
    { /* ... */ }

    // etc
}
{% endhighlight %}

The above `Iterator` isn't object safe: it has generic methods, and so
it isn't possible to implement `Iterator` for `Iterator` itself. This
is unfortunate, since it is very useful to be able to create and use
`Iterator` trait objects, so it *had* to be made object safe.

The solution at the time was extension traits: define a new trait
`IteratorExt` that incorporated all the object unsafe methods, and use
a blanket implementation to implement it for all `Iterator`s "from the
outside".

{% highlight rust linenos %}
trait Iterator {
    type Item;

    fn next(&mut self) -> Option<Self::Item>;

    fn size_hint(&self) -> (usize, Option<usize>) { /* ... */ }
}

trait IteratorExt: Sized + Iterator {
    // ... methods methods methods ...

    fn zip<U>(self, other: U) -> Zip<Self, U::IntoIter>
        where U: IntoIterator
    { /* ... */ }

    fn map<B, F>(self, f: F) -> Map<Self, F>
        where F: FnMut(Self::Item) -> B
    { /* ... */ }

    // etc
}
// blanket impl, for all iterators
impl<I: Iterator> IteratorExt for I {}
{% endhighlight %}

The `next` and `size_hint` methods are object safe, so this version of
`Iterator` can create trait objects: `Box<Iterator<Item = u8>>` is a
legal iterator over bytes. It works because the methods of
`IteratorExt` are no longer part of `Iterator` and so they're not
involved in any object considerations for it.

Fortunately, those methods aren't lost on trait objects, because there
are implementations like the following, allowing the blanket
implementation of `IteratorExt` to kick in:

{% highlight rust linenos %}
// make Box<...> an Iterator by deferring to the contents
impl<I: Iterator + ?Sized> Iterator for Box<I> {
    type Item = I::Item;

    fn next(&mut self) -> Option<I::Item> {
        (**self).next()
    }

    fn size_hint(&self) -> (usize, Option<usize>) {
        (**self).size_hint()
    }
}
{% endhighlight %}

<div class="join"></div>

(The `?Sized` ensures this applies to `Box<Iterator<...>>` trait
objects as well as simply `Box<SomeType>` where `SomeType` is a normal
type that implements `Iterator`.)

This approach has some benefits, like clarifying the separation
between the "core" methods (`next` and `size_hint`) and the
helpers. However, it has several downsides, especially for cases that
aren't `Iterator`:

- extra traits in the documentation,
- users will have to import those extra traits
- it only works with default-able methods,
- the defaults can't be overridden, e.g. there's no way for a specific
  type to slot in a more efficient way to implement a method

All-in-all, it was a wet blanket on libraries. Fortunately, not all
was lost: let's meet our saviour.

## It's a bird... it's a plane...

It's a [`where` clause][where]!

[where]: https://github.com/rust-lang/rfcs/blob/master/text/0135-where.md

`where` clauses allow predicating functions/methods/types on
essentially arbitrary trait relationships, not just the plain `<T:
SomeTrait>`, where the left-hand side has to be a generic type
declared right then and there. For example, one can use
[`From`](http://doc.rust-lang.org/std/convert/trait.From.html) to
convert *to* types with a `where` clause.

{% highlight rust linenos %}
fn convert_to_string<T>(x: T) -> String
    where String: From<T>
{
    String::from(x)
}
{% endhighlight %}

The important realisation was that `where` allows placing restrictions
on `Self` directly on methods, so that certain methods only exist for
some implementing types. This was used to great effect to collapse
piles of traits into a single one, for example in `std::iter`.
[Rust 0.12.0 had](http://doc.rust-lang.org/0.12.0/std/iter/#traits) a
swathe of extra `Iterator` traits: `Additive...`, `Cloneable...`,
`Multiplicative...`, `MutableDoubleEnded...`, `Ord...`.

Each of these were designed to define a few extra methods that
required specific restrictions on the element type of the iterator,
for example, `OrdIterator` needed `Ord` elements:

{% highlight rust linenos %}
trait OrdIterator: Iterator {
     fn max(&mut self) -> Option<Self::Item>;
     // ...
}

impl<A: Ord, I: Iterator<Item = A>> OrdIterator for I {
    fn max(&mut self) -> Option<A> { /* ... */ }

    // ...
}
{% endhighlight %}

The [current `std::iter`](http://doc.rust-lang.org/std/iter) is much
cleaner: all the traits above have been merged into `Iterator` itself
with `where` clauses, e.g.
[`max`](http://doc.rust-lang.org/nightly/std/iter/trait.Iterator.html#method.max):

{% highlight rust linenos %}
trait Iterator {
    type Item;

    // ...

    fn max(self) -> Option<Self::Item>
        where Self::Item: Ord
    { /* ... */ }

    // ...
}
{% endhighlight %}

Notably, there's no restriction on `Item` for general `Iterator`s,
only on `max`, so iterators retain full flexibility while still
gaining a `max` method that only works when it should:

{% highlight rust linenos %}
struct NotOrd;

fn main() {
    (0..10).max(); // ok
    (0..10).map(|_| NotOrd).max();
}
/*
...:5:29: 5:34 error: the trait `core::cmp::Ord` is not implemented for the type `NotOrd` [E0277]
...:5     (0..10).map(|_| NotOrd).max();
                                  ^~~~~
*/
{% endhighlight %}

This approach works fine for normal traits like `Ord`, and also works
equally well for "special" traits like `Sized`:
[it is possible](http://stackoverflow.com/a/27820018/1256624) to
restrict methods to only work when `Self` has a statically known size
with `where Self: Sized`. Initially this had no interaction with
object safety, it would just influence what exactly that method could
do.

## Putting it together

The piece that interacts with object safety is [RFC 817][rfc], which
made `where Self: Sized` special: the compiler now understands that
methods tagged with that cannot ever be used on a trait object, even
in generic code.  This means it is perfectly correct to completely
ignores any methods with that `where` clause when checking object
safety.

The bad example from the start can be written to compile:

{% highlight rust linenos %}
trait Bar {
    fn bad<T>(&self, x: T)
        where Self: Sized;
}

impl Bar for u8 {
    fn bad<T>(&self, _: T)
        where Self: Sized
    {}
}

fn main() {
    &1_u8 as &Bar;
}
{% endhighlight %}

<div class="join"></div>

And also adjusted to not compile: try calling `(&1_u8 as
&Bar).bad("foo")` in `main` and the compiler spits out an error,

{% highlight text linenos %}
...:13:21: 13:31 error: the trait `core::marker::Sized` is not implemented for the type `Bar` [E0277]
...:13     (&1_u8 as &Bar).bad("foo")
                           ^~~~~~~~~~
...:13:21: 13:31 note: `Bar` does not have a constant size known at compile-time
...:13     (&1_u8 as &Bar).bad("foo")
                           ^~~~~~~~~~
{% endhighlight %}

Importantly, this solves the `Iterator` problem: there's no longer a
need to split methods into extension traits to ensure object safety,
one can instead just guard the bad ones. `Iterator` now looks like:

{% highlight rust linenos %}
trait Iterator {
    type Item;

    fn next(&mut self) -> Option<Self::Item>;

    fn size_hint(&self) -> (usize, Option<usize>) { /* ... */ }

    // ... methods methods methods ...

    fn zip<U>(self, other: U) -> Zip<Self, U::IntoIter>
        where Self: Sized, U: IntoIterator
    { /* ... */ }

    fn map<B, F>(self, f: F) -> Map<Self, F>
        where Self: Sized, F: FnMut(Self::Item) -> B
    { /* ... */ }

    // etc
}
{% endhighlight %}

<div class="join"></div>

(Along with `max` and the other `where`-reliant methods from the other
`*Iterator` traits mentioned above.)

The extra flexibility this `where` clauses offer is immensely helpful
for designing that perfect API.  Of course, just adding `where Self:
Sized` isn't a complete solution or the only trick: the current
`Iterator` still has the same sort of implementations of `Iterator`
for `Box<I>` where `I: Iterator + ?Sized`, and traits using the
`where` technique may want to adopt others that `Iterator` does.

{% include comments.html c=page.comments %}

# All About Trait Objects

One of the most powerful parts of
[the Rust programming language](http://rust-lang.org)[^version] is the
[trait system][traits]. They form the basis of the generic system and
polymorphic functions and types. There's an interesting use of traits,
as so-called "trait objects", that allows for dynamic polymorphism and
heterogeneous uses of types, which I'm going to look at in more detail
over a short series of posts.

*Update 2015-02-19*: A lot of this document has been copied into
[the main book][book], with improvements and updates.

[traits]: http://doc.rust-lang.org/nightly/book/traits.html
[book]: http://doc.rust-lang.org/nightly/book/trait-objects.html


[^version]: It's generally good practice for Rust posts to mention
            their version due to language instability, but this post
            and the series won't have much real runnable code and the
            concepts described are pretty stable... but habits die
            hard: `rustc 1.0.0-nightly (44a287e6e 2015-01-08 17:03:40 -0800)`.

which should also be the 1.0.0-alpha release (speaking of which,
the language instability should be starting to settle down now).

## Part 1: Peeking Inside Trait Objects

This post will set the scene, with an introduction to the internals of
a trait object; the remaining posts will look at the `Sized` trait and
"object safety" in detail (a lot of people have encountered trouble
with somewhat abstruse compiler errors about this recently).


### Traits

A simple example of a `trait` is this `Foo`. It has one method that is
expected to return a `String`, and, in the real world, there would be
some expectation about what the string would mean, but this is just a
blog, so you're free to make up your own favourite meaning.

```rust
trait Foo {
    fn method(&self) -> String;
}
```

This can then be implemented for certain types, stating that these
types satisfy whatever behaviours the trait is trying to summarise and
allow polymorphism over. For example, bytes and strings are `Foo`,
apparently:

```rust,ignore
impl Foo for u8 {
    fn method(&self) -> String { format!("u8: {}", *self) }
}
impl Foo for String {
    fn method(&self) -> String { format!("string: {}", *self) }
}
```

There's two basic ways to use traits to be polymorphic:

The first and most common are generic functions like `fn func<T:
Foo>(x: &T)`. These are implemented via monomorphisation, the compiler
creates a specialised version of the generic function for every type
used with it. This has some upsides&mdash;static dispatching of any
method calls[^upsides], allowing for inlining and hence usually higher
performance&mdash;and some downsides&mdash;causing code bloat due to
many copies of the same function existing in the binary, one for each
type[^one-per-type].

Fortunately, there's second option if that trade-off is inappropriate,
or if being required to know every type everywhere is impossible or
undesirable.

[^upsides]: Static dispatching isn't *guaranteed* to be an upside:
            compilers aren't perfect and may "optimise" code to become
            slower. For example, functions inlined too eagerly will
            bloating the instruction cache (cache rules everything
            around us). This is part of the reason that `#[inline]`
            and `#[inline(always)]` that should be used carefully, and
            one reason why using a trait object&mdash;with its dynamic
            dispatch&mdash;is sometimes more efficient.

    However, the common case is that it is more efficient to use
    static dispatch, and one can always have a thin
    statically-dispatched wrapper function that does a dynamic, but
    not vice versa, meaning static calls are more flexible. The
    standard library tries to be statically dispatched where possible
    for this reason.

[^one-per-type]: There's no guarantee that there will actually be a
                 copy of the function for each type that implements
                 the trait, or even for each type that is used with
                 the function, since the compiler is free to combine
                 copies if it can tell that sharing the code would not
                 change semantics. But, in general, this optimisation
                 doesn't trigger.

### Trait objects

Trait objects, like `&Foo` or `Box<Foo>`, are normal values that store
a value of *any* type that implements the given trait, where the
precise type can only be known at runtime. The methods of the trait
can be called on a trait object via a special record of function
pointers (created and managed by the compiler).

A function that takes a trait object&mdash;say `fn func(x: &Foo)`&mdash;is not
specialised to each of the types that implements `Foo`: only one copy
is generated, often (but not always) resulting in less code
bloat. However, this comes at the cost of requiring slower virtual
function calls, and effectively inhibiting any chance of inlining and
related optimisations from occurring.

Trait objects are both simple and complicated: their core
representation and layout is quite straight-forward, but there are
some curly error messages and surprising behaviours to discover.

### Obtaining a trait object

There's two similar ways to get a trait object value: casts and
coercions. If `T` is a type that implements a trait `Foo` (e.g. `u8`
for the `Foo` above), then the two ways to get a `Foo` trait object
out of a pointer to `T` look like:

```rust,ignore
let ref_to_t: &T = ...;

// `as` keyword for casting
let cast = ref_to_t as &Foo;

// using a `&T` in a place that has a known type of `&Foo` will implicitly coerce:
let coerce: &Foo = ref_to_t;

fn also_coerce(_unused: &Foo) {}
also_coerce(ref_to_t);
```

These trait object coercions and casts also work for pointers like
`&mut T` to `&mut Foo` and `Box<T>` to `Box<Foo>`, but that's all at
the moment. Other than some bugs, coercions and casts are identical.

This operation can be seen as "erasing" the compiler's knowledge about
the specific type of the pointer, and hence trait objects are
sometimes referred to "type erasure".


### Representation

Let's start simple, with the runtime representation of a trait
object. The `std::raw` module contains structs with layouts that are
the same as the complicated build-in types,
[including trait objects][stdraw]:

```rust
pub struct TraitObject {
    pub data: *mut (),
    pub vtable: *mut (),
}
```

[stdraw]: http://doc.rust-lang.org/nightly/std/raw/struct.TraitObject.html

That is, a trait object like `&Foo` consists of a "data" pointer and a
"vtable" pointer.

The data pointer addresses the data (of some unknown type `T`) that
the trait object is storing, and the vtable pointer points to the
[vtable][vtable] ("virtual method table") corresponding to the implementation
of `Foo` for `T`.

[vtable]: https://en.wikipedia.org/wiki/Virtual_method_table


A vtable is essentially a struct of function pointers, pointing to the
concrete piece of machine code for each method in the
implementation. A method call like `trait_object.method()` will
retrieve the correct pointer out of the vtable and then do a dynamic
call of it. For example:

```rust,ignore
struct FooVtable {
    destructor: fn(*mut ()),
    size: usize,
    align: usize,
    method: fn(*const ()) -> String,
}


// u8:

fn call_method_on_u8(x: *const ()) -> String {
    // the compiler guarantees that this function is only called
    // with `x` pointing to a u8
    let byte: &u8 = unsafe { &*(x as *const u8) };

    byte.method()
}

static Foo_for_u8_vtable: FooVtable = FooVtable {
    destructor: /* compiler magic */,
    size: 1,
    align: 1,

    // cast to a function pointer
    method: call_method_on_u8 as fn(*const ()) -> String,
};


// String:

fn call_method_on_String(x: *const ()) -> String {
    // the compiler guarantees that this function is only called
    // with `x` pointing to a String
    let string: &String = unsafe { &*(x as *const String) };

    string.method()
}

static Foo_for_String_vtable: FooVtable = FooVtable {
    destructor: /* compiler magic */,
    // values for a 64-bit computer, halve them for 32-bit ones
    size: 24,
    align: 8,

    method: call_method_on_String as fn(*const ()) -> String,
};
```

(The `call_method_on_...` functions could also be UFCS: `<... as
Foo>::method`, but that's somewhat less clear.)

The `destructor` field in each vtable points to a function that will
clean up any resources of the vtable's type, for `u8` it is trivial,
but for `String` it will free the memory. This is necessary for owning
trait objects like `Box<Foo>`, which need to clean-up both the `Box`
allocation and as well as the internal type when they go out of
scope. The `size` and `align` fields store the size of the erased
type, and its alignment requirements; these are essentially unused at
the moment since the information is embedded in the destructor, but
will be used in future, as trait objects are progressively made more
flexible.

Suppose we've got some values that implement `Foo`, the explicit form
of construction and use of `Foo` trait objects might look a bit like
(ignoring the type mismatches: they're all just pointers anyway):

```rust,ignore
let a: String = "foo".to_string();
let x: u8 = 1;

// let b: &Foo = &a;
let b = TraitObject {
    // store the data
    data: &a,
    // store the methods
    vtable: &Foo_for_String_vtable
};

// let y: &Foo = x;
let y = TraitObject {
    // store the data
    data: &x,
    // store the methods
    vtable: &Foo_for_u8_vtable
};

// b.method();
(b.vtable.method)(b.data);

// y.method();
(y.vtable.method)(y.data);
```

If `b` or `y` were owning trait objects (`Box<Foo>`), there would be a
`(b.vtable.destructor)(b.data)` (respectively `y`) call when they went
out of scope.

#### Why pointers?

The use of language like "fat pointer" implies that a trait object is
always a pointer of some form, but why? I wrote above that

> [Trait objects] are normal values and can store a value of *any* type
that implements the given trait, where the precise type can only
be known at runtime.

Rust does not put things behind a pointer by default, unlike many
managed languages, so types can have different sizes. Knowing the size
of the value at compile time is important for things like passing it
as an argument to a function, moving it about on the stack and
allocating (and deallocating) space on the heap to store it.

For `Foo`, we would need to have a value that could be at least either
a `String` (24 bytes) or a `u8` (1 byte), as well as any other type
for which dependent crates may implement `Foo` (any number of bytes at
all). There's no way to guarantee that this last point can work if the
values are stored without a pointer, because those other types can be
arbitrarily large.

Putting the value behind a pointer means the size of the value is not
relevant when we are tossing a trait object around, only the size of
the pointer itself.

## Part 2: The `Sized` Trait


An important piece in my story about trait objects in
[Rust](http://rust-lang.org)[^version] is [the `Sized` trait][sized],
so I'm slotting in this short post between
[my discussion of low-level details][previouspost] and
[the post on "object safety"][nextpost].


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

### `?Sized`

The `Sized` trait gets some special syntax for use in bounds, at the
moment: `?Sized`. Such a bound is necessary because `Sized` is
special: it is a default bound for type parameters in most positions,
and so one needs some way to opt-in to a parameter not necessarily
being sized.

```rust
fn foo<T>() {} // can only be used with sized T

fn bar<T: ?Sized>() {} // can be used with both sized and unsized T
```

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

## Part 3: Object Safety


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

```rust,ignore
fn func<T: Foo + ?Sized>(x: &T) { ... }
```

It would be nice to be able to call it like `func(object)` where
`object: &Foo`; that is, take `T` to be the dynamically sized type
`Foo`. As you might guess from the context, it is not possible to
do this without some notion of object safety: the arbitrary piece of
code `...` can do bad (uncontrolled) things.

Take it on faith (for a few paragraphs) that calling a generic method
is one example of something that can't be done on a trait object. So,
let's define a trait and a function like:

```rust,ignore
trait Bad {
    fn generic_method<A>(&self, value: A);
}

fn func<T: Bad + ?Sized>(x: &T) {
    x.generic_method("foo"); // A = &str
    x.generic_method(1_u8); // A = u8
}
```

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

```rust,ignore
fn Bad::generic_method<Self: Bad + ?Sized, A>(self: &Self, x: A)
```

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

```rust,ignore
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
```

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

```rust,ignore
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
```

Let's go through each case.

*Update 2015-05-06*: [RFC 817][rfc817] added more precise control
  over object safety via `where` clauses, see
  [*Where Self Meets Sized: Revisiting Object Safety*][whereselfsized].

[rfc817]: https://github.com/rust-lang/rfcs/pull/817
[whereselfsized]: {% post_url 2015-05-06-where-self-meets-sized-revisiting-object-safety %}

### Sized `Self`

```rust
trait Foo: Sized {
    fn method(&self);
}
```

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

```rust
trait Foo {
    fn method(self);
}
```

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

```rust
trait Foo {
    fn func() -> i32;
}
```

There's no way to provide a sensible implementation of `func` as a
static method on the type `Foo`:

```rust,ignore
impl<'a> Foo for Foo+'a {
    fn func() -> i32 {
        // what goes here??
    }
}
```

The compiler can't just conjure up some `i32`---the chosen value may
make no sense in context---and it can't call some other type's
`Foo::func` method---which type would it choose? The whole scenario
makes no sense.

### References `Self`

There's two fundamental ways in which this can happen, as an argument
or as a return value, in either case a reference to the `Self` type
means that it must match the type of the `self` value, the true type
of which is unknown at compile time. For example:

```rust
trait Foo {
    fn method(&self, other: &Self);
}
```

The types of the two arguments have to match, but this can't be
guaranteed with a trait object: the erased types of two separate
`&Foo` values may not match:

```rust,ignore
impl<'a> Foo for Foo+'a {
    fn method(&self, other: &(Foo+'a))
        (self.vtable.method)(self.data, /* what goes here? */)
    }
}
```

(Using the explicit-but-invalid notation as above.)

One can't use `other.data` because the `method` entry of `self.vtable`
is assuming that both pointers point to the same, specific type
(whatever type the vtable is specialised for), but there's absolutely
no guarantee `other.data` points to matching data. There's also not
necessarily a (reliable) way to detect a mismatch, and no way the
compiler can know a correct way to handle a mismatch even if it can be
detected.

### Generic method

```rust
trait Foo {
    fn method<A>(&self, a: A);
}
```

As discussed briefly in [the first post][previouspost], generic
functions in Rust are monomorphised, that is, a copy of the function
is created for each type used as a generic parameter. An attempted
implementation might look like

```rust,ignore
impl<'a> Foo for Foo+'a {
    fn method<A>(&self, a: A) {
        (self.vtable./* ... huh ???*/)(self.data, a: A)
    }
}
```

The vtable is a static struct of function pointers, somehow we have to
select a function pointer from it that will work with the arbitrary
type `A`. To have any hope of doing this, one would have[^alternative]
to pregenerate code for every type that could possibly be used for `A`
and then fill in the `huh` above to select the right one. This would
be effectively implicitly adding a whole series of methods to the
trait:

```rust
trait Foo {
    fn method_u8(&self);     // A = u8
    fn method_i8(&self);     // A = i8
    fn method_String(&self); // A = String
    fn method_unit(&self);   // A = ()
    // ...
}
```

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


## Part 4: Where `Self` Meets `Sized`


The concept of object safety in Rust was recently refined to be more
flexible in an important way: the checks can be disabled for specific
methods by using `where` clauses to restrict them to only work when
`Self: Sized`.

[rfc]: https://github.com/rust-lang/rfcs/pull/817
[trait-objects]: {% post_url 2015-01-10-peeking-inside-trait-objects %}
[sized]: {% post_url 2015-01-12-the-sized-trait %}
[object-safety]: {% post_url 2015-01-13-object-safety %}

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

```rust,ignore
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
```

Without the object safety rules one can write functions with type
signatures satisfied by trait objects, where the internals make it
impossible to actually use with trait objects. However, Rust tries to ensure
that this can't happen---code should only need to know the signatures
of anything it calls, not the internals---and hence object safety.

These rules outlaw creating trait objects of, for example, traits with
generic methods:

```rust,ignore
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
```

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

```rust,ignore
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
```

The above `Iterator` isn't object safe: it has generic methods, and so
it isn't possible to implement `Iterator` for `Iterator` itself. This
is unfortunate, since it is very useful to be able to create and use
`Iterator` trait objects, so it *had* to be made object safe.

The solution at the time was extension traits: define a new trait
`IteratorExt` that incorporated all the object unsafe methods, and use
a blanket implementation to implement it for all `Iterator`s "from the
outside".

```rust,ignore
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
```

The `next` and `size_hint` methods are object safe, so this version of
`Iterator` can create trait objects: `Box<Iterator<Item = u8>>` is a
legal iterator over bytes. It works because the methods of
`IteratorExt` are no longer part of `Iterator` and so they're not
involved in any object considerations for it.

Fortunately, those methods aren't lost on trait objects, because there
are implementations like the following, allowing the blanket
implementation of `IteratorExt` to kick in:

```rust,ignore
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
```

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

```rust
fn convert_to_string<T>(x: T) -> String
    where String: From<T>
{
    String::from(x)
}
```

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

```rust,ignore
trait OrdIterator: Iterator {
     fn max(&mut self) -> Option<Self::Item>;
     // ...
}

impl<A: Ord, I: Iterator<Item = A>> OrdIterator for I {
    fn max(&mut self) -> Option<A> { /* ... */ }

    // ...
}
```

The [current `std::iter`](http://doc.rust-lang.org/std/iter) is much
cleaner: all the traits above have been merged into `Iterator` itself
with `where` clauses, e.g.
[`max`](http://doc.rust-lang.org/nightly/std/iter/trait.Iterator.html#method.max):

```rust,ignore
trait Iterator {
    type Item;

    // ...

    fn max(self) -> Option<Self::Item>
        where Self::Item: Ord
    { /* ... */ }

    // ...
}
```

Notably, there's no restriction on `Item` for general `Iterator`s,
only on `max`, so iterators retain full flexibility while still
gaining a `max` method that only works when it should:

```rust,ignore
struct NotOrd;

fn main() {
    (0..10).max(); // ok
    (0..10).map(|_| NotOrd).max();
}
```

```text
...:5:29: 5:34 error: the trait `core::cmp::Ord` is not implemented for the type `NotOrd` [E0277]
...:5     (0..10).map(|_| NotOrd).max();
```

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

```rust,ignore
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
```

<div class="join"></div>

And also adjusted to not compile: try calling `(&1_u8 as
&Bar).bad("foo")` in `main` and the compiler spits out an error,

```text
...:13:21: 13:31 error: the trait `core::marker::Sized` is not implemented for the type `Bar` [E0277]
...:13     (&1_u8 as &Bar).bad("foo")
                           ^~~~~~~~~~
...:13:21: 13:31 note: `Bar` does not have a constant size known at compile-time
...:13     (&1_u8 as &Bar).bad("foo")
                           ^~~~~~~~~~
```

Importantly, this solves the `Iterator` problem: there's no longer a
need to split methods into extension traits to ensure object safety,
one can instead just guard the bad ones. `Iterator` now looks like:

```rust,ignore
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
```

<div class="join"></div>

(Along with `max` and the other `where`-reliant methods from the other
`*Iterator` traits mentioned above.)

The extra flexibility this `where` clauses offer is immensely helpful
for designing that perfect API.  Of course, just adding `where Self:
Sized` isn't a complete solution or the only trick: the current
`Iterator` still has the same sort of implementations of `Iterator`
for `Box<I>` where `I: Iterator + ?Sized`, and traits using the
`where` technique may want to adopt others that `Iterator` does.

> [_Originally published 2015-01-10_](https://huonw.github.io/blog/2015/01/peeking-inside-trait-objects/),
> [2015-01-12](https://huonw.github.io/blog/2015/01/the-sized-trait/),
> [2015-01-13](https://huonw.github.io/blog/2015/01/object-safety/), and
> [2015-05-06](https://huonw.github.io/blog/2015/05/where-self-meets-sized-revisiting-object-safety/).
>
> _License: TBD_

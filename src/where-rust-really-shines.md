---
layout: post
title: "Where Rust really shines"
date: 2015-05-03 03:49:49 +0530
comments: true
categories: [Rust, Mozilla, Programming]
---

Yesterday I was working on a [small feature](https://github.com/rust-lang/rust/pull/25027)
for the Rust compiler, and came across a situation which really showcased Rust's
awesomeness as a language.

There was a struct which was exposed to an API,
and I wished to give it access to a list of things known as "attributes", where the list was [a heap-allocated vector](http://doc.rust-lang.org/std/vec/struct.Vec.html).


Now, I have two ways of actually giving the struct access to a vector. I can either clone it (i.e. make a copy of its contents), 
or use a reference (pointer) to it or its contents.

In a language like C++ there's only once choice in this situation; that is
to clone the vector[^1]. In a large C++ codebase if I wished to use a pointer I would need to be sure that the vector
isn't deallocated by the time I'm done with it, and more importantly, to be sure that no other code pushes to the vector (when a vector overflows its
capacity it will be reallocated, invalidating any other pointers to its contents).

For a smaller codebase this might be possible, but in this specific case it could have taken me a while to become sure of this.
The code was related to the "expansion" portion of compilation, where the AST is expanded to a bigger AST. A lot of things change and get
moved around, so it is reasonable to assume that it might not be possible to safely use it.
I would have had to find out where the vector is originally stored; all the entry points for the code I was
modifying, and make sure it isn't being mutated (not as hard in Rust, but I would
still need to muck around a large codebase). And then I would have to somehow make sure that nobody tries to mutate it
in the future. This is a task which I would not even consider trying in C++.

However, I had another option here, because this was Rust. In Rust I can store a reference to the contents of the vector
without fear of invalidation, since the compiler will prevent me from using the vector in a way that could cause unsafety. 
Such a reference is known as a [slice](http://doc.rust-lang.org/std/primitive.slice.html).

Whilst in C++ I would have to manually go through a lot of code to be sure of safety
(and even after all that be left with code that would be brittle to changes elsewhere
the codebase), in Rust the compiler can do this for me!

Being able to do this was important
&mdash; this code is called quite often for a regular compile, and all those
extra allocations could be heavy, especially given that this was a feature that would be used
by very few.

So first I started off by adding a field to the `FieldInfo` struct which was a [slice of attributes](https://github.com/Manishearth/rust/commit/ede7a6dc8ff5455f9d0d39a90e6d11e9a374e93b#diff-6fa0bf762b2ef85690cce1a0fd8d5a20R285). Notice that I added a lifetime specifier, [the `'a`](https://github.com/Manishearth/rust/commit/ede7a6dc8ff5455f9d0d39a90e6d11e9a374e93b#diff-6fa0bf762b2ef85690cce1a0fd8d5a20R273) to the struct definition.

```rust
/// Summary of the relevant parts of a struct/enum field.
pub struct FieldInfo<'a> {
    /// ...
    /// The attributes on the field
    pub attrs: &'a [ast::Attribute],
}
```

For those of you new to Rust, a lifetime is part of the type of a reference. It's related to the scope of the reference, and generally can be treated as
a generic parameter. So, for example, here, I have a `FieldInfo` with a lifetime parameter of `'a` where `'a` is the lifetime of the inner slice of attributes.
If I construct this struct with slices from different scopes, its type will be different each time. Lifetimes can get automatically cast depending on their context however,
and quite often they get elided away, so one doesn't need to specify them that much (aside from struct/enum definitions). You can find more information [in the Rust book](http://doc.rust-lang.org/nightly/book/ownership.html#lifetimes)

I then updated code everywhere to pass the attributes from [their source](https://github.com/Manishearth/rust/commit/ede7a6dc8ff5455f9d0d39a90e6d11e9a374e93b#diff-6fa0bf762b2ef85690cce1a0fd8d5a20R1440)
to [their destination](https://github.com/Manishearth/rust/commit/ede7a6dc8ff5455f9d0d39a90e6d11e9a374e93b#diff-6fa0bf762b2ef85690cce1a0fd8d5a20R1155) through the chained methods.

An important thing to note here is that none of the lifetime specifiers you see now in the commit were added when I did this. For example, [the return value
of `create_struct_pattern`](https://github.com/Manishearth/rust/commit/ede7a6dc8ff5455f9d0d39a90e6d11e9a374e93b#diff-6fa0bf762b2ef85690cce1a0fd8d5a20R1410) was
`(P<ast::Pat>, Vec<(Span, Option<Ident>, P<Expr>, &[ast::Attribute])>)` at this point, not `(P<ast::Pat>, Vec<(Span, Option<Ident>, P<Expr>, &'a [ast::Attribute])>)`.
You can ignore the complicated types being passed around, for now just pretend that a slice of attributes was returned.

Now comes the magic. After these small changes necessary for the feature, I basically let the compiler do the rest of the work. See, at this point the code was wrong.
I had forgotten lifetime specifiers in places where they were important, and still wasn't sure if storing a reference would in fact be possible in the first place.
However, the compiler was smart enough to figure things out for me. It would tell me to add lifetime specifiers, and I would add them.

First, the compiler asked me to add [a lifetime to the `FieldInfo` parts of `SubstructureFields`](https://github.com/Manishearth/rust/commit/ede7a6dc8ff5455f9d0d39a90e6d11e9a374e93b#diff-6fa0bf762b2ef85690cce1a0fd8d5a20R297). So, the following:

```rust
pub enum SubstructureFields<'a> {
    Struct(Vec<FieldInfo>),
    EnumMatching(usize, &'a ast::Variant, Vec<FieldInfo>),
    // ...
}
```

became


```rust
pub enum SubstructureFields<'a> {
    Struct(Vec<FieldInfo<'a>>),
    EnumMatching(usize, &'a ast::Variant, Vec<FieldInfo<'a>>),
    // ...
}
```

This needed to happen because elision doesn't work for structs and enums,
and besides, the compiler would need to know if the `&ast::Variant` was supposed to be the same lifetime as the parameter of the `FieldInfo`s. I decided
to just use the existing `'a` parameter, which meant that yes, the `&ast::Variant` was supposed to live just as long. I could also have opted to give the `FieldInfo`s
a different lifetime by adding a `'b` parameter, but I guessed that it would work this way too (knowing the origin of the fieldinfo and variant, and that implicit lifetime casting would
fix most issues that cropped up). I didn't need to think this out much, though &mdash; the compiler gave me a suggestion and I could simply copy it.

The next error was in [`create_enum_variant_pattern()`](https://github.com/Manishearth/rust/commit/ede7a6dc8ff5455f9d0d39a90e6d11e9a374e93b#diff-6fa0bf762b2ef85690cce1a0fd8d5a20R1463)
and [`create_struct_pattern()`](https://github.com/Manishearth/rust/commit/ede7a6dc8ff5455f9d0d39a90e6d11e9a374e93b#diff-6fa0bf762b2ef85690cce1a0fd8d5a20R1404) as well as some other places.

Here, the method had a signature of 

```rust

fn create_enum_variant_pattern(&self,
                               cx: &mut ExtCtxt,
                               enum_ident: ast::Ident,
                               variant: &ast::Variant,
                               prefix: &str,
                               mutbl: ast::Mutability)
-> (P<ast::Pat>, Vec<(Span, Option<Ident>, P<Expr>, &[ast::Attribute])>)
```

and I changed it to


```rust

fn create_enum_variant_pattern<'a>(&self,
                               cx: &mut ExtCtxt,
                               enum_ident: ast::Ident,
                               variant: &'a ast::Variant,
                               prefix: &str,
                               mutbl: ast::Mutability)
-> (P<ast::Pat>, Vec<(Span, Option<Ident>, P<Expr>, &'a [ast::Attribute])>)
```

In this case, the code was uncomfortable with taking a slice of attributes out of an arbitrary `StructDef` reference and returning it. What if the `StructDef` doesn't live long enough?
Generally the compiler internally figures out the lifetimes necessary and uses them here, but if you have too many references there's no single way to make the fix.
In this case, the compiler suggested I add a `'a` to `&StructDef` and the returned `&[Attribute]`, and I did so. The `'a` lifetime was declared at [the top of the impl](https://github.com/Manishearth/rust/blob/ede7a6dc8ff5455f9d0d39a90e6d11e9a374e93b/src/libsyntax/ext/deriving/generic/mod.rs#L379), so it was the lifetime parameter of `self`[^2]. This meant that the returned attribute of the function will
have a lifetime tied to `self` and the input `StructDef`, and due to this it cannot outlive the inputs, which is what we wanted in the first place. In essence, I took a bit of code that was doing:

```rust
fn minicreate(&self, variant: &ast::Variant) -> &[ast::Attribute] {
    // do stuff
    // return variant.attributes
}
```

and changed it to 

```rust
// we are sure that the returned slice cannot outlive the variant argument
fn minicreate<'a>(&self, variant: &'a ast::Variant) -> &'a [ast::Attribute] {
    // do stuff
    // return variant.attributes
}
```

Again, I didn't need to think this out much (I'm only thinking it through now for this blog post). I followed the suggestion given to me by the compiler:

```text
error: cannot infer an appropriate lifetime for automatic coercion due to conflicting requirements
help: consider using an explicit lifetime parameter as shown: fn create_enum_variant_pattern<'a>(&self, cx: &mut ExtCtxt, enum_ident: ast::Ident, variant: &'a ast::Variant, prefix: &str, mutbl: ast::Mutability) -> (P<ast::Pat>, Vec<(Span, Option<Ident>, P<Expr>, &'a [ast::Attribute])>)

```

There were a couple of similar errors elsewhere that were caused by tying these two lifetimes together. Since these methods were chained, updating the lifetimes of a child method
would mean that I would have to now update the parent method which passes its arguments down to the children and returns a modification of its return value (and thus must now impose the
same restrictions on its own signature). All of this was done by just listening to the suggestions of the compiler (which all contain a function signature to try out). In [some cases](https://github.com/Manishearth/rust/commit/ede7a6dc8ff5455f9d0d39a90e6d11e9a374e93b#diff-6fa0bf762b2ef85690cce1a0fd8d5a20R890) I introduced a `'b` lifetime, because tying it to `'a`
(the self lifetime parameter) was possibly too restrictive. All of this at the suggestion of the compiler.

While this all seems long and complicated, in reality it wasn't. I simply added the field to the initial struct, tried compiling a couple of times to figure out which code needed updating
to pass around the attributes, and then went through 3-4 more compilation attempts to fix the lifetimes. It didn't take long, and I didn't need to put much mental effort into it. I just
listened to the compiler, and it worked.

And now I trust completely that that code will not cause any segfaults due to attempted access of a destroyed or moved vector. And this is despite the fact that I _still_ don't know
where that particular vector is modified or destroyed &mdash; I didn't explore that far because I didn't need to! (or want to :P)

And this is one place Rust really shines. It lets you do optimizations which you wouldn't dream of doing in C++. In fact, while the C++ way of looking at this problem
would probably be to just clone and move on, most Rust programmers would think of using slices as the default, and not even consider it an "optimization". And again, this wasn't
with much cognitive overhead; I could just follow the compiler and it fixed everything for me.

[^1]: Some people have pointed out that a shared pointer to the vector itself would work here too. This is correct, but a shared pointer also has a runtime overhead, and more importantly doesn't prevent iterator invalidation. I had no idea how the vector was being used elsewhere, so this was a risk I didn't want to take. Additionally, whilst a shared pointer to the vector itself is immune to the issue of the vector being moved, since this was an API, someone consuming the API might take a reference of an attribute and hold on to it long enough for it to become invalidated. This is something we can't have either -- an API consumer should not have to worry about where the pointers will invalidate.
[^2]: Note: This is not the lifetime of the reference `&self`, which is the lifetime of the pointer (`&'b self`), but the lifetime parameter of `self`, a `TraitDef<'a>`, which has a lifetime parameter for its child fields.



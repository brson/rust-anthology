# Abstraction without overhead

[Previous posts][fearless] have covered two pillars of Rust's design:

* Memory safety without garbage collection
* Concurrency without data races

This post begins exploring the third pillar:

* **Abstraction without overhead**

One of the mantras of C++, one of the qualities that make it a good fit for
systems programming, is its principle of zero-cost abstraction:

> C++ implementations obey the zero-overhead principle: What you don't use, you
> don't pay for [Stroustrup, 1994]. And further: What you do use, you couldn't
> hand code any better.
>
> -- Stroustrup

This mantra did not always apply to Rust, which for example used to have
mandatory garbage collection. But over time Rust's ambitions have gotten
ever lower-level, and zero-cost abstraction is now a core principle.

The cornerstone of abstraction in Rust is *traits*:

* **Traits are Rust's sole notion of interface**. A trait can be implemented by
  multiple types, and in fact new traits can provide implementations for
  existing types. On the flip side, when you want to abstract over an unknown
  type, traits are how you specify the few concrete things you need to know
  about that type.

* **Traits can be statically dispatched**. Like C++ templates, you can have
  the compiler generate a separate copy of an abstraction for each way it is
  instantiated. This comes back to the C++ mantra of "What you do use, you
  couldn't hand code any better" -- the abstraction ends up completely erased.

* **Traits can be dynamically dispatched**. Sometimes you really do need an
  indirection, and so it doesn't make sense to "erase" an abstraction at
  runtime. The *same* notion of interface -- the trait -- can also be used when
  you want to dispatch at runtime.

* **Traits solve a variety of additional problems beyond simple abstraction**.
  They are used as "markers" for types, like the `Send` marker described
  [in a previous post][fearless]. They can be used to define "extension methods"
  -- that is, to add methods to an externally-defined type. They largely obviate
  the need for traditional method overloading. And they provide a simple scheme
  for operator overloading.

All told, the trait system is the secret sauce that gives Rust the ergonomic,
expressive feel of high-level languages while retaining low-level control over
code execution and data representation.

This post will walk through each of the above points at a high level, to give
you a sense for how the design achieves these goals, without getting too bogged
down in the details.

### Background: methods in Rust

> Before delving into traits, we need to look at a small but important detail of
> the language: the difference between methods and functions.

Rust offers both methods and free-standing functions, which are very
closely related:

```rust,ignore
struct Point {
    x: f64,
    y: f64,
}

// a free-standing function that converts a (borrowed) point to a string
fn point_to_string(point: &Point) -> String { ... }

// an "inherent impl" block defines the methods available directly on a type
impl Point {
    // this method is available on any Point, and automatically borrows the
    // Point value
    fn to_string(&self) -> String { ... }
}
```

Methods like `to_string` above are called "inherent" methods, because they:

* Are tied to a single concrete "self" type (specified via the `impl` block header).
* Are *automatically* available on any value of that type -- that is, unlike
  functions, inherent methods are always "in scope".

The first parameter for a method is always an explicit "self", which is either
`self`, `&mut self`, or `&self` depending on the
[level of ownership required][socket].  Methods are invoked using the `.`
notation familiar from object-oriented programming, and the self parameter is
*implicitly borrowed* as per the form of `self` used in the method:

```rust,ignore
let p = Point { x: 1.2, y: -3.7 };
let s1 = point_to_string(&p);  // calling a free function, explicit borrow
let s2 = p.to_string();        // calling a method, implicit borrow as &p
```

Methods and their auto-borrowing are an important aspect of the ergonomics of
Rust, supporting "fluent" APIs like the one for spawning processes:

```rust,ignore
let child = Command::new("/bin/cat")
    .arg("rusty-ideas.txt")
    .current_dir("/Users/aturon")
    .stdout(Stdio::piped())
    .spawn();
```

### Traits are interfaces

Interfaces specify the expectations that one piece of code has on another,
allowing each to be switched out independently. For traits, this specification
largely revolves around methods.

Take, for example, the following simple trait for hashing:

```rust
trait Hash {
    fn hash(&self) -> u64;
}
```

In order to implement this trait for a given type, you must provide a `hash`
method with matching signature:

```rust,ignore
impl Hash for bool {
    fn hash(&self) -> u64 {
        if *self { 0 } else { 1 }
    }
}

impl Hash for i64 {
    fn hash(&self) -> u64 {
        *self as u64
    }
}
```

Unlike interfaces in languages like Java, C# or Scala, **new traits can be
implemented for existing types** (as with `Hash` above). That means abstractions
can be created after-the-fact, and applied to existing libraries.

Unlike inherent methods, trait methods are in scope only when their trait
is. But assuming `Hash` is in scope, you can write `true.hash()`, so
implementing a trait extends the set of methods available on a type.

And... that's it! Defining and implementing a trait is really nothing more than
abstracting out a common interface satisfied by more than one type.

### Static dispatch

Things get more interesting on the other side -- consuming a trait. The most
common way of doing so is through *generics*:

```rust,ignore
fn print_hash<T: Hash>(t: &T) {
    println!("The hash is {}", t.hash())
}
```

The `print_hash` function is generic over an unknown type `T`, but requires that
`T` implements the `Hash` trait. That means we can use it with `bool` and `i64`
values:

```rust,ignore
print_hash(&true);      // instantiates T = bool
print_hash(&12_i64);    // instantiates T = i64
```

**Generics are compiled away, resulting in static dispatch**. That is, as with
C++ templates, the compiler will generate *two copies* of the `print_hash`
method to handle the above code, one for each concrete argument type.  That in
turn means that the internal call to `t.hash()` -- the point where the
abstraction is actually used -- has zero cost: it will be compiled to a direct,
static call to the relevant implementation:

```rust,ignore
// The compiled code:
__print_hash_bool(&true);  // invoke specialized bool version directly
__print_hash_i64(&12_i64);   // invoke specialized i64 version directly
```

This compilation model isn't so useful for a function like `print_hash`, but
it's *very* useful for more realistic uses of hashing. Suppose we also introduce
a trait for equality comparison:

```rust
trait Eq {
    fn eq(&self, other: &Self) -> bool;
}
```

(The reference to `Self` here will resolve to whatever type we implement the
trait for; in `impl Eq for bool` it will refer to `bool`.)

We can then define a hash map that is generic over a type `T` implementing both
`Hash` and `Eq`:

```rust,ignore
struct HashMap<Key: Hash + Eq, Value> { ... }
```

The static compilation model for generics will then yield several benefits:

* Each use of `HashMap` with concrete `Key` and `Value` types will result in a
  different concrete `HashMap` type, which means that `HashMap` can lay out the
  keys and values in-line (without indirection) in its buckets. This saves on
  space and indirections, and improves cache locality.

* Each method on `HashMap` will likewise generate specialized code. That means
  there is no extra cost dispatching to calls to `hash` and `eq`, as above.  It
  also means that the optimizer gets to work with the fully concrete code --
  that is, from the point of view of the optimizer, *there is no abstraction*.
  In particular, static dispatch allows for *inlining* across uses of generics.

Altogether, just as in C++ templates, these aspects of generics mean that you
can write quite high-level abstractions that are *guaranteed* to compile down to
fully concrete code that "you couldn't hand code any better".

**But, unlike with C++ templates, clients of traits are fully type-checked in
advance**.  That is, when you compile `HashMap` in isolation, its code is
checked *once* for type correctness against the abstract `Hash` and `Eq` traits,
rather than being checked repeatedly when applied to concrete types. That means
earlier, clearer compilation errors for library authors, and less typechecking
overhead (i.e., faster compilation) for clients.

### Dynamic dispatch

We've seen one compilation model for traits, where all abstraction is compiled
away statically. But sometimes abstraction isn't just about reuse or modularity
-- **sometimes abstraction plays an essential role at runtime that can't be
compiled away**.

For example, GUI frameworks often involve callbacks for responding to events,
such as mouse clicks:

```rust
trait ClickCallback {
    fn on_click(&self, x: i64, y: i64);
}
```

It's also common for GUI elements to allow multiple callbacks to be registered
for a single event. With generics, you might imagine writing:

```rust,ignore
struct Button<T: ClickCallback> {
    listeners: Vec<T>,
    ...
}
```

but the problem is immediately apparent: that would mean that each button is
specialized to precisely one implementor of `ClickCallback`, and that the type
of the button reflects that type. That's not at all what we wanted! Instead,
we'd like a single `Button` type with a set of *heterogeneous* listeners, each
potentially a different concrete type, but each one implementing
`ClickCallback`.

One immediate difficulty here is that, if we're talking about a heterogeneous
group of types, *each one will have a distinct size* -- so how can we even lay
out the internal vector? The answer is the usual one: indirection. We'll store
*pointers* to callbacks in the vector:

```rust,ignore
struct Button {
    listeners: Vec<Box<ClickCallback>>,
    ...
}
```

Here, we are using the `ClickCallback` trait as if it were a type. Actually, in
Rust, [traits *are* types, but they are "unsized"][dst5], which roughly means
that they are only allowed to show up behind a pointer like `Box` (which points
onto the heap) or `&` (which can point anywhere).

In Rust, a type like `&ClickCallback` or `Box<ClickCallback>` is called a "trait
object", and includes a pointer to an instance of a type `T` implementing
`ClickCallback`, *and* a vtable: a pointer to `T`'s implementation of each
method in the trait (here, just `on_click`). That information is enough to
dispatch calls to methods correctly at runtime, and to ensure uniform
representation for all `T`. So `Button` is compiled just once, and the
abstraction lives on at runtime.

Static and dynamic dispatch are complementary tools, each appropriate for
different scenarios. **Rust's traits provide a single, simple notion of
interface that can be used in both styles, with minimal, predictable
costs**. Trait objects satisfy Stroustrup's "pay as you go" principle: you have
vtables when you need them, but the same trait can be compiled away statically
when you don't.

### The many uses of traits

We've seen a lot of the mechanics and basic use of traits above, but they also
wind up playing a few other important roles in Rust. Here's a taste:

* **Closures**. Somewhat like the `ClickCallback` trait, closures in Rust are
  simply particular traits. You can read more about how this works in
  Huon Wilson's [in-depth post][closures] on the topic.

* **Conditional APIs**. Generics make it possible to implement a trait
  conditionally:

  ```rust,ignore
  struct Pair<A, B> { first: A, second: B }
  impl<A: Hash, B: Hash> Hash for Pair<A, B> {
      fn hash(&self) -> u64 {
          self.first.hash() ^ self.second.hash()
      }
  }
  ```

  Here, the `Pair` type implements `Hash` if, and only if, its components do --
  allowing the single `Pair` type to be used in different contexts, while
  supporting the largest API available for each context.  It's such a common
  pattern in Rust that there is built-in support for generating certain kinds of
  "mechanical" implementations automatically:

  ```rust,ignore
  #[derive(Hash)]
  struct Pair<A, B> { .. }
  ```

* **Extension methods**. Traits can be used to extend an existing type (defined
  elsewhere) with new methods, for convenience, similarly to C#'s extension
  methods. This falls directly out of the scoping rules for traits: you just
  define the new methods in a trait, provide an implementation for the type in
  question, and *voila*, the method is available.

* **Markers**. Rust has a handful of "markers" that classify types: `Send`,
  `Sync`, `Copy`, `Sized`. These markers are just *traits* with empty bodies,
  which can then be used in both generics and trait objects. Markers can be
  defined in libraries, and they automatically provide `#[derive]`-style
  implementations: if all of a types components are `Send`, for example, so is
  the type. As we saw [before][fearless], these markers can be very powerful:
  the `Send` marker is how Rust guarantees thread safety.

* **Overloading**. Rust does not support traditional overloading where the same
  method is defined with multiple signatures. But traits provide much of the
  benefit of overloading: if a method is defined generically over a trait, it
  can be called with any type implementing that trait. Compared to traditional
  overloading, this has two advantages. First, it means the overloading is less
  [ad hoc][adhoc]: once you understand a trait, you immediately understand the
  overloading pattern of any APIs using it. Second, it is *extensible*: you can
  effectively provide new overloads downstream from a method by providing new
  trait implementations.

* **Operators**. Rust allows you to overload operators like `+` on your own
  types. Each of the operators is defined by a corresponding standard library
  trait, and any type implementing the trait automatically provides the operator
  as well.

The point: **despite their seeming simplicity, traits are a unifying concept
that supports a wide range of use cases and patterns, without having to pile on
additional language features.**

### The future

One of the primary ways that languages tend to evolve is in their abstraction
facilities, and Rust is no exception: many of our [post-1.0 priorities][post1]
are extensions of the trait system in one direction or another. Here are some
highlights.

* **Statically dispatched outputs**. Right now, it's possible for functions to
  use generics for their parameters, but there's no equivalent for their
  results: you cannot say "this function returns a value of some type that
  implements the `Iterator` trait" and have that abstraction compiled away.
  This is particularly problematic when you want to return a closure that you'd
  like to be statically-dispatched -- you simply can't, in today's Rust. We want
  to make this possible, and [have some ideas already][impl-trait].

* **Specialization**. Rust does not allow overlap between trait implementations,
  so there is never ambiguity about which code to run. On the other hand, there
  are some cases where you can give a "blanket" implementation for a wide range
  of types, but would then like to provide a more specialized implementation for
  a few cases, often for performance reasons. We hope to propose a design in the
  near future.

* **Higher-kinded types** (HKT). Traits today can only be applied to *types*,
  not *type constructors* -- that is, to things like `Vec<u8>`, not to `Vec`
  itself. This limitation makes it difficult to provide a good set of container
  traits, which are therefore not included in the current standard library. HKT
  is a major, cross-cutting feature that will represent a big step forward in
  Rust's abstraction capabilities.

* **Efficient re-use**. Finally, while traits provide some mechanisms for
  reusing code (which we didn't cover above), there are still some patterns of
  reuse that don't fit well into the language today -- notably, object-oriented
  hierarchies found in things like the DOM, GUI frameworks, and many
  games. Accommodating these use cases without adding too much overlap or
  complexity is a very interesting design problem, and one that Niko Matsakis
  has started a separate [blog series][virtual] about. It's not yet clear
  whether this can all be done with traits, or whether some other ingredients
  are needed.

Of course, we're at the eve of the 1.0 release, and it will take some time for
the dust to settle, and for the community to have enough experience to start
landing these extensions. But that makes it an exciting time to get involved:
from influencing the design at this early stage, to working on implementation,
to trying out different use cases in your own code -- we'd love to have your
help!

[zero-cost-cpp]: http://www.stroustrup.com/abstraction-and-machine.pdf
[fearless]: http://blog.rust-lang.org/2015/04/10/Fearless-Concurrency.html
[dst5]: http://smallcultfollowing.com/babysteps/blog/2014/01/05/dst-take-5/
[adhoc]: http://dl.acm.org/citation.cfm?id=75283
[socket]: http://blog.skylight.io/rust-means-never-having-to-close-a-socket/
[post1]: http://internals.rust-lang.org/t/priorities-after-1-0/1901
[virtual]: http://smallcultfollowing.com/babysteps/blog/2015/05/05/where-rusts-enum-shines/
[closures]: http://huonw.github.io/blog/2015/05/finding-closure-in-rust/
[impl-trait]: https://github.com/rust-lang/rfcs/pull/105

> [_Originally published 2015-05-11_](http://blog.rust-lang.org/2015/05/11/traits.html)
>
> _License: TBD_

% The Many Kinds of Code Reuse in Rust

(This article is written against Rust 1.7 stable)

Rust has a lot of *stuff* in its type system. As far as I'm concerned, almost
all of the complexity is dedicated to expressing programs generically. And people
are still clamouring for more! I always have trouble getting the most advanced
parts straight, so this post is basically a "note to self". That said, I like
making things that are useful to other people, so this will also cover some
things which I probably won't forget, but other people might not know.

This post will *not* exhaustively cover syntax or all the details of the features
described. This is mostly focused on *why* things are the way they are, because
that's the part I always forget. If you want to actually learn Rust properly,
you should probably read The Book. That said, I *will* randomly fixate on some
of my favorite aspects of these systems.

This post also likely makes many errors, and should not be considered an
official piece of reference material. It's just what I was able to knock out
over a week before I started a new job.




# A Brief Review of Code Reuse

The desire to take some piece of code and use it more than once has existed
since our computational ancestors carved the first bits from rocks to hunt
mammoths. Clearly, from this description I have no idea what code reuse looked
like in the earliest days of programming. Cheat sheets? Vacuum tube modules?
Punch card stencils? I dunno, I'm not a histogram. I'm more interested in how
things are done today.

The most common form of a code-reuse is, of course, functions. Sure, great,
everyone likes functions. Depending on what language you're in, and what you're
doing, functions may or may not be the start and the end of the code-reuse
story for you. In other cases, they might not be enough. You might want to do
things that are known by various overloaded terms, like "meta-programming"
(describing code itself) or "polymorphism" (writing code that can handle
different kinds of data).

Technically, these are orthogonal concerns, but they get conflated pretty frequently. Lots of
features in different languages hook into all this: macros, templates, generics,
inheritance, function pointers, interfaces, overloading, unions, and so on.
But all these concepts are just fiddling with the semantics. Really, it's all
going to boil down to three major strategies:
monomorphization, virtualization, and enumeration.





## Monomorphization

Monomorphization is the practice of basically copy-pasting code over
and over again, with details changed. The main benefit of monomorphization is
that you can get a "perfect" custom implementation, with nothing weird for your
compiler to try to undo. This is its own weakness, though. In the worst case, the
final binary will contain a distinct copy of a monomorphic interface for every
place it's used. This may just mean large binaries and large compile times, but
it can also mean horrible use of your processor's instruction cache. As far as
it's concerned, there's no code reuse at all! Just piles and piles of code.

The semantic limitation of monomorphization is that it can't be (directly) used
to process multiple distinct things homogeneously. For instance, say I want to
build a job queue that receives tasks, and then executes them in order. If I
want all the tasks to be exactly the same, then monomorphization work fine. But
if I want a single queue to be able to handle different tasks, then it's not
clear how that could be done with monomorphization alone. That's why it's *called*
"mono"morphization. It's all about taking abstract implementations and creating
instances that do *one* thing.

Some common examples of monomorphization: text substitution, C++ templates,
C macros, Go Generate, and C# generics. Most of these are done completely at
compile-time, but C# actually monomorphizes something like `List<T>` on demand
at runtime. All that's created at compile-time is a template. Monomorphization
is also an incredibly popular compiler/JIT optimization. Inlining and specializing
code is, after all, just monomorphizing it!





## Virtualization

Virtualization is monomorphization's natural opposite, leveraging the solution
every programmer comes to after copy-pasting code: adding more indirection.
Both data and functionality can be virtualized, in which case all the user of
a virtualized interface sees are pointers to *something*.

Virtualizing data allows code to handle types with different sizes and layouts
uniformly. Virtualizing functions allows a single function to have custom behaviour,
without having to copy-paste it. The dynamic job queue example that monomorphization
struggled with is handily solved by virtualization. Each task to perform can simply
be a function pointer, which the queue will follow and execute. If you need to
associate data with each task, you can also pass a pointer to data, which the
queue can pass along to the function to interpret appropriately.

Virtualization's primary downside is that it's *usually* worse for performance
to add lots of indirection. Particularly because it often implies doing more
heap allocation, jumping to random places in memory (bad for all caches),
and determining what the heck the thing we're working with is.

However virtualization *can* be more efficient than monomorphization! Whenever
a function is statically invoked (and we aren't doing recursion), a compiler
*could* inline that function call, but they won't always. This is because,
as I mentioned, too much monomorphization makes programs bloated and slow.
For similar reasons, it can be beneficial to *outline* code that is rarely
invoked. For instance, error handling code is presumably unlikely to be executed,
so virtualizing that code just leaves more room for the common path in the
instruction cache.

Some common examples of virtualization: function pointers and void pointers in C,
callbacks, inheritance (Java, C++, C#), generics in Java, and prototypes in
JavaScript. Note that in many of these examples, virtualization of functionality
and data is combined. Inheritance in particular often results in virtualization
of both code and data. For instance, if I have a pointer to an Animal, it might
might actually be a Cat or a Dog. If I ask the animal to `speak`, how does it know
to "bark" or "meow"?

The standard way to handle this is for *every single
instance* of a type in an inheritance hierarchy to secretly store a pointer
to various pieces of information that may be needed at runtime, called a "vtable".
The standard thing for a vtable to store would be a bunch of function pointers
(one of which would be this instance's implementation of `speak`),
but it might also store things like size, alignment, and the actual type.





## Enumeration

Enumerations are a compromise between virtualization and monomorphization.
At runtime monomorphization can only be one thing, while virtualizations can
be anything. Enumerations, on the other hand, can be anything *from a fixed list*.
The usual strategy is just to pass around an integer "tag" which specifies which
implementation is supposed to be used.

For instance, a job queue using enumeration might define three kinds of task
it can perform: "Create", "Update", and "Delete". Someone who wants to perform
a Create task simply bundles up all the data expected for Create, along with the
appropriate tag. The queue then checks the tag, reinterprets the data to be
the kind associated with Create, and executes its logic for creation.

Like code that uses virtualization, enumerated code can handle multiple types
at once, and there's no need to create a new copy of the code for each type.
Like monomorphized code, there's no need for indirection; the only runtime
aspect is checking the value of the tag. This can make it easier for an optimizer
to reason about enums.

Although it should be noted that if indirection *isn't* used, then an enumerated
type can become really big, because every instance needs to have space for
the largest type it *could* be. For instance, Delete may only require a name,
but Create may require a name, author, content, and so on. Even if the queue
is mostly storing Delete commands, it will use up the space of a queue full of
Create commands.

Of course, the biggest limitation of all is that you need to know the full
set of choices upfront. Both virtualization and monomorphization can be used
with interfaces that are "open" to extension. Anyone can extend a class, and
any type can be provided to a template, but enumeration is "closed" to extension.
The set of implementations is set in stone when it is declared. Adding or removing
elements from this set will likely break consumers of an enumeration!

Because of this, this strategy is relatively obscure. Many languages provide a
notion of an enumeration as an `enum`, but often lack support for those enums
having associated data, which limits their usefulness. C provides the ability
to declare that a field is the union of two types, but leaves it up to the
programmer to determine which type the field should be interpreted as. Many functional
languages provide tagged unions, which are the combination of an enum and a C union,
allowing arbitrary data to be associated with each variant of an enum.





# Back to Rust

Alright, so those are the major code reuse strategies as seen in *other*
languages. What's Rust got? Rust's story is split up into three major pillars:

* Macros (simple monomorphization!)
* Enums (full enumeration!)
* Traits (where the complexity is)





# Macros

Macros are the easiest. They're pure, raw, code reuse. In Rust they generally
work on parts of the AST (Abstract Syntax Tree; chunks of source code).
You give them some bits of AST, and it spews out some new bits of AST at
compile time. There's no type information beyond stuff like "this string looked
like a type name".

There's basically two reasons to use macros: you want to extend the language,
or you want to copy-paste some code with minor tweaks. The standard library
[exports a few examples of the former][vec-macro] (`println!`, `thread_local!`,
`vec!`, `try`, etc):

```rust,ignore
/// Creates a `Vec` containing the arguments.
///
/// `vec!` allows `Vec`s to be defined with the same syntax as array expressions.
/// There are two forms of this macro:
///
/// - Create a `Vec` containing a given list of elements:
///
/// ```
/// let v = vec![1, 2, 3];
/// assert_eq!(v[0], 1);
/// assert_eq!(v[1], 2);
/// assert_eq!(v[2], 3);
/// ```
///
/// - Create a `Vec` from a given element and size:
///
/// ```
/// let v = vec![1; 3];
/// assert_eq!(v, [1, 1, 1]);
/// ```
///
/// Note that unlike array expressions this syntax supports all elements
/// which implement `Clone` and the number of elements doesn't have to be
/// a constant.
///
/// This will use `clone()` to duplicate an expression, so one should be careful
/// using this with types having a nonstandard `Clone` implementation. For
/// example, `vec![Rc::new(1); 5]` will create a vector of five references
/// to the same boxed integer value, not five references pointing to independently
/// boxed integers.
#[cfg(not(test))]
#[macro_export]
#[stable(feature = "rust1", since = "1.0.0")]
macro_rules! vec {
    ($elem:expr; $n:expr) => (
        $crate::vec::from_elem($elem, $n)
    );
    ($($x:expr),*) => (
        <[_]>::into_vec($crate::boxed::Box::new([$($x),*]))
    );
    ($($x:expr,)*) => (vec![$($x),*])
}
```


and internally [makes good use of the latter][copy-pasta-macros]
when implementing lots of repetitive interfaces (primitives, tuples, and arrays
are common offenders):

```rust,ignore
// Conversion traits for primitive integer and float types
// Conversions T -> T are covered by a blanket impl and therefore excluded
// Some conversions from and to usize/isize are not implemented due to portability concerns
macro_rules! impl_from {
    ($Small: ty, $Large: ty) => {
        impl From<$Small> for $Large {
            fn from(small: $Small) -> $Large {
                small as $Large
            }
        }
    }
}

// Unsigned -> Unsigned
impl_from! { u8, u16 }
impl_from! { u8, u32 }
impl_from! { u8, u64 }

// this goes on for literally 40 more impls...
```




As far as I'm concerned, macros are basically the worst game in town. They sorta
try to be helpful (variable names don't leak into or out of the macro), but
fall over in lots of places (using unsafe code inside a macro does weird
things to the outside). Macros are basically regexes (ignoring that `expr` and `tt`
aren't at all regular to parse); no one likes reading regexes!

Most critically to me, though, is that macros are basically dynamically typed
metaprogramming. The compiler can't evaluate the the body of a macro matches its
signature, and that the macro is being invoked correctly for its signature. It
just has to expand the macro out to some code and then check that code. This
leads to the standard problem with dynamic programming: late binding of errors.
With macros, we can get the spiritual equivalent of "undefined in not a function"
in the compiler.


```rust,ignore
macro_rules! make_struct {
    (name: ident) => {
        struct name {
            field: u32,
        }
    }
}


make_struct! { Foo }
```

```text
<anon>:10:16: 10:19 error: no rules expected the token `Foo`
<anon>:10 make_struct! { Foo }
                         ^~~
playpen: application terminated with error code 101
```

What's the error here? Well obviously I left off the `$` on name, so this
macro actually always expects to be invoked as literally `make_struct! { name: ident }`,
and always produces literally `struct name { field: u32 }`.

Further, when a "normal" Rust error happens to occur in the expansion of a macro,
the resulting output is a mess!

```ignore
use std::fs::File;

fn main() {
    let x = try!(File::open("Hello"));
}
```

```text
<std macros>:5:8: 6:42 error: mismatched types:
 expected `()`,
    found `core::result::Result<_, _>`
(expected (),
    found enum `core::result::Result`) [E0308]
<std macros>:5 return $ crate:: result:: Result:: Err (
<std macros>:6 $ crate:: convert:: From:: from ( err ) ) } } )
<anon>:4:13: 4:38 note: in this expansion of try! (defined in <std macros>)
<std macros>:5:8: 6:42 help: see the detailed explanation for E0308
```

The upside of this mess is the usual upside for dynamic typing: way more flexibility.
Macros are a godsend where we use them, they're just... fragile.




## An Honorable Mention: Syntax Extensions and Code Generation

Macros have limits. They can't execute arbitrary code at compile time.
This is a good thing for security and repeatable builds, but sometimes it's
not enough. There are two ways to deal with this in Rust: syntax extensions
(AKA "procedural macros"), and code generation (AKA build.rs).
Both of these basically give you carte-blanche to execute arbitrary code
to generate source code.

Syntax extensions look like macros or annotations, but they cause the
compiler to execute custom code to (ideally) modify the AST.
`build.rs` files are a file that Cargo will compile and execute whenever
a crate is built. Obviously, this lets them do anything they please to the
project. Hopefully they'll just add some nice source code.

I could give examples or elaborate, but I don't really know much about these
options or care about them. It's code generation, what's there to say?
Also, I've been writing this article for days and it's SO LONG AND I WANT TO BE DONE.






# Enums

Enums in Rust are exactly the tagged unions we described earlier.

The most common enums you'll interact with in Rust are Option and Result, which
generally express success/failure. In other words, they let us write code that
uniformly manipulates success and failure.

What about your own custom enums? Let's say you're writing some networking code.
For whatever reason you want this code to be generic over IPv4 and IPv6. You are
absolutely certain that you don't care about the possibility of some hypothetical
IPv8, and honestly you don't have a clue how to define an interface that would
handle that anyway. One way to be generic over IPv4 and IPv6 is to define an enum:

```rust,ignore
enum IpAddress {
    V4(IPv4Address),
    V6(Ipv6Address),
}

fn connect(addr: IpAddress) {
    // Check which version it was, and choose the right impl
    match addr {
        V4(ip) => connect_v4(ip),
        V6(ip) => connect_v6(ip),
    }
}
```

That's it. Now you can write all sorts of code that just passes around generic
`IpAddress`es, and whenever someone needs to actually care about what version is
being used, they can `match` on the value and extract the contents.







# Traits

Alright, that's the easy stuff out of the way. Now onto The Hard Stuff. Traits
are Rust's answer to *everything* else. Monomorphization, virtualization,
reflection, operator overloading, type conversions, copy semantics, thread safety,
higher order functions, and bloody *for loops* all pipe through traits. In due
time, traits will also be the center piece for specialization and probably
every other big new user-facing feature added to Rust.

All that said, traits are just interfaces. That's it.

```rust
struct MyType {
    data: u32,
}

// Defining an interface
trait MyTrait {
    fn foo(&self) -> u32;
}

// Implementing an interface
impl MyTrait for MyType {
    fn foo(&self) -> u32 {
        self.data
    }
}

fn main() {
    let mine = MyType { data: 0 };
    println!("{}", mine.foo());
}
```

For the most part, you can just think of traits as interfaces in Java or C#, but there's
some slight differences. In particular, traits are designed to be more flexible. In C# and
Java, as far as I know, the only one who can implement `MyTrait` for `MyType`
is the declarer of `MyType`. But in Rust, the declarer of `MyTrait` can *also*
implement it for MyType. This lets a downstream library or application define interfaces
and have them implemented by types declared in e.g. the standard library.

Of course, letting this go completely unchecked would be chaos. People could
inject functions onto arbitrary types! To keep the chaos under control, trait
implementations are only visible to code that has the relevant trait in scope.
This is why doing I/O without importing the Read and Write traits often falls
apart.





# Aside: Coherence

Those familiar with Haskell may recognize traits to be quite similar to Haskell's *type classes*.
Those same people may then raise the (incredibly reasonable) question: what happens if there are
multiple implementations of the same trait for the same type? This is the coherence
problem. In a coherent world, everything only has one implementation. I don't want
to get into coherence, but the long and the short of it is that Rust has more
restrictions in place to avoid the problems Haskell has with coherence.

The bulk of these restrictions are: you need to either be declaring the trait
or declaring the type to `impl Trait for Type`, and crates can't circularly
depend on each-other (dependencies must form a DAG). The messy case is that this
is actually a lie, and you can do things like `impl Trait for Box<MyType>`, even
though Trait and Box are declared elsewhere. Most of the complexity in coherence,
to my knowledge, is dealing with these special cases. The rules that govern this
are the "orphan rules", which basically ensure that, for any web of dependencies,
there's a *single* crate which can declare a particular `impl Trait for ...`.

The result is
that it's impossible for two separate libraries to compile but introduce a conflict
when imported at the same time. That said, the restrictions imposed by coherence
can be *really annoying*, and sometimes I curse Niko Matsakis' name.

The standard library (which is secretly several disjoint libraries stitched together)
is constantly on the cusp of breaking in half because of coherence. There's several
implementations that are conspicuously missing, and several types and traits that
are defined in weird places, precisely because of coherence. Also that wasn't even
sufficient and a special hack had to be added to the compiler called `#[fundamental]`
which declares that certain things have special coherence rules.

Coherence is really important.

I really hate coherence.

Specialization might make it better.

I should probably explain the orphan rules properly.

I'm not going to.




# Generics

So how do we actually use traits for reuse? Well, Rust actually
let's us decide! We can either use virtualization or monomorphization. Monomorphization
is *overwhelmingly* the choice in Rust's standard library, and in most Rust code I've
seen. This is because monomorphization is *probably* the more efficient thing on
average, and it's also strictly more general in Rust. That is, a monomorphic interface
can be converted into a virtualized one by the user. We'll see that in a bit.

Declaring a monomorphic interface is done with what Rust calls generics:


```rust,ignore
// Plain struct, for comparison purposes.
struct Concrete {
    data: u32,
}

// A generic struct. `<..>` is how we declare generic arguments.
// One can create a version of `Generic` for any type, unlike
// `Concrete`, which only works with `u32`.
struct Generic<T> {
    data: T,
}


// Plain impl
impl Concrete {
    fn new(data: u32) -> Concrete {
        Concrete { data: data }
    }

    fn is_big(&self) -> bool {
        self.data > 120
    }
}

// Implementing functionality for a specific
// version of Foo. Note that this is *not*
// "specialization", in the sense that any names
// declared here can't conflict with other impls.
impl Generic<u32> {
    fn is_big(&self) -> bool {
        self.data > 120
    }
}


// Implementing functionality for all choices of T.
// Note that the "impl" is also Generic here.
// Hopefully this in conjunction with the previous
// example demonstrates why the extra <T> is necessary.
impl<T> Generic<T> {
    fn new(data: T) -> Generic<T> {
        Generic { data: data }
    }

    fn get(&self) -> &T {
        &self.data
    }
}




// A normal trait declaration.
trait Clone {
    fn clone(&self) -> Self;
}

// A generic trait declaration.
// Generic traits introduce a relationship to some
// other type. In this case, we want to be able to
// compare our type to *other* types. This will
// be clearer when we see impls.
trait Equal<T> {
    fn equal(&self, other: &T) -> bool;
}



// Plain-jane trait impl
impl Clone for Concrete {
    fn clone(&self) -> Self {
        Concrete { data: self.data }
    }
}

// Implementing a generic trait concretely
impl Equal<Concrete> for Concrete {
    fn equal(&self, other: &Concrete) -> bool {
        self.data == other.data
    }
}

// Oh hey, we can do this for types we don't own, like primitives!
impl Clone for u32 {
    fn clone(&self) -> Self {
        *self
    }
}

impl Equal<u32> for u32 {
    fn equal(&self, other: &u32) -> Self {
        *self == *other
    }
}

// Taking advantage of that sweet generic trait!
impl Equal<i32> for u32 {
    fn equal(&self, other: &i32) -> Self {
        if *other < 0 {
            false
        } else {
            *self == *other as u32
        }
    }
}


// Implementing a generic trait for a concrete type generically
impl<T: Equal<u32>> Equal<T> for Concrete {
    fn equal(&self, other: &T) -> bool {
        other.equal(&self.data)
    }
}

// Implementing a concrete trait for a generic type generically.
// Note that we require that `T` implements the
// `Clone` trait! This is a *trait bound*.
impl<T: Clone> Clone for Generic<T> {
    fn clone(&self) -> Self {
        Generic { data: self.data.clone() }
    }
}

// Implementing a generic trait for a generic type generically.
// Note that we have two generic types in play; T and U.
impl<T: Equal<U>, U> Equal<Generic<U>> for Generic<T> {
    fn equal(&self, other: &Generic<U>) -> bool {
       self.equal(&other.data)
    }
}



// And finally, individual functions can also be generic.
impl Concrete {
    fn my_equal<T: Equal<u32>>(&self, other: &T) -> bool {
        other.equal(&self.data)
    }
}

impl<T> Generic<T> {
    // Interesting problem: we've inverted the order on `equal` here
    // (`x == y` is being evaluated as `y == x`). How can we express
    // `T: Equal<U>` to fix this? Note that we can't do this at the
    // time where we declare `T`, because `U` doesn't exist yet!
    // More on this later!
    fn my_equal<U: Equal<T>>(&self, other: &Generic<U>) -> bool {
       other.data.equal(&self.data)
    }
}
```



*phew*

So we can see that there's a *lot* of combinations of situations
you can run into as soon as you want to start describing interfaces
and providing implementations that are generic over those interfaces.
As I mentioned, anything that tries to use any of these structures
and implementations will be monomorphized.

So, at least before optimization passes kick in, the following code
will be expanded as follows:

```rust,ignore
// Before
struct Generic<T> { data: T }
impl<T> Generic<T> {
    fn new(data: T) {
        Generic { data: data }
    }
}

fn main() {
    let thing1 = Generic::new(0u32);
    let thing2 = Generic::new(0i32);
}
```

```rust,ignore
// After
struct Generic_u32 { data: u32 }
impl Generic_u32 {
    fn new(data: u32) {
        Generic { data: data }
    }
}

struct Generic_i32 { data: i32 }
impl Generic_i32 {
    fn new(data: i32) {
        Generic { data: data }
    }
}


fn main() {
    let thing1 = Generic_u32::new(0u32);
    let thing2 = Generic_i32::new(0i32);
}
```

It may or may not surprise you to learn that some really common functions
get copied *a lot*. For instance, brson measured that 1700 copies of
`Option<T>::map` [were being created while building Servo][servo-monomorph].
Granted, virtualizing all those calls probably would have been disastrous for
runtime performance.





# Aside: Generic Inference and The Turbofish

Generics in Rust are inferred. This is really nice when it works out,
but it can also let us express some very strange things.

```rust
// Vec::new() is a generic function, whose output type
// is inferred based on usage. It's definitely some kind of
// `Vec`, but what type of value it stores is ambiguous.
let mut x = Vec::new();

// Inserting a `u8` into the `x` solidifies its type to `Vec<T>`
x.push(0u8);
x.push(10);
x.push(20);

// `collect` is a generic function. It can produce anything that
// implements `FromIterator`, usually a collection like Vec or VecDeque.
// It's often completely ambiguous what the result of `collect` should
// be, because unlike `Vec::new()`, this function can really produce
// just about anything.

// To deal with this, we can specify the type of y explicitly.
let y: Vec<u8> = x.clone().into_iter().collect();

// Or directly tell collect what its generic arguments should be
// with the turbofish operator `::<>`!
let y = x.clone().into_iter().collect::<Vec<u8>>();
```



# Trait Objects

So how do we do virtualization? How do we erase a type to just be "something"?
Rust's solution to this is called *trait objects*. All you do is specify that
the type of something *is* some trait, and Rust will handle the rest. Of course,
in order to do this, you need to put your type behind a pointer like `&`, `&mut`
`Box`, `Rc`, or `Arc`.

```rust
trait Print {
    fn print(&self);
}

impl Print for i32 {
    fn print(&self) { println!("{}", self); }
}

impl Print for i64 {
    fn print(&self) { println!("{}", self); }
}

fn main() {
    // Normal static, monomorphized usage
    let x = 0i32;
    let y = 10i64;
    x.print();      // 0
    y.print();      // 10

    // Box<Print> is a trait object, and therefore can store any
    // implementor of Print. To create a Box<Print>, we just create
    // a `Box<T: Print>`, and try to put it somewhere that expects
    // a `Box<Print>`. Here we specify that `data` contains `Box<Print>`s,
    // so the array literal happily does the coercion for us!
    // Note that we use this to insert an i32 and an i64 into the same
    // list, which would be prevented if we used static dispatch.
    let data: [Box<Print>; 2] = [Box::new(20i32), Box::new(30i64)];

    // Now we can print all the data in this list uniformly.
    for val in &data {
        val.print();    // 20, 30
    }
}
```

Note that the requirement that things are behind pointers is more pervasive than
you might think. For instance, consider the `Clone` trait we defined earlier:

```
trait Clone {
    fn clone(&self) -> Self;
}
```

This trait defines a function that returns Self by-value. What would happen
if we tried to write the following?

```ignore
fn main() {
    let x: &Clone = ...; // doesn't matter
    let y = x.clone();   // Clone the data...?
}
```

How much space on the stack should `y` reserve in this case? What type should `y`
even have? The answer is that *we can't know at compile time*. This means that
a Clone trait object is actually nonsensical. More generally, *any* trait that
talks about Self by-value *anywhere* can't be turned into a trait object.

Trait objects are also, interestingly, implemented in a rather unconventional
way. Recall that the *usual* strategy for this sort of thing is for virtualizable
types to store a secret vtable field. This is annoying for two reasons.

First, everything is storing and setting a pointer *even when it doesn't need to*.
Whether you will actually be virtualized or not doesn't matter, because a type
needs to have a fixed layouts. So if some Widgets could be virtualized, then all
Widgets need to store that pointer.

Second, once you get to such a type's vtable, it's actually
non-trivial to determine where the functions you're interested in are stored. This is
because interfaces are, effectively, multiple inheritance (C++ meanwhile literally has
multiple inheritance). As an example, consider this set of types, traits, and
implementations:

```rust
trait Animal { }
trait Feline { }
trait Pet { }

// Animal, Feline, Pet
struct Cat { }

// Animal, Pet
struct Dog { }

// Animal, Feline
struct Tiger { }
```

What would the static layout of an `Animal + Pet` and `Animal + Feline`
be? Well, `Animal + Pet` consists of Cats and Dogs. We can lay them out
so Cats and Dogs look the same:

```text
Cat vtable              Dog vtable              Tiger vtable
+-----------------+     +-----------------+     +-----------------+
| type stuff      |     | type stuff      |     | type stuff      |
+-----------------+     +-----------------+     +-----------------+
| Animal stuff    |     | Animal stuff    |     | Animal stuff    |
+-----------------+     +-----------------+     +-----------------+
| Pet stuff       |     | Pet stuff       |     | Feline stuff    |
+-----------------+     +-----------------+     +-----------------+
| Feline stuff    |
+-----------------+
```


But now Cats and Tigers don't look the same. Swapping Pet and Feline in Cat
fixes that:

```text
Cat vtable              Dog vtable              Tiger vtable
+-----------------+     +-----------------+     +-----------------+
| type stuff      |     | type stuff      |     | type stuff      |
+-----------------+     +-----------------+     +-----------------+
| Animal stuff    |     | Animal stuff    |     | Animal stuff    |
+-----------------+     +-----------------+     +-----------------+
| Feline stuff    |     | Pet stuff       |     | Feline stuff    |
+-----------------+     +-----------------+     +-----------------+
| Pet stuff       |
+-----------------+
```


But now Cats and Dogs don't look the same! In this case, we can take the
following tact:

```text
Cat vtable              Dog vtable              Tiger vtable
+-----------------+     +-----------------+     +-----------------+
| type stuff      |     | type stuff      |     | type stuff      |
+-----------------+     +-----------------+     +-----------------+
| Animal stuff    |     | Animal stuff    |     | Animal stuff    |
+-----------------+     +-----------------+     +-----------------+
| Feline stuff    |     |                 |     | Feline stuff    |
+-----------------+     +-----------------+     +-----------------+
| Pet stuff       |     | Pet stuff       |
+-----------------+     +-----------------+
```

But this doesn't scale very well. In the limit, every interface would have a
globally unique offset, so every vtable would have to reserve space for every single
interface! Well, you could actually trim off trailing padding like Tiger does, but
still, lots of wasted space. More fatally, this assumes that we *know* about
every interface. This is in fact not the case when dynamically linking libraries!
If a dynamic library passes you a `Box<Pet>`, you would need some way to agree
on the offset of a `Pet`, while knowing completely different sets of interfaces.
This is why most languages just toss in more indirection for resolving the layout
of a vtable at runtime.

But in Rust, this is all irrelevant! Rust doesn't store vtable pointers in types.
Rust represents trait objects as *fat pointers*. `Box<Pet>` is not, in fact,
a single pointer. It's a pair of pointers, `(data, vtable)`. The vtable pointed
to also isn't *the* vtable for the data's type, it's *a* vtable. Specifically,
it's a custom vtable made explicitly for `Pet`:

```text
Cat's Pet vtable        Dog's Pet vtable
+-----------------+     +-----------------+
| type stuff      |     | type stuff      |
+-----------------+     +-----------------+
| Pet stuff       |     | Pet stuff       |
+-----------------+     +-----------------+
```

Similarly, `Pet + Animal` or `Animal + Feline` would each get a custom vtable.
We are, in effect, monomorphizing vtables for every requested combination of
traits.

This strategy completely eliminates the problems with the embedded vtable
solution. Values that don't participate in virtualization don't have any
additional data associated with them, and one can statically know where a
particular `Pet` function can be found for *every* `Pet` vtable.

However it has its own drawbacks. First off, fat pointers obviously occupy
twice as much space, which may be a problem if you're storing a lot of them.
Second off, *we're monomorphizing vtables for every requested combination
of traits*. This is possible because everything has a statically known type
at *some* point, and all coercions to trait objects are also statically known.
Still, generous use of virtualization could lead to some serious bloat!

**Warning! Hypothetical speculation**:

Fat pointers could also, in principle, be generalized to *obese pointers*.
With fat pointers, `Animal + Feline` is a single vtable pointer, but there's
no reason why it couldn't be *two* vtable pointers, one for each trait. This
could be used to reduce monomorphization, at the cost of even larger pointers.
This idea has been tossed around at various times, but there's no serious
roadmap for it.

Finally, let's return to a claim that was made several section ago:
a monomorphic interface can be converted into a virtualized one by the user.
This is done by a feature called "impl Trait for Trait", which means that
trait objects implement their own traits. The end result is that the following
works:

```rust
// Stuff we've seen before...
trait Print {
    fn print(&self);
}

impl Print for i32 {
    fn print(&self) { println!("{}", self); }
}

impl Print for i64 {
    fn print(&self) { println!("{}", self); }
}

// ?Sized specifies that T may be virtualized.
// Sized is a trait that all concrete types implicitly
// implement. However, things like Traits and
// [T] are "unsized types". Specifying that `T: ?Sized`
// indicates to the compiler that it should be an error
// to ever try to use T by-value, because Sized *might not*
// be implemented.
fn print_it_twice<T: ?Sized + Print>(to_print: &T) {
    to_print.print();
    to_print.print();
}

fn main() {
    // Static dispatch; monomorphized version for each type.
    print_it_twice(&0i32);  // 0, 0
    print_it_twice(&10i64); // 10, 10

    // Causes vtables for i32::Print and i64::Print to be constructed
    let data: [Box<Print>; 2] = [Box::new(20i32), Box::new(30i64)];

    for val in &data {
        // Dynamic dispatch; a single virtualized version is monomorphized.
        // Annoying manual conversion from &Box<Print> to &Print because
        // generics and auto-deref have a bad interaction.
        print_it_twice(&**val);    // 20, 20, 30, 30
    }
}
```

Nifty! Not silky smooth, but nifty none-the-less. Also, unfortunately,
there is no `impl Trait for Box<Trait>`. I believe this could have a bad
interaction with the ability to `impl<T: Trait> Trait for Box<T>`, but
I haven't thought about it too much. Possibly the fact that `T` is `Sized`
in such an impl makes it fine?






# Associated Types

When we declare that something is generic over a type, what are the consequences?
What are we trying to express? Usually, the idea being expressed, and the ultimate
consequence, is that someone can give us a type, and we'll figure out how to handle it.
That is, we accept types as *input*. `struct Foo<T>` states that given a `T`, we can produce the
type `Foo<T>`. Note that `Foo` itself is not really a well-formed type on its
own.

If you like fancy terms, you could say that `Foo` is a type constructor -- a function
that takes a type and returns a type -- and we're working with higher-kinded types.
For this reason, you may occasionally see generic arguments referred to as *input
types*. This is particularly apt, because these types are usually given as input
by the caller of generic code.

Traits can also be generic, what does that mean? What does `trait Eat<T>` express?
Ultimately, it's expressing that it's possible to implement the interface `Eat`
multiple times. However it's also saying that any implementation must in some
way be connected to some other type, and it shall be called `T`.

Like generic arguments to types, an implementation is *incomplete* without specifying this.
One cannot implement `Eat`. One must implement `Eat<T>`. Similarly, one cannot
demand that `Eat` is implemented. One must demand that `Eat<T>` is implemented.
Once again, the final choice of `T` is an input given by the end user of the
interface.

That's all fine and good, but why do we care? Consider providing an interface
for Iterators:

```rust
trait Iterator<T> {
    fn next(&mut self) -> Option<T>;
}

/// An iterator that yields the elements
/// from a Vec, Stackwise.
struct StackIter<T> {
    data: Vec<T>,
}

// An iterator over the range [min, max)
struct RangeIter {
    min: u32,
    max: u32,
}

impl<T> Iterator<T> for StackIter<T> {
    fn next(&mut self) -> Option<T> {
        self.data.pop()
    }
}

impl Iterator<u32> for RangeIter {
    fn next(&mut self) -> Option<u32> {
        if self.min >= self.max {
            None
        } else {
            let res = Some(self.min);
            self.min += 1;
            res
        }
    }
}
```

Ok, this all seems good! We can express concrete and generic implementations of
this interface. Perfect. But note something strange here: every *real* type only
implements Iterator exactly once. That is, `StackIter<Cat>` only implements
`Iterator<Cat>`. It's never going to implement `Iterator<Dog>`. In fact, upon
reflection, allowing this would probably be a bad idea. It would mean that any
time someone tried to get the next element out of an iterator, it would be
ambiguous what kind of element they're actually requesting!

Really, we don't want `T` to be an input to `Iterator` in the same way `T` is an
input to `StackIter`. But this is necessary, because we can't hard-code what kind
of type is yielded by an iterator. That information needs to be provided by
the implementor!

And that's what associated types are for. With associated types, we can specify
that an implementation of a trait needs to specify some types that are associated
with a particular implementation, just as we can specify that functions
must be provided. Here's `Iterator` refactored to use them:

```rust
trait Iterator {
    // Every iterator yields a particular type of
    // item, which they must specify.
    type Item;
    fn next(&mut self) -> Option<Self::Item>;
}

/// An iterator that yields the elements
/// from a Vec, Stackwise.
struct StackIter<T> {
    data: Vec<T>,
}

// An iterator over the range [min, max)
struct RangeIter {
    min: u32,
    max: u32,
}

impl<T> Iterator for StackIter<T> {
    // Associated items can still be
    // derived from other generics
    type Item = T;
    fn next(&mut self) -> Option<Self::Item> {
        self.data.pop()
    }
}

impl Iterator for RangeIter {
    // Or concretely specified.
    type Item = u32;
    fn next(&mut self) -> Option<Self::Item> {
        if self.min >= self.max {
            None
        } else {
            let res = Some(self.min);
            self.min += 1;
            res
        }
    }
}
```

And now we've forbidden a type implementing Iterator in multiple ways.
Although associated types can be generic, they can't be specified to
be completely independent of all other types. So for instance, this
is completely invalid code:

```rust,ignore
impl<T> Iterator for RangeIter {
    type Item = T;
    fn next(&mut self) -> Option<Self::Item> {
        unimplemented!()
    }
}
```

```text
<anon>:3:6: 3:7 error: the type parameter `T` is not constrained by the impl trait, self type, or predicates [E0207]
<anon>:3 impl<T> Iterator for RangeIter {
              ^
```

For this reason, we sometimes call associated types *output types*.

Ok, so we can restrict implementations with associated types. But do they
let us create implementations that *couldn't* be expressed before? Actually, yes!

Consider a modified version of Iterator -- StateMachine.

```rust
trait StateMachine {
    type NextState: StateMachine;
    fn step(self) -> Option<Self::NextState>;
}
```

Ok, so a StateMachine is some type that you can tell do a step, and it
will turn itself into a new StateMachine of some kind. Let's try to write
that out as a generic trait:

```rust,ignore
trait StateMachine<NextStep: StateMachine<UHHH_WHAT_GOES_HERE>> {
    fn step(self) -> Option<NextState>;
}
```

Trying to express StateMachine as a generic trait leads to infinite type recursion!
Because generics are inputs, all of the types need to be provided by the *consumer*
of the interface. Which, in this case, is the interface itself. That said, there
*is* a way to resolve this without associated types: virtualization!

```rust
trait StateMachine {
    // Box is magic! self can be type Box<Self>.
    // This doesn't work with e.g. Rc<Self>, because *magic*.
    fn step(self: Box<Self>) -> Option<Box<StateMachine>>;
}
```

This expresses much the same intent as the associated type code. We consume
ourselves, and we yield *something* that implements the interface. However,
in order to get this working we have to mandate that all StateMachines must
be boxed up, and after the first call to `step`, the type of the resultant
StateMachine will be completely unknown. With associated types, nothing needs
to be boxed, and concrete code always knows the type of a StateMachine.

Oh, one last thing: traits objects don't work with associated types for the
exact same reason they don't work with by-value Self. No way to know the type
statically, so no way to work with it. If you specify all the associated types,
it does work though! That is, `Box<Iterator>` doesn't work, but
`Box<Iterator<Item=u32>>` does.








# Where Clauses

Hey, remember this example?

```rust,ignore
impl<T> Generic<T> {
    // Interesting problem: we've inverted the order on `equal` here
    // (`x == y` is being evaluated as `y == x`). How can we express
    // `T: Equal<U>` to fix this? Note that we can't do this at the
    // time where we declare `T`, because `U` doesn't exist yet!
    // More on this later!
    fn my_equal<U: Equal<T>>(&self, other: &Generic<U>) -> bool {
       other.data.equal(&self.data)
    }
}
```

And now that we've seen associated items, what about this kind of code?

```rust
// Interesting problem: associated types were supposed to let us avoid
// declaring "output types", but we need to declare it if we want to
// bound the item, right?
fn min<I: Iterator<Item = T>, T: Ord>(mut iter: I) -> Option<I::Item> {
    if let Some(first) = iter.next() {
        let mut min = first;
        for x in iter {
            if x < min {
                min = x;
            }
        }
        Some(min)
    } else {
        None
    }
}
```

The solution to this problem and more is to use a *where clause*:

```rust,ignore
impl<T> Generic<T> {
    fn my_equal<U>(&self, other: &Generic<U>) -> bool
        where T: Equal<U>
    {
       self.data.equal(&other.data)
    }
}

fn min<I>(mut iter: I) -> Option<I::Item>
    where I: Iterator,
          I::Item: Ord,
{
    if let Some(first) = iter.next() {
        let mut min = first;
        for x in iter {
            if x < min {
                min = x;
            }
        }
        Some(min)
    } else {
        None
    }
}
```

Where clauses allow us to specify bounds on *arbitrary* types. That's it. It's
just a more flexible syntax than the inline one. You can put where clauses
at the top of trait declarations, trait implementations, function declarations,
enum declarations, and struct declarations. Pretty much anywhere you could've
started defining generic arguments.

In addition to letting you go completely nuts with with weird requirements
(`impl Send for MyReference<T> where &T: Send` anybody?), they also have a
magical interaction with trait objects. Remember when I said that any trait
that makes reference to Self by-value can't be turned into a trait object?
Well, you can sort-of fix that with where clauses.

```rust
trait Print {
    fn print(&self);

    // `where Self: Sized` means this function
    // isn't available for trait-objects. So it's
    // safe to use Print as a trait object!
    fn copy(&self) -> Self where Self: Sized;
}


impl Print for u32 {
    fn print(&self) { println!("{}", self); }
    fn copy(&self) -> Self { *self }
}

fn main() {
    let x: Box<Print> = Box::new(0u32);
    x.print();
}
```





# Higher Rank Trait Bounds

Alright, so from here on out is where we really go off the rails. This is
the really obscure stuff that only the depraved type-system aficionados
take pleasure in.

We would like to write higher order functions, which is a really fancy term
for "functions that take functions". The classic example of a higher-order
function is `map`:

```rust
let x: Option<u32> = Some(0);
let y: Option<bool> = x.map(|v| v > 5);
```

Several thousand words ago, you may have seen an off-hand comment that Rust
does this with traits. Granted, they're magic traits, but they're traits
nonetheless! We have `Fn`, `FnMut`, and `FnOnce`. This distinction isn't really important,
for our purposes, so ~*handwave*~ it's about ownership and we're just always going
to use the right one without any explanation.

`Fn` itself isn't a trait though. It's actually a big family of traits.
`Fn(A, B) -> C`, on the other hand, is a proper trait. It's just like generics.
Actually it's literally generics. `Fn(A, B) -> C` is actually sugar for a generic
trait, which you can't actually use in stable Rust (as of 1.7). Under the wraps,
it desugars to something like `Fn<(A, B), Output=C>`. Inputs are all input types,
and outputs are output types. Hey nice, terminology actually lining up!

So for instance the closure in the example above implements `FnOnce(u32) -> bool`.
Everything sounding good so far. What about this?

```rust
fn get_first(input: &(u32, i32)) -> &u32 { &input.0 }

fn main() {
    let a = (0, 1);
    let b = (2, 3);

    let x = Some(&a);
    let y = Some(&b);

    println!("{}", x.map(get_first).unwrap());
    println!("{}", y.map(get_first).unwrap());
}
```

What, exactly, does `get_first` implement? `Fn(&(u32, i32)) -> &u32`, right?
Here's the thing: *that's not a thing*. Let's make our own trait to test:

```rust,ignore
trait MyFn<Input> {
    type Output;
}

// Dummy type; don't care about
// actually implementing a function here.
struct Thunk;

impl MyFn<&(u32, i32)> for Thunk {
    type Output = &u32;
}
```

```text
<anon>:9:11: 9:22 error: missing lifetime specifier [E0106]
<anon>:9 impl MyFn<&(u32, i32)> for Thunk {
                   ^~~~~~~~~~~
<anon>:9:11: 9:22 help: see the detailed explanation for E0106
<anon>:10:19: 10:23 error: missing lifetime specifier [E0106]
<anon>:10     type Output = &u32;
                            ^~~~
<anon>:10:19: 10:23 help: see the detailed explanation for E0106
error: aborting due to 2 previous errors
```

References without a lifetime are a charade. Anywhere a reference
is used in a type, a lifetime has to be provided! Rust just has
some really nice rules that let you skip it 99% of the time, because
there's an obvious default.

In this case, `get_first` is actually sugar for this:

```
fn get_first<'a>(input: &'a (u32, i32)) -> &'a u32 { &input.0 }
```

Anywhere you see references in a function signature, they're actually
generic. This implies a generic trait implementation; let's try it.

```rust
trait MyFn<Input> {
    type Output;
}

struct Thunk;

impl<'a> MyFn<&'a (u32, i32)> for Thunk {
    type Output = &'a u32;
}
```

Which compiles perfectly fine. But here's the thing: `Fn(&(u32, i32)) -> &u32`
is *totally* a thing, and I lied to you. In order to see how and why, let's
consider writing `filter` for an `Iterator`:

```rust
/// A filter over an iterator
struct Filter<I, F> {
    iter: I,
    pred: F,
}

/// Constructs a filter
fn filter<I, F>(iter: I, pred: F) -> Filter<I, F> {
    Filter { iter: iter, pred: pred }
}

impl<I, F> Iterator for Filter<I, F>
    where I: Iterator,
          F: Fn(&I::Item) -> bool,  // Magic! What's the lifetime?
{
    type Item = I::Item;

    fn next(&mut self) -> Option<I::Item> {
        while let Some(val) = self.iter.next() {
            if (self.pred)(&val) {
                return Some(val);
            }
        }
        None
    }
}

fn main() {
    let x = vec![1, 2, 3, 4, 5];
    for v in filter(x.into_iter(), |v: &i32| *v % 2 == 0) {
        println!("{}", v); // 2, 4
    }
}
```

Straight-up wizard magic. Here's the deal: our `pred` function needs to be able
to work with the lifetime of `&val`. Unfortunately, *it's literally impossible
to name that lifetime* -- even if we put a `where` clause on the `next`
function itself (which would be illegal for the Iterator trait regardless).
That lifetime is just some temporary in the middle of a function. So we need
`pred` to work with "some" lifetime that we can't name, what are we to do?
Our solution to this problem is simple brute force; demand that `pred` works
with *every* lifetime!

It turns out that `F: Fn(&I::Item) -> bool` is sugar for

```rust,ignore
for<'a> F: Fn(&I::Item) -> bool
```

Where `for<'a>` is intended to read as literally "for all 'a". We call this a
*higher rank trait bound* (HRTB). Unless you're into some deep type-level nonsense,
you will literally only ever see HRTBs used with the function traits, and
function traits have this nice sugar so you usually don't have to use HRTBs at
all. Note that HTRBs literally only work for lifetimes right now.







# Higher Kinded Types

We previously noted that generics are essentially expressing higher-kinded types.
That is, one can think of `Vec` as a type constructor of the form `(T) -> Vec<T>`.
We can talk about this type constructor to some extent when writing generic code.
That is, we can say something like `impl<T> Trait for Vec<T>` or
`fn make_vec<T>() -> Vec<T>`. But we have a limitation here: to talk about a type
constructor, we need to concretely name the type constructor we're interested in.
That is, we can't be generic over type constructors themselves.

For instance, say we wanted to write a data structure that uses reference-counted
pointers internally. Rust's standard library provides two choices: `Rc`, and `Arc`.
`Rc` is more efficient, but `Arc` is thread-safe. For the purposes of our implementation,
these two types are completely interchangeable. To the consumers of out implementation,
which type is used has important semantic consequences.

*Ideally*, our data structure would be generic over Rc and Arc. That is, we'd
like to write something like:

```rust,ignore
// NOTE: This code is nonsense and doesn't work!

/// A simple reference-counted linked list.
/// RefCount can either be Rc or Arc; You Decide!
struct Node<RefCount: RcLike, T> {
    elem: T,
    next: Option<RefCount<Node<RefCount, T>>>,
}
```

But alas, we cannot do this! Our users can't pass `Rc` or `Arc` unadorned to
us. These types must be completed as `Rc<SomeType>`. One solution is to
specifying a trait for the entirety of `Rc<Node<T>>`, but this is considerably
less composable than just specifying `Rc` or `Arc` themselves.

Another instance where this would be useful would be talking about generic
return types that borrow. For instance, today we can express

```rust,ignore
/// An iterator that doesn't allow `next` to be called
/// again until the last yielded item is disposed of.
trait RefIterator {
    type Item;
    fn next(&mut self) -> &mut T
}
```

which as we saw in the previous section, is sugar for

```rust
trait RefIterator {
    type Item;
    fn next<'a>(&'a mut self) -> &'a mut Self::Item;
}
```

One annoying aspect of this definition is that we're hardcoding the fact
that the reference is the outermost object. This implies that Self::Item
has to be stored somewhere. What we'd really like to express is the
following:

```rust,ignore
trait RefIterator {
    type Item;
    fn next<'a>(&'a mut self) -> Self::Item<'a>;
}
```

This is strictly more general, because one can always choose `Self::Item = &mut T`.
But this means that `Item` is now actually a type-constructor, and we're not allowed
to talk about those generically!

Ok so don't tell anyone I told you this, but Rust actually does let you talk
about type-constructors. Sort of. Terribly.

The key insight is that traits have input types and output types, so they're
basically type-level functions. In particular:

```ignore,ignore
trait TypeToType<Input> {
    type Output;
}
```

is exactly the shape of a type constructor. With this, we can actually
describe RefIter!

```rust
use std::marker::PhantomData;
use std::mem;
use std::cmp;

// A type we'd like to yield from a RefIter
struct MyType<'a> {
    slice: &'a mut [u8],
    index: usize,
}

// Kind: Lifetime -> Type
trait LifetimeToType<'a> {
    type Output;
}

// Stub types representing the type constructors
// that we want to work with.

/// &'* T
struct Ref_<T>(PhantomData<T>);
/// &'* mut T
struct RefMut_<T>(PhantomData<T>);
/// MyType<*>
struct MyType_;

// Describe the mapping each type constructor performs
impl<'a, T: 'a> LifetimeToType<'a> for Ref_<T> {
    type Output = &'a T;
}
impl<'a, T: 'a> LifetimeToType<'a> for RefMut_<T> {
    type Output = &'a mut T;
}
impl<'a> LifetimeToType<'a> for MyType_ {
    type Output = MyType<'a>;
}


// The actual trait we want to implement!
// `Self::TypeCtor as LifetimeToType<'a>>::Output`
// is the result of applying 'a to the TypeCtor.
//
// Note: <X as Trait>::AssociatedItem is "the inverse turbofish",
// for referring to associated items unambiguously.
//
// Note: I don't think we can use HRTB here,
// because of the `T: 'a` requirement.
// `for<'a> Self::TypeCtor: LifetimeToType<'a>` would basically
// mandate that `&'a T` is well-formed for all choices of `'a`,
// but this is only true if `T: 'static`!
// Instead use a "last minute" where clause on `next`.
trait RefIterator {
    type TypeCtor;
    fn next<'a>(&'a mut self)
        -> Option<<Self::TypeCtor as LifetimeToType<'a>>::Output>
        where Self::TypeCtor: LifetimeToType<'a>;

}

// Iterators!
struct Iter<'a, T: 'a> {
    slice: &'a [T],
}

struct IterMut<'a, T: 'a> {
    slice: &'a mut [T],
}

struct MyIter<'a> {
    slice: &'a mut [u8],
}


// FIXME: https://github.com/rust-lang/rust/issues/31580
// rustc is failing to resolve some types that it should.
// Passing them through these functions (which is a no-op)
// forces it to "get it".
fn _hack_project_ref<'a, T>(v: &'a T) -> <Ref_<T> as LifetimeToType<'a>>::Output { v }
fn _hack_project_ref_mut<'a, T>(v: &'a mut T) -> <RefMut_<T> as LifetimeToType<'a>>::Output { v }
fn _hack_project_my_type<'a>(v: MyType<'a>) -> <MyType_ as LifetimeToType<'a>>::Output { v }

// Actual implementations (nothing super notable)
impl<'x, T> RefIterator for Iter<'x, T> {
    type TypeCtor = Ref_<T>;
    fn next<'a>(&'a mut self)
        -> Option<<Self::TypeCtor as LifetimeToType<'a>>::Output>
        where Self::TypeCtor: LifetimeToType<'a>
    {
        if self.slice.is_empty() {
            None
        } else {
            let (l, r) = self.slice.split_at(1);
            self.slice = r;
            Some(_hack_project_ref(&l[0]))
        }
    }
}

impl<'x, T> RefIterator for IterMut<'x, T> {
    type TypeCtor = RefMut_<T>;
    fn next<'a>(&'a mut self)
        -> Option<<Self::TypeCtor as LifetimeToType<'a>>::Output>
        where Self::TypeCtor: LifetimeToType<'a>
    {
        if self.slice.is_empty() {
            None
        } else {
            let (l, r) = mem::replace(&mut self.slice, &mut []).split_at_mut(1);
            self.slice = r;
            Some(_hack_project_ref_mut(&mut l[0]))
        }
    }
}


impl<'x> RefIterator for MyIter<'x> {
    type TypeCtor = MyType_;
    fn next<'a>(&'a mut self)
        -> Option<<Self::TypeCtor as LifetimeToType<'a>>::Output>
        where Self::TypeCtor: LifetimeToType<'a>
    {
        if self.slice.is_empty() {
            None
        } else {
            let split = cmp::min(self.slice.len(), 5);
            let (l, r) = mem::replace(&mut self.slice, &mut []).split_at_mut(split);
            self.slice = r;
            let my_type = MyType { slice: l, index: split / 2 };
            Some(_hack_project_my_type(my_type))
        }
    }
}

// Usage!

fn main() {
    let mut data: [u8; 12] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
    {
        let mut iter = Iter { slice: &data };
        while let Some(v) = iter.next() {
            println!("{:?}", v);
        }
    }
    {
        let mut iter = IterMut { slice: &mut data };
        while let Some(v) = iter.next() {
            println!("{:?}", v);
        }
    }
    {
        let mut iter = MyIter { slice: &mut data };
        while let Some(v) = iter.next() {
            println!("{:?} {}", v.slice, v.index);
        }
    }
}
```

I'm not sure I can give too much insight into how this works. It's just a
natural consequence of all the other systems in action. Can we also solve
the `Rc`/`Arc` problem with this trick?

Sort of!

We can do the following:

```rust
use std::rc::Rc;
use std::sync::Arc;
use std::ops::Deref;

// Kind: Type -> Type
trait RcLike<T> {
    type Output;
    fn new(data: T) -> Self::Output;
}

// Stubs
struct Rc_;
struct Arc_;

impl<T> RcLike<T> for Rc_ {
    type Output = Rc<T>;
    fn new(data: T) -> Self::Output {
        Rc::new(data)
    }
}

impl<T> RcLike<T> for Arc_ {
    type Output = Arc<T>;
    fn new(data: T) -> Self::Output {
        Arc::new(data)
    }
}

struct Node<Ref, T>
    // This `where` clause is the problem! (more on that later)
    where Ref: RcLike<Node<Ref, T>>,
{
    elem: T,
    // basically: Option<Rc<Node<Rc_, T>>
    next: Option<<Ref as RcLike<Node<Ref, T>>>::Output>
}

struct List<Ref, T>
    where Ref: RcLike<Node<Ref, T>>,
{
    head: Option<<Ref as RcLike<Node<Ref, T>>>::Output>
}

impl<Ref, T, RefNode> List<Ref, T>
    where Ref: RcLike<Node<Ref, T>, Output=RefNode>,
          RefNode: Deref<Target=Node<Ref, T>>,
          RefNode: Clone,
{
    fn new() -> Self {
        List {
            head: None
        }
    }

    fn push(&self, elem: T) -> Self {
        List {
            head: Some(Ref::new(Node {
                elem: elem,
                next: self.head.clone(),
            }))
        }
    }

    fn tail(&self) -> Self {
        List {
            head: self.head.as_ref().and_then(|head| head.next.clone())
        }
    }
}




fn main() {
    // Usage (pretend we bothered to impl proper iterators/accessors)

    let list: List<Rc_, u32> = List::new().push(0).push(1).push(2).tail();
    println!("{}", list.head.unwrap().elem); // 1

    let list: List<Arc_, u32> = List::new().push(10).push(11).push(12).tail();
    println!("{}", list.head.unwrap().elem); // 11
}
```

This is *almost* perfect, there's just one problem: `where Ref: RcLike<Node<Ref, T>>`.
This is a breach of our abstraction boundary. We don't want users of our data structure
to know or care about Nodes, but we're forced to talk about them here. What we'd *really*
like is to be able to say is that Ref is RcLike for *everything*. In other words,
we'd like to write `where for<T> Ref: RcLike<T>`. This would allow us to hide
how we actually intend to use `Ref`.

Unfortunately, higher rank trait bounds don't work on non-lifetimes today.
They may work one day (wild speculation!), but today is not that day. If HRTBs
worked for types, we would actually be able to fully express HKTs!

Still, I hope you can see that talking about type constructors, even just in
the limited way we can, is a huge friggin' pain in Rust. Ideally, Rust would
support "native" HKT with its own syntax to make this more ergonomic.





# Generativity

Have you ever though about the fact that two instances of a type are completely
interchangeable? If we have two Widgets we're allowed to swap them, and no one cares.
Most of the time, this is completely desirable. But what if it weren't? What if
we wanted two instances of the same type to *stop* being interchangeable?

Consider arrays. Normally, when we iterate an array we do it to get the elements.
However this requires us to provide various iterators for all the different modes
of access: `Iter`, `IterMut`, and `IntoIter`. Wouldn't it be more composable if
the iterator told us *where* to look, but let us decide how to perform the access?

Well, you can do that by having an array provide an iterator over its indices
themselves. `0, 1, 2, ...,  len - 1`. Then we can just index into the array
however we please! Unfortunately, doing this would reduce the reliability of
iterators. Normal iterators have some nice properties: they're guaranteed to
never fail, and they're guaranteed to access each element at most once
(making `IterMut` sound).

With plain integer indices, iteration can become unreliable again. Indices can
be changed (forged), they can be held onto until after an array's length
changes (invalidated), and they can be used with a different array altogether
(mismatched)! Most of these problems are fairly easy to fix. To prevent forgeries,
we can simply wrap the integers up into a new type that hides the real values from
users. To prevent invalidation, we can tie the indices to the array by a lifetime.

But how do we prevent mismatches? If I have two arrays, the types of their indices
will be interchangeable, right? In order to do this, we need a way to solve that.
The solution to this problem is called *generativity*. Generativity is basically
the idea that different instances of the same type can have *different* associated
types. That is, which instance of a type an associated value is derived from really
matters.

I'm really, really tired. We're so close to done, so I'm just going to
copy-paste the demonstration of this that I wrote several months ago.
Explanation in the comments.


```rust
// This program demonstrates sound unchecked indexing
// by having slices generate valid indices, and "signing"
// them with an invariant lifetime. These indices cannot be used on another
// slice, nor can they be stored until the array is no longer valid
// (consider adapting this to Vec, and then trying to use indices after a push).
//
// This represents a design "one step removed" from iterators, providing greater
// control to the consumer of the API. Instead of getting references to elements
// we get indices, from which we can get references or hypothetically perform
// any other "index-related" operation (slicing?). Normally, these operations
// would need to be checked at runtime to avoid indexing out of bounds, but
// because the array knows it personally minted the indices, it can trust them.
// This hypothetically enables greater composition. Using this technique
// one could also do "only once" checked indexing (let idx = arr.validate(idx)).
//
// The major drawback of this design is that it requires a closure to
// create an environment that the signatures are bound to, complicating
// any logic that flows between the two (e.g. moving values in/out and try!).
// In principle, the compiler could be "taught" this trick to eliminate the
// need for the closure, as far as I know. Although how one would communicate
// that they're trying to do this to the compiler is another question.
// It also relies on wrapping the structure of interest to provide a constrained
// API (again, consider applying this to Vec -- need to prevent `push` and `pop`
// being called). This is the same principle behind Entry and Iterator.
//
// It also produces terrible compile errors (random lifetime failures),
// because we're hacking novel semantics on top of the borrowchecker which
// has no idea what's going on.
//
// This technique was first pioneered by gereeter to enable safely constructing
// search paths in BTreeMap. See Haskell's ST Monad for a related design.
//
// The example isn't maximally generic or fleshed out because I got bored trying
// to express the bounds necessary to handle &[T] and &mut [T] appropriately.

fn main() {
    use indexing::indices;

    let arr1: &[u32] = &[1, 2, 3, 4, 5];
    let arr2: &[u32] = &[10, 20, 30];

    // concurrent iteration (hardest thing to do with iterators)
    indices(arr1, |arr1, it1| {
        indices(arr2, move |arr2, it2| {
            for (i, j) in it1.zip(it2) {
                println!("{} {}", arr1.get(i), arr2.get(j));

                // should be invalid to idx wrong source
                // println!("{} ", arr2.get(i));
                // println!("{} ", arr1.get(j));
            }
        });
    });

    // can hold onto the indices for later, as long they stay in the closure
    let _a = indices(arr1, |arr, mut it| {
        let a = it.next().unwrap();
        let b = it.next_back().unwrap();
        println!("{} {}", arr.get(a), arr.get(b));
        // a    // should be invalid to return an index
    });

    // can get references out, just not indices
    let (x, y) = indices(arr1, |arr, mut it| {
        let a = it.next().unwrap();
        let b = it.next_back().unwrap();
        (arr.get(a), arr.get(b))
    });
    println!("{} {}", x, y);

    // Excercise to the reader: sound multi-index mutable indexing!?
    // (hint: it would be unsound with the current design)
}

mod indexing {
    use std::marker::PhantomData;
    use std::ops::Deref;
    use std::iter::DoubleEndedIterator;

    // Cell<T> is invariant in T; so Cell<&'id _> makes `id` invariant.
    // This means that the inference engine is not allowed to shrink or
    // grow 'id to solve the borrow system.
    type Id<'id> = PhantomData<::std::cell::Cell<&'id mut ()>>;

    pub struct Indexer<'id, Array> {
        _id: Id<'id>,
        arr: Array,
    }

    pub struct Indices<'id> {
        _id: Id<'id>,
        min: usize,
        max: usize,
    }

    #[derive(Copy, Clone)]
    pub struct Index<'id> {
        _id: Id<'id>,
        idx: usize,
    }

    impl<'id, 'a> Indexer<'id, &'a [u32]> {
        pub fn get(&self, idx: Index<'id>) -> &'a u32 {
            unsafe {
                self.arr.get_unchecked(idx.idx)
            }
        }
    }

    impl<'id> Iterator for Indices<'id> {
        type Item = Index<'id>;
        fn next(&mut self) -> Option<Self::Item> {
            if self.min != self.max {
                self.min += 1;
                Some(Index { _id: PhantomData, idx: self.min - 1 })
            } else {
                None
            }
        }
    }

    impl<'id> DoubleEndedIterator for Indices<'id> {
        fn next_back(&mut self) -> Option<Self::Item> {
            if self.min != self.max {
                self.max -= 1;
                Some(Index { _id: PhantomData, idx: self.max })
            } else {
                None
            }
        }
    }

    pub fn indices<Array, F, Out>(arr: Array, f: F) -> Out
        where F: for<'id> FnOnce(Indexer<'id, Array>, Indices<'id>) -> Out,
              Array: Deref<Target = [u32]>,
    {
        // This is where the magic happens. We bind the indexer and indices
        // to the same invariant lifetime (a constraint established by F's
        // definition). As such, each call to `indices` produces a unique
        // signature that only these two values can share.
        //
        // Within this function, the borrow solver can choose literally any lifetime,
        // including `'static`, but we don't care what the borrow solver does in
        // *this* function. We only need to trick the solver in the caller's
        // scope. Since borrowck doesn't do interprocedural analysis, it
        // sees every call to this function produces values with some opaque
        // fresh lifetime and can't unify any of them.
        //
        // In principle a "super borrowchecker" that does interprocedural
        // analysis would break this design, but we could go out of our way
        // to somehow bind the lifetime to the inside of this function, making
        // it sound again. Borrowck will never do such analysis, so we don't
        // care.
        let len = arr.len();
        let indexer = Indexer { _id: PhantomData, arr: arr };
        let indices = Indices { _id: PhantomData, min: 0, max: len };
        f(indexer, indices)
    }
}
```

Haha, totally simple right?! No, it's friggin' nightmare. And it's all really,
*really* unsafe and brittle. This is like the magnum-opus of the claim that
Unsafe Rust is something that contaminates the whole module. A single line
is marked as `unsafe`, but the safety of the whole system depends on getting
all the types right, and thinking about all the different corner cases.

Relying on generativity working right is really dangerous, which is why I'd
really like to see Rust explicitly support it, rather than simply having it
as an emergent behaviour of HRTBs.



# Exeunt

That's it. That's everything I have the energy to write about. This got way too
long.

I'm sorry.

I'm sorry.




[vec-macro]: https://github.com/rust-lang/rust/blob/7bcced73b77ba56834c3b5da0c4f82f80aa74db8/src/libcollections/macros.rs#L11-L52

[copy-pasta-macros]: https://github.com/rust-lang/rust/blob/7bcced73b77ba56834c3b5da0c4f82f80aa74db8/src/libcore/num/mod.rs#L2428-L2488

[servo-monomorph]: https://gist.github.com/brson/18a1517e9b747a09c492

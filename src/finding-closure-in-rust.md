---
layout: default
title: "Finding Closure in Rust"
description: >
    Closures in Rust are powerful and flexible, building on traits,
    generics and ownership.

comments:
    users: "https://users.rust-lang.org/t/finding-closure-in-rust/1285"
    r_rust: "http://www.reddit.com/r/rust/comments/359tj5/finding_closure_in_rust/"
---

Have you ever used an [iterator adapter][iteratorext] in [Rust][Rust]?
Called a method on [`Option`][option]? [Spawned][spawn] a thread?
You've almost certainly used a [closure]. The design in Rust may seem
a little complicated, but it slides right into Rust's normal ownership
model so let's reinvent it from scratch.

[Rust]: http://rust-lang.org
[iteratorext]: http://doc.rust-lang.org/std/iter/trait.Iterator.html
[option]: http://doc.rust-lang.org/std/option/enum.Option.html
[spawn]: http://doc.rust-lang.org/std/thread/fn.spawn.html
[closure]: https://en.wikipedia.org/wiki/Closure_%28computer_programming%29

The new design was introduced in [RFC 114][rfc], moving Rust to a
model for closures similar to C++11's. The design builds on Rust's
standard trait system to allow for allocation-less
statically-dispatched closures, but also giving the choice to opt-in
to type-erasure and dynamic dispatch and the benefits that brings. It
incorporates elements of inference that "just work" by ensuring that
ownership works out.

[rfc]: https://github.com/rust-lang/rfcs/blob/master/text/0114-closures.md

> Steve Klabnik has written
> [some docs on Rust's closures][book-closures] for the official
> documentation. I've explicitly avoided reading it so far because
> I've always wanted to write this, and I think it's better to give a
> totally independent explanation while I have the chance. If
> something is confusing here, maybe they help clarify.

[book-closures]: http://doc.rust-lang.org/book/closures.html

## What's a closure?

In a sentence: a closure is a function that can directly use variables
from the scope in which it is defined. This is often described as the
closure *closing over* or *capturing* variables (the
*captures*). Collectively, the variables are called the *environment*.

Syntactically, a closure in Rust is an anonymous function[^anon] value
defined a little like Ruby, with pipes: `|arguments...| body`. For
example, `|a, b| a + b` defines a closure that takes two arguments and
returns their sum. It's just like a normal function declaration, with
more inference:

{% highlight rust linenos %}
// function:
fn foo(a: i32, b: i32) -> i32 { a + b }
// closure:
      |a,      b|               a + b
{% endhighlight %}

Just like a normal function, they can be called with parentheses:
`closure(arguments...)`.

[^anon]: The Rust `|...| ...` syntax is more than just a closure: it's
         an [anonymous function][anon]. In general, it's possible to have things
         that are closures but aren't anonymous (e.g. in Python,
         functions declared with `def foo():` are closures too, they
         can refer to variables in any scopes in which the `def foo`
         is contained). The anonymity refers to the fact that the
         closure expression is a value, it's possible to just use it
         directly and there's no separate `fn foo() { ... }` with the
         function value referred to via `foo`.

[anon]: http://en.wikipedia.org/wiki/Anonymous_function


To illustrate the capturing, this code snippet calls
[`map`][Option::map] on an `Option<i32>`, which will call a closure on
the `i32` (if it exists) and create a new `Option` containing the
return value of the call.

[Option::map]: http://doc.rust-lang.org/std/option/enum.Option.html#method.map

{% highlight rust linenos %}
fn main() {
    let option = Some(2);

    let x = 3;
    // explicit types:
    let new: Option<i32> = option.map(|val: i32| -> i32 { val + x });
    println!("{:?}", new); // Some(5)

    let y = 10;
    // inferred:
    let new2 = option.map(|val| val * y);
    println!("{:?}", new2); // Some(20)
}
{% endhighlight %}

The closures are capturing the `x` and `y` variables, allowing them to
be used while mapping. (To be more convincing, imagine they were only
known at runtime, so that one couldn't just write `val + 3` inside the
closure.)

## Back to basics

Now that we have the semantics in mind, take a step back and riddle me
this: how would one implement that sort of generic `map` if Rust
didn't have closures?

The functionality of `Option::map` we're trying to duplicate is (equivalently):

{% highlight rust linenos %}
fn map<X, Y>(option: Option<X>, transformer: ...) -> Option<Y> {
    match option {
        Some(x) => Some(transformer(x)), // (closure syntax for now)
        None => None,
    }
}
{% endhighlight %}

We need to fill in the `...` with something that transforms an `X` into
a `Y`. The biggest constraint for perfectly replacing `Option::map` is
that it needs to be generic in some way, so that it works with
absolutely any way we wish to do the transformation. In Rust, that
calls for a generic bounded by a trait.

{% highlight rust linenos %}
fn map<X, Y, T>(option: Option<X>, transform: T) -> Option<Y>
    where T: /* the trait */
{
{% endhighlight %}


This trait needs to have a method that converts some specific type
into another. Hence there'll have to be form of type parameters to
allow the exact types to be specified in generic bounds like
`map`. There's two choices: generics in the trait definition ("input
type parameters") and associated types ("output type parameters"). The
quoted names hint at the choices we should take: the type that gets
input into the transformation should be a generic in the trait, and
the type that is output by the transformation should be an associated
type.[^assoc-vs-not]

[^assoc-vs-not]: This choice is saying that transformers can be
                 overloaded by the starting type, but the ending type
                 is entirely determined by the pair of the transform
                 and the starting type. Using an associated type for
                 the return value is more restrictive (no overloading
                 on return type only) but it gives the compiler a much
                 easier time when inferring types. Using an associated
                 type for the input value too would be too
                 restrictive: it is very useful for the output type to
                 depend on the input type, e.g. a transformation `&'a
                 [i32]` to `&'a i32` (by e.g. indexing) has the two
                 types connected via the generic lifetime `'a`.

So, our trait looks something like:

{% highlight rust linenos %}
trait Transform<Input> {
    type Output;

    fn transform(/* self?? */, input: Input) -> Self::Output;
}
{% endhighlight %}

The last question is what sort of `self` (if any) the method should
take?

The transformation should be able to incorporate arbitrary information
beyond what is contained in `Input`. Without any `self` argument, the
method would look like `fn transform(input: Input) -> Self::Output`
and the operation could only depend on `Input` and global
variables (ick). So we do need one.

The most obvious options are by-reference `&self`,
by-mutable-reference `&mut self`, or by-value `self`. We want to allow
the users of `map` to have as much power as possible while still
enabling `map` to type-check. At a high-level `self` gives
*implementers* (i.e. the types users define to implement the trait)
the most flexibility, with `&mut self` next and `&self` the least
flexible. Conversely, `&self` gives *consumers* of the trait
(i.e. functions with generics bounded by the trait) the most
flexibility, and `self` the least.

|             | **Implementer**                | **Consumer**                                 |
|------------:|----------------------------|-------------------------------------------------|
|      `self` | Can move out and mutate    | Can only call method once                       |
| `&mut self` | Can't move out, can mutate | Can call many times, only with unique access |
|     `&self` | Can't move out or mutate   | Can call many times, with no restrictions       |

<div class="join"></div>

("Move out" and "mutate" in the implementer column are referring to data stored inside `self`.)

Choosing between them is a balance, we usually want to chose the
highest row of the table that still allows the consumers to do what
they need to do, as that allows the external implementers to do as
much as possible.

Starting at the top of that table: we can try `self`. This gives `fn
transform(self, input: Input) -> Self::Output`. The by-value `self`
will consume ownership, and hence `transform` can only be called
once. Fortunately, `map` only needs to do the transformation once, so
by-value `self` works perfectly.

In summary, our `map` and its trait look like:

{% highlight rust linenos %}
trait Transform<Input> {
    type Output;

    fn transform(self, input: Input) -> Self::Output;
}

fn map<X, Y, T>(option: Option<X>, transform: T) -> Option<Y>
    where T: Transform<X, Output = Y>
{
    match option {
        Some(x) => Some(transform.transform(x)),
        None => None,
    }
}
{% endhighlight %}


The example from before can then be reimplemented rather verbosely, by
creating structs and implementing `Transform` to do the appropriate
conversion for that struct.

{% highlight rust linenos %}
// replacement for |val| val + x
struct Adder { x: i32 }

impl Transform<i32> for Adder {
    type Output = i32;

    // ignoring the `fn ... self`, this looks similar to |val| val + x
    fn transform(self, val: i32) -> i32 {
        val + self.x
    }
}

// replacement for |val| val * y
struct Multiplier { y: i32 }

impl Transform<i32> for Multiplier {
    type Output = i32;

    // looks similar to |val| val * y
    fn transform(self, val: i32) -> i32 {
        val * self.y
    }
}

fn main() {
    let option = Some(2);

    let x = 3;
    let new: Option<i32> = map(option, Adder { x: x });
    println!("{:?}", new); // Some(5)

    let y = 10;
    let new2 = map(option, Multiplier { y: y });
    println!("{:?}", new2); // Some(20)
}
{% endhighlight %}

We've manually implemented something that seems to have the same
semantics as Rust closures, using traits and some structs to store and
manipulate the captures. In fact, the struct has some uncanny
similarities to the "environment" of a closure: it stores a pile of
variables that need to be used in the body of `transform`.

## How do real closures work?

Just like that, plus a little more flexibility and syntactic
sugar. The real definition of `Option::map` is:

{% highlight rust linenos %}
impl<X> Option<X> {
    pub fn map<Y, F: FnOnce(X) -> Y>(self, f: F) -> Option<Y> {
        match self {
            Some(x) => Some(f(x)),
            None => None
        }
    }
}
{% endhighlight %}

`FnOnce(X) -> Y` is another name for our `Transform<X, Output = Y>`
bound, and, `f(x)` for `transform.transform(x)`.

There are three traits for closures, all of which provide the
`...(...)` call syntax (one could regard them as different kinds of
`operator()` in C++). They differ only by the `self` type of the call
method, and they cover all of the `self` options listed above.

- `&self` is [`Fn`](http://doc.rust-lang.org/std/ops/trait.Fn.html)
- `&mut self` is [`FnMut`](http://doc.rust-lang.org/std/ops/trait.FnMut.html)
- `self` is [`FnOnce`](http://doc.rust-lang.org/std/ops/trait.FnMut.html)

These traits are covering exactly the three core ways to handle data
in Rust, so having each of them meshes perfectly with Rust's
type-system.

When you write `|args...| code...` the compiler will implicitly define
a unique new struct type storing the captured variables, and then
implement one of those traits using the closure's body, rewriting any
mentions of captured variables to go via the closure's
environment. The struct type doesn't have a user visible name, it is
purely internal to the compiler. When the program hits the closure
definition at runtime, it fills in an instance of struct and passes
that instance into whatever it needs to (like we did with our `map`
above).

There's two questions left:

1. how are variables captured? (what type are the fields of the environment struct?)
2. which trait is used? (what type of `self` is used?)

The compiler answers both by using some local rules to choose the
version that will give the most flexibility. The local rules are
designed to be able to be checked only knowing the definition
the closure, and the types of any variables it captures.[^i-think]

[^i-think]: This statement isn't precisely true in practice,
            e.g. `rustc` will emit different errors if closures are
            misused in certain equivalent-but-non-identical
            ways. However, I believe these are just improved
            diagnostics, not a fundamental language thing... however,
            I'm not sure.

By "flexibility" I mean the compiler chooses the option that (it
thinks) will compile, but imposes the least on the programmer.

### Structs and captures

If you're familiar with closures in C++11, you may recall the `[=]`
and `[&]` capture lists: capture variables by-value[^copy] and
by-reference respectively. Rust has similar capability: variables can
be captured by-value---the variable is moved into the closure
environment---or by-reference---a reference to the variable is stored
in the closure environment.

[^copy]: "By-value" in C++, including `[=]`, is really "by-copy" (with
          some copy-elision rules to sometimes elide copies in certain
          cases), whereas in Rust it is always "by-move", more similar
          to rvalue references in C++.

By default, the compiler looks at the closure body to see how captured
variables are used, and uses that to infers how variables should be
captured:

- if a captured variable is only ever used through a shared reference,
  it is captured by `&` reference,
- if it used through a mutable reference (including assignment), it is
  captured by `&mut` reference,
- if it is moved, it is forced to be captured by-value. (NB. using a
  [`Copy`](http://doc.rust-lang.org/std/marker/trait.Copy.html) type
  by-value only needs a `&` reference, so this rule only applies to
  non-`Copy` ones.)

The algorithm seems a little non-trivial, but it matches exactly the
mental model of a practiced Rust programmer, using ownership/borrows
as precisely as it can. In fact, if a closure is "non-escaping", that
is, never leaves the stack frame in which it is created, I believe
this algorithm is perfect: code will compile without needing any
annotations about captures.

To summarise, the compiler will capture variables in the way that is
least restrictive in terms of continued use outside the closure (`&`
is preferred, then `&mut` and lastly by-value), and that still works
for all their uses within the closure. This analysis happens on a
per-variable basis, e.g.:

{% highlight rust linenos %}
struct T { ... }

fn by_value(_: T) {}
fn by_mut(_: &mut T) {}
fn by_ref(_: &T) {}

let x: T = ...;
let mut y: T = ...;
let mut z: T = ...;

let closure = || {
    by_ref(&x);
    by_ref(&y);
    by_ref(&z);

    // forces `y` and `z` to be at least captured by `&mut` reference
    by_mut(&mut y);
    by_mut(&mut z);

    // forces `z` to be captured by value
    by_value(z);
};
{% endhighlight %}

To focus on the flexibility: since `x` is only captured by shared
reference, it is legal for it be used while `closure` exists, and
since `y` is borrowed (by mutable reference) it can be used once
`closure` goes out of scope, but `z` cannot be used at all, even once
`closure` is gone, since it has been moved into the `closure` value.

The compiler would create code that looks a bit like:

{% highlight rust linenos %}
struct Environment<'x, 'y> {
    x: &'x T,
    y: &'y mut T,
    z: T
}

/* impl of FnOnce for Environment */

let closure = Environment {
    x: &x,
    y: &mut y,
    z: z
};
{% endhighlight %}

The struct desugaring allows the full power of Rust's type system is
brought to bear on ensuring it isn't possible to accidentally get a
dangling reference or use freed memory or trigger any other memory
safety violation by misusing a closure. If there is problematic code,
the compiler will point it out.

### `move` and escape

I stated above that the inference is perfect for non-escaping
closures... which implies that it is not perfect for "escaping" ones.

If a closure is escaping, that is, if it might leave the stack frame
where it is created, it must not contain any references to values
inside that stack frame, since those references would be dangling when
the closure is used outside that frame: very bad. Fortunately the
compiler will emit an error if there's a risk of that, but returning
closures can be useful and so should be possible; for example[^trait-object]:

[^trait-object]: Since closure types are unique and unnameable, the
                 only way to return one is via a trait object, at
                 least until Rust gets something like the "abstract
                 return types" of [RFC 105][rfc105], something much
                 desired for handling closures. This is a little like
                 an interface-checked version of C++11's
                 `decltype(auto)`, which, I believe, was also partly
                 motivated by closures with unnameable types.

[rfc105]: https://github.com/rust-lang/rfcs/pull/105

{% highlight rust linenos %}
/// Returns a closure that will add `x` to its argument.
fn make_adder(x: i32) -> Box<Fn(i32) -> i32> {
    Box::new(|y| x + y)
}

fn main() {
    let f = make_adder(3);

    println!("{}", f(1)); // 4
    println!("{}", f(10)); // 13
}
{% endhighlight %}

<div class="join"></div>

Looks good, except... it doesn't actually compile:

{% highlight text linenos %}
...:3:14: 3:23 error: closure may outlive the current function, but it borrows `x`, which is owned by the current function [E0373]
...:3     Box::new(|y| x + y)
                   ^~~~~~~~~
...:3:18: 3:19 note: `x` is borrowed here
...:3     Box::new(|y| x + y)
                       ^
{% endhighlight %}

The problem is clearer when everything is written as explicit structs:
`x` only needs to be captured by reference to be used with `+`, so the
compiler is inferring that the code can look like:

{% highlight rust linenos %}
struct Closure<'a> {
    x: &'a i32
}

/* impl of Fn for Closure */

fn make_adder(x: i32) -> Box<Fn(i32) -> i32> {
    Box::new(Closure { x: &x })
}
{% endhighlight %}

`x` goes out of scope at the end of `make_adder` so it is illegal to
return something that holds a reference to it.

So how do we fix it? Wouldn't it be nice if the compiler could tell
us...

Well, actually, I omitted the last two lines of the error message above:

{% highlight text linenos %}
...:3:14: 3:23 help: to force the closure to take ownership of `x` (and any other referenced variables), use the `move` keyword, as shown:
...:      Box::new(move |y| x + y)
{% endhighlight %}

A new keyword! The `move` keyword can be placed in front of a closure
declaration, and overrides the inference to capture all variables by
value. Going back to the previous section, if the code used `let
closure = move || { /* same code */ }` the environment struct would
look like:

{% highlight rust linenos %}
struct Environment {
    x: T,
    y: T,
    z: T
}
{% endhighlight %}

Capturing entirely by value is also strictly more general than
capturing by reference: the reference types are first-class in Rust,
so "capture by reference" is the same as "capture a reference by
value". Thus, unlike C++, there's little fundamental distinction
between capture by reference and by value, and the analysis Rust does
is not actually *necessary*: it just makes programmers' lives easier.

To demonstrate, the following code will have the same behaviour and
same environment as the first version, by capturing references using
`move`:

{% highlight rust linenos %}
let x: T = ...;
let mut y: T = ...;
let mut z: T = ...;

let x_ref: &T = &x;
let y_mut: &mut T = &mut y;

let closure = move || {
    by_ref(x_ref);
    by_ref(&*y_mut);
    by_ref(&z);

    by_mut(y_mut);
    by_mut(&mut z);

    by_value(z);
};
{% endhighlight %}

The set of variables that are captured is exactly those that are used
in the body of the closure, there's no fine-grained capture lists like
in C++11. The `[=]` capture list exists as the `move` keyword, but
that is all.

We can now solve the original problem of returning from `make_adder`:
by writing `move` we force the compiler to avoid any
implicit/additional references, ensuring that the closure isn't tied
to the stack frame of its birth. If we take the compiler's suggestion
and write `Box::new(move |y| x + y)`, the code inside the compiler
will look more like:

{% highlight rust linenos %}
struct Closure {
    x: i32
}

/* impl of Fn for Closure */

fn make_adder(x: i32) -> Box<Fn(i32) -> i32> {
    Box::new(Closure { x: x })
}
{% endhighlight %}

It is clear that the compiler doesn't infer when `move` is required
(or else we wouldn't need to write it), but the fact that the `help`
message exists suggests that the compiler does know enough to infer
when `move` is necessary or not... in some cases. Unfortunately, doing
so in general in a reliable way (a `help` message can be
heuristic/best-effort, but inference built into the language cannot
be), would require more than just an analysis of the internals of the
closure body: it would require more complicated machinery to look at
how/where the closure value is used.


### Traits

The actual "function" bit of closures are handled by the traits
mentioned above. The implicit struct types will also have implicit
implementations of some of those traits, exactly those traits that
will actually work for the type.

Let's start with an example: for the `make_adder` example, the `Fn`
trait is implemented for the implicit closure struct:

{% highlight rust linenos %}
// (this is just illustrative, see the footnote for the gory details)
impl Fn(i32) -> i32 for Closure {
    fn call(&self, y: i32) -> i32 {
    // |y|   x + y
        self.x + y
    }
}
{% endhighlight %}

[^invalid]: I wrote an invalid `Fn` implementation because the real
            version is ugly and much less clear, and doesn't work with
            stable compilers at the moment. But since you asked, here
            is what's required:

        #![feature(unboxed_closures, core)]

        impl Fn<(i32,)> for Closure {
            extern "rust-call" fn call(&self, (y,): (i32,)) -> i32 {
                self.x + y
            }
        }
        impl FnMut<(i32,)> for Closure {
            extern "rust-call" fn call_mut(&mut self, args: (i32,)) -> i32 {
                self.call(args)
            }
        }
        impl FnOnce<(i32,)> for Closure {
            type Output = i32;
            extern "rust-call" fn call_once(self, args: (i32,)) -> i32 {
                self.call(args)
            }
        }

    Just looking at that, one might be able to guess at a few of the
    reasons that manual implementations of the function traits aren't
    stabilised for general use. The only way to create types
    implementing those traits with the 1.0 compiler is with a closure
    expression.

In reality, there are also implicit implementations[^invalid] of
`FnMut` and `FnOnce` for `Closure`, but `Fn` is the "fundamental" one
for this closure.

There's three traits, and so seven non-empty sets of traits that *could*[^inherit] possibly be
implemented... but there's actually only three interesting
configurations:

[^inherit]: I'm ignoring the inheritance, which means that certain
            sets are actually statically illegal, i.e., without other
            constraints there are seven possibilities.

- `Fn`, `FnMut` and `FnOnce`,
- `FnMut` and `FnOnce`,
- only `FnOnce`.

Why? Well, the three closure traits are actually three nested sets:
every closure that implements `Fn` can also implement `FnMut` (if
`&self` works, `&mut self` also works; proof: `&*self`), and similarly
every closure implementing `FnMut` can also implement `FnOnce`. This
hierarchy is enforced at the type level,
e.g. [`FnMut`](http://doc.rust-lang.org/std/ops/trait.FnMut.html)
has declaration:

{% highlight rust linenos %}
pub trait FnMut<Args>: FnOnce<Args> {
    ...
}
{% endhighlight %}

<div class="join"></div>
In words: anything that implements `FnMut` *must* also implement
`FnOnce`.

There's no subtlety required when inferring what traits to implement
as the compiler can and will just implement *every* trait for which
the implementation is legal. This is in-keeping with the "offer
maximum flexibility" rule that was used for the inference of the
capture types, since more traits means more options. The subset nature
of the `Fn*` traits means that following this rule will always result
in one of the three sets listed above being implemented.

As an example, this code demonstrates a closure for which an
implementation of `Fn` is illegal but both `FnMut` and `FnOnce` are
fine.

{% highlight rust linenos %}
let mut v = vec![];

// nice form
let closure = || v.push(1);

// explicit form
struct Environment<'v> {
    v: &'v mut Vec<i32>
}

// let's try implementing `Fn`
impl<'v> Fn() for Environment<'v> {
    fn call(&self) {
        self.v.push(1) // error: cannot borrow data mutably
    }
}
let closure = Environment { v: &mut v };
{% endhighlight %}

It is illegal to mutate via a `& &mut ...`, and `&self` is creating
that outer shared reference. If it was `&mut self` or `self`, it would
be fine: the former is more flexible, so the compiler implements
`FnMut` for `closure` (and also `FnOnce`).

Similarly, if `closure` was to be `|| drop(v);`---that is, move out of
`v`---it would be illegal to implement either `Fn` or `FnMut`, since
the `&self` (respectively `&mut self`) means that the method would be
trying to steal ownership out of borrowed data: criminal.

## Flexibility

One of Rust's goals is to leave choice in the hands of the programmer,
allowing their code to be efficient, with abstractions compiling away
and just leaving fast machine code. The design of closures to use
unique struct types and traits/generics is key to this.

Since each closure has its own type, there's no compulsory need for
heap allocation when using closures: as demonstrated above, the
captures can just be placed directly into the struct value. This is a
property Rust shares with C++11, allowing closures to be used in
essentially any environment, including bare-metal environments.

The unique types does mean that one can't use different closures
together automatically, e.g. one can't create a vector of several
distinct closures. They may have different sizes and require different
invocations (different closures correspond to different internal code,
so a different function to call). Fortunately, the use of traits to
abstract over the closure types means one can opt-in to these features
and their benefits "on demand", via [trait objects][pito]: returning
the `Box<Fn(i32) -> i32>` above used a trait object.

{% highlight rust linenos %}
let mut closures: Vec<Box<Fn()>> = vec![];

let text = "second";

closures.push(Box::new(|| println!("first")));
closures.push(Box::new(|| println!("{}", text)));
closures.push(Box::new(|| println!("third")));

for f in &closures {
    f(); // first / second / third
}
{% endhighlight %}

[pito]: {% post_url 2015-01-10-peeking-inside-trait-objects %}

An additional benefit to the approach of unique types and generics
means that, by default, the compiler has full information about what
closure calls are doing at each call site, and so has the choice to
perform key optimisations like inlining. For example, the following
snippets compile to the same code,

{% highlight rust linenos %}
x.map(|z| z + 3)

match x {
    Some(z) => Some(z + 3),
    None => None
}
{% endhighlight %}

<div class="join"></div>

(When I tested it by placing them into separate functions in a single
binary, the compiler actually optimised the second function to a
direct call to the first.)

This is all due to how Rust implements generics via monomorphisation,
where generic functions are compiled for each way their type
parameters are chosen, explicitly substituting the generic type with a
concrete one. Unfortunately, this isn't always an optimisation, as it
can result in code bloat, where there are many similar copies of a
single function, which is again something that trait objects can
tackle: by using a trait object instead, one can use dynamically
dispatched closures to ensure there's only one copy of a function,
even if it is used with many different closures.

{% highlight rust linenos %}
fn generic_closure<F: Fn(i32)>(f: F) {
    f(0);
    f(1);
}

generic_closure(|x| println!("{}", x)); // A
generic_closure(|x| { // B
    let y = x + 2;
    println!("{}", y);
});


fn closure_object(f: &Fn(i32)) {
    f(0);
    f(1);
}

closure_object(&|x| println!("{}", x));
closure_object(&|x| {
    let y = x + 2;
    println!("{}", y);
});
{% endhighlight %}

The final binary will have two copies of `generic_closure`, one for
`A` and one for `B`, but only one copy of `closure_object`. In fact,
there are implementations of the `Fn*` traits for pointers, so one can
even use a trait object directly with `generic_closure`,
e.g. `generic_closure((&|x| { ... }) as &Fn(_))`: so users of
higher-order functions can choose which trade-off they want themselves.

All of this flexibility falls directly out of using traits[^stdfunction] for
closures, and the separate parts are independent and very
compositional.

[^stdfunction]: C++ has a similar choice, with `std::function` able to
                provide type erasure/dynamic dispatch for closure
                types, although it requires separate definition as a
                library type, and requires allocations. The Rust trait
                objects are a simple building block in the language,
                and don't require allocations (e.g. `&Fn()` is a trait
                object that can be created out of a pointer to the
                stack).

The power closures offer allow one to build high-level, "fluent" APIs
without losing performance compared to writing out the details by
hand. The prime example of this is
[iterators](http://doc.rust-lang.org/std/iter): one can write long
chains of calls to adapters like `map` and `filter` which get
optimised down to efficient C-like code. (For example, I wrote
[a post][knn] that demonstrates this, and the situation has only
improved since then: the closure design described here was implemented
months later.)

[knn]: {% post_url 2014-06-10-comparing-knn-in-rust %}

## In closing

Rust's C++11-inspired closures are powerful tools that allow for
high-level and efficient code to be build, marrying two properties
often in contention. The moving parts of Rust's closures are built
directly from the normal type system with traits, structs and
generics, which allows them to automatically gain features like heap
allocation and dynamic dispatch, but doesn't require them.

(Thanks to Steve Klabnik and Aaron Turon for providing feedback on a
draft, and many commenters on [/r/rust]({{ page.comments.r_rust }})
and on IRC for finding inaccuracies and improvements.)

{% include comments.html c=page.comments %}

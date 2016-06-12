---
layout: post
title: "Mixing matching, mutation, and moves in Rust"
author: Felix S. Klock II
description: "A tour of matching and enums in Rust."
---

One of the primary goals of the Rust project is to enable safe systems
programming. Systems programming usually implies imperative
programming, which in turns often implies side-effects, reasoning
about shared state, et cetera.

At the same time, to provide *safety*, Rust programs and data types
must be structured in a way that allows static checking to ensure
soundness. Rust has features and restrictions that operate in tandem
to ease writing programs that can pass these checks and thus ensure
safety. For example, Rust incorporates the notion of *ownership* deeply
into the language.

Rust's `match` expression is a construct that offers an interesting
combination of such features and restrictions. A `match` expression
takes an input value, classifies it, and then jumps to code written to
handle the identified class of data.

In this post we explore how Rust processes such data via `match`.
The crucial elements that `match` and its counterpart `enum` tie
together are:

* Structural pattern matching: case analysis with ergonomics vastly
  improved over a C or Java style `switch` statement.

* Exhaustive case analysis: ensures that no case is omitted
  when processing an input.

* `match` embraces both imperative and functional styles of
  programming: you can continue using `break` statements, assignments,
  et cetera,
  rather than being forced to adopt an expression-oriented mindset.

* `match` "borrows" or "moves", as needed: Rust encourages the developer to
  think carefully about ownership and borrowing. To ensure that
  one is not forced to yield ownership of a value
  prematurely, `match` is designed with support for merely *borrowing*
  substructure (as opposed to always *moving* such substructure).

We cover each of the items above in detail below, but first we
establish a foundation for the discussion: What does `match` look
like, and how does it work?

### The Basics of `match`

The `match` expression in Rust has this form:

```rust
match INPUT_EXPRESSION {
    PATTERNS_1 => RESULT_EXPRESSION_1,
    PATTERNS_2 => RESULT_EXPRESSION_2,
    ...
    PATTERNS_n => RESULT_EXPRESSION_n
}
```

where each of the `PATTERNS_i` contains at least one *pattern*. A
pattern describes a subset of the possible values to which
`INPUT_EXPRESSION` could evaluate.
The syntax `PATTERNS => RESULT_EXPRESSION` is called a "match arm",
or simply "arm".

Patterns can match simple values like integers or characters; they
can also match user-defined symbolic data, defined via `enum`.

The below code demonstrates generating the next guess (poorly) in a number
guessing game, given the answer from a previous guess.

```rust
enum Answer {
    Higher,
    Lower,
    Bingo,
}

fn suggest_guess(prior_guess: u32, answer: Answer) {
    match answer {
        Answer::Higher => println!("maybe try {} next", prior_guess + 10),
        Answer::Lower  => println!("maybe try {} next", prior_guess - 1),
        Answer::Bingo  => println!("we won with {}!", prior_guess),
    }
}

#[test]
fn demo_suggest_guess() {
    suggest_guess(10, Answer::Higher);
    suggest_guess(20, Answer::Lower);
    suggest_guess(19, Answer::Bingo);
}
```

(Incidentally, nearly all the code in this post is directly
executable; you can cut-and-paste the code snippets into a file
`demo.rs`, compile the file with `--test`, and run the resulting
binary to see the tests run.)

Patterns can also match [structured data][structured data] (e.g. tuples, slices, user-defined
data types) via corresponding patterns. In such patterns, one often
binds parts of the input to local variables;
those variables can then be used in the result expression.

The special `_` pattern matches any single value, and is often used as
a catch-all; the special `..` pattern generalizes this by matching any
*series* of values or name/value pairs.

Also, one can collapse multiple patterns into one arm by separating the
patterns by vertical bars (`|`); thus that arm matches either this pattern,
or that pattern, et cetera.

These features are illustrated in the following revision to the
guessing-game answer generation strategy:

```rust
struct GuessState {
    guess: u32,
    answer: Answer,
    low: u32,
    high: u32,
}

fn suggest_guess_smarter(s: GuessState) {
    match s {
        // First arm only fires on Bingo; it binds `p` to last guess.
        GuessState { answer: Answer::Bingo, guess: p, .. } => {
     // ~~~~~~~~~~   ~~~~~~~~~~~~~~~~~~~~~  ~~~~~~~~  ~~
     //     |                 |                 |     |
     //     |                 |                 |     Ignore remaining fields
     //     |                 |                 |
     //     |                 |      Copy value of field `guess` into local variable `p`
     //     |                 |
     //     |   Test that `answer field is equal to `Bingo`
     //     |
     //  Match against an instance of the struct `GuessState`
     
            println!("we won with {}!", p);
        }

        // Second arm fires if answer was too low or too high.
        // We want to find a new guess in the range (l..h), where:
        //
        // - If it was too low, then we want something higher, so we
        //   bind the guess to `l` and use our last high guess as `h`.
        // - If it was too high, then we want something lower; bind
        //   the guess to `h` and use our last low guess as `l`.
        GuessState { answer: Answer::Higher, low: _, guess: l, high: h } |
        GuessState { answer: Answer::Lower,  low: l, guess: h, high: _ } => {
     // ~~~~~~~~~~   ~~~~~~~~~~~~~~~~~~~~~   ~~~~~~  ~~~~~~~~  ~~~~~~~
     //     |                 |                 |        |        |
     //     |                 |                 |        |    Copy or ignore
     //     |                 |                 |        |    field `high`,
     //     |                 |                 |        |    as appropriate
     //     |                 |                 |        |
     //     |                 |                 |  Copy field `guess` into
     //     |                 |                 |  local variable `l` or `h`,
     //     |                 |                 |  as appropriate
     //     |                 |                 |
     //     |                 |    Copy value of field `low` into local
     //     |                 |    variable `l`, or ignore it, as appropriate
     //     |                 |
     //     |   Test that `answer field is equal
     //     |   to `Higher` or `Lower`, as appropriate
     //     |
     //  Match against an instance of the struct `GuessState`

            let mid = l + ((h - l) / 2);
            println!("lets try {} next", mid);
        }
    }
}

#[test]
fn demo_guess_state() {
    suggest_guess_smarter(GuessState {
        guess: 20, answer: Answer::Lower, low: 10, high: 1000
    });
}
```

This ability to simultaneously perform case analysis *and* bind input
substructure leads to powerful, clear, and concise code, focusing the
reader's attention directly on the data relevant to the case at hand.

That is `match` in a nutshell.

So, what is the interplay between this construct and Rust's approach to
ownership and safety in general?

### Exhaustive case analysis

> ...when you have eliminated all which is impossible,
> then whatever remains, however improbable, must be the truth.
>
> -- Sherlock Holmes (Arthur Conan Doyle, "The Blanched Soldier")

One useful way to tackle a complex problem is to break it down
into individual cases and analyze each case individually.
For this method of problem solving to work, the breakdown must be
*collectively exhaustive*; all of the cases you identified must
actually cover all possible scenarios.

Using `enum` and `match` in Rust can aid this process, because
`match` enforces exhaustive case analysis:
Every possible input value for a `match` must be covered by the pattern
in a least one arm in the match.

This helps catch bugs in program logic and ensures that the value of a
`match` expression is well-defined.

So, for example, the following code is rejected at compile-time.

```rust
fn suggest_guess_broken(prior_guess: u32, answer: Answer) {
    let next_guess = match answer {
        Answer::Higher => prior_guess + 10,
        Answer::Lower  => prior_guess - 1,
        // ERROR: non-exhaustive patterns: `Bingo` not covered
    };
    println!("maybe try {} next", next_guess);
}
```

Many other languages offer a pattern matching construct (ML and
various macro-based `match` implementations in Scheme both come to
mind), but not all of them have this restriction.

Rust has this restriction for these reasons:

* First, as noted above, dividing a problem into cases only yields a
general solution if the cases are exhaustive. Exhaustiveness-checking
exposes logical errors.

* Second, exhaustiveness-checking can act as a refactoring aid.  During
the development process, I often add new variants for a particular
`enum` definition.  The exhaustiveness-check helps points out all of
the `match` expressions where I only wrote the cases from the prior
version of the `enum` type.

* Third, since `match` is an expression form, exhaustiveness ensures
that such expressions always either evaluate to a value of the correct type,
*or* jump elsewhere in the program.

#### Jumping out of a match
[jumping]: #jumping-out-of-a-match

The following code is a fixed version of the `suggest_guess_broken`
function we saw above; it directly illustrates "jumping elsewhere":

```rust
fn suggest_guess_fixed(prior_guess: u32, answer: Answer) {
    let next_guess = match answer {
        Answer::Higher => prior_guess + 10,
        Answer::Lower  => prior_guess - 1,
        Answer::Bingo  => {
            println!("we won with {}!", prior_guess);
            return;
        }
    };
    println!("maybe try {} next", next_guess);
}

#[test]
fn demo_guess_fixed() {
    suggest_guess_fixed(10, Answer::Higher);
    suggest_guess_fixed(20, Answer::Lower);
    suggest_guess_fixed(19, Answer::Bingo);
}
```

The `suggest_guess_fixed` function illustrates that `match` can handle
some cases early (and then immediately return from the function),
while computing whatever values are needed from the remaining cases
and letting them fall through to the remainder of the function
body.

We can add such special case handling via `match` without fear
of overlooking a case, because `match` will force the case
analysis to be exhaustive.

### Algebraic Data Types and Structural Invariants
[adts]: #algebraic-data-types-and-structural-invariants

[Algebraic data types] succinctly describe classes of data and allow one
to encode rich structural invariants. Rust uses `enum` and `struct`
definitions for this purpose.

An `enum` type allows one to define mutually-exclusive classes of
values. The examples shown above used `enum` for simple symbolic tags,
but in Rust, enums can define much richer classes of data.

For example, a binary tree is either a leaf, or an internal node with
references to two child trees. Here is one way to encode a tree of
integers in Rust:

```rust
enum BinaryTree {
    Leaf(i32),
    Node(Box<BinaryTree>, i32, Box<BinaryTree>)
}
```

(The `Box<V>` type describes an owning reference to a heap-allocated
instance of `V`; if you own a `Box<V>`, then you also own the `V` it
contains, and can mutate it, lend out references to it, et cetera.
When you finish with the box and let it fall out of scope, it will
automatically clean up the resources associated with the
heap-allocated `V`.)

The above `enum` definition ensures that if we are given a `BinaryTree`, it
will always fall into one of the above two cases. One will never
encounter a `BinaryTree::Node` that does not have a left-hand child.
There is no need to check for null.

One *does* need to check whether a given `BinaryTree` is a `Leaf` or
is a `Node`, but the compiler statically ensures such checks are done:
you cannot accidentally interpret the data of a `Leaf` as if it were a
`Node`, nor vice versa.

Here is a function that sums all of the integers in a tree
using `match`.

```rust
fn tree_weight_v1(t: BinaryTree) -> i32 {
    match t {
        BinaryTree::Leaf(payload) => payload,
        BinaryTree::Node(left, payload, right) => {
            tree_weight_v1(*left) + payload + tree_weight_v1(*right)
        }
    }
}

/// Returns tree that Looks like:
///
///      +----(4)---+
///      |          |
///   +-(2)-+      [5]
///   |     |   
///  [1]   [3]
///
fn sample_tree() -> BinaryTree {
    let l1 = Box::new(BinaryTree::Leaf(1));
    let l3 = Box::new(BinaryTree::Leaf(3));
    let n2 = Box::new(BinaryTree::Node(l1, 2, l3));
    let l5 = Box::new(BinaryTree::Leaf(5));

    BinaryTree::Node(n2, 4, l5)
}

#[test]
fn tree_demo_1() {
    let tree = sample_tree();
    assert_eq!(tree_weight_v1(tree), (1 + 2 + 3) + 4 + 5);
}
```

Algebraic data types establish structural invariants that are strictly
enforced by the language. (Even richer representation invariants can
be maintained via the use of modules and privacy; but let us not
digress from the topic at hand.)

### Both expression- and statement-oriented

Unlike many languages that offer pattern matching, Rust *embraces*
both statement- and expression-oriented programming.

Many functional languages that offer pattern matching encourage one to
write in an "expression-oriented style", where the focus is always on
the values returned by evaluating combinations of expressions, and
side-effects are discouraged. This style contrasts with imperative
languages, which encourage a statement-oriented style that focuses on
sequences of commands executed solely for their side-effects.

Rust excels in supporting both styles.

Consider writing a function which maps a non-negative integer to a
string rendering it as an ordinal ("1st", "2nd", "3rd", ...).

The following code uses range patterns to simplify things, but also,
it is written in a style similar to a `switch` in a statement-oriented
language like C (or C++, Java, et cetera), where the arms of the
`match` are executed for their side-effect alone:

```rust
fn num_to_ordinal(x: u32) -> String {
    let suffix;
    match (x % 10, x % 100) {
        (1, 1) | (1, 21...91) => {
            suffix = "st";
        }
        (2, 2) | (2, 22...92) => {
            suffix = "nd";
        }
        (3, 3) | (3, 23...93) => {
            suffix = "rd";
        }
        _                     => {
            suffix = "th";
        }
    }
    return format!("{}{}", x, suffix);
}

#[test]
fn test_num_to_ordinal() {
    assert_eq!(num_to_ordinal(   0),    "0th");
    assert_eq!(num_to_ordinal(   1),    "1st");
    assert_eq!(num_to_ordinal(  12),   "12th");
    assert_eq!(num_to_ordinal(  22),   "22nd");
    assert_eq!(num_to_ordinal(  43),   "43rd");
    assert_eq!(num_to_ordinal(  67),   "67th");
    assert_eq!(num_to_ordinal(1901), "1901st");
}
```

The Rust compiler accepts the above program. This is notable because
its static analyses ensure both:

* `suffix` is always initialized before we run the `format!` at the end
  of the function, and

* `suffix` is assigned *at most once* during the function's execution (because if
  we could assign `suffix` multiple times, the compiler would force us
  to mark `suffix` as mutable).

To be clear, the above program certainly *can* be written in an
expression-oriented style in Rust; for example, like so:

```rust
fn num_to_ordinal_expr(x: u32) -> String {
    format!("{}{}", x, match (x % 10, x % 100) {
        (1, 1) | (1, 21...91) => "st",
        (2, 2) | (2, 22...92) => "nd",
        (3, 3) | (3, 23...93) => "rd",
        _                     => "th"
    })
}
```

Sometimes expression-oriented style can yield very succinct code;
other times the style requires contortions that can be
avoided by writing in a statement-oriented style.
(The ability to return from one `match` arm in the
`suggest_guess_fixed` function [earlier][jumping] was an example of this.)

Each of the styles has its use cases. Crucially, switching to a
statement-oriented style in Rust does not sacrifice every other
feature that Rust provides, such as the guarantee that a non-`mut`
binding is assigned at most once.

An important case where this arises is when one wants to
initialize some state and then borrow from it, but only on
*some* control-flow branches.

```rust
fn sometimes_initialize(input: i32) {
    let string: String; // a dynamically-constructed string value
    let borrowed: &str; // a reference to string data
    match input {
        0...100 => {
            // Construct a String on the fly...
            string = format!("input prints as {}", input);
            // ... and then borrow from inside it.
            borrowed = &string[6..];
        }
        _ => {
            // String literals are *already* borrowed references
            borrowed = "expected between 0 and 100";
        }
    }
    println!("borrowed: {}", borrowed);

    // Below would cause compile-time error if uncommented...

    // println!("string: {}", string);

    // ...namely: error: use of possibly uninitialized variable: `string`
}

#[test]
fn demo_sometimes_initialize() {
    sometimes_initialize(23);  // this invocation will initialize `string`
    sometimes_initialize(123); // this one will not
}
```

The interesting thing about the above code is that after the `match`,
we are not allowed to directly access `string`, because the compiler
requires that the variable be initialized on every path through the
program before it can be accessed.
At the same time, we *can*, via `borrowed`, access data that
may held *within* `string`, because a reference to that data is held by the
`borrowed` variable when we go through the first match arm, and we
ensure `borrowed` itself is initialized on every execution path
through the program that reaches the `println!` that uses `borrowed`.

(The compiler ensures that no outstanding borrows of the
`string` data could possibly outlive `string` itself, and the
generated code ensures that at the end of the scope of `string`, its
data is deallocated if it was previously initialized.)

In short, for soundness, the Rust language ensures that data is always
initialized before it is referenced, but the designers have strived to
avoid requiring artificial coding patterns adopted solely to placate
Rust's static analyses (such as requiring one to initialize `string`
above with some dummy data, or requiring an expression-oriented style).

### Matching without moving
[matching without moving]: #matching-without-moving

Matching an input can *borrow* input substructure, without taking
ownership; this is crucial for matching a reference (e.g. a value of
type `&T`).

The ["Algebraic Data Types" section][adts] above described a tree datatype, and
showed a program that computed the sum of the integers in a tree
instance.

That version of `tree_weight` has one big downside, however: it takes
its input tree by value. Once you pass a tree to `tree_weight_v1`, that
tree is *gone* (as in, deallocated).

```rust
#[test]
fn tree_demo_v1_fails() {
    let tree = sample_tree();
    assert_eq!(tree_weight_v1(tree), (1 + 2 + 3) + 4 + 5);

    // If you uncomment this line below ...
    
    // assert_eq!(tree_weight_v1(tree), (1 + 2 + 3) + 4 + 5);

    // ... you will get: error: use of moved value: `tree`
}
```

This is *not* a consequence, however, of using `match`; it is rather
a consequence of the function signature that was chosen:

```rust
fn tree_weight_v1(t: BinaryTree) -> i32 { 0 }
//                   ^~~~~~~~~~ this means this function takes ownership of `t`
```

In fact, in Rust, `match` is designed to work quite well *without*
taking ownership. In particular, the input to `match` is an *[L-value][L_value]
expression*; this means that the input expression is evaluated to a
*memory location* where the value lives.
`match` works by doing this evaluation and then
inspecting the data at that memory location.

(If the input expression is a variable name or a field/pointer
dereference, then the L-value is just the location of that variable or
field/memory.  If the input expression is a function call or other
operation that generates an unnamed temporary value, then it will be
conceptually stored in a temporary area, and that is the memory
location that `match` will inspect.)

So, if we want a version of `tree_weight` that merely borrows a tree
rather than taking ownership of it, then we will need to make use of
this feature of Rust's `match`.

```rust
fn tree_weight_v2(t: &BinaryTree) -> i32 {
    //               ^~~~~~~~~~~ The `&` means we are *borrowing* the tree
    match *t {
        BinaryTree::Leaf(payload) => payload,
        BinaryTree::Node(ref left, payload, ref right) => {
            tree_weight_v2(left) + payload + tree_weight_v2(right)
        }
    }
}

#[test]
fn tree_demo_2() {
    let tree = sample_tree();
    assert_eq!(tree_weight_v2(&tree), (1 + 2 + 3) + 4 + 5);
}
```

The function `tree_weight_v2` looks very much like `tree_weight_v1`.
The only differences are: we take `t` as a borrowed reference (the `&`
in its type), we added a dereference `*t`, and,
importantly, we use `ref`-bindings for `left` and
`right` in the `Node` case.

The dereference `*t`, interpreted as an L-value expression, is just
extracting the memory address where the `BinaryTree` is represented
(since the `t: &BinaryTree` is just a *reference* to that data in
memory). The `*t` here is not making a copy of the tree, nor moving it
to a new temporary location, because `match` is treating it as an
L-value.

The only piece left is the `ref`-binding, which
is a crucial part of how destructuring bind of
L-values works.

First, let us carefully state the meaning of a *non-ref* binding:

* When matching a value of type `T`, an identifier pattern `i` will, on
  a successful match, *move* the value out of the original input and
  into `i`. Thus we can always conclude in such a case that `i` has type
  `T` (or more succinctly, "`i: T`").

  For some types `T`, known as *copyable* `T` (also pronounced "`T`
  implements `Copy`"), the value will in fact be copied into `i` for such
  identifier patterns. (Note that in general, an arbitrary type `T` is not copyable.)

  Either way, such pattern bindings do mean that the variable `i` has
  *ownership* of a value of type `T`.

Thus, the bindings of `payload` in `tree_weight_v2` both have type
`i32`; the `i32` type implements `Copy`, so the weight is copied into
`payload` in both arms.

Now we are ready to state what a ref-binding is:

* When matching an L-value of type `T`, a `ref`-pattern `ref i`
  will, on a successful match, merely *borrow* a reference into the
  matched data. In other words, a successful `ref i` match of a value of
  type `T` will imply that `i` has the type of a *reference* to `T`
  (or more succinctly, "`i: &T`").

Thus, in the `Node` arm of
`tree_weight_v2`, `left` will be a reference to the left-hand box (which
holds a tree), and `right` will likewise reference the right-hand tree.

We can pass these borrowed references to trees into the recursive calls to `tree_weight_v2`,
as the code demonstrates.

Likewise, a `ref mut`-pattern (`ref mut i`) will, on a successful
match, borrow a *mutable reference* into the input: `i: &mut T`. This allows
mutation and ensures there are no other active references to that data
at the same time. A destructuring
binding form like `match` allows one to take mutable references to
disjoint parts of the data simultaneously.

This code demonstrates this concept by incrementing all of the
values in a given tree.

```rust
fn tree_grow(t: &mut BinaryTree) {
    //          ^~~~~~~~~~~~~~~ `&mut`: we have exclusive access to the tree
    match *t {
        BinaryTree::Leaf(ref mut payload) => *payload += 1,
        BinaryTree::Node(ref mut left, ref mut payload, ref mut right) => {
            tree_grow(left);
            *payload += 1;
            tree_grow(right);
        }
    }
}

#[test]
fn tree_demo_3() {
    let mut tree = sample_tree();
    tree_grow(&mut tree);
    assert_eq!(tree_weight_v2(&tree), (2 + 3 + 4) + 5 + 6);
}
```

Note that the code above now binds `payload` by a `ref mut`-pattern;
if it did not use a `ref` pattern, then `payload` would be bound to a
local copy of the integer, while we want to modify the actual integer
*in the tree itself*. Thus we need a reference to that integer.

Note also that the code is able to bind `left` and `right`
simultaneously in the `Node` arm. The compiler knows that the two
values cannot alias, and thus it allows both `&mut`-references to live
simultaneously.

## Conclusion

Rust takes the ideas of algebraic data types and pattern matching
pioneered by the functional programming languages, and adapts them to
imperative programming styles and Rust's own ownership and borrowing
systems. The `enum` and `match` forms provide clean data definitions
and expressive power, while static analysis ensures that the resulting
programs are safe.

For more information
on details that were not covered here, such as:

* how to say `Higher` instead of `Answer::Higher` in a pattern,

* defining new named constants,

* binding via `ident @ pattern`, or

* the potentially subtle difference between `{ let id = expr; ... }` versus `match expr { id => { ... } }`,

consult the Rust
[documentation][rust_docs], or quiz our awesome community (in `#rust` on IRC, or in
the [user group]).

(Many thanks to those who helped review this post, especially Aaron Turon
and Niko Matsakis, as well as
`Mutabah`, `proc`, `libfud`, `asQuirrel`, and `annodomini` from `#rust`.)

[structured data]: http://en.wikipedia.org/wiki/Record_%28computer_science%29
[Algebraic data types]: http://en.wikipedia.org/wiki/Algebraic_data_type
[rust_docs]: https://doc.rust-lang.org/
[user group]: http://users.rust-lang.org/
[L_value]: https://doc.rust-lang.org/reference.html#lvalues,-rvalues-and-temporaries

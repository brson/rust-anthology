---
layout: post
title: "Reading Rust Function Signatures"
author: "Andrew Hobden"
tags:
 - Rust
 - Tutorials
---

In Rust, function signatures tell a story. Just from glancing at the signature of a function an experienced Rust user can tell much of the functions behaivor.

In this article we'll explore some signatures and talk about how to read them and extract information from them. While exploring, you can find many great function signature examples in the [Rust API docs](https://doc.rust-lang.org/stable/std/). You can play around on the [Playpen](https://play.rust-lang.org/).

This article assumes some knowledge of Rust, glossing over a bit of the [book](https://doc.rust-lang.org/stable/book/README.html) should be quite sufficient if you are lacking that but have programmed before.

If you're used to programming in something like Python or Javascript, this all may seem a bit foreign to you. I hope by the end of it that you're convinced this additional information is both a good thing, and that it is not something you often have in dynamically typed languages.

If you're used to C++, C, or the other systemsy languages hopefully this should all seem very familiar, despite the syntax differences. Ideally by the end of your article you'll think more about your function signatures as you write them!

# Baby Steps

Your first function definition in Rust almost definitely looks like this:

```rust
fn main() {}
```

So since you've already most likely wrote this let's start here!

* `fn`: is the syntax which tells Rust we're declaring a function.
* `main`: is the name of the function. `main` is special because it's what the program invokes when built and run as a binary. Function names are always `snake_case` and not `camelCase`.
* `()`: Is the arguments list. In this case, `main` accepts no arguments.
* `{}`: Are the delimiters for the inside of a function. In this case, it's empty.

So what would we write for a function that does nothing useful?

```rust
fn do_nothing_useful() {}
```

Great, now you too can do nothing useful!

# Visibility

By default, all functions are private and cannot be used outside of the module they are in. Making them usable by a different module is simple.

```rust
mod dog {
    fn private_function() {}
    pub fn public_function() {}
}

// Optional to avoid `foo::`
use dog::public_function;

fn main() {
    dog::public_function();
    // With `use`
    public_function();
}
```

Like mutability, Rust is conservative in its assumptions about things like visibility. If you try to use a private function the compiler will let you know and help point you to where you need to make the function public.

If you have a function like `foo::bar::baz::rad()` in your project and want to make it usable as `foo::rad()` add `pub use bar::baz::rad;` to your `foo` module. This is called re-exporting.

# Simple Parameters

No longer happy with `do_nothing_useful()` you decide to adopt a dog. Good for you! Now you have a new problem, you have to walk it and play with it!

```rust
fn walk_dog(dog_name: String) {}
fn play_with(dog_name: String, game_name: String) {}
```

Parameters are declared `variable_name: Type`, and are comma seperated. But c'mon! Our dog is a lot more than just a `String`! Good news, you can use your own types too.

```rust
struct Dog;  // Let's not go overboard.
struct Game; // Simple types in demos!

fn walk_dog(dog: Dog) {}
fn play_with(dog: Dog, game: Game) {}
```

Great, looking better already. Let's get that awesome day started.

```rust
fn main() {
    let rover = Dog;
    walk_dog(rover);

    let fetch = Game;
    play_with(rover, fetch); // Compiler Error!
}
```

Whoa whoa! That's a perfectly good day the compiler is totally *ruining* for us! Rover is going to be super sad.

Let's look at the error:

```
<anon>:11:15: 11:20 error: use of moved value: `rover`
<anon>:11     play_with(rover, fetch);
                        ^~~~~
<anon>:9:14: 9:19 note: `rover` moved here because it has type `Dog`, which is non-copyable
<anon>:9     walk_dog(rover);
                      ^~~~~
```

Here the compiler is telling us that `rover` was *moved* when we passed it into `walk_dog()`. That's because `fn walk_dog(dog: Dog) {}` accepts a `Dog` value and we haven't tell the compiler they are copyable! Values with `Copy` are implictly copied when passed to functions. You can make something `Copy` by adding `#[derive(Copy)]` above the declaration.

**We're going to keep `Dog` not copyable because, gosh darnit, you can't copy dogs.** So how do we fix this?

We could clone `rover`. But our `Dog` struct isn't `Clone` either! `Clone` means we can explicitly make a copy of an object. You can make something `Clone` just like you did as `Copy`. To clone our dog you can do `rover.clone()`

But really neither of those possible solutions solved the real problem: *We want to walk and play with the same dog!*

# Borrowing

> Can I borrow your dog?

Instead of moving our `Dog` into the `walk_dog()` function we really just want to *lend* the function our `Dog`. When you walk your dog it (generally) ends up coming back to the house with you, right?

Rust uses `&` to symbolize a borrow. Borrowing something tells the compiler that when the function is done the ownership of the value returns back to the caller.

```rust
fn walk_dog(dog: &Dog) {}
fn play_with(dog: &Dog, game: Game) {}
```

There are immutable borrows as well as mutable borrows (`&mut`). You can have an immutable borrow passed to any number of things at once, and a mutable borrow only passed to one thing at a time. This provides data safety.

So our new borrowing functions don't really cut it, do they? We can't even mutate the `Dog`! Let's try anyways to see the error message.

```rust
struct Dog {
    walked: bool
}

fn walk_dog(dog: &Dog) {
    dog.walked = true;
}

fn main() {
    let rover = Dog { walked: false };
    walk_dog(&rover);
    assert_eq!(rover.walked, true);
}
```

As we expected:

```
<anon>:6:5: 6:22 error: cannot assign to immutable field `dog.walked`
<anon>:6     dog.walked = true;
             ^~~~~~~~~~~~~~~~~
error: aborting due to previous error
```

Changing the function signature to `fn walk_dog(dog: &mut Dog) {}` and updating our `main()` we can solve this.

```rust
fn main() {
    let mut rover = Dog { walked: false };
    walk_dog(&mut rover);
    assert_eq!(rover.walked, true);
}
```

As you can see, the function signature tells the programmer *if a value is mutable* and *if the value is consumed or referenced*.

# Returning

Let's revisit exactly *how* we get Rover, because thats how we can explore return types! Let's say we want a function `adopt_dog()` which takes a name and gives us a `Dog`.

```rust
struct Dog {
    name: String,
    walked: bool,
}

fn adopt_dog(name: String) -> Dog {
    Dog { name: name, walked: false }
}

fn main() {
    let rover = adopt_dog(String::from("Rover"));
    assert_eq!(rover.name, "Rover");
}
```

So the `-> Dog` part of the function signature tells us that the function returns a `Dog`. Note that the `name` is *moved* in and given to the dog, not copied or cloned.

# Inside Traits

If you're implementing functions in a trait you also have access the following two tools:

* The `Self` return type which represents the current type.
* The `self` parameter which specifies the borrowing/moving/mutability of the structure instance. In `walk()` below we take a mutable borrow, a bare `self` moves the value.

An example:

```rust
// ... `Dog` struct from before.
impl Dog {
    pub fn adopt(name: String) -> Self {
        Dog { name: name, walked: false }
    }
    pub fn walk(&mut self) {
        self.walked = true
    }
}

fn main() {
    let mut rover = Dog::adopt(String::from("Rover"));
    assert_eq!(rover.name, "Rover");
    rover.walk();
    assert_eq!(rover.walked, true);
}
```

# Generics

Let's face it, there are a lot of different kinds of dogs! But moreso, there are a lot of types of animals! Some of these we might want to walk too, like our `Bear`.

Generics let us do this. We can have a `Dog` and `Bear` struct that implement the `Walk` trait, then have a `walk_pet()` function accept any `Walk` traited structure!

Generics are specified to functions in between the name and the parameters using sharp brackets. The important thing to note about generics is when you're accepting a generic *you may only use the functions from the constraints*. This means that if you pass a `Read` to a function that wants `Write`, it still can't `Read` in it unless the constraints include it.

```rust
struct Dog { walked: bool, }
struct Bear { walked: bool, }

trait Walk {
    fn walk(&mut self);
}
impl Walk for Dog {
    fn walk(&mut self) {
        self.walked = true
    }
}
impl Walk for Bear {
    fn walk(&mut self) {
        self.walked = true
    }
}

fn walk_pet<W: Walk>(pet: &mut W) {
    // Try setting `pet.walked` here!
    // You can't!
    pet.walk();
}

fn walk_pet_2(pet: &mut Walk) {
    // Try setting `pet.walked` here!
    // You can't!
    pet.walk();
}

fn main() {
    let mut rover = Dog { walked: false, };
    walk_pet(&mut rover);
    assert_eq!(rover.walked, true);
}
```

You can also use a different `where` syntax as function signatures with complex generics can get rather long.

```rust
fn walk_pet<W>(pet: &mut W)
where W: Walk {
    pet.walk();
}
```

If you have multiple generics you can comma seperate them in both cases. If you'd like more than one trait contraint you can use `where W: Walk + Read` or `<W: Walk + Read>`.

```rust
fn stuff<R, W>(r: &R, w: &mut W)
where W: Write, R: Read + Clone {}
```

Look at all of the information you can derive from that function signature! It's not helpfully named but you can still tell *almost for sure* what it does!

There are also these crazy things called **Associated Types** which are used in stuff like `Iterator`. When being written in a signature you want to use something like `Iterator<Item=Dog>` to say an iterator of `Dog`s.

# Passing Functions

Sometimes it's desirable to pass functions into other functions. In Rust, accepting a function as an argument is fairly straightforward. Functions have traits and they are passed like generics!

> You should definitely use the `where` syntax here.

```rust
struct Dog {
    walked: bool
}

fn do_with<F>(dog: &mut Dog, action: F)
where F: Fn(&mut Dog) {
    action(dog);
}

fn walk(dog: &mut Dog) {
    dog.walked = true;
}

fn main() {
    let mut rover = Dog { walked: false, };
    // Fn
    do_with(&mut rover, walk);
    // Closure
    do_with(&mut rover, |dog| dog.walked = true);
}
```

Functions in Rust implement traits which determine where (and how) they are passed:

* [`FnOnce`](https://doc.rust-lang.org/stable/core/ops/trait.FnOnce.html) - Takes a by-value reciever.
* [`FnMut`](https://doc.rust-lang.org/stable/core/ops/trait.FnMut.html) - Takes a mutable reciever.
* [`Fn`](https://doc.rust-lang.org/stable/core/ops/trait.Fn.html) - Takes a immutable reciever.

A particular [Stack Overflow answer](http://stackoverflow.com/a/30232500/2084424) summises the differences very well:

> A closure `|...| ...` will automatically implement as many of those as it can.

> * All closures implement `FnOnce`: a closure that can't be called once doesn't deserve the name. Note that if a closure only implements `FnOnce`, it can be called only once.
> * Closures that don't move out of their captures implement `FnMut`, allowing them to be called more than once (if there is unaliased access to the function object).
> * Closures that don't need unique/mutable access to their captures implement `Fn`, allowing them to be called essentially everywhere.


Essentially, the differences between the different types is how they interact with their environment. In my experience, you only *really* need to worry about the distinction for Closures, which may capture variables in scope (in our above example, the `main()` function).

Have no fear, though! The compiler messages when one type is provided when another are needed are very helpful!

# Lifetimes

So, you're probably feeling pretty good about yourself right now. I mean, look at that scrollbar, it's almost to the bottom of the page! You'll be a Rust function signature **master** in no time!

Let's finish up with a bit of talk about lifetimes because you'll eventually come across them and likely get quite confused.

> Let me be honest with you upfront here. Lifetimes are an arcane art to me. I used them a bit back in 0.7-0.10 and then I haven't really had to use them since. If you know really anything at all about them you're much more qualified to write this section than I am.

Modern Rust has a really robust and effective *lifetime ellision* which removes the vast majority of lifetime gymnastics we used to need to concern ourselves with. But *when* you do things can start to untangle.

So, if you start dealing with a lot of lifetimes, your first step should really be to **sit back and think about it**. Unless your code is quite complex it's quite likely you won't need to deal with lifetimes. If you're bumping into lifetimes in a simple example your notion of the problem is probably **incorrect**.

Here is a function with lifetimes from [`Option`'s implementation](https://doc.rust-lang.org/stable/core/option/enum.Option.html#method.as_slice).

```rust
as_slice<'a>(&'a self) -> &'a [T]
```

Lifetimes are denoted by the tick (`'`) and given a name. In this case, `'a` but they can also be things like `'burrito` if you prefer inside jokes. Essentially what this is saying is:

> The lifetime of the `Option<T>` this is called upon is the same as the lifetime of the returned `[T]`

Great! I'm really not qualified to write anymore about lifetimes but if you have anything to add let me know and I'll credit you for sure.

# Challenge Time

Below, you'll find a set of functions pulled from the standard library along with links to their documentation. Can you tell from their function signature what they do? (For added fun, I've removed the function name!)

```rust
// In `File`
fn name<P: AsRef<Path>>(path: P) -> Result<File>
```
[Source](https://doc.rust-lang.org/stable/std/fs/struct.File.html#method.create)

```rust
// In `Option<T>`
fn name<E, T>(self, err: E) -> Result<T, E>
```

[Source](https://doc.rust-lang.org/stable/core/option/enum.Option.html#method.ok_or)

```rust
// In `Iterator<Item=T>`
fn name<B: FromIterator<Self::Item>>(self) -> B
where Self: Sized
```

[Source](https://doc.rust-lang.org/stable/core/iter/trait.Iterator.html#method.collect)

```rust
// In `Iterator<Item=T>`
fn name<B, F>(self, init: B, f: F) -> B
where Self: Sized, F: FnMut(B, Self::Item) -> B
```

[Source](https://doc.rust-lang.org/stable/core/iter/trait.Iterator.html#method.fold)

```rust
// In `Result<T,E>`
fn name<F, O: FnOnce(E) -> F>(self, op: O) -> Result<T, F>
```

[Source](https://doc.rust-lang.org/stable/core/result/enum.Result.html#method.map_err)

I hope that went **fantastically**, I was just over here cheering you on!

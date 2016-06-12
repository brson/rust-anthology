---
layout: post
title: String vs &str in Rust functions
tags:
- rustlang
status: publish
type: post
published: true
---

<link rel="alternate" href="http://habrahabr.ru/post/274585/" hreflang="ru" />
<link rel="alternate" href="{{ site.url }}{{ page.url }}" hreflang="en" />
<link rel="alternate" href="{{ site.url }}{{ page.url }}" hreflang="x-default" />

<a href="https://habrahabr.ru/post/274485/">Russian Translation</a>

For all the people frustrated by having to use `to_string()` to get programs to compile this post is for you. For those not quite understanding why Rust has two string types `String` and `&str`, I hope to shed a little light on the matter.

## Functions That Accept A String

I want to discuss how to build interfaces that accept strings. I am an avid hypermedia fan and am obsessed about designing interfaces that are easy to use. Let's start with a method that accepts a [String][String]. Our search hints that `std::string::String` is a good choice here.

```rust
fn print_me(msg: String) {
    println!("the message is {}", msg);
}

fn main() {
    let message = "hello world";
    print_me(msg);
}
```

This gives a compiler error:

```
expected `collections::string::String`,
    found `&'static str`
```

So a string literal is of type `&str` and does not appear compatible with the type `String`. We can change the `message` type to a `String` and compile succesfully: `let message = "hello world".to_string();`. This works, but it is analogous to using `clone()` to get around ownership/borrowing errors. Here are three reasons to change `print_me` to accept a `&str` instead:

   * The `&` symbol is a reference type and means we are _borrowing_ the variable. When `print_me` is done with the variable, ownership will return to the original owner. Unless we have good reason to _move_ ownership of the `message` variable into our function, we should elect to borrow.
   * Using a reference is more efficient. Using `String` for `message` means the program must _copy_ the value. When using a reference, such as `&str`, no copy is made.
   * A `String` type can be magically turned into a `&str` type using the [Deref][Deref] trait and type coercion. This will make more sense with an example.

## Example of Deref Coercion

This example creates strings in four different ways that all work with the `print_me` function. The key to making this all work is passing values by reference. Rather than passing `owned_string` as a `String` to `print_me`, we instead pass it as `&String`. When the compiler sees a `&String` being passed to a function that takes `&str`, it coerces the `&String` into a `&str`. This same coercion takes places for the reference counted and atomically referenced counted strings. The `string` variable is already a reference, so no need to use a `&` when calling `print_me(string)`. Knowing this, we no longer need to have `.to_string()` calls littering our code.

```rust
fn print_me(msg: &str) { println!("msg = {}", msg); }

fn main() {
    let string = "hello world";
    print_me(string);

    let owned_string = "hello world".to_string(); // or String::from_str("hello world")
    print_me(&owned_string);

    let counted_string = std::rc::Rc::new("hello world".to_string());
    print_me(&counted_string);

    let atomically_counted_string = std::sync::Arc::new("hello world".to_string());
    print_me(&atomically_counted_string);
}
```

You can also use Deref coercion with other types, such as a `Vector`. After all, a `String` is just a vector of 8-byte `chars`. Read more about [Deref coercions] in the Rust lang book.


## Introducing struct

At this point we should be free of extraneous `to_string()` calls for our functions. However, we run into some problems when we try to introduce a struct. Using what we just learned, we might make a struct like this:

```rust
struct Person {
    name: &str,
}

fn main() {
    let _person = Person { name: "Herman" };
}
```

We get the error:

```
<anon>:2:11: 2:15 error: missing lifetime specifier [E0106]
<anon>:2     name: &str,
```

Rust is trying to ensure that `Person` does not outlive the reference to `name`. If `Person` did manage to outlive `name`, then we risk our program crashing. The whole point of Rust is to prevent this. So let's start trying to get this code to compile. We need to specify a [lifetime][lifetime], or scope, so Rust can keep us safe. The conventional lifetime specifier is `'a`. I do not know why that was picked, but let's go with that.


```rust
struct Person {
    name: &'a str,
}

fn main() {
    let _person = Person { name: "Herman" };
}
```

Compile again and we get another error:

```
<anon>:2:12: 2:14 error: use of undeclared lifetime name `'a` [E0261]
<anon>:2     name: &'a str,
```

Let's think about this. We know we want to hint to the Rust compiler that our struct `Person` should not outlive `name`. So, we need to delcare our lifetime on the `Person` struct. Some searching will point us to `<'a>` being the syntax to declare lifetimes.


```rust
struct Person<'a> {
    name: &'a str,
}

fn main() {
    let _person = Person { name: "Herman" };
}
```

This compiles! We normally implement methods on our structs though. Let's add a `greet` function to our `Person` class.

```rust
struct Person<'a> {
    name: &'a str,
}

impl Person {
    fn greet(&self) {
        println!("Hello, my name is {}", self.name);
    }
}

fn main() {
    let person = Person { name: "Herman" };
    person.greet();
}
```

We now get the error:

```
<anon>:5:6: 5:12 error: wrong number of lifetime parameters: expected 1, found 0 [E0107]
<anon>:5 impl Person {
```

Our `Person` struct has a lifetime paremeter so our implementation should have it too. Let's declare our `'a` lifetime to the implementation of `Person` like `impl Person<'a> {`. Unfortunately, this gives us a confusing error when we compile:

```
<anon>:5:13: 5:15 error: use of undeclared lifetime name `'a` [E0261]
<anon>:5 impl Person<'a> {
```

In order for us to _declare_ the lifetime, we need to specify the lifetime right after the `impl` like `impl<'a> Person {`. Compile again and we get the error:

```
<anon>:5:10: 5:16 error: wrong number of lifetime parameters: expected 1, found 0 [E0107]
<anon>:5 impl<'a> Person {
```

Now we are back on track. Let's add back our lifetime parameter back to the implementation of `Person` like `impl<'a> Person<'a> {`. Now our program compiles. Here is the complete working code:

```rust
struct Person<'a> {
    name: &'a str,
}

impl<'a> Person<'a> {
    fn greet(&self) {
        println!("Hello, my name is {}", self.name);
    }
}

fn main() {
    let person = Person { name: "Herman" };
    person.greet();
}
```

### String or &str In struct

The question is now whether to use a String or a `&str` in your struct. In other words when should we use a reference to another type in a struct? We should use a reference if our struct does not need ownership of the variable. This concept might be a little vague, but there are some rules I use to get at an answer.

   * Do I need to use the variable outside of my struct? Here is a contrived example:

```rust
struct Person {
    name: String,
}

impl Person {
    fn greet(&self) {
        println!("Hello, my name is {}", self.name);
    }
}

fn main() {
    let name = String::from_str("Herman");
    let person = Person { name: name };
    person.greet();
    println!("My name is {}", name); // move error
}
```

I should use a reference here since I need to use the variable later. Here is a real-world example in [rustc_serialize][rustc_serialize]. The `Encoder` struct does not need to own the `writer` variable that implements [std::fmt::Write][std::fmt::Write], just use (borrow) it for a little while. In fact, `String` implements `Write`. In this example using the [encode][encode] function, the variable of type `String` is passed to the Encoder and then returned to the caller of `encode`.

   * Is my type large? If the type is large, then passing it by reference will save unncessary memory usage. Remember, passing by reference does not cause a copy of the variable. Consider a String buffer that contains a large amount of data. Copying that around will cause the program to be much slower.

We should now be able to create functions that accept strings whether they are `&str`, `String` or event reference counted. We are also able to create `struct`s that are able to have variables that are references. The lifetime of the `struct` is linked to those referenced variables to make sure that the `struct` does not outlive the referenced variable and caused bad things to happen in our program. We also have a initial understanding of whether or not the varibles in our `struct` should be types or references to types.

### What about 'static

Random aside, but I thought it worth mentioning. We can use a `'static` lifetime to get our original example to compile, but I caution against it:

```rust
struct Person {
    name: &'static str,
}

impl Person {
    fn greet(&self) {
        println!("Hello, my name is {}", self.name);
    }
}

fn main() {
    let person = Person { name: "Herman" };
    person.greet();
}
```

The `'static` lifetime is valid for the entire program. You may not need `Person` or `name` to live that long.

## Related

   * [Creating a Rust function that accepts String or &str][related post]


[String]: https://doc.rust-lang.org/std/string/struct.String.html?search=String
[Deref]: http://doc.rust-lang.org/nightly/std/ops/trait.Deref.html
[Deref coercions]: http://doc.rust-lang.org/nightly/book/deref-coercions.html
[lifetime]: http://doc.rust-lang.org/nightly/book/ownership.html#lifetimes
[rustc_serialize]: https://github.com/rust-lang/rustc-serialize/blob/master/src/json.rs#L552
[std::fmt::Write]: http://doc.rust-lang.org/nightly/std/fmt/trait.Write.html
[encode]: https://github.com/rust-lang/rustc-serialize/blob/master/src/json.rs#L372
[related post]: /2015/05/06/creating-a-rust-function-that-accepts-string-or-str.html

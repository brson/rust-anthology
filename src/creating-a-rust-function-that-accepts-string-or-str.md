---
layout: post
title: "Creating a Rust function that accepts String or &str"
tags:
- rustlang
status: publish
type: post
published: true
---

<link rel="alternate" href="http://habrahabr.ru/post/274455/" hreflang="ru" />
<link rel="alternate" href="{{ site.url }}{{ page.url }}" hreflang="en" />
<link rel="alternate" href="{{ site.url }}{{ page.url }}" hreflang="x-default" />

<a href="http://habrahabr.ru/post/274455/">Russian Translation</a>

In my [last post][last post] we talked a lot about using `&str` as the preferred type for functions accepting a string argument. Towards the end of that post there was some discussion about when to use `String` vs `&str` in a `struct`. I think this advice is good, but there are cases where using `&str` instead of `String` is not optimal. We need another strategy for these use cases.

## A struct Containing Strings

Consider the `Person` struct below. For the sake of discussion, let's say `Person` has a real need to own the `name` variable. We choose to use the `String` type instead of `&str`.

```rust
struct Person {
    name: String,
}
```

Now we need to implement a `new()` function. Based on my last blog post, we prefer a `&str`:

```rust
impl Person {
    fn new (name: &str) -> Person {
        Person { name: name.to_string() }
    }
}
```

This works as long as we remember to call `.to_string()` inside of the `new()` function. However, the ergonomics of this function are less than desired. If we use a string literal, then we can make a new `Person` like `Person.new("Herman")`. If we already have a `String` though, we need to ask for a reference to the `String`:

```rust
let name = "Herman".to_string();
let person = Person::new(name.as_ref());
```

It feels like we are going in circles though. We had a `String`, then we called `as_ref()` to turn it into a `&str` only to then turn it back into a `String` inside of the `new()` function. We could go back to using a `String` like `fn new(name: String) -> Person {`, but that means we need to force the caller to use `.to_string()` whenever there is a string literal.

## Into<T> conversions

We can make our function easier for the caller to work with by using the [Into trait][Into trait]. This trait will can automatically convert a `&str` into a `String`. If we already have a `String`, then no conversion happens.

```rust
struct Person {
    name: String,
}

impl Person {
    fn new<S: Into<String>>(name: S) -> Person {
        Person { name: name.into() }
    }
}

fn main() {
    let person = Person::new("Herman");
    let person = Person::new("Herman".to_string());
}
```

This syntax for `new()` looks a little different. We are using [Generics][Generics] and [Traits][Traits] to tell Rust that some type `S` must implement the trait `Into` for type `String`. The `String` type implements `Into<String>` as noop because we already have a `String`. The `&str` type implements `Into<String>` by using the same `.to_string()` method we were originally doing in the `new()` function. So we aren't side-stepping the need for the `.to_string()` call, but we are taking away the need for the caller to do it. You might wonder if using `Into<String>` hurts performance and the answer is no. Rust uses [static dispatch][static dispatch] and the concept of [monomorphization][monomorphization] to handle all this during the compiler phase.

Don't worry if things like _static dispatch_ and _monomorphization_ are confusing. You just need to know that using the syntax above you can create functions that accept both `String` and `&str`. If you are thinking that `fn new<S: Into<String>>(name: S) -> Person {` is a lot of syntax, it is. It is important to point out though that there is nothing special about `Into<String>`. It is just a trait that is part of the Rust standard library. You could implement this trait yourself if you wanted to. You can implement similar traits you find useful and publish them on [crates.io][crates.io]. All this userland power is what makes Rust an awesome language.

### Another Way To Write Person::new()

The _where_ syntax also works and may be easier to read, especially if the function signature becomes more complex:

```rust 
struct Person {
    name: String,
}

impl Person {
    fn new<S>(name: S) -> Person where S: Into<String> {
        Person { name: name.into() }
    }
}
```

## Related

   * [String vs &str in Rust functions](http://hermanradtke.com/2015/05/03/string-vs-str-in-rust-functions.html)
   * [Creating a Rust function that returns a &str or String](http://hermanradtke.com/2015/05/29/creating-a-rust-function-that-returns-string-or-str.html)

[last post]: /2015/05/03/string-vs-str-in-rust-functions.html
[Into trait]: http://doc.rust-lang.org/nightly/core/convert/trait.Into.html
[Generics]: http://doc.rust-lang.org/nightly/book/generics.html
[Traits]: http://doc.rust-lang.org/nightly/book/traits.html
[static dispatch]: http://doc.rust-lang.org/nightly/book/trait-objects.html#static-dispatch
[monomorphization]: http://stackoverflow.com/a/14198060/775246
[crates.io]: https://crates.io/

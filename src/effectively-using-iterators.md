---
layout: post
title: "Effectively Using Iterators In Rust"
tags:
- rustlang
status: publish
type: post
published: true
---

In Rust, you quickly learn that vector and slice types are not iterable themselves. Depending on which tutorial or example you see first, you call `.iter()` or `.into_iter()`. If you do not realize both of these functions exist or that they do different things, you may find yourself fighting with the compiler to get your code to work. Let us take a journey through the world of iterators and figure out the differences between iter() and into_iter() in Rust.

## Iter

Most examples I have found use `.iter()`. We can call `v.iter()` on something like a vector or slice. This creates an `Iter<'a, T>` type and it is this `Iter<'a, T>` type that implements the `Iterator` trait and allows us to call functions like `.map()`. It is important to note that this `Iter<'a, T>` type only has a reference to `T`. This means that calling `v.iter()` will create a struct that _borrows_ from `v`. Use the `iter()` function if you want to iterate over the values by _reference_.

Let us write a simple map/reduce example:

```rust
fn use_names_for_something_else(_names: Vec<&str>) {
}

fn main() {
    let names = vec!["Jane", "Jill", "Jack", "John"];
    
    let total_bytes = names
        .iter()
        .map(|name: &&str| name.len())
        .fold(0, |acc, len| acc + len );
        
    assert_eq!(total_bytes, 16);
    use_names_for_something_else(names);
}
```

In this example, we are using `.map()` and `.fold()` to count the number of bytes (not characters! Rust strings are UTF-8) for all strings in the `names` vector. We [know][previous blog post] that the `len()` function can use an immutable reference. As such, we prefer `iter()` instead of `iter_mut()` or `into_iter()`. This allows us to _move_ the `names` vector later if we want. I put a bogus `use_names_for_something()` function in the example just to prove this. If we had used `into_iter()` instead, the compiler would have given us an _error: use of moved value: `names`_ response.

The closure used in `map()` does not require the `name` parameter to have a type, but I specified the type to show how it is being passed as a reference. Notice that the type of name is `&&str` and not `&str`. The string `"Jane"` is of type `&str`. The `iter()` function creates an iterator that has a _reference_ to each element in the `names` vector. Thus, we have a _reference_ to a _reference_ of a string slice. This can get a little unwieldy and I generally do not worry about the type. However, if we are destructuring the type, we do need to specify the reference:

```rust
fn main() {
    let player_scores = [
        ("Jack", 20), ("Jane", 23), ("Jill", 18), ("John", 19),
    ];

    let players = player_scores
        .iter()
        .map(|(player, _score)| {
            player
        })
        .collect::<Vec<_>>();

    assert_eq!(players, ["Jack", "Jane", "Jill", "John"]);
}
```

In the above example, the compiler will complain that we are specifying the type `(_, _)` instead of `&(_, _)`. Changing the pattern to `&(player, _score)` will satisfy the compiler.

Rust is immutable by default and iterators make it easy to manipulate data without needing mutability. If you do find yourself wanting to mutate some data, you can use the `iter_mut()` method to get a mutable reference to the values. Example use of `iter_mut()`:

```rust
fn main() {
    let mut teams = [
        [ ("Jack", 20), ("Jane", 23), ("Jill", 18), ("John", 19), ],
        [ ("Bill", 17), ("Brenda", 16), ("Brad", 18), ("Barbara", 17), ]
    ];
    
    let teams_in_score_order = teams
        .iter_mut()
        .map(|team| {
            team.sort_by(|&a, &b| a.1.cmp(&b.1).reverse());
            team
        })
        .collect::<Vec<_>>();
        
    println!("Teams: {:?}", teams_in_score_order);
}
```

Here we are using a mutable reference to sort the list of players on each team by highest score. The `sort_by()` function performs the sorting of the Vector/slice in place. This means we need the ability to mutate `team` in order to sort. I do not use `.iter_mut()` often, but sometimes functions like `.sort_by()` provide no immutable alternative. 

I tend to use `.iter()` most. I try to be very concious and deliberate about when I _move_ resources and default to borrowing (or referencing) first. The reference created by `.iter()` is short-lived, so we can _move_ or use our original value afterwards. If you find yourself running into _does not live long enough_, _move_ errors or using the `.clone()` function, this is a sign that you probably want to use `.into_iter()` instead.

## IntoIter

Use the `into_iter()` function when you want to _move_, instead of _borrow_, your value. The `.into_iter()` function creates a `IntoIter<T>` type that now has ownership of the original value. Like `Iter<'a, T>`, it is this `IntoIter<T>` type that actually implements the `Iterator` trait. The word _into_ is commonly used in Rust to signal that `T` is being _moved_. The docs also use the words _owned_ or _consumed_ interchangeably with _moved_. I normally find myself using `.into_iter()` when I have a function that is transforming some values:

```rust
fn get_names(v: Vec<(String, usize)>) -> Vec<String> {
    v.into_iter()
        .map(|(name, _score)| name)
        .collect()
}

fn main() {
    let v = vec!( ("Herman".to_string(), 5));
    let names = get_names(v);

    assert_eq!(names, ["Herman"]);
}
```

The `get_names` function is plucking out the name from a list of tuples. I chose `.into_iter()` here because we are transforming the tuple into a `String` type.

The concept behind `.into_iter()` is similar to the [core::convert::Into][core::convert::Into] trait we discussed when accepting `&str` and `String` in a function. In fact, the [std::iter::Iterator][std::iter::Iterator] type implements [std::iter::IntoIterator][std::iter::IntoIterator] too. That means we can do something like `vec![1, 2, 3, 4].into_iter().into_iter().into_iter()`. In each subsequent call to `.into_iter()` just returns itself. This is an example of the [identity function][identity function]. I mention that only because I find it interesting to identify functional concepts that I see being used in the wild.

### How for Loops Actually Work

One of the first errors a new Rustacean will run into is the _move_ error after using a for loop:

```rust
fn main() {
    let values = vec![1, 2, 3, 4];

    for x in values {
        println!("{}", x);
    }

    let y = values; // move error
}
```

The question we immediately ask ourselves is "How do I create a for loop that uses a reference?". A [for loop][for loop] in Rust is really just syntatic sugar around `.into_iter()`. From the manual:

```rust
// Rough translation of the iteration without a `for` iterator.
let mut it = values.into_iter();
loop {
    match it.next() {
        Some(x) => println!("{}", x),
        None => break,
    }
}
```

Now that we know `.into_iter()` creates a type `IntoIter<T>` that _moves_ `T`, this behavior makes perfect sense. If we want to use `values` after the for loop, we just need to use a reference instead:

```rust
fn main() {
    let values = vec![1, 2, 3, 4];

    for x in &values {
        println!("{}", x);
    }

    let y = values; // perfectly valid
}
```

Instead of moving `values`, which is type `Vec<i32>`, we are moving `&values`, which is type `&Vec<i32>`. The for loop only _borrows_ `&values` for the duration of the loop and we are able to _move_ `values` as soon as the for loop is done.

## core::iter::Cloned

There are times when you want create a new value when iterating over your original value. You might first try something like:

```rust
fn main() {
    let x = vec!["Jill", "Jack", "Jane", "John"];

    let _ = x
        .clone()
        .into_iter()
        .collect::<Vec<_>>();
}
```

Exercise for the reader: _Why would `.iter()` not work in this example?_

While this is valid, we want to give Rust every chance to optimize our code. What if we only wanted the first two names from that list?

```rust
fn main() {
    let x = vec!["Jill", "Jack", "Jane", "John"];

    let _ = x
        .clone()
        .into_iter()
        .take(2)
        .collect::<Vec<_>>();
}
```

If we clone all of `x`, then we are cloning all four elements, but we only need two of them. We can do better by using `.map()` to clone the elements of the underlying iterator:


```rust
fn main() {
    let x = vec!["Jill", "Jack", "Jane", "John"];

    let y = x
        .iter()
        .map(|i| i.clone())
        .take(2)
        .collect::<Vec<_>>();
}
```

The Rust compiler can now optimize this code and only clone two out of the four elements of `x`. This pattern is used so often that Rust core now has a special function that does this for us called [cloned()][cloned()]. This is a recent addition and will be stable in Rust 1.1. Our code now looks something like:

```rust
fn main() {
    let x = vec!["Jill", "Jack", "Jane", "John"];

    let y = x
        .iter()
        .cloned()
        .take(2)
        .collect::<Vec<_>>();
}
```

## Iterators Outside of Core

There is a really great crate, called [itertools][itertools], that provides extra iterator adaptors, iterator methods and macros. If you are looking for some iterator functionality in the Rust docs and do not see it, there is a good chance it is part of itertools. I recently added an [itertools::IterTools::sort_by()][itertools::IterTools::sort_by()] function so we can sort collections without needed to use a mutable iterator. One of the nice things about working with Rust is that the documentation looks the same across all these crates. The [documentation for itertools][documentation for itertools] looks the same as the [documentation for Rust std library][documentation for Rust std library].

## Related

   * [Creating a Rust function that accepts String or &str](/2015/05/06/creating-a-rust-function-that-accepts-string-or-str.html)


[previous blog post]: /2015/06/09/strategies-for-solving-cannot-move-out-of-borrowing-errors-in-rust.html
[core::convert::Into]: https://doc.rust-lang.org/nightly/core/convert/trait.Into.html
[std::iter::Iterator]: https://doc.rust-lang.org/stable/std/iter/trait.Iterator.html
[std::iter::IntoIterator]: https://github.com/rust-lang/rust/blob/b5b3a99f84f2b4dbf9495dccd7112c74f4357acc/src/libcore/iter.rs#L1184-1192
[identity function]: https://en.wikipedia.org/wiki/Identity_function
[itertools]: https://crates.io/crates/itertools
[documentation for itertools]: http://bluss.github.io/rust-itertools/doc/itertools/index.html
[documentation for Rust std library]: https://doc.rust-lang.org/std/
[for loop]: https://doc.rust-lang.org/stable/std/iter/index.html
[cloned()]: https://doc.rust-lang.org/stable/std/iter/trait.Iterator.html#method.cloned
[itertools::IterTools::sort_by()]: http://bluss.github.io/rust-itertools/doc/itertools/trait.Itertools.html#method.sort_by 

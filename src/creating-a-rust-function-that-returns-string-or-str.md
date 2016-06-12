---
layout: post
title: "Creating a Rust function that returns a &str or String"
tags:
- rustlang
status: publish
type: post
published: true
---

<link rel="alternate" href="http://habrahabr.ru/post/274565/" hreflang="ru" />
<link rel="alternate" href="{{ site.url }}{{ page.url }}" hreflang="en" />
<link rel="alternate" href="{{ site.url }}{{ page.url }}" hreflang="x-default" />

<a href="http://habrahabr.ru/post/274565/">Russian Translation</a>

We learned how to [create a function that accepts String or &str][Into<String>] as an argument. Now I want to show you how to create a function that returns either `String` or `&str`. I also want to discuss why we would want to do this. To start, let us write a function to remove all the spaces from a given string. Our function might look something like this:

```rust
fn remove_spaces(input: &str) -> String {
   let mut buf = String::with_capacity(input.len());

   for c in input.chars() {
      if c != ' ' {
         buf.push(c);
      }
   }

   buf
}

```

This function allocates memory for a string buffer, loops through each character of `input` and appends all non-space characters to the string buffer. Now I ask: what if my input did not contain spaces at all? The value `input` would be the same as `buf`. In that case, it would be more efficient to not create `buf` in the first place. Instead, we would like to just return the given `input` back to the caller. The type of `input` is a `&str` but our function returns a String though. We could change the type of `input` to a `String`:

```rust
fn remove_spaces(input: String) -> String { ... }
```

but this causes two problems. First, by making `input` of type `String` we are forcing the caller to _move_ the ownership of `input` into our function. This prevents the caller from using that value in the future. We should only take ownership of `input` if we actually need it. Second, the input might already be of type `&str` and we are now forcing the caller to convert it into a `String` which defeats our attempts to not allocate new memory when creating `buf`.

## Clone-on-write

What we really want is the ability to return our input string (`&str`) if there are no spaces and to return a new string (`String`) if there are spaces we need to remove. This is where the clone-on-write or [Cow][Cow] type can be used. The `Cow` type allows us to abstract away whether something is `Owned` or `Borrowed`. In our example, the `&str` is a reference to an existing string so that would be _borrowed_ data. If there are spaces, then we need to allocate memory for a new `String`. That new `String` is _owned_ by the `buf` variable. Normally, we would _move_ the ownership of `buf` by returning it to the caller. When using `Cow`, we want to _move_ the ownership of `buf` into the `Cow` type and return that.

```rust
use std::borrow::Cow;

fn remove_spaces<'a>(input: &'a str) -> Cow<'a, str> {
    if input.contains(' ') {
        let mut buf = String::with_capacity(input.len());

        for c in input.chars() {
            if c != ' ' {
                buf.push(c);
            }
        }

        return Cow::Owned(buf);
    }

    return Cow::Borrowed(input);
}
```

Our function now checks to see if the given `input` contains a space and only then allocates memory for a new buffer. If the `input` does not contain a space, the `input` is simply returned. We are adding a bit of [runtime complexity][Big O] to optimize how we allocate memory. Notice that our `Cow` type has the same lifetime of the `&str` type. As we discussed previously, the compiler needs to track the `&str` reference to know when it can safely free (or `Drop`) the memory.

The beauty of `Cow` is that it implements the `Deref` trait so you can call immutable functions without knowing whether or not the result is a new string buffer or not. Example:

```rust
let s = remove_spaces("Herman Radtke");
println!("Length of string is {}", s.len());
```

If I do need to mutate `s`, then I can convert it into an _owned_ variable using the `into_owned()` function. If the variant of `Cow` was already `Owned` then we are simply moving ownership. If the variant of `Cow` is `Borrowed`, then we are allocating memory. This allows us to lazily clone (allocate memory) only when we want to write (or mutate) the variable.


Example where a `Cow::Borrowed` is mutated:

```rust
let s = remove_spaces("Herman"); // s is a Cow::Borrowed variant
let len = s.len(); // immutable function call using Deref
let owned: String = s.into_owned(); // memory is allocated for a new string
```

Example where a `Cow::Owned` is mutated:

```rust
let s = remove_spaces("Herman Radtke"); // s is a Cow::Owned variant
let len = s.len(); // immutable function call using Deref
let owned: String = s.into_owned(); // no new memory allocated as we already had a String
```

The idea behind `Cow` is two-fold:

   1. Delay the allocation of memory for as long as possible. In the best case, we never have to allocate any new memory.
   1. Allow the caller of our `remove_spaces` function to not care if memory was allocated or not. The usage of the `Cow` type is the same in either case.

### Leveraging the `Into` Trait

We previously discussed using the [`Into` trait][Into<String>] to convert a `&str` into a `String`. We can also use the `Into` trait to convert the `&str` or `String` into the proper `Cow` variant. By calling `.into()` the compiler will perform the conversion automatically. Using `.into()` will not speed up or slow down the code. It is simply an option to avoid having to specify `Cow::Owned` or `Cow::Borrowed` explicitly.

```rust
fn remove_spaces<'a>(input: &'a str) -> Cow<'a, str> {
    if input.contains(' ') {
        let mut buf = String::with_capacity(input.len());
        let v: Vec<char> = input.chars().collect();

        for c in v {
            if c != ' ' {
                buf.push(c);
            }
        }

        return buf.into();
    }
    return buf.into();
}
```

We can also clean this up a bit using just iterators:

```rust
fn remove_spaces<'a>(input: &'a str) -> Cow<'a, str> {
    if input.contains(' ') {
        input
        .chars()
        .filter(|&x| x != ' ')
        .collect::<std::string::String>()
        .into()
    } else {
        input.into()
    }
}
```

## Real World Uses of `Cow`

My example of removing spaces may seem a bit contrived, but there are some great real-world applications of this strategy. Inside of Rust core there is a function that [converts bytes to UTF-8 in a lossy manner][from_utf8_lossy] and a function that will [translate CRLF to LF][translate_crlf]. Both of these functions have a case where a `&str` can be returned in the optimal case and another case where a `String` has to be allocated. Other examples I can think of are properly encoding an xml/html string or properly escaping a SQL query. In many cases, the input is already properly encoded or escaped. In those cases, it is better to just return the input string back to the caller. When the input does need to be modified we are forced to allocate new memory, in the form of a String buffer, and return that to the caller.

## Why use `String::with_capacity()` ?

While we are on the topic of efficient memory management, notice that I used `String::with_capacity()` instead of `String::new()` when creating the string buffer. You can use `String::new()` instead of `String::with_capacity()`, but it is more efficient to allocate memory for the buffer all at once instead of re-allocating memory as we push more `char`s onto the buffer. Let us walk through what Rust does when we use `String::new()` and then push characters onto the string.

A `String` is really a `Vec` of UTF-8 code points. When `String::new()` is called, Rust creates a vector with zero bytes of capacity. If we then push the character `a` onto the string buffer, like `input.push('a')` , Rust has to increase the capacity of the vector. In this case, it will allocate 2 bytes of memory. As we push more characters and exceed the capacity, Rust will double the size of the string by re-allocating memory. It will continue to double the size each time the capacity is exceeded. The sequence of memory allocation is `0, 2, 4, 8, 16, 32 ... 2^n` where n is the number of times Rust detected that capacity was exceeded. Re-allocating memory is really slow (edit: kmc_v3 [explained][kmc_v3 comment] that it might not be as slow as I thought). Not only does Rust have to ask the kernel for new memory, it must also copy the contents of the vector from the old memory space to the new memory space. Check out the source code for [Vec::push][Vec::push] to see the resizing logic first-hand.

In general, we want to allocate new memory only when we need it and only allocate as much as we need. For small strings, like `remove_spaces("Herman Radtke")`, the overheard of re-allocating memory is not a big deal. What if I wanted to remove all of the spaces in each JavaScript file for my website? The overhead of re-allocating memory for a buffer is much higher. When pushing data onto a vector (String or otherwise) it can be a good idea to specify a capacity to start with. The best situation is when you already know the length and the capacity can be exactly set. The [code comments][Vec code comments] for `Vec` give a similar warning.

## Related

   * [String vs &str in Rust functions](http://hermanradtke.com/2015/05/03/string-vs-str-in-rust-functions.html)
   * [Creating a Rust function that accepts String or &str](http://hermanradtke.com/2015/05/06/creating-a-rust-function-that-accepts-string-or-str.html)


[Cow]: https://doc.rust-lang.org/stable/std/borrow/enum.Cow.html
[Big O]: https://en.wikipedia.org/wiki/Analysis_of_algorithms
[from_utf8_lossy]: https://github.com/rust-lang/rust/blob/720735b9430f7ff61761f54587b82dab45317938/src/libcollections/string.rs#L153
[translate_crlf]: https://github.com/rust-lang/rust/blob/c23a9d42ea082830593a73d25821842baf9ccf33/src/libsyntax/parse/lexer/mod.rs#L271
[Vec::push]: https://github.com/rust-lang/rust/blob/720735b9430f7ff61761f54587b82dab45317938/src/libcollections/vec.rs#L628
[Vec code comments]: https://github.com/rust-lang/rust/blob/720735b9430f7ff61761f54587b82dab45317938/src/libcollections/vec.rs#L147-152
[Into<String>]: /2015/05/06/creating-a-rust-function-that-accepts-string-or-str.html
[kmc_v3 comment]: http://www.reddit.com/r/rust/comments/37q8sr/creating_a_rust_function_that_returns_a_str_or/croylbu

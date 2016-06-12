---
layout: post
title: "Strategies for solving 'cannot move out of' borrowing errors in Rust"
tags:
- rustlang
status: publish
type: post
published: true
---

The rules around [references and borrowing][references and borrowing] in Rust are fairly straight-forward. Given an owned variable, we are allowed to have as many _immutable_ references to that variable as we want. Rust defaults to immutability, so even functions like [trim][trim] are written in such a way that the result is a reference to the original string:

```rust
fn main() {
   let name = " Herman ".to_string();
   let trimmed_name = name.trim(); // == &[1..n-1]
}
```

The only caveat is that I cannot _move_ the `name` variable anymore. If I try to move `name`, the compiler will give me an error: _cannot move out of `name` because it is borrowed_.

```rust
fn main() {
   let name = " Herman ".to_string();
   let trimmed_name = name.trim();

   let owned_name = name; // move error
}
```

The compiler knows that `trimmed_name` is a reference to `name`. As long as `trimmed_name` is still in scope, the compiler will not let us pass `name` to a function, reassign it or do any other _move_ operation. We could `clone()` the `name` variable and then trim it, but we really just want to let the compiler know when we are done _borrowing_ `name`. The key word here is _scope_. If the reference to `name` goes out of scope, the compiler will let us _move_ `name` because it is no longer being _borrowed_. Let us wrap the call to `trim()` in curly braces to denote a different scope.

```rust
fn main() {
   let name = " Herman ".to_string();

   {
      let trimmed_name = name.trim();
   }

   let owned_name = name;
}
```

That is simple enough, but let us take it a step further. Suppose we wanted to get back the length of the trimmed string from within our scope. If we do that inside our curly braces, then `trimmed_name_len` will no longer exist once we leave that scope.

```rust
fn main() {
   let name = " Herman ".to_string();

   {
      let trimmed_name = name.trim();
      let trimmed_name_len = trimmed_name.len();
   }

   println!("Length of trimmed string is {}", trimmed_name_len); // no such variable error
   let owned_name = name;
}
```

## Strategies

There are a few ways to deal with this. They all look pretty similar, but have different trade-offs. We can return the value from a scoped block of code:

```rust
fn main() {
   let name = " Herman ".to_string();

   let trimmed_name_len = {
      let trimmed_name = name.trim();
      trimmed_name.len()
   };

   println!("Length of trimmed string is {}", trimmed_name_len);
   let owned_name = name;
}
```

This is a cheap and quick way to force the reference to go out of scope. It does not require us to specify parameters or their types nor does it require us to specify the return type. It is not reusable though. We can get some more reuse if we use an anonymous function (or closure):

```rust
fn main() {
   let name = " Herman ".to_string();

   let f = |name: &str| {
      let trimmed_name = name.trim();
      trimmed_name.len()
   };

   let trimmed_name_len = f(&name);

   println!("Length of trimmed string is {}", trimmed_name_len);
   let owned_name = name;
}
```

A closure requires us to specify parameters and their types, but makes specifying the return type optional. The way this is written, the anonymous function `f` is only usable within the function scope. If we want complete reusuability we can use a normal function:

```rust
fn len_of_trimmed_string(name: &str) -> usize {
      let trimmed_name = name.trim();
      trimmed_name.len()
}

fn main() {
   let name = " Herman ".to_string();

   let trimmed_name_len = len_of_trimmed_string(name.as_ref());

   println!("Length of trimmed string is {}", trimmed_name_len);
   let owned_name = name;
}
```

These strategies only work if we are calling immutable functions. We are temporarily keeping the reference to get some other peice of information. This works really well that information is something like implements the `Copy` trait, such as numbers or booleans. If we wanted to do something like remove all spaces on a string like `"H e r m a n"` then we are mutating the string. We would have to call `name.clone()` in order to later _move_ the original `name` variable.

### Closure Without Parameters

You may have wondered if we really did have to specify parameters when using a closure. If we try to access the `name` variable from within the closure, it will create a reference during compile time. That reference will continue to exist, even if we try to remove the closure `f` from scope. Example:

```rust
fn main() {
   let name = " Herman ".to_string();

   let f = || {
      let trimmed_name = name.trim();
      trimmed_name.len()
   };

   let trimmed_name_len = f();

   println!("Length of trimmed string is {}", trimmed_name_len);
   let owned_name = name; // move error
}
```

```
error: cannot move out of `name` because it is borrowed
   let owned_name = name;
               ^~~~~~~~~~
note: borrow of `name` occurs here
    let f = || {
       let trimmed_name = name.trim();
       trimmed_name.len()
    };
note: in expansion of closure expansion
```

## Real World Example

The above examples are pretty contrived. However, you will run into this when you are breaking down functions into smaller parts. In this below example, I was using a `find_matches` function that required an input of type `&str`. Given a `PathBuf`, I needed to call the immutable `file_name()` method on it and then convert it to a `&str` by calling `to_str()` before calling `find_matches(file_name)`. In order to return a tuple of `(p, matches)`, I had to make sure reference created by `file_name` was out of scope. I chose to use a function, but could have use curly braces or a closure as we discussed above.

```rust
fn find_matches(s: &str) -> f64 {
   // ...
}

fn count_filename_matches(path: &Path) -> f64 {
    let file_name = path.file_name()
        .and_then(|f| f.to_str())
        .unwrap_or_else(|| {
            debug!("Unable to determine filename for {:?}", path);
            ""
        });

    find_matches(file_name)
}

fn find_filename_matches_in_path(path: &str) -> Vec<(PathBuf, f64)> {
    fs::read_dir(path).unwrap()
        .map(|p| p.unwrap().path())
        .map(|p| {
            let matches = count_filename_matches(p.as_ref(), cmd);
            (p, matches)
        })
        .filter(|&(ref _p, matches)| {
            matches > 0.0
        })
        .collect()
}
```

[references and borrowing]: https://doc.rust-lang.org/stable/book/references-and-borrowing.html#the-rules
[trim]: https://doc.rust-lang.org/stable/std/primitive.str.html#method.trim

---
layout: default
title: "simple_parallel 0.3: Revisiting k-NN"
description: >
    Two examples of using `simple_parallel`, which was recently
    updated to work on stable Rust.

comments:
    r_rust: "https://www.reddit.com/r/rust/comments/3px8y9/simple_parallel_03_revisiting_knn/"
    users: "https://users.rust-lang.org/t/simple-parallel-0-3-revisiting-k-nn/3383"

---

I recently released version 0.3 of my
[`simple_parallel`][simple_parallel] crate, which builds on
[Aaron Turon's `crossbeam`][crossbeam] to resolve
[the stability and safety difficulties][safstab]: the crate now works
with Rust 1.3.0 stable, and offers safe data-parallel `for` loops and
`map`s.

I still don't recommend it for general use, but I think it's a neat
demonstration of what Rust's type system allows, and hopefully
inspiration for something awesome.

[crossbeam]: https://crates.io/crates/crossbeam
[simple_parallel]: https://crates.io/crates/simple_parallel
[safstab]: https://users.rust-lang.org/t/simple-parallel-now-partially-compiles-on-stable/1536
[comparing]: {% post_url 2014-06-10-comparing-knn-in-rust %}
[1.0]: http://blog.rust-lang.org/2015/05/15/Rust-1.0.html
[crates]: https://crates.io/
[better-send]: https://github.com/rust-lang/rfcs/blob/master/text/0458-send-improvements.md
[files]: https://github.com/c4fsharp/Dojo-Digits-Recognizer/tree/1eb4297a49dbd82a952c1523f5413519b8f1d62a/Dojo

<div class="centered-libs">
{% include rust-lib.html name="simple_parallel" inline=true %}
</div>

## `simple_parallel` in 16 lines

Taster: safely setting the values in an array stored directly on the
stack of a parent thread, in parallel, with 4 threads.

{% highlight rust linenos %}
// (add `simple_parallel = "0.3"` to your Cargo.toml)
extern crate simple_parallel;

fn main() {
    let mut pool = simple_parallel::Pool::new(4);

    let mut stack_array = [0; 10];

    let large_complicated_thing = vec![4, 3, 2, 1];

    pool.for_(stack_array.iter_mut().enumerate(), |(i, elem)| {
        *elem = large_complicated_thing[i % 4]
    });

    println!("{:?}", &stack_array);
}
{% endhighlight %}

This is the same as writing `for (i, elem) in
stack_array.iter_mut().enumerate() { ... }`, and the output is:
`[4, 3, 2, 1, 4, 3, 2, 1, 4, 3]`.

It is a rather complicated way to initialise an array with those
values, but it demonstrates some nice properties:

- `stack_array` is **allocated directly on the stack of the main thread**;
  it doesn't need to be pushed to the heap. Lifetimes and
  `simple_parallel`'s API ensures that the subthreads can't hold
  references to it for too long statically (no GC necessary).
- the `large_complicated_thing` `Vec` is safely shared between all
  threads, no copies necessary. Each thread gets a `&Vec<_>`
  reference, and they all point to the same `large_complicated_thing`
  value stored on the main thread's stack. Again lifetimes ensure that
  the references won't be dangling, but more interestingly the vector
  can be read without needing to copy or lock: **zero-overhead
  immutable shared data**.
- the `iter_mut` method creates an iterator over `&mut` references to
  the elements of `stack_array`. The closure is called on each of them
  in parallel, and the references are
  disjoint/not-aliasing[^cache-line], meaning each call is
  manipulating a different section of memory. **No atomics or locks
  are needed** to mutate what the iterator feeds the closure.
- the `simple_parallel` APIs all consume (nearly) arbitrary iterators:
  I can take the slice iterator and create a new (lazy) iterator via
  `enumerate`, pairing the output of the slice iterator with
  indices. (There are of course restrictions about the thread-safety
  properties of the iterator and its elements, necessary to get points
  above safely.)


Some of this is driven by `simple_parallel`, some of it is
`crossbeam`, but most of it is the power of Rust's type system: it
[comes together just right][right] to ensure[^not-proved]
[concurrency can be done fearlessly][fearless].

[fearless]: http://blog.rust-lang.org/2015/04/10/Fearless-Concurrency.html

[^cache-line]: The pointers are disjoint, so safety/semantically
               everything is cool, but in the real world there are
               performance concerns, like false sharing: the values
               are all adjacent in memory and so probably share a
               cache-line. In practice, this shouldn't be a problem:
               either the time to compute each value will be
               significant, so the false sharing hit is irrelevant, or
               one doesn't need to/shouldn't parallelise at the level
               of individual elements.

[^not-proved]: Strictly speaking, "ensure" isn't quite right: there's
               not a formal proof that `Send`/`Sync`/... all do have
               this guarantee, but there is work on
               [formalisations of Rust][formal] that will either
               tackle this directly, or form important groundwork.

[right]: {% post_url 2015-02-20-some-notes-on-send-and-sync %}
[formal]: https://www.ralfj.de/blog/2015/10/12/formalizing-rust.html

It's not perfect, it's not even *great*&mdash;there's
unnecessary overhead and it doesn't offer many operations&mdash;but
has been useful for me (e.g. speeding up processing some pictures just
required replacing `for photo in photos` with `pool.for_(photos,
|photo|`) and serves as a neat little exploration into Rust's type
system. I'm confident we'll see better libraries from better
programmers that allow for some magical things.

## *k*-NN

The very first post on this blog was
[*Comparing k-NN in Rust*][comparing], which ended with parallelising
the task of validating a *k*-nearest neighbour (*k*-NN) classifier,
using the safe-but-crude tools Rust-circa-0.11 offered at the time. We
now live in a promised land, with [language stability][1.0],
[Cargo & thousands of crates][crates], and
[`Send` without `'static`][better-send], so there's shiny new
safe-and-less-crude tools!

The example above disguised the role of `crossbeam`, but the
`simple_parallel`/`crossbeam` combo means it's easy to process a
stream in parallel, sharing data from parent threads with no overhead
at all. The *k*-NN code loads [two files][files] into `Vec`s of
784-dimensional "pixels" via `slurp_file`&mdash;one of 5000 pixels of training
data and one of 500 samples to test the classifier against&mdash;and then
uses the `classify` function to predict a label for each of the
validation samples based on the training ones, finally printing how
many were predicted correctly.

The full code is available at [huonw/revisiting-knn][repo], updated
from 0.11.0 (which wasn't too hard at all[^update]), so I'm just going
to focus on the interesting bit: `main`. The sequential version is
short:

[^update]: This code is pretty simple, so was barely affected by
           language/library changes: some import paths changed, some
           imports became necessary and others could be dropped, and
           all the `.as_slice()` calls disappeared.

[repo]: https://github.com/huonw/revisiting-knn

{% highlight rust linenos %}
fn main() {
    let training_set = slurp_file("trainingsample.csv");
    let validation_sample = slurp_file("validationsample.csv");

    let num_correct = validation_sample.iter()
        .filter(|x| classify(&training_set, &x.pixels) == x.label)
        .count();

    println!("Percentage correct: {:.1}%",
             num_correct as f64 / validation_sample.len() as f64 * 100.0);
}
{% endhighlight %}

All the work is happening in the `filter` call: the `classify`
function is the expensive one: each call does 5000 784-dimensional
[vector distance calculations][dist]. `perf`'s instruction level
profiling tells me that nearly 95% of the time is spent in
[the loop][loop][^simd] for that calculation (which actually gets inlined all
the way into `main` itself).

[dist]: https://github.com/huonw/revisiting-knn/blob/219ad78a9b15554b10d08c4e626e11e09256b8dd/src/main.rs#L44
[loop]: https://github.com/huonw/revisiting-knn/blob/219ad78a9b15554b10d08c4e626e11e09256b8dd/src/main.rs#L36

[^simd]: The code is actually slower than strictly necessary: if the
         `fold` is separated into `.map(|(&a, &b)| a - b).fold(0, |s,
         d| s + d * d)`, it is autovectorised by LLVM to use SIMD
         instructions and runs twice as fast. However, I decided
         against doing this in the spirit of Rust 1.3 v. Rust 0.11
         comparisons: IIRC the old code didn't get SIMD-ified.

The parallel `main` isn't much longer:

{% highlight rust linenos %}
fn main() {
    // load files
    let training_set = slurp_file("trainingsample.csv");
    let validation_sample = slurp_file("validationsample.csv");

    // create a thread pool
    let mut pool = simple_parallel::Pool::new(4);

    crossbeam::scope(|scope| {
        let num_correct =
            pool.unordered_map(scope, &validation_sample, |x| {
                // is it classified right? (in parallel)
                classify(&training_set, &x.pixels) == x.label
            })
            .filter(|t| t.1)
            .count();

        println!("Percentage correct: {:.1}%",
                 num_correct as f64 / validation_sample.len() as f64 * 100.0);
    });
}
{% endhighlight %}

[umap]: http://huonw.github.io/simple_parallel/simple_parallel/pool/struct.Pool.html#method.unordered_map
[map]: http://huonw.github.io/simple_parallel/simple_parallel/pool/struct.Pool.html#method.map

The [`unordered_map`][umap] function is a bit more complicated than
`for_` above: this takes an iterator over `A`s, and a function from
`A` to any type `B`, and returns an iterator of `(usize, B)`s, in some
random order[^order]. For above, `B` is a `bool`: whether the
predicted classification was correct or not.

[^order]: There's also [the plain old `map` function][map], which is
          careful to return the elements in the same order as they
          were in the original iterator. This is a bit more expensive.

The hardest part of parallelising that was working out where to put
the `crossbeam::scope`: as I wrote it above, or `let num_correct =
crossbeam::scope(...);`. It was correct and ran in parallel the first
time!

Interestingly, this code benefits greatly from being able to share
stacks: firstly, each `x` in the loop is just a pointer into the
`validation_sample` `Vec`, it can point right to the large chunk of
memory (for a 784D vector) owned by the main thread without having to
copy. Secondly, and even better, all the parallel `classify` calls can
read share the one huge `training_set` array without needing to copy
it, which is 5000 of those high-dimensional vectors.


### Numbers

Discussing parallelism means nothing without proving it is doing
something useful: making things run faster. The sequential code took
1.86s, and the parallel version slashed that to 0.69s, 2.7&times; faster.

I'm running 1.3.0 stable, and compiled the [the code][repo] with
`cargo build --release --features sequential` and `cargo build
--release` for the two `main` functions above, the rest of the code
stayed the same. I measured the time to run with `perf stat -r 5
...`.

I'm on a different/faster computer to the [previous post][comparing],
and the original Rust code no longer compiles. However, the OCaml code
still does: with the same compiler, it takes approximately 8.5 seconds
on this one, about 1.6-1.7&times; faster. The sequential Rust code is
nearly 2&times; faster than the old version&mdash;meaning the
compiler/standard library has likely improved&mdash;and the parallel
version even more... but this computer has more cores so the
comparison isn't so interesting.

## `crossbeam::scope`

The key trick that allowed me to get the APIs to be safe is
[this `scope` function][scope]. It was somewhat infamously
[realised][24292] that destructors cannot be relied upon for
scope-based memory safety: it is possible to leave a scope without
running a destructor, in safe code, e.g. get the value stuck in a
reference cycle of `Rc`s. This means that if a library ever hands away
an instance of something with a destructor, it has to be sure that
things won't go completely wrong if that destructor never executes.

The alternative used in `crossbeam` was
[described in a Rust RFC][take2] (that never landed in Rust itself)
written by Aaron, `crossbeam`'s author. The approach is to be a
control freak: never let anyone else control your value, only hand off
`&` references to it, so what runs when is in your power, and yours
alone. This is what `scope` does,

Its signature is:

{% highlight rust linenos %}
pub fn scope<'a, F, R>(f: F) -> R
    where F: FnOnce(&Scope<'a>) -> R
{% endhighlight %}

That is, `scope` takes one argument, which is a closure, and then
passes a reference to a [`Scope`][scope_] to that closure. This
`Scope` object allows for spawning threads/deferring functions, with
the guarantee that the thread will exit/the function will run before
`scope` returns.

Only the iterator *adapters* like `unordered_map` (rather than
consumers like `for_`) in `simple_parallel` need to think about this
externally: they act asynchronously, and so return an object that
can't live too long and needs to control the threads spawned to do the
parallel processing, where as the consumers can just block. By taking
a `Scope` argument, these iterator adapters can defer functions that
do the thread control, giving the nice iterator APIs with a fairly
minimal usage overhead (wrapping the calls in a closure and passing an
extra argument).

[24292]: https://github.com/rust-lang/rust/issues/24292
[scope]: http://aturon.github.io/crossbeam-doc/crossbeam/fn.scope.html
[scope_]: http://aturon.github.io/crossbeam-doc/crossbeam/struct.Scope.html
[take2]: https://github.com/aturon/rfcs/blob/75db90de40849d7cd28e334388ffa74b9e7a9bcf/text/0000-scoped-take-2.md

{% include comments.html c=page.comments %}

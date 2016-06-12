---
layout: default
title: Comparing k-NN in Rust
description: >
    Implementing a k-nearest neighbour algorithm in Rust, using the
    powerful concurrency tools for simple and safe parallelisation.

comments:
    r_rust: "http://www.reddit.com/r/rust/comments/27s7ei/comparing_knn_in_rust/"
    r_programming: "http://www.reddit.com/r/programming/comments/27s7g6/comparing_knn_in_rust/"
    hn: "https://news.ycombinator.com/item?id=7872398"
---

In my voyages around the internet, I came across [a pair][original] of
[blog posts][followup] which compare the implementation of a
*k*-nearest neighbour (*k*-NN) classifier in F# and OCaml. I couldn't
resist writing the code into [Rust][rust] to see how it fared.

[original]: http://philtomson.github.io/blog/2014/05/29/comparing-a-machine-learning-algorithm-implemented-in-f-number-and-ocaml/
[followup]: http://philtomson.github.io/blog/2014/05/30/stop-the-presses-ocaml-wins/
[rust]: http://rust-lang.org/

Rust is a memory-safe systems language under heavy development; this
code compiles with [the latest nightly][nightly] (as of 2014-06-10 12:00 UTC),
specifically `rustc 0.11.0-pre-nightly (e55f64f 2014-06-09 01:11:58
-0700)`.

[nightly]: http://www.rust-lang.org/install.html

## Code

The Rust code is a nearly-direct translation of the original F# code,
the only change was changing `distance` to compute the squared
distance, that is, `a*a + b*b + ...` (square root is strictly
increasing, yo).

For clarity, all errors are ignored (that's the `.unwrap()` calls):
the input is assumed to be valid and IO is assumed to succeed. I wrote
[a follow-up post describing how one would handle errors][errorhandling]. Also,
I made no effort to remove/reduce/streamline allocations.

[errorhandling]: {% post_url 2014-06-11-error-handling-in-rust-knn-case-study %}

{% highlight rust linenos %}
use std::io::{File, BufferedReader};

struct LabelPixel {
    label: int,
    pixels: Vec<int>
}


fn slurp_file(file: &Path) -> Vec<LabelPixel> {
    BufferedReader::new(File::open(file).unwrap())
        .lines()
        .skip(1)
        .map(|line| {
            let line = line.unwrap();
            let mut iter = line.as_slice().trim()
                .split(',')
                .map(|x| from_str(x).unwrap());

            LabelPixel {
                label: iter.next().unwrap(),
                pixels: iter.collect()
            }
        })
        .collect()
}

fn distance_sqr(x: &[int], y: &[int]) -> int {
    // run through the two vectors, summing up the squares of the differences
    x.iter()
        .zip(y.iter())
        .fold(0, |s, (&a, &b)| s + (a - b) * (a - b))
}

fn classify(training: &[LabelPixel], pixels: &[int]) -> int {
    training
        .iter()
        // find element of `training` with the smallest distance_sqr to `pixel`
        .min_by(|p| distance_sqr(p.pixels.as_slice(), pixels)).unwrap()
        .label
}

fn main() {
    let training_set = slurp_file(&Path::new("trainingsample.csv"));
    let validation_sample = slurp_file(&Path::new("validationsample.csv"));

    let num_correct = validation_sample.iter()
        .filter(|x| {
            classify(training_set.as_slice(), x.pixels.as_slice()) == x.label
        })
        .count();

    println!("Percentage correct: {}%",
             num_correct as f64 / validation_sample.len() as f64 * 100.0);
}
{% endhighlight %}

(Prints `Percentage correct: 94.4%`, matching the OCaml.)


## How's it compare?

I don't have an F# compiler, so I'll only compare against the fastest
OCaml solution (from [the follow-up post][followup]), after making the
same modification to `distance`.

The Rust was compiled with `rustc -O`, and the OCaml with `ocamlopt
str.cmxa` (as recommended), using version 4.01.0. I ran each 3 times
(times in seconds) on [these CSV files][csv].

[csv]: https://github.com/c4fsharp/Dojo-Digits-Recognizer/tree/1eb4297a49dbd82a952c1523f5413519b8f1d62a/Dojo

| Lang  | 1    | 2    | 3    |
|------:|-----:|-----:|-----:|
| Rust  | 3.56 | 3.46 | 3.86 |
| OCaml | 13.9 | 14.7 | 14.1 |

So the Rust code is about 3.5&ndash;4&times; faster than the
OCaml.

It's worth noting that the Rust code is entirely safe and built
directly (and mostly minimally) using the abstractions provided by the
standard library. The speed is mainly due to the magic of
[Rust's (lazy) iterators](http://doc.rust-lang.org/master/std/iter/)
which provide very efficient sequential access to elements of
vectors/slices, as well as a variety of efficient
[adaptors](http://doc.rust-lang.org/master/guide-container.html#iterator-adaptors)
implementing various useful algorithms. These may look high-level and
hard to optimise, but they are very transparent to the compiler,
resulting in fast machine code.

> *Updated 2014-06-11*: the Rust code is not as fast as it could be,
> due to bugs like
> [#11751](https://github.com/mozilla/rust/issues/11751), caused by
> LLVM being unable to understand that `&` pointers are never
> null. benh wrote a [short slice-zip iterator][slicezip] that may
> make its way into the standard library: he even
> [used it](https://news.ycombinator.com/item?id=7875969) to make the
> code 3 times faster.

[slicezip]: https://gist.github.com/huonw/7b7473ac3981fead07ab


In comparison, the OCaml code has had to manually write a few
functions (for folding and for reading lines from a file), and
contains two possibly-concerning pieces of code:

{% highlight ocaml linenos %}
let v1 = unsafe_get a1 i in
let v2 = unsafe_get a2 i in
{% endhighlight %}


It might be interesting to compare against
[this D code](http://leonardo-m.livejournal.com/111598.html), but I
can't get it to compile right.

## What about parallelism?

I'm glad you asked! Rust is designed to be good for concurrency, using
[the type system](http://doc.rust-lang.org/master/std/kinds/trait.Share.html)
to guarantee that code is threadsafe. As I said before, Rust is under
heavy development, and currently lacks a data parallelism library (so
there's no parallel-map to just call directly yet), but it's easy
enough to use
[the built-in futures](http://doc.rust-lang.org/master/sync/struct.Future.html)
for this.

The code can be made parallel simply by replacing the `main` function
with the following.

{% highlight rust linenos %}
// how many chunks should the validation sample be divided into? (==
// how many futures to create.)
static NUM_CHUNKS: uint = 32;

fn main() {
    use sync::{Arc, Future};
    use std::cmp;

    // "atomic reference counted": guaranteed thread-safe shared
    // memory. The type signature and API of `Arc` guarantees that
    // concurrent access to the contents will be safe, due to the `Share`
    // trait.
    let training_set = Arc::new(slurp_file(&Path::new("trainingsample.csv")));
    let validation_sample = Arc::new(slurp_file(&Path::new("validationsample.csv")));

    let chunk_size = (validation_sample.len() + NUM_CHUNKS - 1) / NUM_CHUNKS;

    let mut futures = range(0, NUM_CHUNKS).map(|i| {
        // create new "copies" (just incrementing the reference
        // counts) for our new future to handle.
        let ts = training_set.clone();
        let vs = validation_sample.clone();

        Future::spawn(proc() {
            // compute the region of the vector we are handling...
            let lo = i * chunk_size;
            let hi = cmp::min(lo + chunk_size, vs.len());

            // ... and then handle that region.
            vs.slice(lo, hi)
                .iter()
                .filter(|x| {
                    classify(ts.as_slice(), x.pixels.as_slice()) == x.label
                })
                .count()
        })
    }).collect::<Vec<Future<uint>>>();

    // run through the futures (waiting for each to complete) and sum the results
    let num_correct = futures.mut_iter().map(|f| f.get()).fold(0, |a, b| a + b);

    println!("Percentage correct: {}%",
             num_correct as f64 / validation_sample.len() as f64 * 100.0);
}
{% endhighlight %}

(Also prints `Percentage correct: 94.4%`.)

This gives a nice speed up, approximately halving the time required:
the real time is now stable around 1.81 seconds (6.25 s of user time)
on my machine.

{% include comments.html c=page.comments %}

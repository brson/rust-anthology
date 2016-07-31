# TOC

- Forward
- About the Authors
- Introduction
  - [Understanding Over Guesswork](https://www.hoverbear.org/2015/09/12/understand-over-guesswork/)
  - [An Alternative Introduction to Rust](http://words.steveklabnik.com/a-new-introduction-to-rust)
- Ownership
  - [Where Rust Really Shines](https://manishearth.github.io/blog/2015/05/03/where-rust-really-shines/)
  - [Rust Means Never Having to Close a Socket](http://blog.skylight.io/rust-means-never-having-to-close-a-socket/)
  - [The Problem with Single-threaded Shared Mutability](https://manishearth.github.io/blog/2015/05/17/the-problem-with-shared-mutability/)
  - [Rust Ownership the Hard Way](https://chrismorgan.info/blog/rust-ownership-the-hard-way.html)
  - [Strategies for Solving "cannot move out of" Borrowing Errors](http://hermanradtke.com/2015/06/09/strategies-for-solving-cannot-move-out-of-borrowing-errors-in-rust.html)
  - Interior Mutability In Rust
    - [Interior mutability in Rust: what, why, how?](https://ricardomartins.cc/2016/06/08/interior-mutability)
    - [Interior mutability in Rust, part 2: thread safety](https://ricardomartins.cc/2016/06/25/interior-mutability-thread-safety)
    - [Interior mutability in Rust, part 3: behind the curtain](https://ricardomartins.cc/2016/07/11/interior-mutability-behind-the-curtain)
  - [`&` vs. `ref` in Patterns](http://xion.io/post/code/rust-patterns-ref.html)
  - Holy `std::borrow::Cow`
    - [Holy `std::borrow::Cow`!](https://llogiq.github.io/2015/07/09/cow.html)
    - [Holy `std::borrow::Cow`!](https://llogiq.github.io/2015/07/10/cow-redux.html)
- Concurrency
  - [Fearless Concurrency with Rust](http://blog.rust-lang.org/2015/04/10/Fearless-Concurrency.html)
  - [How Rust Achieves Thread Safety](https://manishearth.github.io/blog/2015/05/30/how-rust-achieves-thread-safety/)
  - [Defaulting to Thread-safety: Closures and Concurrency](https://huonw.github.io/blog/2015/05/defaulting-to-thread-safety/)
  - [Some Notes on `Send` and `Sync`](https://huonw.github.io/blog/2015/02/some-notes-on-send-and-sync/)
  - Niko's Rayon Trilogy
    - [Rayon: Data Parallism in Rust](http://smallcultfollowing.com/babysteps/blog/2015/12/18/rayon-data-parallelism-in-rust/)
    - [Parallel Iterators in Rust Part 1: Foundations](http://smallcultfollowing.com/babysteps/blog/2016/02/19/parallel-iterators-part-1-foundations/)
    - [Parallel Iterators in Rust Part 2: Producers](http://smallcultfollowing.com/babysteps/blog/2016/02/25/parallel-iterators-part-2-producers/)
- Traits
  - [Abstraction Without Overhead](https://blog.rust-lang.org/2015/05/11/traits.html)
  - [Going Down the Rabbit Hole with Rust Traits](http://www.jonathanturner.org/2016/02/down-the-rabbit-hole-with-traits.html)
  - Huon's Trait Object Quadrilogy
    - [Peeking Inside Trait Objects](https://huonw.github.io/blog/2015/01/peeking-inside-trait-objects/)
    - [The `Sized` Trait](https://huonw.github.io/blog/2015/01/the-sized-trait/)
    - [Object Safety](http://huonw.github.io/blog/2015/01/object-safety/)
    - [Where `Self` meets `Sized`: Revisiting Object Safety](https://huonw.github.io/blog/2015/05/where-self-meets-sized-revisiting-object-safety/)
  - [Rust's Built-in Traits, the When, How & Why](https://llogiq.github.io/2015/07/30/traits.html)
  - [Rust Traits for Developer Friendly Libraries](https://benashford.github.io/blog/2015/05/24/rust-traits-for-developer-friendly-libraries/)
- The Rust Language
  - [Finding Closure in Rust](https://huonw.github.io/blog/2015/05/finding-closure-in-rust/)
  - [Mixing Matching, Mutations and Moves](https://blog.rust-lang.org/2015/04/17/Enums-match-mutation-and-moves.html)
  - [Reading Rust Function Signatures](http://hoverbear.org/2015/07/10/reading-rust-function-signatures/)
  - [Myths and Legends About Integer Overflow in Rust](https://huonw.github.io/blog/2016/04/myths-and-legends-about-integer-overflow-in-rust/)
  - [A Practical Introduction to Rust Macros](https://danielkeep.github.io/practical-intro-to-macros.html)
  - [Effectively Using Iterators in Rust](http://hermanradtke.com/2015/06/22/effectively-using-iterators-in-rust.html)
  - [A Journey Into Iterators](https://hoverbear.org/2015/05/02/a-journey-into-iterators/)
  - Macros In Rust
    - [Part 1](http://www.ncameron.org/blog/macros-in-rust-pt1/)
    - [Part 2](http://www.ncameron.org/blog/macros-in-rust-pt2/)
    - [Part 3](http://www.ncameron.org/blog/macros-in-rust-pt3/)
    - [Part 4](http://www.ncameron.org/blog/macros-in-rust-pt4/)
- `unsafe` Rust
  - [Unsafe Rust: An Intro and Open Questions](http://cglab.ca/~abeinges/blah/rust-unsafe-intro/)
  - [What Does Rust's `unsafe` Mean?](https://huonw.github.io/blog/2014/07/what-does-rusts-unsafe-mean/)
  - [Memory Leaks are Memory Safe](https://huonw.github.io/blog/2016/04/memory-leaks-are-memory-safe/)
  - [On Reference Counting and Leaks](http://smallcultfollowing.com/babysteps/blog/2015/04/29/on-reference-counting-and-leaks/)
  - [A Few More Remarks on Reference Counting and Leaks](http://smallcultfollowing.com/babysteps/blog/2015/04/30/a-few-more-remarks-on-reference-counting-and-leaks/)
  - [Pre-pooping Your Pants With Rust](http://cglab.ca/~abeinges/blah/everyone-poops/)
  - Tootsie-pop model
    - [Unsafe Abstractions](http://smallcultfollowing.com/babysteps/blog/2016/05/23/unsafe-abstractions/)
    - [The "Tootsie Pop" Model for Unsafe Code](http://smallcultfollowing.com/babysteps/blog/2016/05/27/the-tootsie-pop-model-for-unsafe-code/)
- Rust in Practice
  - [The Many Kinds of Code Reuse in Rust](http://cglab.ca/~abeinges/blah/rust-reuse-and-recycle/)
  - [Rust Error Handling](http://blog.burntsushi.net/rust-error-handling/)
  - [Why your first FizzBuzz implementation may not work](https://chrismorgan.info/blog/rust-fizzbuzz.html)
  - Herman Radtke's `String` Trilogy
    - [`String` vs. `&str` in Rust Functions](http://hermanradtke.com/2015/05/03/string-vs-str-in-rust-functions.html)
    - [Creating a Rust Function That Accepts `String` or `&str`](http://hermanradtke.com/2015/05/06/creating-a-rust-function-that-accepts-string-or-str.html)
    - [Creating a Rust Function That Returns `String` or `&str`](http://hermanradtke.com/2015/05/29/creating-a-rust-function-that-returns-string-or-str.html)
  - Gankro's Collections Trilogy
    - [Rust, Lifetimes, and Collections](http://cglab.ca/~abeinges/blah/rust-lifetimes-and-collections/)
    - [Rust, Generics, and Collections](http://cglab.ca/~abeinges/blah/rust-generics-and-collections/)
    - [Rust Collections Case Study: BTreeMap](http://cglab.ca/~abeinges/blah/rust-btree-case/)
  - [Learning Rust with Entirely Too Many Linked Lists](http://cglab.ca/~abeinges/blah/too-many-lists/book/)
  - [Working With C Unions in Rust FFI](http://hermanradtke.com/2016/03/17/unions-rust-ffi.html)
  - [Quick tip: the `#[cfg_attr]` attribute](https://chrismorgan.info/blog/rust-cfg_attr.html)
  - Using the `Option` Type Effectively
    - [Part 1](http://blog.8thlight.com/dave-torre/2015/03/11/the-option-type.html)
    - [Part 2](http://blog.8thlight.com/uku-taht/2015/04/29/using-the-option-type-effectively.html)
  - [Rust + Nix = Easier Unix Systems Programming](http://kamalmarhubi.com/blog/2016/04/13/rust-nix-easier-unix-systems-programming-3/)
- The Rust Toolbox
  - Travis on the Train
    - [Helping Travis Catch the `rustc` Train](http://huonw.github.io/blog/2015/04/helping-travis-catch-the-rustc-train/)
    - [Travis on the Train, Part 2](http://huonw.github.io/blog/2015/05/travis-on-the-train-part-2/)
  - [Rust, Travis and GitHub Pages](http://hoverbear.org/2015/03/07/rust-travis-github-pages/)
  - [Benchmarking In Rust](https://llogiq.github.io/2015/06/16/bench.html)
  - [Profiling Rust Applications on Linux](https://llogiq.github.io/2015/07/15/profiling.html)
- `mio`
  - [Getting Acquainted with `mio`](https://hoverbear.org/2015/03/03/getting-acquainted-with-mio/)
  - [My Basic Understanding of `mio` and Async I/O](http://hermanradtke.com/2015/07/12/my-basic-understanding-of-mio-and-async-io.html)
  - [Creating a Simple Protocol With `mio`](http://hermanradtke.com/2015/09/12/creating-a-simple-protocol-when-using-rust-and-mio.html)
  - [Managing Connection State With `mio`](http://hermanradtke.com/2015/10/23/managing-connection-state-with-mio-rust.html)
- Culture
  - [Stability as a Deliverable](https://blog.rust-lang.org/2014/10/30/Stability.html)
  - [The Not Rocket Science Rule of Software Engineering](http://graydon2.dreamwidth.org/1597.html)
  - RIIR
    - [Rewrite Everything In Rust](http://robert.ocallahan.org/2016/02/rewrite-everything-in-rust.html)
    - [Have You Considered Rewriting it In Rust?](http://transitiontech.ca/random/RIIR)
  - [Making Your Open Source Project Newcomer Friendly](http://manishearth.github.io/blog/2016/01/03/making-your-open-source-project-newcomer-friendly/)
  - [Rust Discovery, or: How I Figure Things Out](http://carol-nichols.com/2015/08/01/rustc-discovery/)
- Cheat Sheets
  - [Periodic Table of Rust Types](http://cosmic.mearie.org/2014/01/periodic-table-of-rust-types)
  - [Rust String Conversions Cheat Sheet](https://docs.google.com/spreadsheets/d/19vSPL6z2d50JlyzwxariaYD6EU2QQUQqIDOGbiGQC7Y/pubhtml?gid=0&single=true)
  - [Rust Iterator Cheat Sheet](https://danielkeep.github.io/itercheat_baked.html) - [Daniel Keep][]
- Additional Reading
  - [The Book](http://doc.rust-lang.org/nightly/book)
  - [The Nomicon](https://doc.rust-lang.org/nightly/nomicon/)
  - [Rust By Example](https://www.rustbyexample.com)
  - [Writing an OS in Rust](http://os.phil-opp.com/)
  - [Rust 101](https://www.ralfj.de/projects/rust-101/main.html)
  - [rustlings](https://github.com/carols10cents/rustlings)
  - [The Little Book of Rust Macros](https://danielkeep.github.io/tlborm/)
  - [The Rust FFI Omnibus](http://jakegoulding.com/rust-ffi-omnibus/?updated=2015-11-08) - Jake Goulding
- Uncategorized Chapters
  - [Why Is A Rust Executable Large?](https://lifthrasiir.github.io/rustlog/why-is-a-rust-executable-large.html)
  - [Wrapper Types in Rust: Choosing Your Guarantees](https://doc.rust-lang.org/book/choosing-your-guarantees.html)
  - [Rust Faster!](https://llogiq.github.io/2015/10/03/fast.html)
  - [Where Are You `From::from`?](https://llogiq.github.io/2015/11/27/from-into.html)
  - Type-level Shenanigans
    - [Type-level Shenanigans](https://llogiq.github.io/2015/12/12/types.html)
    - [More Type-level Shenanigans](https://llogiq.github.io/2016/02/23/moretypes.html)
  - [Rustic Bits](https://llogiq.github.io/2016/02/11/rustic.html)
  - [Mapping Over Arrays](https://llogiq.github.io/2016/04/28/arraymap.html)
  - [Rust for Functional Programmers](http://science.raphael.poss.name/rust-for-functional-programmers.html)
  - [From &str to Cow](http://blog.jwilm.io/from-str-to-cow/)
  - Graydon's Lists
    - [Five Lists of Six Things About Rust](http://graydon2.dreamwidth.org/214016.html)
    - [Things Rust Shipped Without](http://graydon2.dreamwidth.org/218040.html)

# Links

- [Strategies for Solving "cannot move out of" Borrowing Errors](strategies-for-solving-cannot-move-out-of-borrowing-errors.md)
- [Abstraction Without Overhead[(abstraction-without-overhead.md)
- [Defaulting to Thread-safety](defaulting-to-thread-safety.md)
- [How Rust Achieves Thread Safety](how-rust-achieves-thread-safety.md)
- [Some Notes on `Send` and `Sync`](some-notes-on-send-and-sync.md)
- [Comparing k-NN in Rust](comparing-knn-in-rust.md)
- [`simple_parallel`: Revisiting k-NN](simple-parallel-revisiting-knn.md)
- [Enums, `match`, Mutations and Moves](enums-match-mutation-and-moves.md)
- [Reading Rust Function Signatures](reading-rust-function-signatures.md)
- [Memory Leaks are Memory Safe](memory-leaks-are-memory-safe.md)
- [Myths and Legends About Integer Overflow in Rust](myths-and-legends-about-integer-overflow-in-rust.md)
- [What Does Rust's `unsafe` Mean?](what-does-rusts-unsafe-mean.md)
- [Peeking Inside Trait Objects](peeking-inside-trait-objects.md)
- [The `Sized` Trait](the-sized-trait.md)
- [Object Safety](object-safety.md)
- [Where `Self` meets `Sized`: Revisiting Object Safety](where-self-meets-sized-revisiting-object-safety.md)
- [Working With C Unions in Rust FFI](unions-rust-ffi.md)
- [Terminal Window Size With Rust FFI](terminal-window-size-with-rust-ffi.md)
- [Getting Acquainted with `mio`](getting-acquainted-with-mio.md)
- [My Basic Understanding of `mio` and Async I/O](my-basic-understanding-of-mio-and-async-io.md)
- [Creating a Simple Protocol With `mio`](creating-a-simple-protocol-with-mio.md)
- [Managing Connection State With `mio`](managing-connection-state-with-mio.md)
- [Get Data From a URL](get-data-from-a-url.md)
- [Effectively Using Iterators in Rust](effectively-using-iterators.md)
- [`String` vs. `&str` in Rust Functions](string-vs-str-in-rust-functions.md)
- [Creating a Rust Function That Accepts `String` or `&str`](creating-a-rust-function-that-accepts-string-or-str.md)
- [Creating a Rust Function That Returns `String` or `&str`](creating-a-rust-function-that-returns-string-or-str.md)
- [Understanding Over Guesswork](understanding-over-guesswork.md)
- [Rust, Lifetimes, and Collections](rust-lifetimes-and-collections.md)
- [Rust, Generics, and Collections](rust-generics-and-collections.md)
- [Rust Collections Case Study: BTreeMap](rust-btree-case.md)
- [Pre-pooping Your Pants With Rust](everyone-poops.md)
- [The Many Kinds of Code Reuse in Rust](rust-reuse-and-recycle.md)

# Notes

- 'finding closure in rust' needs to come before 'defaulting to thread-safety'

# Candidates

- http://blog.adamperry.me/rust/2016/07/24/profiling-rust-perf-flamegraph/
  - good writing supposedly
- http://sunjay.ca/2016/07/25/rust-code-coverage
- http://xion.io/post/code/rust-for-loop.html
  - details about for loops and iterators

# Editing

## rust built in traits

Section on Deref could emphasize that it is for smart pointers. And it should
say that it is the only one of these the language treats specially and how.

> Note that this does not necessarily mean consuming the value – maybe we take a reference to it in the same expression, e.g. &*x (which you will likely find in code that deals with special kinds of pointers, e.g. syntax::ptr::P is widely used in clippy and other lints / compiler plugins. Perhaps as_ref() would be clearer in those cases (see below), but here we are.

I don't understand this sentence, and it's criticizing Rust in some way.
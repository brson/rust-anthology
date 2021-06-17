# Rust Anthology 1

The best short-form writing about Rust, collected.

Rust needs more documentation, right? Well, yeah, it does, but there
are actually a lot of great Rust docs out there right now, and a lot
of great Rust writers! This project aims to collect their work into a
single book.

__Note: As of February 2020, this project is only lightly maintained. The only
notable thing here is [the master list](master-list.md), the final "unevaluated"
section which I add to occassionally.__

[See the current draft](https://brson.github.io/rust-anthology).

[![Travis Build Status][travis-build-status-svg]][travis-build-status]

[travis-build-status]: https://travis-ci.org/brson/rust-anthology
[travis-build-status-svg]: https://img.shields.io/travis/brson/rust-anthology.svg

## Goals

- The _primary_ goal is to collect valuable information into one
  place, get it under test, and present it in a consistent way.
- Celebrate authors of excellent Rust documentation.
- Create a coherent full-length book.
- Self-publish a book in print form to give away as conference prizes.
- Create a yearly tradition of collecting the best Rust writing.
- Incentivise yet more high-quality blogging about Rust with the anticipation
  of being selected for next-year's book.

## Building

Rust Anthology is built with [mdbook].
> Make sure Rust is already installed. To install

```shell
$ curl https://sh.rustup.rs -sSf | sh
```

 To build:
 
```shell
$ cargo install mdbook
$ mdbook build
```

[mdbook]: https://github.com/azerupi/mdBook

Testing is again with mdbook:

```shell
$ mdbook test
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## On curation

There is a lot of good writing about Rust. Not all of it will make the
cut. We'll have to make some hard decisions, and some authors will
probably be disappointed at not being included. That's just reality,
and we have to manage it as nicely as we can.

## Authorship and licensing

Authors maintain the copyright to their chapters, and each chapter is
licensed individually according to the author's preference. Copyright
of modifications to chapters as part of the editorial process is
relinquished to the original authors. Additional content, such as
chapter descriptions, is owned by the contributing editor and licensed
CC-BY-4.0.

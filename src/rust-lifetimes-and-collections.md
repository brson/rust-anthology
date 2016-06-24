% Rust, Lifetimes, and Collections

# Rust, Lifetimes, and Collections

## Alexis Beingessner

Collections are hard. Using collections safely is even harder. Using collections safely *and* efficiently is even harder. And let's toss on "and not wanting to burn your computer to the ground while doing it" to the list for good measure. Fundamentally, there has to be a tradeoff here. If you can index into a run-time-sized array with runtime information, you either need to do some kind of bounds check, or you have to accept that someone can read beyond the intended bounds of memory. And this is just for *an array*. The simplest data structure there is!

Rust seeks to bridge the performance-safety gap while still being usable. For the most part, this is done with a really fancy type-system and tons of static analysis built on top of some of the best ideas from different programming languages. We believe that if the compiler can prevent you from a bug that manifests at runtime, that's pretty great. Especially if you're wading into the kind of territory that C++ occupies. How many people have the energy to learn all the different ways that you can invoke Undefined Behaviour in a language like C++, *and* actually remember them when it matters? Where many dynamic languages patch over this with lots of runtime solutions (GC really is great for preventing tons of memory errors), Rust just uses a few simple rules to make sure everything is defined, safe, and *usually* super fast.

First a big omission: we do runtime bounds checking on array indexing. We're sorry, but... we have to. No amount of compile-time type-system is going to get us out of that hole without seriously reducing usability. But Rust has an escape hatch. A superset of the Rust language includes the notion of `unsafe` code. Since Rust is itself written in Rust, there's a lot of places where we need to dance with completely unsafe operations in order to build our basic programming abstractions. You need to manually `free` some memory? Sorry, that's always going to be unsafe. Normally, Rust would prevent you from calling such a function by marking it `unsafe`. `unsafe` code is infectious like Java's exceptions. If you call an unsafe function, you need to mark yourself as unsafe, or explicitly state the boundaries where the unsafety is handled. This is done with an `unsafe` block:

```
fn do_stuff(data: &[u32]) -> u32 {

    // Dear compiler, I know that calling unsafe_get is considered unsafe, since it omits the
    // bounds check arrays need to make to be sane in general. I promise to you that I know what
    // I'm doing here. Any invariants you assume about programs in general will be upheld before
    // and after this block. In between I won't invoke any Undefined Behaviour,
    // but I know you can't tell.
    //
    // Love, Alexis
    unsafe {
        data.unsafe_get(7) // 7 is my lucky number, I can't possibly index outta bounds with that
    }
}
```

The unsafe block does nothing but make a promise to the compiler that you know what you're doing. In no way is this checked. This also does not change the semantics of the language, or behaviour of any function. It just allows you do things that are formally marked as unsafe.

What exactly is considered unsafe? To newcomers to Rust, this can be a bit of a contentious subject. For instance, Rust doesn't consider integer overflow to be unsafe (it actually defines what happens, instead of making it Undefined). However it's fairly easy to make an incorrect program by overflowing an integer. Some would therefore assert that it should be unsafe to add two integers together. However "being able to write an incorrect program" isn't what Rust cares about. That's impossible to guarantee with any amount of analysis, static *or* dynamic, [unless you hate mathematicians](/~abeinges/blah/halting/). Rust specifically constrains itself to *memory* safety.

In safe Rust code you can't do some obviously wrong things like double-free a pointer, read unintialized memory, or dereference a null pointer. But you also can't do some more subtle things. A lot of Rust's safety model is built around its two main pointer types: `&T` and `&mut T`, the immutable and mutable reference types. Not only can these types can never be null, they can never point to anything that isn't a totally valid instance of `T`. We'll see how that's possible in a bit, but they come with some extra constraints. To understand these constraints, I think it's useful to consider `&T` to be a "view" and `&mut T` to be a "loan". You can take as many views into an object as you want, but you can't loan an object while doing this. You also can't loan out an object multiple times. This prevents a massive class of data race errors. You can either have lots of read-only views into a location in memory, or a single read-write loan of a location of memory. Anything that obeys these rules is not only *trivially* thread-safe, but also much easier to reason about. Even in the single threaded case, if you have an `&mut T` you know *no one* is going to change that location of memory unless you explicitly loan it out to someone else, or do it yourself. That's pretty nice to just *know*, you know?

There's a whole mess of other things that are considered `unsafe`, you can check out the [Rust language reference](http://static.rust-lang.org/doc/master/reference.html#unsafety) for more details (may not be 100% accurate as of this writing; like everything in Rust, some things are in flux here). Now at this point some people may scoff at the `unsafe` block. What good is having a notion of unsafety in the type system if you can just say "yeah I got it". The comparison to Java's checked exceptions here seems particularly unfavourable, where people quickly descend into `try{ foo(); } catch (Exception e){}` and `throws Exception`. However there are some key differences to keep in mind. Unlike Java's Exceptions, Rust does *not* intend `unsafe` to be used liberally. Unsafe is for the lowest levels of abstraction to deal with (often just the standard libraries themselves). Ideally, an application developer can avoid ever usig `unsafe`. In this sense `unsafe` avoids being ignored by virtue of novelty; if you see something marked unsafe, you're going to pay attention. However it also has another massive benefit: reasoning about errors. Your program segfaulted? And you didn't write any unsafe code? It literally *can't* be your fault. Isn't that liberating? You know for a fact that some library you're depending on has messed up. And where did it mess up? *It has to be somewhere in an unsafe block*. You can skip almost all of the code in the library and focus on an adorably tiny subset of the code.

Now of course someone *could* just mark everything `unsafe` and wrap main in an `unsafe` block but... ugh. If you see someone do that... run away. Far. Away. Possibly call the police. They need help.

But anyway that's all very theoretical. Let's see some very real code and some very real problems now.

You get a reference into a collection, and someone then mutates the collection. What does your reference point to now?

In garbage-collected languages, this is easy: it points to the same thing it did before! The object will never be moved in memory, and will only be removed from memory altogether once all references to it disappear. An array of `T`'s isn't an array of `T`'s at all, it's actually an array of pointers to `T`, all of which live on the GC heap! Awesome, problem solved. But what about languages that don't have GC like C or C++? Well, if you're lucky the pointer you have is still pointing to what you want. If you're unlucky, the collection shifted around, and now you have a pointer to... something else. Whatever it is, you're probably not going to be happy. Especially since this is almost certainly going to invoke Undefined Behaviour. If the compiler catches on, it's free to do *literally anything it wants*. Including sell your soul for a hamburger. Ouch.

Rust doesn't have GC, so it needs to worry about this. So what happens when you run this code?

```
    // Vec is our growable heap-allocated array type.
    // This is just a handy way to make one with some fixed data.
    let mut v = vec![1i32, 2, 3, 4, 5];
    let x = v.get(2);
    v.push(6); // oops, sorry x!
```

It doesn't. You can't compile this code. This goes back to our good friends *view* and *loan*. Let's look at the signature of `get` and `push`:

```
fn push(&mut self, value: T);
fn get(&self, index: uint) -> Option<&T>;
```

`get` takes a *view* into `self` and returns (maybe) a view into an element in the Vec. `push` takes a *loan* of self and a value, and pushes that value onto the end of the Vec. So why won't this work? Well, `get` is actually a sugared function signature using something called *lifetime elision*. It can also be written explicitly as:

```
fn get<'a>(&'a self, index: uint) -> Option<&'a T>;
```

We've added some crazy `'a` sigil now. What does it mean? This sigil is called a *lifetime* in Rust, but I prefer to just think of it as the name of a borrow, which loans and views both are. This is saying that that the view in the returned Option is part of the original view into the Vec itself. Therefore, while we hold onto `x` in our code, we're holding onto a view into `v`. When we go to call `push`, it then tries to take a *loan* of `v`, but the compiler stops it: there's an outstanding view into `v`. Calling push here will violate our safe aliasing rules! This, however, *will* work:

```
    let mut v = vec![1i32, 2, 3, 4, 5];
    {
        let x = v.get(2);
        // maybe do some work with `x`...
    }
    v.push(6);
```

Here we make sure that `x` goes out of scope before `v` does, and the compiler is happy. It knows that `v` isn't loaned or being viewed when we call `push`, and so it's perfectly fine to loan it out. Nice! Problem solved. Right? What we've really done here is reduced the space of programs the compiler will accept. But what about this:

```
    let mut v = vec![1i32, 2, 3, 4, 5];
    let x = v.get(0); // Sure
    let y = v.get(1); // Mhmm
    let z = v.get_mut(2); // Should be fine..?
```

Ack! The compiler will reject this too. The borrowing system isn't particularly sophisticated. All it knows is that all of `v` is under view, and any kind of loan isn't allowed. But any C++ programmer knows that this code is totally safe, even by Rust's rules! Except, we could have written:

```
    let mut v = vec![1i32, 2, 3, 4, 5];
    let x = v.get(0); // Sure
    let y = v.get(1); // Mhmm
    let z = v.get_mut(0); // Mwahaha mutable aliasing!
```

And just like with bounds-checking, there's no way for the compiler to know it (those indices could be determined by user input!). So in some sense the compiler *is* right to prevent this. Still, here we have Rust legitimately getting in our way. What can we do? Well, there's this gem of a function:

```
fn split_at_mut(&mut self, mid: uint) -> (&mut [T], &mut [T]);
```

You give it an index into an array, and it returns *two* loaned arrays (mutable slices, by official Rust parlance), separated by that index. Huh? Doesn't this break aliasing rules? Well... yes. And no. As far as the compiler is concerned, this is totally not legit. But, with a little sprinkle of `unsafe` inside this method, we can make it happen. It's totally safe because the regions of memory that these cover are *totally disjoint*. Now we can index into these two slices independently, and no one will complain. The compiler knows the original array is definitely loaned out, and will only relinquish the loan once *both* slices go out of scope. You can of course also recursively `split_at` to get arbitrary subdivisions.

Rust's standard libraries are full of tricks like these. They require a bit of unsafe magic to make happen, but once they're written, they can be safely used by everyone. That's really the `unsafe` ideal, in my books. Want to be able to have multiple potential mutators of a value? Can I interest you in our [Mutex types](http://doc.rust-lang.org/sync/)? Or how about our [Cell types](http://doc.rust-lang.org/core/cell/index.html), which allow mutating through views by performing runtime checks?

But my all-time favourite `unsafe` trick is collection iterators. If you've been a miffed this whole time about that whole "bounds checking" thing, you're going to really like this. So you want to loop over a Vec. One way you could do this is like this:

```
    let mut v = vec![1i32, 2, 3, 4, 5];
    for i in range(0, v.len()) {
        // Array litteral syntax will just crash the program if you index out of bounds,
        // instead of returning an Option.
        let x = &mut v[i];
        // do some work with x
    }
```

That's all perfectly sound and good, but it's wasting tons of time doing bounds checking! It's also totally unidiomatic. The way you *should* do this in Rust is the following:

```
    let mut v = vec![1i32, 2, 3, 4, 5];
    for x in v.iter_mut() {
        // do some work with x
    }
```

Much less boiler-plate, and I'll let you in on a secret: that bounds checking's all gone. How is that
possible? Well, as always, the answer is: there's some `unsafe` code in there. The iterator can be as unsafe as it wants, because it knows the range and order of accesses. But as consumers of the interface, that's all abstracted away for us. All we know is that it's convenient and fast.

That reminds me, here's another common collection problem that is trivially solved by borrows: iterator invalidation. If you get an iterator into a collection, and then call a mutation method on the collection, you're very likely to break the iterator. However in Rust this is simply impossible: the iterator will borrow the collection in some form, making mutation through the collection's interface impossible! Yay!

But let's take a look at the [Iterator interface](http://doc.rust-lang.org/std/iter/trait.Iterator.html) (Trait):

```
    pub trait Iterator<A> {
        fn next(&mut self) -> Option<A>;

        // ... oh my god so many convenience methods, and these aren't even all of them in practice
    }
```

There's a ton of stuff on there, but all that really matters is `next`. It temporarily borrows the iterator,
and then returns... something. Anything, really. This single interface supports making an `Iterator<int>`, `Iterator<&int>`, and `Iterator<&mut int>`. Nothing too strange there. Something that *isn't* obvious about this interface is that there's actually no way to connect the A to the &mut self. You can't make an iterator that becomes borrowed by the elements it yields. Consequently you can always call `next` again, no matter how many outstanding results you already have. And this is totally safe, for exactly the reason that `split_at` is safe: we know all the references that are yielded will be disjoint. Using an iterator, you can efficiently obtain a reference to *every single element at the same time* in a Vec. Super handy if you want to look at, say, 3 elements at a time.

But this interface is a double-edged sword for collections. Here's some things that *aren't* possible with this interface:

* This design *requires* (!) unsafe code to return references. The iterator necessarily has some kind of reference to the collection, which means yielding a reference to the collection should borrow the iterator itself in safe code.

* Going backwards. Always being able to call `next` is safe because each element will be yielded *at most* once. This doesn't work if you have a `prev` method. Note that this is only a problem for `&mut` iterators. It's perfectly fine to get multiple views of the same element.

* Insertion/Removal during iteration is very difficult to support, if not impossible, in general. Every single mutation would have to guarantee that all the previously yielded references won't be affected.

Mandatory usage of `unsafe` is pretty gnarly, but it's not so bad in practice. If your collection is built on top of another collection, you can often avoid using any unsafe code at all by building on top of *its* iterator. Also, collections often use copious unsafe code internally anyway. This is a place where we're comfortable with that kind of thing.

The other two restrictions are troubling, though. Being able to go backwards is pretty handy. A doubly-linked-list, for instance, is substantially worsened without bidirectional seeking. The insertion/removal one is the worst though. Now, it's not totally hopeless. Our doubly-linked-list actually manages to pull it off by offering a `peek` method which *does* borrow the iterator. It also provides a `pop_next` method for removing the value yielded by `peek`. This is totally sound because deleting one node in a doubly-linked-list doesn't affect the location in memory that any other element in the list occupies. You can do the same for a binary search tree. But what about inserting into a Vec? Or inserting or deleting in a B-Tree? That's not going to work.

For this we need a new interface. I've been referring to this hypothetical interface as the Cursor interface. The precise details of what it would or wouldn't support aren't that important. All that matters to me is this minimal version:

```
    pub trait Cursor<T> {
        fn next(&mut self) -> &mut T;
    }
```

Which you may recall is sugar for:

```
    pub trait Cursor<T> {
        fn next<'a>(&'a mut self) -> &'a mut T;
    }
```

That's all we need. With that, you can only get one reference at a time, and you can't do anything with the cursor until you forget it. Then you can add `prev`, `remove`, `insert`, whatever you want. It also wouldn't require any unsafe code! Both Iterator and Cursor have their uses. Iterator's here to stay, but I hope we can some day add Cursors as well (really, someone with enough time just needs to write some proof-of-concept implementations).

That's all I'm going to talk about today, but before I go I want to emphasize that Rust really isn't perfect here. The compile-time borrow checker is *very* conservative, and currently only works with lexical scopes. It's pretty easy to run into a case that logically should work, but the compiler rejects. There's plans to make this better over time, but it can be frustrating when you run into it. Although honestly even now, more often than not the compiler is actually right, as in my indexing example. Static types are also fun and cool to play with, but you only get as much out as you put in. Our types are built around memory-safety and type-safety. They aren't going to prevent various other classes of programming errors. There's also absolutely safe code that invokes Undefined Behaviour right now (oh hey there, `2u32 << 1000`), but that's a bug, not a longterm design flaw.

Anyway the moral is that Rust is a work in progress. If you have some problems with how it does things, we're more than willing to hear you out. Just keep in mind that Rust is a moving target, and has been for years. If you see something nasty, it might be a legitimate design flaw, or just something that *used* to make sense but doesn't any more. The Iterator API I talked about today? Boy did that look different a year or two ago. How I said Rust doesn't have Gc? It was supposed to, originally. Vec? Used to be built-in to the language. Stuff changes here. Although we've reached the point where we think we really get how the language is supposed to work now. We've started aggressively ripping out and refactoring everything to bring some sanity to this inconsistent mess we call home. There's still a lot of work to do, though. [Won't you join us](https://github.com/rust-lang/rust/)?
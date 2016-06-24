% Rust, Generics, and Collections

# Rust, Generics, and Collections

## Alexis Beingessner

[Last time](/~abeinges/blah/rust-lifetimes-and-collections/) I wrote about how Rust's notion of lifetimes lets us write and use collections much in the same way that we would in other languages, while protecting us from many of the classic mistakes you can make when working with collections. Things like iterator invalidation and mutating a collection while holding an internal reference just can't happen. All with purely compile-time checks!

Today I want to talk about another really cool part of Rust's type system: generics.

In programming, there are two major families of generic code: compile-time generics, and run-time generics. Like C++, Rust provides facilities for both mechanisms. It provides compile-time generics (which we just call generics, since this is the preferred mechanism) in much the same way that C++ does through templates, but in a more restrictive and type-safe way. It also provides run-time generics through a system called *trait objects*, which is similar to virtual functions in C++, and generics in Java.

Here's an example of Rust generics:

```
fn main(){
    // u32 suffix literal an unsigned 32-bit integer; i16 is signed 16-bit.
    // All other values in the arrays are inferred to be of the same type.
    let a = find_min(vec![1u32,2,3,4]);
    let b = find_min(vec![10i16,20,30,40]);
    println!("{} {}", a, b);
}

// Dat Code Reuse
fn find_min<T: Ord>(data: Vec<T>) -> Option<T> {
    let mut it = data.into_iter();
    let mut min = match it.next() {
        Some(elem) => elem,
        None => return None,
    };
    for elem in it {
        if elem < min {
            min = elem;
        }
    }
    Some(min)
}
```

The key line is this one:

```
fn find_min<T: Ord>(data: Vec<T>) -> Option<T> {
```

The `<T: Ord>` is declaring this function to be generic over any type `T` that implements the Ord trait. Ord provides comparison, which allows us to do `elem < min`. Note also that Vec and Option are generic *types*, which means they can be instantiated for any concrete type `T`. By writing our `find_min` function generically, we can call it for any choice of `T` that satisfies these bounds. In this case, we pass in u32's and i16's. Note that the function implementation is verified to work for *any* type that could possibly implement `Ord`. If `find_min` used any functionality that `Ord` didn't imply, the compiler would refuse to compile `find_min`. This analysis is independent of the concrete types we actually try to call this function on. Note that this is also a fairly simple generic bound. You can do some pretty elaborate stuff with this system. We'll get to some more advanced stuff later.

Like C++ templates, generic code is actually compiled by *monomorphization* of the code. This is just a fancy word for "take the code written here, and copy-paste it with the actual concrete types when it's used". So presumably our `find_min` example should generate the same executable as if we hand-wrote a special implementation of `find_min` for i16 and u32. This is great for the optimizer, as it can do all the crazy inlining and type-specific optimizations it wants. However it comes at the cost of producing a lot of code and bloating up reultant binaries. Also, generic code in libraries needs to preserved even after compilation so consumers can monomorphize the code to their own types.

However what if you wanted to have a `Vec<T>` where the T's can be anything that implements `MyTrait`, but aren't necessarily all the same concrete type. For intance, a `Vec<Ord>` containing u32's *and* u16's. Generics as we've seen them don't really work here, because when you monomorphize `T`, it can't be *multiple* concrete types. That's exactly what the *mono* part of the word is all about. Further, allowing this wouldn't really make sense because a `u16` takes up a different amount of space as a `u32`.

This is the problem that trait objects solve. Trait objects are actually very new to the language, so standard library support is pretty shaky for them. As such, here's a slightly contrived example of their usage:

```
use std::num::{Num, Zero, One};

pub trait Counter {
    fn increment(&mut self);
    fn is_zero(&mut self) -> bool;
}

// Ooh, implementing a trait for all types that satisfy a generic bound! AKA a blanket impl.
// Note that this can be problematic if you want other implementations to coexist with this one.
// For instance, if I manually implement this for MyCoolCounter, the compiler has to be able
// to prove that there's no way this implementation can apply to it. Otherwise there would be
// an ambiguity as to what implementation to use!
//
// Also note that Num/Zero/One are deprecated as of this writing, but that's not super
// important for this.
impl<T: Num + Add<T, T>> Counter for T {
    fn increment(&mut self) {
        *self = *self + One::one();
    }

    fn is_zero(&mut self) -> bool {
        *self == Zero::zero()
    }
}

fn main(){
    let mut data: Vec<Box<Counter>> = Vec::new();
    data.push(box 1u32);
    data.push(box 0u16);
    data.push(box 0i8);

    for x in data.iter_mut() { println!("{}", x.is_zero()); }
    for x in data.iter_mut() { x.increment(); }
    for x in data.iter_mut() { println!("{}", x.is_zero()); }
}

```

Here the key piece of code is `Vec<Box<Counter>>`. Counter is not a concrete type, it's a trait. In this way we signal that our Vec can contain any Box of any type that implements Counter. Note that it's important that we use a Box here (which is our unique_ptr equivalent). u32 and u16 have different sizes, and our Vec can't handle that. In Rust parlance Counter is a *dynamically sized type* (DST). We can't just directly store DSTs because it's impossible to know their size at compile time (how much stack space does the variable `x: Counter` require?). So we heap allocate the numbers and store a *pointer* to them in the Vec. All of these pointers are the same size, so that will work. It's worth noting that Rust's doing a bit of magic here for us. The pointers are actually "fat", in that they consist of *two* pointers. One to the data on the heap, and one to a vtable of the Counter functions that each element provides. This is necessary to actually figure out what the methods to call at runtime are. Also note that the heap allocation is actually unnecessary, we could have also created a `Vec<&mut Counter>`. But with Boxes the Vec owns all its data and can be moved around freely.

Trait objects are actually basically what generics in Java are. If you make an `ArrayList<Counter>` in Java, that's the same as our `Vec<Box<Counter>>` (modulo GC). Since Java *only* has boxed trait objects for generics, you can get a lot of nasty patterns when working with data structures. For instance, you have to make checks like "are these two types actually the same type?". This is also where we get the infamous wrapper types for primitives. In Java, types like `int` and `bool` aren't on the heap normally, so to use them with generics, you need to send them to the heap by wrapping them in Integer and Boolean types that *are* on the heap.

In Rust we don't have the problem, because we can just *monomorphize* our collections to work with a particular type. `Vec<int>`, Vec<Vec<Vec<int>>>`, and `Vec<Box<int>>` all work. And if you want Java-style run-time generics, you can *opt into* that behaviour using trait objects.

Trait objects can be powerful and useful, but they're going to be more expensive and restrictive to use in most cases. Generics are definitely to be preffered when possible. Although you may want to design your libraries with trait objects in mind. This is because trait objects come with a special restriction we call *object safety*. An object-safe trait has no methods which take or return a value dependent on the implementer's own type. That is, a trait like Clone:

```
pub trait Clone {
    fn clone(&self) -> Self;
}
```

is *not* object-safe, because it returns a value of type Self (which is the implementer's type). If you had an `&Clone` and called `clone()` on it, it would produce a value whose type is unknown at compile time. The space it would occupy on the stack would be indeterminate. Rust's solution to this problem (at the moment) is to just forbid traits like this from being used as a trait object at all. This is why we've recently had to split up our Iterator trait into the following methods:

```
pub trait Iterator<A> {
    fn next(&mut self) -> Option<A>
}
```

and

```
pub trait IteratorExt<A>: Iterator<A> {
    // Note: all of these methods are implemented by default, as denoted by the `{ ... }`'s
    // that follow the method declaration. Because IteratorExt inherits Iterator,
    // the trait can assume all implementors impl Iterator, and use that in the default
    // impls.

    fn chain<U: Iterator<A>>(self, other: U) -> Chain<Self, U> { ... }
    fn zip<B, U: Iterator<B>>(self, other: U) -> Zip<Self, U> { ... }
    fn map<B>(self, f: |A| -> B) -> Map<'r, A, B, Self> { ... }
    fn filter(self, predicate: |&A| -> bool) -> Filter<'r, A, Self> { ... }
    // ... and so on
}
```

Iterator is totally object-safe, but the IteratorExt methods aren't. So we can have a `Box<Iterator>`, but not a `Box<IteratorExt>`. Thankfully, we can add the following generic impls:

```
// Every concrete instance of iterator automatically implements IteratorExt.
// No need for an implementation body because IteratorExt provides everything by
// default.
impl<I: Iterator<A>, A> IteratorExt<A> for I {}

// Automatically implement Iterator for a Box<Iterator>, so that
// IteratorExt now works for them too.
impl<A> Iterator<A> for Box<Iterator<A>> {
    fn next(&mut self) -> Option<A> {
        self.deref().next()
    }
}
```

Now all iterators get the "extension" methods for free, and `Box<Iterator>` can be used as
a concrete iterator with the extensions as well.

Monomorphization also interacts in a *really* cool way with one of the more exotic concepts in Rust: zero-sized types (ZSTs). Zero-sized types are exactly what the name implies. They're a type that takes up absolutely no space. As a data-type, this makes them essentially useless: every member of a ZST is... exactly the same value! For a concrete example, we can look at Rust's most popular ZST: the empty tuple `()`. What values can the empty tuple take on? Exactly one. `()`. Totally useless, right? Well, it sure would be... if it weren't for generics!

Rust knows that zero-sized types are totally useless. As such, any time you tell it to do something with a zero-sized type, it completely ignores you. Want to pass around some `()`'s by value? Sure thing. Let me just go pass around all this *absolutely nothing at all*. Want to dereference this reference to a `()`? Sure thing. Let me do *absolutely nothing at all*. Heap allocate a `()`? Totally. Here's a pointer to some garbage. Go ahead, try to make me deref it, I *dare you*.

So wait, why is it useful again? Well, the classic example is Rust's `Result<T, E>` type. Result is defined to be the union of two possibilities: `Ok(T)`, or `Err(E)`. It's our primary error handling mechanism. You ask a function to do something fallible, and it comes back with a Result. Then you match on whether you got back an `Ok(thing_i_wanted)` or `Err(oh_noooo)`. But a lot of the time there's no reasonable value to give back in the `Err` case. Sometimes there's not even a reasonable use for the `Ok` case! So what do we do then? Use the empty tuple! Don't have anything useful to give back on error? `Result<T, ()>`. Just want to respond with success/failure, and don't have any value to give back either way? `Result<(), ()>`. Congratulations on that last one by the way, you've just re-invented the *boolean*. But it's a super-boolean because it works with all the code built for working with Results!

So that's pretty cool, but we're here to talk about collections. How does this relate to them? Well you see `Result<T, ()>` is basically a Monad and Monads ar-- J/K there's actual data structure-y things to talk about here.

Two big classes of collections are Maps and Sets. It's a common observation that a Set is just a really bad Map. That is, if you implement your favourite kind of Map, you've basically built a Set on the keys you insert into it. Those keys just happen to map to values. Now, it would be *really* nice if we could re-use that same implementation for Sets. Write a HashMap, get a HashSet for free. Write a TreeMap, get a TreeSet for free. And of course you can: Just make `Set<T> = Map<T, bool>`. Great! Although we're doing a lot of pointless work. We're allocating space for a bunch of booleans we don't care about, and actually reading and writing them all over the place. If we took the time to custom write a HashSet, there's no way we'd do this!

But we're lazy, why would we rewrite our HashMap? Instead, we can just tell Rust that we don't care what the second type is with zero-sized types: Make `Set<T> = Map<T, ()>`. Allocating space for the values? Sure. I'll go ahead and allocate you all the nothing you could ever hope for! Reading and writing those values? Oh, absolutely. I'll get *right on that*. Just like that, we've got code for a Set type as if we custom wrote it, but we're just using the unmodified Map type! Pretty slick. And this isn't just theoretical.
[This](https://github.com/rust-lang/rust/blob/ff88510535611f8497047584b18b819b7fe5cb3a/src/libcollections/btree/set.rs#L33)
[is](https://github.com/rust-lang/rust/blob/5eec666c8c4be3706a79755e6cb1119990390c79/src/libcollections/tree/set.rs#L101)
[exactly](https://github.com/rust-lang/rust/blob/16c8cd931cd5ccc9c73b87cac488938556018019/src/libcollections/trie/set.rs#L57)
[how](https://github.com/rust-lang/rust/blob/80a2867ea736007397aa2fbaa0e4c539c80e162c/src/libstd/collections/hash/set.rs#L97)
the standard libraries do it.

Now, were messing around with collections, so here's where I mention unsafe code. Unsafe code is generally pretty happy about zero-sized types. They can't be uninitialized, can't be in an inconsistent state, and you can't really read or write to them at all. Sounds great. But there's two things to watch out for with zero-sized types:

First, naively applying the usual code you would use to manually allocate an object on the heap will (correctly) have you asking your allocator to allocate 0 bytes. You best believe the allocator is treating that as all kinds of Undefined Behaviour. If you're talking directly to the allocator (rather than using `Vec` or `Box` to handle it for you), you'll probably need to explicitly have a guard for `size_of<T> == 0`, and return a garbage sentinel value. In fact, Rust [defines](http://doc.rust-lang.org/nightly/alloc/heap/) one for us to use:

```
/// An arbitrary non-null address to represent zero-size allocations.
///
/// This preserves the non-null invariant for types like `Box<T>`. The address may overlap with
/// non-zero-size memory allocations.
pub const EMPTY: *mut () = 0x1 as *mut ();
```

Similarly, asking the allocator to free a zero-sized type is going to cause some trouble. Just guard against that too. But there's a subtlety here. See, zero-sized types can have destructors (Actually this isn't strictly true. For legacy design reasons, a zero-sized type with a destructor currently stops being zero-sized. But it will be true Very Soon). So you still need to read the value out of the pointer so that its destructor will run. Just don't free the pointer afterwards.

The second problem is a funner one. A reasonable pattern you might see in C to iterate over an array of values is to make a pointer at both ends, and advance them towards each other. When they point to the same address, you're done iterating. Right? But what if you have an array of ZSTs? Well, you compute both pointers and... they're exactly the same. If you try to offset a pointer to a zero-sized type, it (correctly) does absolutely nothing. You just asked the program to offset by 0 bytes. Oops. The way you would normally write it, iteration of a zero-sized array will yield absolutely no elements. This is sort of benign in the sense that it doesn't trigger undefined behaviour or anything, but it's almost certainly Not Correct.

As a result, here's what by-value iteration ends up looking like for std's Vec (slightly modified for simplicity):

```
...
if mem::size_of::<T>() == 0 {
    // purposefully don't use 'ptr.offset' because for
    // vectors with 0-size elements this would return the
    // same pointer.
    self.ptr = (self.ptr as uint + 1) as *const T;

    // Read whatever, doesn't matter
    Some(ptr::read(self.ptr))
} else {
    let old = self.ptr;
    self.ptr = self.ptr.offset(1);

    Some(ptr::read(old))
}
```

It just casts the pointers to integers, increments those, and casts them back to pointers. That way we know the pointer values will actually change, and that iteration will yield the right amount of values. That's kind of the funny thing about `Vec<()>`. It's just a glorified integer counter! You tell it to insert and remove elements, and all that does is change its recorded length. Then when you tell it to iterate, it counts up to its length, and "returns" the same value over and over.

I'll just re-emphasize this point from the previous post though: this is totally something you don't have to care about in safe code, which is what you should be writing 99.9% of the time. Unsafe code is for writing basic computational primitives, and optimizing that one hot path of code that total safety gets in the way of. And these particular problems only come up if you're writing *generic* unsafe code.

The allocate/free ZST issue is also only around because we don't have any raw allocation middle-ware in the standard library. Either you're using totally safe Boxes and Vecs, or you're talking to jemalloc pretty much directly. Work is being done to introduce better abstractions that will let us be generic over allocators (custom and non-global allocators, yay!), while also handling a lot of the allocator boiler-plate that unsafe code does. No need for us to rewrite ZST handling and size/alignment computation everywhere. Also if you're committed to just aborting on out-of-memory, no need to manually check the result for a null.

As always, Rust is a work in progress. But at least we've got a good idea of where it's headed.

To close things off, I want to share one of the coolest things we've worked out with generics and collections. First off, here's the problem: most of Rust's collections are expected to define three kinds of iterators: by-reference, by-mutable-reference, and by-value. Due to the way that ownership works in Rust, you often need to just re-write the iteration logic for these from scratch, which sucks. That's serious code duplication of often non-trivial code. As discussed in the previous post, iterators are basically required to use unsafe code internally too! Copy-pasting unsafe code is a quick road to disaster.

Previously, there have been a few solutions to this. The old TreeMap and TrieMap codebases address this problem using macros. This is... pretty nasty. Here's a quick snippet of what TreeMap's iterator code looks like today:

```
// FIXME #5846 we want to be able to choose between &x and &mut x
// (with many different `x`) below, so we need to optionally pass mut
// as a tt, but the only thing we can do with a `tt` is pass them to
// other macros, so this takes the `& <mutability> <operand>` token
// sequence and forces their evaluation as an expression.
macro_rules! addr { ($e:expr) => { $e }}
// putting an optional mut into type signatures
macro_rules! item { ($i:item) => { $i }}

macro_rules! define_iterator {
    ($name:ident,
     $rev_name:ident,

     // the function to go from &m Option<Box<TreeNode>> to *m TreeNode
     deref = $deref:ident,

     // see comment on `addr!`, this is just an optional `mut`, but
     // there's no support for 0-or-1 repeats.
     addr_mut = $($addr_mut:tt)*
     ) => {
        // private methods on the forward iterator (item!() for the
        // addr_mut in the next_ return value)
        item!(impl<'a, K, V> $name<'a, K, V> {
            #[inline(always)]
            fn next_(&mut self, forward: bool) -> Option<(&'a K, &'a $($addr_mut)* V)> {
                while !self.stack.is_empty() || !self.node.is_null() {
                    if !self.node.is_null() {
                        let node = unsafe {addr!(& $($addr_mut)* *self.node)};
                        {
                            let next_node = if forward {
                                addr!(& $($addr_mut)* node.left)
    ... and so on
```

That's... ugh. Have fun reviewing `let node = unsafe {addr!(& $($addr_mut)* *self.node)};`.

HashMap then swept in with a really cool design for handling by-ref and by-mutable-ref. You can be generic over `&T` and `&mut T` via the Deref and DerefMut traits. Basically, anything that implements `Deref<T>`, you provide logic for moving the iterator around, and then if the type implements `DerefMut<T>`, you specialize the iterator implementation to yield an `&mut T` instead of an `&T`. `&T` implements `Deref<T>`, and `&mut T` implements both, so with a little maneuvering, this works and you achieve some code reuse. Pretty slick.

However we came up with an even sweeter pattern for BTreeMap. I was also able to port this to my [experimental BList implementation](https://github.com/Gankro/collect-rs/blob/master/src/blist.rs) (doubly-linked-list of array-deques). You can't always implement this pattern. In particluar, it depends on building on top of lower-level iterators. BTreeMap can do this because it needs to iterate its nodes. BList can do it because it's built on top of two iterable collections. However I believe TreeMap and TrieMap can similarly implement this pattern, as BTreeMap does.

I'm going to look at the BList implementation, since it's a bit simpler.

We start by definining the following trait:

```
/// Abstracts over getting the appropriate iterator from a T, &T, or &mut T
trait Traverse<I> {
    fn traverse(self) -> I;
}
```

And implement it for `&RingBuf<T>`, `&mut RingBuf` and `RingBuf`:

```
impl<'a, T> Traverse<ring_buf::Items<'a, T>> for &'a RingBuf<T> {
    fn traverse(self) -> ring_buf::Items<'a, T> { self.iter() }
}

impl<'a, T> Traverse<ring_buf::MutItems<'a, T>> for &'a mut RingBuf<T> {
    fn traverse(self) -> ring_buf::MutItems<'a, T> { self.iter_mut() }
}

impl<T> Traverse<ring_buf::MoveItems<T>> for RingBuf<T> {
    fn traverse(self) -> ring_buf::MoveItems<T> { self.into_iter() }
}
```

Then we define the following generic iterator:

```
/// An iterator that abstracts over all three kinds of ownership for a BList
struct AbsItems<DListIter, RingBufIter> {
    list_iter: DListIter,
    left_block_iter: Option<RingBufIter>,
    right_block_iter: Option<RingBufIter>,
    len: uint,
}
```

So now we have an iterator that is generic over *something* that iterates over a DList, and *something* that iterates over RingBuf. We also have a generic trait for converting some kind of RingBuf into an appropriate kind of RingBuf iterator.

And then we  jsutgo *nuts* with generics on the implementation:

```
impl<A,
    RingBufIter: Iterator<A>,
    DListIter: Iterator<T>,
    T: Traverse<RingBufIter>>
        Iterator<A> for AbsItems<DListIter, RingBufIter> {

    // I would like to thank all my friends and the fact that Iterator::next doesn't
    // borrow self, for this passing borrowck with minimal gymnastics
    fn next(&mut self) -> Option<A> {
        if self.len > 0 { self.len -= 1; }
        // Keep loopin' till we hit gold
        loop {
            // Try to read off the left iterator
            let (ret, iter) = match self.left_block_iter.as_mut() {
                // No left iterator, try to get one from the list iterator
                None => match self.list_iter.next() {
                    // No blocks left in the list, use the right iterator
                    None => match self.right_block_iter.as_mut() {
                        // Truly exhausted
                        None => return None,
                        // Got right iter; don't care about fixing right_block in forward iteration
                        Some(iter) => return iter.next(),
                    },
                    // Got new block from list iterator, make it the new left iterator
                    Some(block) => {
                        let mut next_iter = block.traverse();
                        let next = next_iter.next();
                        (next, Some(next_iter))
                    },
                },
                Some(iter) => match iter.next() {
                    // None out the iterator so we ask for a new one, or go to the right
                    None => (None, None),
                    Some(next) => return Some(next),
                },
            };

            // If we got here, we want to change what left_block_iter is, so do that
            // Also, if we got a return value, return that. Otherwise, just loop until we do.
            self.left_block_iter = iter;
            if ret.is_some() {
                return ret;
            }
        }
    }

    fn size_hint(&self) -> (uint, Option<uint>) {
        (self.len, Some(self.len))
    }
}

impl<A,
    RingBufIter: DoubleEndedIterator<A>,
    DListIter: DoubleEndedIterator<T>,
    T: Traverse<RingBufIter>>
        DoubleEndedIterator<A> for AbsItems<DListIter, RingBufIter> {

    // see `next` for details. This should be an exact mirror.
    fn next_back(&mut self) -> Option<A> {
       //... basically symmetric logic
    }
}
```

The key line being `let mut next_iter = block.traverse();` which is the only place where we
actually use the Traverse trait to convert some-kind-of RingBuf into the right kind of RingBuf
iterator. Now, at this point we can just create the three kinds of iterators as type synonyms for AbsItems with the appropriate concrete types. But that would expose our implementation details. So for completions sake, we have to do some trivial boiler-plate to "wrap" AbsItems:

```
// only showing by-ref because it's identical logic for all of them:

/// A by-ref iterator for a BList
pub struct Items<'a, T: 'a> {
    iter: AbsItems<dlist::Items<'a, RingBuf<T>>, ring_buf::Items<'a, T>>,
}

impl<'a, T> Iterator<&'a T> for Items<'a, T> {
    fn next(&mut self) -> Option<&'a T> { self.iter.next() }
    fn size_hint(&self) -> (uint, Option<uint>) { self.iter.size_hint() }
}
impl<'a, T> DoubleEndedIterator<&'a T> for Items<'a, T> {
    fn next_back(&mut self) -> Option<&'a T> { self.iter.next_back() }
}
impl<'a, T> ExactSizeIterator<&'a T> for Items<'a, T> {}
```

Finally, out actual `BList::iter` method needs to initialize the thing:

```
/// Gets a by-reference iterator over the elements in the list.
pub fn iter(&self) -> Items<T> {
    let len = self.len();
    Items { iter: AbsItems {
        list_iter: self.list.iter(),
        right_block_iter: None,
        left_block_iter: None,
        len: len,
    } }
}
```

and AbsItems does all the work. We've only written our quite complicated iteration logic once, and we've gotten three conceptually distinct iterators as a result. All we have to do is some trivial one-time boiler-plate. If we want to change any of the "real" logic, it's all in one place! No macros, and no specialization for DerefMut. Also, since we're using generics this will all monomorphize to custom iterator impls at compilation time!

I think that's all I have to say about generics in Rust for now. See you all next time!
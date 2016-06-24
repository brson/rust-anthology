% Rust Collections Case Study: BTreeMap

## Alexis Beingessner

This is the third entry in a series on implementing collections in the Rust programming language. The full list of entries can be found [here][index].

In my previous two posts I talked a lot about some high-level patterns and issues that make implementing collections in Rust an interesting problem. Today I'd like to really dig into one of my two favourite collections in the standard library: BTreeMap. There are a few reasons why I like it a lot:

* I wrote the original implementation (so I know it well).
* It's some of the "newest" code in the whole standard library, which means it leverages modern idioms and ideas.
* It's actually a pretty complicated collection.
* Several tricks were "invented" to handle this complexity.

Now what exactly BTreeMap *is* is in flux. Between gereeter and me, there have already been something like 6 major revisions of the design, with pczarn doing some iterator work as I write this. The later versions are more complex because they push the boundaries of performance and safety quite a bit. My first merged version (v3) was *very* naive in several places because my primary goal was to write up a version of the collection that was safe and correct *but* reasonably upgradeable into a less naive implementation. Several revisions later (all credit to gereeter there), I think that's largely held up. A lot of the high-level structure and ideas from my implementation are still there but optimized using several tricks.

So I'm going to do this case study by looking at *several* versions of the collection to highlight some of the design choices made at different stages of development. Also the current version is fairly overwhelming at first, so it's nice to start with my naive implementation.

## There's Something About Binary Search Trees

Traditionally, sorted maps have been the domain of [*binary* search trees (BSTs)][bst]. BSTs enjoy a huge ecosystem of literature, implementations, and promotion in the education system. They're really nice to think about, have great theoretical and practical properties, and have about a million different variations to satisfy your *exact* use-case.

The basic idea of a BST is as follows: Every element in the tree gets a single node. Each node has two pointers: a left child node and a right child node. Nodes in the sub-tree to the left must contain elements that are smaller than the parent, and nodes to the right must contain elements that are larger. This makes search fairly straight-forward: start at the "root" of the tree and compare the element in that node to your search key. Then recursively search either the left or right tree accordingly (or stop if you find an exact match).

![Example BST from Wikimedia Commons][bst-img]

[Example BST from Wikimedia Commons][bst-attr].

If you use everybody's favourite BST, the [red-black tree][rbt], then every basic map operation (search, insert, remove) will take O(log n) worst-case time. Great!

However BSTs have some serious practical issues in terms of how actual computers work. A lot of  applications are not bound by how fast the CPU can execute instructions, but by how fast it can access memory. Modern CPUs go so fast that the data that they're working with has to be *really* fast and close to CPU to actually be used. Light only travels so fast! Consequently CPUs have a hierarchy of caches that range from "very small and very fast" to "very large and very slow (relatively)". (Also fast memory is big and expensive *I guess*. The speed of light reason is funner and more fundamental.)

Caches usually work based on a time-space locality assumption: if you're working with some data at location x right now, you'll probably want data near location x next. A great case for this assumption is something like looping over an array: every piece of data you want next is literally right next to the last one. A bad case would be random indexing into an array: every piece of data you want next is unlikely to be near the last one.

This assumption is usually implemented in some way like: when location y in memory is requested, check if it is in the fastest cache. If is, (cache hit) great! If it's not (cache miss), check the next (slower, bigger) level of cache. In the worst-case this bottoms out into your computer's RAM (or, god-forbid, the disk!). When you *do* find the data, it gets added to all the previous (smaller, faster) levels of cache, along with some of the data surrounding it. This, of course, evicts some data that is somehow determined to be unlikely to be needed. Precise details aren't super important here, the moral is: cache hits are fast, so we want to access data in a space-time local way. [To get a sense of scale, you can check out these numbers][numbers]. We're talking order-of-magnitude differences.

So how do BSTs access data? Basically randomly. Each node is generally allocated separately from every other node. Even if you assume that they were all allocated in a tightly-packed array, the memory access pattern for a search will roughly amount to a series of random accesses into the array. As a rough estimate, every time you follow a pointer you can expect a cache miss. Dang.

To add insult to injury, BSTs are actually pretty memory inefficient. Every node has *two* pointers for every *single* entry in the tree. on 64-bit that means you've got a 16-byte overhead for every element. Worse yet, half of those pointers are just null! They don't do a damn thing! And that's *best case*. When you factor in issues like padding and any extra metadata that nodes need to store (such as the red/black flag in the aforementioned red-black tree), this is pretty nasty.

As a final knife-twist against BSTs, note that *every insertion* triggers an allocation. Allocations are generally regarded as a slow thing to do, so that's something we'd like to avoid if possible!

So what can we do? B-Trees!

## What's a B-Tree? Why's a B-Tree?

B-Trees take the idea of a BST, and say "lets put some arrays in there; computers love arrays". Rather than each node consisting of a *single* element with two children, B-Tree nodes have an *array* of elements with an *array* of children.

Specifically, for some fixed constant *B*, each node contains between *B-1* and *2B-1* elements in sorted order (root can have as few as one element). An *internal* node (one which has children) with *k* elements has *k+1* children. In this way each element still has a "left" and "right" child, but e.g. the 2nd child contains elements strictly between the first and second element.

![Example B-Tree from Wikimedia Commons][btree-img]

[Example B-Tree from Wikimedia Commons][btree-attr]

B-Trees have historically been popular as a data structure stored on *disk*. This is because  accessing disk is a *super* slow operation, but you get back big chunks at once. So if you e.g. pick *B = 1000*, then you can grab a thousand entries in the tree all at once and process them in RAM relatively instantly. Your tree will also be *really* shallow, meaning each search will maybe hit the disk by following a pointer only a couple times. Sound familiar? This is exactly the cache-hit problem! The difference between disk and ram is *very* similar to the difference between ram and cache, but with the scales a bit different. In theory, we should be able to use the same ideas to make a faster search tree.

I'll briefly cover the three primary operations in a B-Tree here, but if you're really interested, I highly recommend checking out the [excellent description][ods-btree] found in [Open Data Structures][ods], which is available in a few different programming/human languages, completely free, and licensed under a creative commons license. It is the primary reference I used for the standard Rust implementation, though I only really used it for the high-level details. (disclaimer: it is primarily written by one of my supervisors)

Once constructed, searching for a key is the same basic idea as in a BST, but rather than compare to just one element per-node, you search a node for the smallest element larger than the key. Then you recursively search that element's left child (or the last child if no such element exists). How you choose to search is an implementation detail: you can go linear, binary, or anything between.

Inserting into a B-Tree involves searching for where the element to insert would be if it *was* contained (which always terminates at a leaf if it's not in there), doing an ordered insertion into that node's arrays (so shifting about B elements in an array), and then potentially performing an overflow handling operation. Overflow occurs when the node to insert into is already full. The solution is fairly simple: make a new node, copy half of the elements into it, and insert that into the parent using an element from the split node. This essentially "punts" the insertion problem to the parent node. If overflow makes it all the way to the root, we simply make a new root and insert the two halves of the old root into the new one.

Removing from a B-Tree is the "hard" operation. Like insertion, you first search for the element normally. If it's not in a leaf node, you need to swap it with the smallest element in its right-subtree, so that it *is* at a leaf. Then you do an ordered array removal (again, shifting about B elements in an array), and potentially handle underflow. Underflow occurs when a node has less elements than the allowed minimum. Handling underflow is a two phase process. First, you try to steal an element from a neighbour. If they have elements to spare, this works fine. However if they are *also* minimally full, this would just cause *them* to underflow. In this case we merge the two nodes into one node, stealing the separating element from the parent along the way. Like overflow, this punts the removal problem to the parent. If underflow makes it to the root, we replace the root with its single remaining child.

If that was a lot to take in, don't worry. It's not that important. If you really want to get it, [Open Data Structures][ods-btree] has a way more detailed description, code, and diagrams.

This is where we see that B-Trees have a significant cache-work trade-off built into them in the form of *B*. BSTs usually require O(log<sub>2</sub> n) time for all operations. For B-Trees, search takes O(log<sub>2</sub>n) time (if binary searching of the nodes), and mutation takes O(B + log<sub>B</sub> n) amortized time. So if you really crank up B you're looking at doing more "work" to perform mutations, *but better cache efficiency while doing it*. At one extreme (*B = 1000*), your tree will be maybe two-or-three layers deep, with you binary-searching and inserting into massive sorted arrays. At another extreme (*B = 2*), you basically get a BST.

How you search the nodes is also a cache-work tradeoff. Linear search is of course the cache-friendliest thing you can do, but takes O(B) time. Binary search is a bit less cache friendly, but takes O(log B) time. For the B I chose as the default (6) from some hasty micro-benchmarking, linear search blew binary out of the water. We *might* just have a bad binary search implementation in the standard library though (in theory, standard binary search should do whatever is fastest anyway, even if that means linear search-- future work for someone interested!). This of course flies in the face of naive asymptotic analysis, and that's because Real Computers are Complicated. Cache, inlining, branch-prediction, and good-old hidden-constant costs all interact in funky ways that you really need to profile!

On the note of allocations, rather than allocating once per node like BSTs, we allocate only once per B elements on average. That's basically an order of magnitude reduction for a reasonable choice of B! Niiice.

On the note of wasted space, this is trickier to compute. There's tons of ways to represent the nodes that will have significant space-time trade-offs. For simplicity I will address this issue at only a high-level. Remark that there is *basically* only one child-pointer per element, plus a few constant fiddly bits (the right-most child-pointer, a counter for the number of elements in the node, probably some pointers to the arrays, possibly B itself). If space is your only concern you can really crank B up and have basically 1 pointer wasted per element. This gets even better when you realize you can just *not* allocate space for pointers on leaves (which will never become internal due to the way the split and merge operations work). Then you have only the constant node overhead which you can wash out with a huge B to basically 0 overhead. Note also that the vast majority of your nodes will be leaves.

However if your nodes aren't packed to capacity, you now have wasted space in the form of unused element slots. Also, rather than storing a pointer to a child, you might instead store the children by-value if you store the arrays themselves as pointers in your nodes. This will bloat up the child array as nodes are going to be bigger than a pointer, exacerbating the wasted space for unused elements slots (because they imply unused child slots).

This tradeoff isn't a space we've adequately explored in Rust for me to give a really good analysis here. Part of the problem is that fixed-sized by-value arrays in Rust kind of suck because we don't have type-level integers. So you can't have a `Node<K, V, B>`. As a result we currently heap-allocate the arrays rather than the whole nodes, and then opt for the bloaty by-value children approach. For simplicity/safety we've also opted to store B on each node instance. Hopefully when we get the tooling for type-level numbers in Rust we can explore the options here better.

Finally, I'd just like to note that this isn't a total slam-dunk for B-Trees. The unique association of elements to nodes in BSTs means that they can more cleanly support various intrusive and simultaneous manipulation tricks. [As I understand it][google-btree], certain iterator invalidation requirements in the C++ STL basically make B-Trees a non-starter. Meanwhile [jemalloc][] maintains a pair of intrusive BSTs over the same set of data.

B-Trees also appear to require more code to implement than a simple BST, meaning they will have more code, which will potentially hurt the CPUs cache for the actual *code*. Although I would argue B-Tree code is often conceptually *simpler* than BST code. There's just *more* of it.

It's also not totally free perf, either. You need to write a good implementation with a good compiler backing you up. Unfortunately `rustc` is just an "okay" compiler right now, and it often messes stuff up.

## Okay But Seriously the Implementation

Alright, let's talk some actual implementation details. In particular I want to get started looking at the representation of my naive implementation. If you want, you can browse [the full source as it was when first merged][naive-impl].

BTreeMap is a key-value store, so an "element" is a key-value pair. Right away this gives us a design decision to make: we can store key-value pairs in a single array, or split them into two separate arrays of keys and values. An array of (key, value) is unlikely to be the right choice here for a couple reasons. First, we spend all of our search time interested in keys, and not values. First, since we want to use B-Trees for cache reasons, it seems silly to clog up the caches for our key searches with values we don't actually care about. Second, we'll probably be wasting more space for padding in the general case by insisting on (key, value).

Here's what I went with:

```
pub struct Node<K, V> {
    keys: Vec<K>,
    edges: Vec<Node<K, V>>,
    vals: Vec<V>,
}
```

First off: definitely not optimal. `Vec`'s representation is `(ptr, capacity, length)`, so that means this representation is basically 9 pointers big. However the capacity isn't needed, because all of these arrays should never change size. `keys` and `vals` should have exactly space for `2B - 1` elements, and `edges` should have space for `2B`. Length is similarly redundant to track 3 times; the length of one implies the length of the others. Finally, we're actually doing *3* allocations per node. Ick. All in all, if you wanted to get down-and-dirty, you could crush this all down to a single ptr, a single len, and a single allocation. You know, casually shave off 7 ptrs of size.

You can also see that I'm taking the bloaty by-value-edges approach discussed in the previous section. I *could* have Boxed the nodes up to make the edges array leaner, but that would add more indirection and a bigger memory footprint for "full" nodes.

That said it's definitely correct and safe, and I don't need to implement all the damn Vec logic myself! If you look closely, you can also see an adorable attempt at a micro-optimization by having keys "first" followed by edges. The logic being that during search we are mostly interested in keys, with a secondary interest in edges, and no interest in values.

As for BTreeMap itself:

```
pub struct BTreeMap<K, V> {
    root: Node<K, V>,
    length: uint,
    depth: uint,
    b: uint,
}
```

Root, length, and b are all pretty obvious fields to include (again, no type-level integers, so b has to be stored at runtime). Depth is a bit odd, though. B-Trees are a bit interesting in that all leaves are at the same depth, and that depth only changes when you modify the root. The consequence of this is that you can easily track the depth, and if you do you have a precise upper-bound on how far any search path will be. And since most values are stored in leaves, it's a pretty good guess at the exact length, too. We'll see where we can use this later, but even then it's potentially a fairly dubious inclusion. I don't recall doing any actual profiling, it just made sense at the time. *shrug*

Also a full-blown pointer-sized integer for `b` and `depth` is absolutely overkill. u16 if not u8 should be big enough for anything. I'll stress again that this design was strictly interested in *correctness*. :)

Finally, I split the collection up into two modules: `node` and `map`. `node` contains all the understanding of what a node "is". How to search, insert, remove, and the local parts of underflow and overflow handling. map, meanwhile, handles the higher-level logic of traversing and manipulating the nodes. `map` has no privileged information of `node`, it consumes a public interface provided by `node`. In this way we should be able to change the representation without having to change `map` much. This also marks a *safety* boundary, which is a concept that isn't often discussed in Rust development, but I think is important to think about.

In an ideal world, calling a safe (not `unsafe`) function should always be safe. But in internal APIs it can easily be the case that calling an otherwise safe function at the wrong time *can* be unsafe. This is because we generally assume that some underlying *state* is consistent. Such as the `len` field in a Vec being accurate, or the `ptr` field pointing to allocated memory. In this sense safety becomes a bit of a lie from an internal perspective. However what we *can* (and should) guarantee is that a consumer of our public safe API will always be safe. Internally we can cause total chaos and havoc, but as long as invariants are restored and all inputs are correctly handled, the *public* API will be safe. It also lets us play a bit fast-and-loose with safety in our private methods, because it can be tedious to ensure that some utility function handles inputs that we don't actually care about.

Alright, that's structure out of the way, what does actual *code* look like. Here's searching in its entirety (thank god I'm obsessive about documenting implementation details):

```
// map.rs

impl<K: Ord, V> Map<K, V> for BTreeMap<K, V> {
    // Searching in a B-Tree is pretty straightforward.
    //
    // Start at the root. Try to find the key in the current node. If we find it, return it.
    // If it's not in there, follow the edge *before* the smallest key larger than
    // the search key. If no such key exists (they're *all* smaller), then just take the last
    // edge in the node. If we're in a leaf and we don't find our key, then it's not
    // in the tree.
    fn find(&self, key: &K) -> Option<&V> {
        let mut cur_node = &self.root;
        loop {
            match cur_node.search(key) {
                Found(i) => return cur_node.val(i),
                GoDown(i) => match cur_node.edge(i) {
                    None => return None,
                    Some(next_node) => {
                        cur_node = next_node;
                        continue;
                    }
                }
            }
        }
    }
}
```

```
// node.rs

impl<K: Ord, V> Node<K, V> {
    /// Searches for the given key in the node. If it finds an exact match,
    /// `Found` will be yielded with the matching index. If it fails to find an exact match,
    /// `GoDown` will be yielded with the index of the subtree the key must lie in.
    pub fn search(&self, key: &K) -> SearchResult {
        // FIXME(Gankro): Tune when to search linear or binary based on B (and maybe K/V).
        // For the B configured as of this writing (B = 6), binary search was *singnificantly*
        // worse for uints.
        self.search_linear(key)
    }

    fn search_linear(&self, key: &K) -> SearchResult {
        for (i, k) in self.keys.iter().enumerate() {
            match k.cmp(key) {
                Less => {},
                Equal => return Found(i),
                Greater => return GoDown(i),
            }
        }
        GoDown(self.len())
    }
}
```

So BTreeMap's search is basically just a loop that asks the current node to search itself, and handles the result accordingly by returning or following an edge. Meanwhile search in Node is just a simple linear search (with a nice little comment from me about why that is). Simple stuff. Of note is the fact that the node and map communicate via raw integer indices (with a nice custom enum to communicate what the search result means). This is simply the "easy" choice, but it *does* mean the safe Node API has to do bounds-checking on those indices, since it has no way of knowing where those came from. We *could* do unchecked indexing, but we'd rather be safe to start. At this stage of development, an index-out-of-bounds is much easier to debug than simply invoking Undefined Behaviour.

In this particular case it turns out to not *really* matter. We leverage the bounds-check to do an implict is-a-leaf check with `match cur_node.edge(i)`. Leaves have no allocated edges, so any index is out-of-bounds. Meanwhile our Map API already returns an Option for the value, so we're just forwarding the bounds-check Option in `return cur_node.val(i)`.

Also I do a pointless `continue` in `find` for funsies and a bit of semantics.

Let's move on to insertion (the `swap` name was the convention at the time; this is now called `insert` -- oh hey, and does anyone remember when we had these collection traits???):

```
impl<K: Ord, V> MutableMap<K, V> for BTreeMap<K, V> {
    // Insertion in a B-Tree is a bit complicated.
    //
    // First we do the same kind of search described in `find`. But we need to maintain a stack of
    // all the nodes/edges in our search path. If we find a match for the key we're trying to
    // insert, just swap the vals and return the old ones. However, when we bottom out in a leaf,
    // we attempt to insert our key-value pair at the same location we would want to follow another
    // edge.
    //
    // If the node has room, then this is done in the obvious way by shifting elements. However,
    // if the node itself is full, we split node into two, and give its median key-value
    // pair to its parent to insert the new node with. Of course, the parent may also be
    // full, and insertion can propagate until we reach the root. If we reach the root, and
    // it is *also* full, then we split the root and place the two nodes under a newly made root.
    //
    // Note that we subtly deviate from Open Data Structures in our implementation of split.
    // ODS describes inserting into the node *regardless* of its capacity, and then
    // splitting *afterwards* if it happens to be overfull. However, this is inefficient.
    // Instead, we split beforehand, and then insert the key-value pair into the appropriate
    // result node. This has two consequences:
    //
    // 1) While ODS produces a left node of size B-1, and a right node of size B,
    // we may potentially reverse this. However, this shouldn't effect the analysis.
    //
    // 2) While ODS may potentially return the pair we *just* inserted after
    // the split, we will never do this. Again, this shouldn't effect the analysis.

    fn swap(&mut self, key: K, mut value: V) -> Option<V> {
        // This is a stack of rawptrs to nodes paired with indices, respectively
        // representing the nodes and edges of our search path. We have to store rawptrs
        // because as far as Rust is concerned, we can mutate aliased data with such a
        // stack. It is of course correct, but what it doesn't know is that we will only
        // be popping and using these ptrs one at a time in child-to-parent order. The alternative
        // to doing this is to take the Nodes from their parents. This actually makes
        // borrowck *really* happy and everything is pretty smooth. However, this creates
        // *tons* of pointless writes, and requires us to always walk all the way back to
        // the root after an insertion, even if we only needed to change a leaf. Therefore,
        // we accept this potential unsafety and complexity in the name of performance.
        //
        // Regardless, the actual dangerous logic is completely abstracted away from BTreeMap
        // by the stack module. All it can do is immutably read nodes, and ask the search stack
        // to proceed down some edge by index. This makes the search logic we'll be reusing in a
        // few different methods much neater, and of course drastically improves safety.
        let mut stack = stack::PartialSearchStack::new(self);

        loop {
            // Same basic logic as found in `find`, but with PartialSearchStack mediating the
            // actual nodes for us
            match stack.next().search(&key) {
                Found(i) => unsafe {
                    // Perfect match, swap the values and return the old one
                    let next = stack.into_next();
                    mem::swap(next.unsafe_val_mut(i), &mut value);
                    return Some(value);
                },
                GoDown(i) => {
                    // We need to keep searching, try to get the search stack
                    // to go down further
                    stack = match stack.push(i) {
                        stack::Done(new_stack) => {
                            // We've reached a leaf, perform the insertion here
                            new_stack.insert(key, value);
                            return None;
                        }
                        stack::Grew(new_stack) => {
                            // We've found the subtree to insert this key/value pair in,
                            // keep searching
                            new_stack
                        }
                    };
                }
            }
        }
    }
}
```

Those comments are pretty thorough, and nail down the basic logic, but there's some new stuff here. As a minor point, I *do* use an unchecked index in `next.unsafe_val_mut(i)`. This was basically more to avoid an unwrap than a bounds-check, if I recall correctly. Less unwinding-bloat, cleaner code.

However the big new introduction is this idea of a search stack. Unlike some BSTs, B-Trees absolutely *do not* store a "parent" pointer. This is because we do a lot of bulk shifting of nodes, and having to update visit all the children to update their parent pointers would completely trash the whole "cache-friendly" thing. However insertion (and removal) requires us to potentially walk back up the search path to modify ancestors. Therefore, we need to maintain an explicit stack of visited nodes.

Where this would be a fairly benign thing to do in many other languages, this is pretty hazardous from Rust's perspective. As the comment in the code discusses, all the compiler can see is that we're taking a mutable borrow of some node (a reference to a child), and then trying to give another mutable borrow out (storing a reference to it in a stack). From its perspective this is hazardous, and it's totally right. We *could* just take the reference back out of the stack and mutate it while it's borrowed. So we're forced to go over the compiler's head and use raw `*mut` pointers in the stack. These don't borrow the collection, so it's "fine" as far as the compiler is concerned. It is now however considered unsafe to dereference them.

This is where the SearchStack abstraction is introduced. This was some new tech that we came up with to try to handle this problem a bit more gracefully than "fuck it: `Vec<*mut Node>`". To start, you create a *PartialSearchStack* by passing it a mutable reference to a BTreeMap. The stack then initializes itself to have the root of the tree as its "next" value. We then start searching as we normally would, but by continuously asking the stack for the "next" value.

Things get interesting here: `stack = match stack.push(i)`. PartialSearchStack::push takes the index of the edge to follow next. However it actually takes self by-value. This means that is actually *consumes* the PartialSearchStack to push a value into it. There are then one of two results: Either the stack was able to follow the edge and `Grew`, or it wasn't, and we're `Done`. If it `Grew`, it's still partial, and we make that the new stack. If we're `Done`, then it is no longer partial. It is now a proper SearchStack. SearchStack has a completely different API from PartialSearchStack. You cannot add elements to a SearchStack, you can only ask it to `insert` or `remove` a value. In this case, we ask for an `insert`:

```
impl<'a, K, V> SearchStack<'a, K, V> {
    /// Inserts the key and value into the top element in the stack, and if that node has to
    /// split recursively inserts the split contents into the next element stack until
    /// splits stop.
    ///
    /// Assumes that the stack represents a search path from the root to a leaf.
    ///
    /// An &mut V is returned to the inserted value, for callers that want a reference to this.
    pub fn insert(self, key: K, val: V) -> &'a mut V {
        unsafe {
            let map = self.map;
            map.length += 1;

            let mut stack = self.stack;
            // Insert the key and value into the leaf at the top of the stack
            let (node, index) = self.top;
            let (mut insertion, inserted_ptr) = {
                (*node).insert_as_leaf(index, key, val)
            };

            loop {
                match insertion {
                    Fit => {
                        // The last insertion went off without a hitch, no splits! We can stop
                        // inserting now.
                        return &mut *inserted_ptr;
                    }
                    Split(key, val, right) => match stack.pop() {
                        // The last insertion triggered a split, so get the next element on the
                        // stack to recursively insert the split node into.
                        None => {
                            // The stack was empty; we've split the root, and need to make a
                            // a new one. This is done in-place because we can't move the
                            // root out of a reference to the tree.
                            Node::make_internal_root(&mut map.root, map.b, key, val, right);

                            map.depth += 1;
                            return &mut *inserted_ptr;
                        }
                        Some((node, index)) => {
                            // The stack wasn't empty, do the insertion and recurse
                            insertion = (*node).insert_as_internal(index, key, val, right);
                            continue;
                        }
                    }
                }
            }
        }
    }
}
```

Here we can see I got a bit lazy about being precise about what is-or-isn't unsafe. We're going to be dereffing a bunch of raw pointers, screw it, wrap it all in an `unsafe` block. So we start off by just ripping `self` into the constituent parts of `map`, `top`, and `stack`. Map and stack I hope are fairly self explanatory, but `top` is a bit interesting. You see we know our stack *has* to contain some value, so we've encoded this by keeping the "top" of the stack as a separate field. This way we don't have to do any `unwrap`s when we ask for the top of the stack, which a Vec (reasonably) reports as an Option.

Our stack contains (node, index) pairs, fully encoding the search path. We start by unconditionally asking the node to insert the given key-value pair into itself, and get back a couple values as a result. `insertion` is another custom enum to express the possible consequences of an insertion: either it `Fit`, or we had to `Split` (yay fun rhymes to remember complex algorithms). The node helpfully handles the actual split for us, and just spits out the key-value pair and new child we want to insert in the parent. We then pop the parent off the stack and ask it to do an insertion. If the stack runs out of nodes, then we know we've hit the root, and handle it accordingly.

The other return value is a bit weird. `inserted_ptr` is something that is actually totally useless for the parts of the API we've seen. It's a raw pointer to the inserted value, and `swap` doesn't care about that. It's actually for the *entry* API, which *does* return a reference to the inserted value:

```
impl<'a, K: Ord, V> VacantEntry<'a, K, V> {
    /// Sets the value of the entry with the VacantEntry's key,
    /// and returns a mutable reference to it.
    pub fn set(self, value: V) -> &'a mut V {
        self.stack.insert(self.key, value)
    }
}
```

The entry API works really nice with this design, because our "entry" is just a SearchStack. Yay code reuse!

Let's move on to removal (ne pop):

```
impl<K: Ord, V> MutableMap<K, V> for BTreeMap<K, V> {
    // Deletion is the most complicated operation for a B-Tree.
    //
    // First we do the same kind of search described in
    // `find`. But we need to maintain a stack of all the nodes/edges in our search path.
    // If we don't find the key, then we just return `None` and do nothing. If we do find the
    // key, we perform two operations: remove the item, and then possibly handle underflow.
    //
    // # removing the item
    //      If the node is a leaf, we just remove the item, and shift
    //      any items after it back to fill the hole.
    //
    //      If the node is an internal node, we *swap* the item with the smallest item in
    //      in its right subtree (which must reside in a leaf), and then revert to the leaf
    //      case
    //
    // # handling underflow
    //      After removing an item, there may be too few items in the node. We want nodes
    //      to be mostly full for efficiency, although we make an exception for the root, which
    //      may have as few as one item. If this is the case, we may first try to steal
    //      an item from our left or right neighbour.
    //
    //      To steal from the left (right) neighbour,
    //      we take the largest (smallest) item and child from it. We then swap the taken item
    //      with the item in their mutual parent that separates them, and then insert the
    //      parent's item and the taken child into the first (last) index of the underflowed node.
    //
    //      However, stealing has the possibility of underflowing our neighbour. If this is the
    //      case, we instead *merge* with our neighbour. This of course reduces the number of
    //      children in the parent. Therefore, we also steal the item that separates the now
    //      merged nodes, and insert it into the merged node.
    //
    //      Merging may cause the parent to underflow. If this is the case, then we must repeat
    //      the underflow handling process on the parent. If merging merges the last two children
    //      of the root, then we replace the root with the merged node.

    fn pop(&mut self, key: &K) -> Option<V> {
        // See `swap` for a more thorough description of the stuff going on in here
        let mut stack = stack::PartialSearchStack::new(self);
        loop {
            match stack.next().search(key) {
                Found(i) => {
                    // Perfect match. Terminate the stack here, and remove the entry
                    return Some(stack.seal(i).remove());
                },
                GoDown(i) => {
                    // We need to keep searching, try to go down the next edge
                    stack = match stack.push(i) {
                        stack::Done(_) => return None, // We're at a leaf; the key isn't in here
                        stack::Grew(new_stack) => {
                            new_stack
                        }
                    };
                }
            }
        }
    }
}
```

Same basic stuff as `swap`. Although here we manually `seal` the search stack. On to `remove` in the stack:

```
impl<'a, K, V> SearchStack<'a, K, V> {
    /// Removes the key and value in the top element of the stack, then handles underflows as
    /// described in BTree's pop function.
    pub fn remove(mut self) -> V {
        // Ensure that the search stack goes to a leaf. This is necessary to perform deletion
        // in a BTree. Note that this may put the tree in an inconsistent state (further
        // described in leafify's comments), but this is immediately fixed by the
        // removing the value we want to remove
        self.leafify();

        let map = self.map;
        map.length -= 1;

        let mut stack = self.stack;

        // Remove the key-value pair from the leaf that this search stack points to.
        // Then, note if the leaf is underfull, and promptly forget the leaf and its ptr
        // to avoid ownership issues.
        let (value, mut underflow) = unsafe {
            let (leaf_ptr, index) = self.top;
            let leaf = &mut *leaf_ptr;
            let (_key, value) = leaf.remove_as_leaf(index);
            let underflow = leaf.is_underfull();
            (value, underflow)
        };

        loop {
            match stack.pop() {
                None => {
                    // We've reached the root, so no matter what, we're done. We manually
                    // access the root via the tree itself to avoid creating any dangling
                    // pointers.
                    if map.root.len() == 0 && !map.root.is_leaf() {
                        // We've emptied out the root, so make its only child the new root.
                        // If it's a leaf, we just let it become empty.
                        map.depth -= 1;
                        map.root = map.root.pop_edge().unwrap();
                    }
                    return value;
                }
                Some((parent_ptr, index)) => {
                    if underflow {
                        // Underflow! Handle it!
                        unsafe {
                            let parent = &mut *parent_ptr;
                            parent.handle_underflow(index);
                            underflow = parent.is_underfull();
                        }
                    } else {
                        // All done!
                        return value;
                    }
                }
            }
        }
    }

    /// Subroutine for removal. Takes a search stack for a key that might terminate at an
    /// internal node, and mutates the tree and search stack to *make* it a search stack
    /// for that same key that *does* terminates at a leaf. If the mutation occurs, then this
    /// leaves the tree in an inconsistent state that must be repaired by the caller by
    /// removing the entry in question. Specifically the key-value pair and its successor will
    /// become swapped.
    fn leafify(&mut self) {
        unsafe {
            let (node_ptr, index) = self.top;
            // First, get ptrs to the found key-value pair
            let node = &mut *node_ptr;
            let (key_ptr, val_ptr) = {
                (node.unsafe_key_mut(index) as *mut _,
                 node.unsafe_val_mut(index) as *mut _)
            };

            // Try to go into the right subtree of the found key to find its successor
            match node.edge_mut(index + 1) {
                None => {
                    // We're a proper leaf stack, nothing to do
                }
                Some(mut temp_node) => {
                    //We're not a proper leaf stack, let's get to work.
                    self.stack.push((node_ptr, index + 1));
                    loop {
                        // Walk into the smallest subtree of this node
                        let node = temp_node;
                        let node_ptr = node as *mut _;

                        if node.is_leaf() {
                            // This node is a leaf, do the swap and return
                            self.top = (node_ptr, 0);
                            node.unsafe_swap(0, &mut *key_ptr, &mut *val_ptr);
                            break;
                        } else {
                            // This node is internal, go deeper
                            self.stack.push((node_ptr, 0));
                            temp_node = node.unsafe_edge_mut(0);
                        }
                    }
                }
            }
        }
    }
}
```

Nothing super-new or mind-blowing here either. The control-flow is *a bit* different, but basically the same. We ask the node to remove from itself, and if we need to handle underflow, we get pop-off the parent and tell it to handle it. Repeat until finished.

The private subroutine to leafify the stack, meanwhile, is probably the most troubling manipulation we do in this module. One of my revisions definitely accidentally broke it once, causing me a ton of debugging pain. 

I could dig into the implementation details of Node a bit, but honestly don't think it would be that instructive. You can [check out the source][naive-impl] if you want, but it's really just a lot of moving data around. Not much to say there.

So that's the naive implementation. I have a few issues with it:

* it has an abhorrently inefficient (but convenient!) data representation,
* it passes around plain indices that we have to bounds-check to be safe (or be unsafe)
* the search-stack design is *a bit* half-assed. e.g. we completely drop down to Vec<*mut> in insert/remove. Also you can `seal` early and then `insert`, and it will do something wrong.

As an aside, I'd like to reassert that iterators are totally awesome magic here, because the whole problem that SearchStack solves is a complete non-issue for iterators. Because the reference yielded by `next` in an iterator doesn't borrow the iterator itself, you can just build a simple Node iterator and push as many of those onto a stack as you want and it just works perfectly without any problems. Just iterate the top of the stack. If it's you hit an edge push the node's iterator on. If you finish an iterator just pop it off. Boom easy tree traversal.

I'm not going to go into BTreeMap's iterator code in this, even though it's actually quite interesting. [I covered the interesting bits in the previous post][generics-post]. Everything else is just BTree-specific logic. pczarn's already written a much better version anyway.

## The Cool Impl

So then gereeter kicked down the door with a wild look in his eyes and started hacking this thing to pieces. Right off the bat, he tackled the obvious inefficient representation. Three disjoint Vecs is too much. Fortuntately, this is exactly the same problem that our HashMap faced. It wants to store three arrays for keys, values, and hashes. However it talks to the allocator directly to allocate a single big array of bytes to store all three arrays in. So he just ripped out the code there, tweaked it a bit for our usecase, and boom we've got better nodes. He dutifully doc'd up the struct explaining basically all the design decisions for me:

```
/// A B-Tree Node. We keep keys/edges/values separate to optimize searching for keys.
#[unsafe_no_drop_flag]
pub struct Node<K, V> {
    // To avoid the need for multiple allocations, we allocate a single buffer with enough space
    // for `capacity` keys, `capacity` values, and (in internal nodes) `capacity + 1` edges.
    // Despite this, we store three separate pointers to the three "chunks" of the buffer because
    // the performance drops significantly if the locations of the vals and edges need to be
    // recalculated upon access.
    //
    // These will never be null during normal usage of a `Node`. However, to avoid the need for a
    // drop flag, `Node::drop` zeroes `keys`, signaling that the `Node` has already been cleaned
    // up.
    keys: Unique<K>,
    vals: Unique<V>,

    // In leaf nodes, this will be null, and no space will be allocated for edges.
    edges: Unique<Node<K, V>>,

    // At any given time, there will be `_len` keys, `_len` values, and (in an internal node)
    // `_len + 1` edges. In a leaf node, there will never be any edges.
    //
    // Note: instead of accessing this field directly, please call the `len()` method, which should
    // be more stable in the face of representation changes.
    _len: uint,

    // FIXME(gereeter) It shouldn't be necessary to store the capacity in every node, as it should
    // be constant throughout the tree. Once a solution to this is found, it might be possible to
    // also pass down the offsets into the buffer that vals and edges are stored at, removing the
    // need for those two pointers.
    //
    // Note: instead of accessing this field directly, please call the `capacity()` method, which
    // should be more stable in the face of representation changes.
    _capacity: uint,
}
```

Some minor points for some of the fancier stuff. `#[unsafe_no_drop_flag]` is an optimization that is on its way out once the way destructors work changes. For now it's a necessary evil to avoid some extra bloat on the struct. `Unique` is an alias for `*mut` that just asserts some things to the type system about ownership of the pointed-to values. Using it just auto-implements some multi-threading traits for us. Also some fields are prefixed with `_` to encourage use of getters.

As discussed in the comments and earlier sections, this is still not The Ideal Representation. We're gonna have to wait for type-level integers to get the design we *really* want, but for now this is a definite improvement. From 9 ptrs down to 5. Note that we've *intentionally* accepted some bloat in the name of profiled performance.

The unfortunate result of this is having to re-implement a bunch of `unsafe` logic from both Vec and HashMap to deal with these Nodes. I have plans to undo this duplication in the longterm, but we don't have the type system to do it right at the moment. Just another reason why 1.0 Will Suck :P

The awesome thing about this change is that my `node`/`map` separation worked! Minimal changes were made to `map`. However we were a bit squeemish about it because it was introducing a *huge* amount of new unsafe code. I mentioned off-hand an idea about a more robust handle-based API to replace the indices we pass around and gereeter just went *crazy* with it. It's... glorious ;_;

First off, the handle type:

```
pub struct Handle<NodeRef, Type, NodeType> {
    node: NodeRef,
    index: uint
}
```

Well that's... odd. Our handle is generic over three types, but only one type shows up in the body? What's going on? Well first off let's talk about the one that is used: NodeRef. The Handles are generic over the *kind* of reference to a node they have. This is primarily to deal with the differences between `&mut` and `&`. Certain handle APIs should only be available to a mutable reference, but some should be available to both. This is primarily handled by having some `impl`s state that the type implements `DerefMut`, while others only require `Deref`. However our search-stacks also want to have raw-ptrs, so we also support the raw-ptrs here to, mostly as an intermediate form that can be downgraded from or unsafely upgraded into a proper `&` or `&mut` handle.

So what's up with those other types? That right there is leveraging a thing called *phantom types*. Phantom types are a way to mark up values with compile-time-only metadata that guarantees a certain value isn't used the wrong way. A canonical example of using phantom types would be something like having a `String` type that can be `String<Raw>` or `String<Escaped>`. User inputs come in as `Raw`, and APIs that expect all the data to be escaped (like say a database query) only accept a `String<Escaped>`. The only way to convert a `String<Raw>` to a `String<Escaped>` is to pass it to pass it to an escaping function. What are `Raw` and `Escaped`? Just some concrete empty types, nothing more.

So what phantom types do we work with on our Handle?

```
pub mod handle {
    // Handle types.
    pub enum KV {}
    pub enum Edge {}

    // Handle node types.
    pub enum LeafOrInternal {}
    pub enum Leaf {}
    pub enum Internal {}
}
```

Handles can either be to a key-value pair, or to an edge. Similarly, they can know if they are a handle to a leaf, internal, or unknown type of node. Certain combinations of these phantom types expose completely different APIs on the Nodes! For instance, you may have noticed that in the naive implementation we had some `_as_leaf` and `_as_internal` methods on the nodes. In the naive design it was completely up to use to use these correctly. Consequently they had to be written to not do something memory-unsafe if you misused them. Although they *definitely* would have still freaked out and made the collection do crazy things that are totally wrong.

But with *handles* this is a thing of the past. Of course, we get some pretty hard-core generic soup, but it's not that hard to grok if you stare at it for a bit:

```
impl<K, V, NodeRef> Handle<NodeRef, handle::Edge, handle::Leaf> where
    NodeRef: Deref<Target=Node<K, V>> + DerefMut,
{
    /// Tries to insert this key-value pair at the given index in this leaf node
    /// If the node is full, we have to split it.
    ///
    /// Returns a *mut V to the inserted value, because the caller may want this when
    /// they're done mutating the tree, but we don't want to borrow anything for now.
    pub fn insert_as_leaf(mut self, key: K, value: V) ->
            (InsertionResult<K, V>, *mut V) {
            // ...
    }
}
```

So what does search look like now? Well, we refactored the public collection APIs a fair bit, so the names and signature have changed a bit, but the core logic is largely the same:

```
impl<K: Ord, V> BTreeMap<K, V> {
    pub fn get<Sized? Q>(&self, key: &Q) -> Option<&V> where Q: BorrowFrom<K> + Ord {
        let mut cur_node = &self.root;
        loop {
            match Node::search(cur_node, key) {
                Found(handle) => return Some(handle.into_kv().1),
                GoDown(handle) => match handle.force() {
                    Leaf(_) => return None,
                    Internal(internal_handle) => {
                        cur_node = internal_handle.into_edge();
                        continue;
                    }
                }
            }
        }
    }
}

impl<K: Ord, V> Node<K, V> {
    /// Searches for the given key in the node. If it finds an exact match,
    /// `Found` will be yielded with the matching index. If it doesn't find an exact match,
    /// `GoDown` will be yielded with the index of the subtree the key must lie in.
    pub fn search<Sized? Q, NodeRef: Deref<Target=Node<K, V>>>(node: NodeRef, key: &Q)
                  -> SearchResult<NodeRef> where Q: BorrowFrom<K> + Ord {
        // FIXME(Gankro): Tune when to search linear or binary based on B (and maybe K/V).
        // For the B configured as of this writing (B = 6), binary search was *significantly*
        // worse for uints.
        let (found, index) = node.search_linear(key);
        if found {
            Found(Handle {
                node: node,
                index: index
            })
        } else {
            GoDown(Handle {
                node: node,
                index: index
            })
        }
    }

    fn search_linear<Sized? Q>(&self, key: &Q) -> (bool, uint) where Q: BorrowFrom<K> + Ord {
        for (i, k) in self.keys().iter().enumerate() {
            match key.cmp(BorrowFrom::borrow_from(k)) {
                Greater => {},
                Equal => return (true, i),
                Less => return (false, i),
            }
        }
        (false, self.len())
    }
}

/// Represents the result of a search for a key in a single node
pub enum SearchResult<NodeRef> {
    /// The element was found at the given index
    Found(Handle<NodeRef, handle::KV, handle::LeafOrInternal>),
    /// The element wasn't found, but if it's anywhere, it must be beyond this edge
    GoDown(Handle<NodeRef, handle::Edge, handle::LeafOrInternal>),
}
```

We still ask the node to search itself, but now it comes back with a handle. Nodes are now fairly dumb, and don't have much of an API. They're primarily manipulated through handles, which we primarily get out of searches. The type of handle depends on the result of the search. If we `Found` the key, you get a KV handle. If we didn't, you get an `Edge` handle. This means you can only do sane operations with the result. For instance, you can't request a key using an edge's index. Also, the handle "forwards" the reference that you give it. For now this just means everything stays at the same level of mutability, but later we'll see how else this is important.

Another new addition is the `force` method, which asks the handle to figure out if it's actually a leaf or internal node. This used to be implicit in a bad edge-indexing, but now it's explicit. We don't have to check anymore if any indexing operations are successful, because the handle types guarantee it without bounds-checks in a totally safe way!

Alright, search is covered, how's insertion looking? Well, insertion is a bit trickier now. Before, we guaranteed some level of path sanity by `push` taking an index. The SearchStack could be sure it had a full path to a given node because it was it did all the indexing for us. It just told us what the resulting node was. But now we have handles, which *include* the node. We could do a run-time check that the new handle's node matches what we expected, but that's... a runtime check. And not a super cheap one either.

So gereeter did a beautiful thing. Remember when I said that `search` forwards the given reference? Well, that's *super* important now. To perform a search with a search-stack, we ask the stack for the next node as before, but it now hands us a `Pusher` and an `IdRef` *wrapper* for a node reference. Critically, the pusher and wrapper both contain a `marker::InvariantLifetime`, which is a special type in Rust. Normally, these Lifetime markers are to remember or otherwise borrow some reference correctly. The classic example is to have a lifetime tied to a `*mut`. However here it's being used for *straight up magic*. The InvariantLifetime is a finger-print that tells the `Pusher` that the given `IdRef` is its sister. The `Pusher` consequently only accepts a handle containing its sister. And this is all done with compile-time information!

Here's the code:

```
impl<K: Ord, V> BTreeMap<K, V> {
    pub fn insert(&mut self, mut key: K, mut value: V) -> Option<V> {
    // This is a stack of rawptrs to nodes paired with indices, respectively
    // representing the nodes and edges of our search path. We have to store rawptrs
    // because as far as Rust is concerned, we can mutate aliased data with such a
    // stack. It is of course correct, but what it doesn't know is that we will only
    // be popping and using these ptrs one at a time in child-to-parent order. The alternative
    // to doing this is to take the Nodes from their parents. This actually makes
    // borrowck *really* happy and everything is pretty smooth. However, this creates
    // *tons* of pointless writes, and requires us to always walk all the way back to
    // the root after an insertion, even if we only needed to change a leaf. Therefore,
    // we accept this potential unsafety and complexity in the name of performance.
    //
    // Regardless, the actual dangerous logic is completely abstracted away from BTreeMap
    // by the stack module. All it can do is immutably read nodes, and ask the search stack
    // to proceed down some edge by index. This makes the search logic we'll be reusing in a
    // few different methods much neater, and of course drastically improves safety.
    let mut stack = stack::PartialSearchStack::new(self);

    loop {
        let result = stack.with(move |pusher, node| {
            // Same basic logic as found in `find`, but with PartialSearchStack mediating the
            // actual nodes for us
            return match Node::search(node, &key) {
                Found(mut handle) => {
                    // Perfect match, swap the values and return the old one
                    mem::swap(handle.val_mut(), &mut value);
                    Finished(Some(value))
                },
                GoDown(handle) => {
                    // We need to keep searching, try to get the search stack
                    // to go down further
                    match handle.force() {
                        Leaf(leaf_handle) => {
                            // We've reached a leaf, perform the insertion here
                            pusher.seal(leaf_handle).insert(key, value);
                            Finished(None)
                        }
                        Internal(internal_handle) => {
                            // We've found the subtree to insert this key/value pair in,
                            // keep searching
                            Continue((pusher.push(internal_handle), key, value))
                        }
                    }
                }
            }
        });
        match result {
            Finished(ret) => { return ret; },
            Continue((new_stack, renewed_key, renewed_val)) => {
                stack = new_stack;
                key = renewed_key;
                value = renewed_val;
            }
        }
    }
}

impl<'a, K, V> PartialSearchStack<'a, K, V> {
    /// Breaks up the stack into a `Pusher` and the next `Node`, allowing the given closure
    /// to interact with, search, and finally push the `Node` onto the stack. The passed in
    /// closure must be polymorphic on the `'id` lifetime parameter, as this statically
    /// ensures that only `Handle`s from the correct `Node` can be pushed.
    ///
    /// The reason this works is that the `Pusher` has an `'id` parameter, and will only accept
    /// handles with the same `'id`. The closure could only get references with that lifetime
    /// through its arguments or through some other `IdRef` that it has lying around. However,
    /// no other `IdRef` could possibly work - because the `'id` is held in an invariant
    /// parameter, it would need to have precisely the correct lifetime, which would mean that
    /// at least one of the calls to `with` wouldn't be properly polymorphic, wanting a
    /// specific lifetime instead of the one that `with` chooses to give it.
    ///
    /// See also Haskell's `ST` monad, which uses a similar trick.
    pub fn with<T, F: for<'id> FnOnce(Pusher<'id, 'a, K, V>,
                                      IdRef<'id, Node<K, V>>) -> T>(self, closure: F) -> T {
        let pusher = Pusher {
            map: self.map,
            stack: self.stack,
            marker: marker::InvariantLifetime
        };
        let node = IdRef {
            inner: unsafe { &mut *self.next },
            marker: marker::InvariantLifetime
        };

        closure(pusher, node)
    }
}

impl<'id, 'a, K, V> Pusher<'id, 'a, K, V> {
    /// Pushes the requested child of the stack's current top on top of the stack. If the child
    /// exists, then a new PartialSearchStack is yielded. Otherwise, a VacantSearchStack is
    /// yielded.
    pub fn push(mut self, mut edge: node::Handle<IdRef<'id, Node<K, V>>,
                                                 handle::Edge,
                                                 handle::Internal>)
                -> PartialSearchStack<'a, K, V> {
        self.stack.push(edge.as_raw());
        PartialSearchStack {
            map: self.map,
            stack: self.stack,
            next: edge.edge_mut() as *mut _,
        }
    }

    /// Converts the PartialSearchStack into a SearchStack.
    pub fn seal<Type, NodeType>
               (self, mut handle: node::Handle<IdRef<'id, Node<K, V>>, Type, NodeType>)
                -> SearchStack<'a, K, V, Type, NodeType> {
        SearchStack {
            map: self.map,
            stack: self.stack,
            top: handle.as_raw(),
        }
    }
}
```

The final code ends up using a closure to correctly restrict the lifetimes, and a bit of dancing to safely move values in and out of it, but these are all zero-cost abstractions that should ideally get compiled away completely.

And that, my friends, is why you don't mess with gereeter. He will mess you up with type-systems beyond your wildest dreams.

Everything else is changed up in a similar way to work with these new APIs, but I don't think it would be particularly instructive to look at it in detail. [Here's a snapshot of the full impl as of this writing][modern-impl].

I think that's all the *really* interesting parts of BTreeMap. This post has gone entirely too long anyway. Have a great day!




[index]: http://cglab.ca/~abeinges/blah/
[rbt]: http://en.wikipedia.org/wiki/Red%E2%80%93black_tree
[bst]: http://en.wikipedia.org/wiki/Binary_search_tree
[b-tree]: http://en.wikipedia.org/wiki/B-tree
[ods]: http://opendatastructures.org/
[ods-btree]: http://opendatastructures.org/ods-python/14_2_B_Trees.html
[google-btree]: https://code.google.com/p/cpp-btree/
[jemalloc]: http://www.canonware.com/jemalloc/
[naive-impl]: https://github.com/rust-lang/rust/tree/b6edc59413f79016a1063c2ec6bc05516bc99cb6/src/libcollections/btree
[modern-impl]: https://github.com/rust-lang/rust/tree/340f3fd7a909b30509a63916df06f2b885d113f7/src/libcollections/btree
[generics-post]: http://cglab.ca/~abeinges/blah/rust-generics-and-collections/
[btree-attr]: http://commons.wikimedia.org/wiki/File:B-tree.svg
[bst-attr]: http://commons.wikimedia.org/wiki/File:Binary_search_tree.svg
[bst-img]: http://upload.wikimedia.org/wikipedia/commons/d/da/Binary_search_tree.svg
[btree-img]: http://upload.wikimedia.org/wikipedia/commons/6/65/B-tree.svg
[numbers]: http://surana.wordpress.com/2009/01/01/numbers-everyone-should-know/
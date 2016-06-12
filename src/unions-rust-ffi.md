---
layout: post
title: "Working with C unions in Rust FFI"
tags:
- rustlang
status: publish
type: post
published: true
---


When building a foreign function interface to C code, we will inevitably run into a struct that has a union. Rust has no built-in support for unions, so we must come up with a strategy on our own. A union is a type in C that stores different data types in the same memory location. There are a number of reasons why someone may want to choose a union, including: converting between binary representations of integers and floats, implementing pseudo-polymorphism and direct access to bits. I am going to focus on the pseudo-polymorphism case.

Edit: Added a [warning](#warning) at the bottom based on feedback from [Joe Groff](https://twitter.com/jckarter/status/710875695539310592).

Note: This post assumes the reader is familiar with [Rust FFI](https://doc.rust-lang.org/book/ffi.html), [endianess](https://en.wikipedia.org/wiki/Endianness) and [ioctl](https://en.wikipedia.org/wiki/Ioctl).

As an example, let us get the MAC address based on an interface name. We can summarize the steps to get the MAC address as follows:

   * Specify a request type to be used with `ioctl`. If I want to get the MAC (or hardware) address, I specify `SIOCGIFHWADDR`.
   * Write the interface name to `ifr_name`. An interface name is something like `eth0`.
   * Make the request using `ioctl`. A successful request will write some data to `ifr_ifru`.

For more details on how to get a MAC address, read this [howto](http://www.microhowto.info/howto/get_the_mac_address_of_an_ethernet_interface_in_c_using_siocgifhwaddr.html).

We need to use the C `ioctl` function and also pass the `ifreq` struct to the function. Looking in `/usr/include/net/if.h`, we can see that `ifreq` is defined as follows:

```C
struct  ifreq {
        char    ifr_name[IFNAMSIZ];
        union {
                struct  sockaddr ifru_addr;
                struct  sockaddr ifru_dstaddr;
                struct  sockaddr ifru_broadaddr;
                short   ifru_flags;
                int     ifru_metric;
                int     ifru_mtu;
                int     ifru_phys;
                int     ifru_media;
                int     ifru_intval;
                caddr_t ifru_data;
                struct  ifdevmtu ifru_devmtu;
                struct  ifkpi   ifru_kpi;
                u_int32_t ifru_wake_flags;
                u_int32_t ifru_route_refcnt;
                int     ifru_cap[2];
        } ifr_ifru;
}
```

The `ifr_ifru` union is where things start to get tricky. Glancing at the possible types in `ifr_ifru`, we notice that they are not all the same size. A `short` is 2 bytes and `u_int32_t` is 4 bytes. To complicate matters, we have a number of different struct definitions of unknown size. It is important that we figure out exactly what the size of the `ifreq` struct so we can write the proper Rust code. I wrote a small C program and figured out that `ifreq` uses 16 bytes for `ifr_name` and 24 bytes for `ifr_ifru`.

Armed with the knowledge of how large teh struct is, we can start representing this in Rust. One strategy is to make a specialized struct for each type in the union.

```rust
#[repr(C)]
pub struct IfReqShort {
    ifr_name: [c_char; 16],
    ifru_flags: c_short,
}
```

We can use `IfReqShort` when making a request of type `SIOCGIFINDEX`. This struct is smaller than the `ifreq` struct in C though. Even though we are expecting only 2 bytes to be written, the external ioctl interface expects there to be a total of 24 bytes. To be safe, let us add 22 bytes of padding at the end:


```rust
#[repr(C)]
pub struct IfReqShort {
    ifr_name: [c_char; 16],
    ifru_flags: c_short,
    _padding: [u8; 22],
}
```

We would then repeat this process for each type in the union. I find this a bit tedious to do as we need to make a lot of structs and be very careful to make them the correct size. Another way to represent the union is to have a buffer of raw bytes. We can make a single C representation of `ifreq` in Rust like this:

```rust
#[repr(C)]
pub struct IfReq {
    ifr_name: [c_char; 16],
    union: [u8; 24],
}
```

This `union` buffer can store the raw bytes for any type. We can now define methods to convert the raw bytes into the type we want. We will avoid unsafe code by not using transmute. Let us create a method to get the MAC address by converting the raw bytes in a `sockaddr` C type.

```rust
impl IfReq {
    pub fn ifr_hwaddr(&self) -> sockaddr {
        let mut s = sockaddr {
            sa_family: u16::from_be((self.data[0] as u16) << 8 | (self.data[1] as u16)),
            sa_data: [0; 14],
        };

        // basically a memcpy
        for (i, b) in self.data[2..16].iter().enumerate() {
            s.sa_data[i] = *b as i8;
        }

        s
    }
}
```

With this strategy, we have one struct and a method to convert the raw bytes into the concrete type that we want. Looking back at our `ifr_ifru` union, we will notice that there are at least two others requests that will also require me to create a `sockaddr` from raw bytes. To _DRY_ this up, we could implement a private method on `IfReq` to convert raw bytes to `sockaddr`. However, we can do better by abstracting away the details of creating a `sockaddr`, `short`, `int`, etc from `IfReq`. We really just want to _tell_ the union to give me back a specified type. So, let us make a `IfReqUnion` type to do that:

```rust
#[repr(C)]
struct IfReqUnion {
    data: [u8; 24],
}

impl IfReqUnion {
    fn as_sockaddr(&self) -> sockaddr {
        let mut s = sockaddr {
            sa_family: u16::from_be((self.data[0] as u16) << 8 | (self.data[1] as u16)),
            sa_data: [0; 14],
        };

        // basically a memcpy
        for (i, b) in self.data[2..16].iter().enumerate() {
            s.sa_data[i] = *b as i8;
        }

        s
    }

    fn as_int(&self) -> c_int {
        c_int::from_be((self.data[0] as c_int) << 24 |
                       (self.data[1] as c_int) << 16 |
                       (self.data[2] as c_int) <<  8 |
                       (self.data[3] as c_int))
    }

    fn as_short(&self) -> c_short {
        c_short::from_be((self.data[0] as c_short) << 8 |
                         (self.data[1] as c_short))
    }
}
```

We implement methods for each of the various types that make up the union. Now that our type conversions are handled by `IfReqUnion`, we can now implement the methods on `IfReq` like this:

```rust
#[repr(C)]
pub struct IfReq {
    ifr_name: [c_char; IFNAMESIZE],
    union: IfReqUnion,
}

impl IfReq {
    pub fn ifr_hwaddr(&self) -> sockaddr {
        self.union.as_sockaddr()
    }

    pub fn ifr_dstaddr(&self) -> sockaddr {
        self.union.as_sockaddr()
    }

    pub fn ifr_broadaddr(&self) -> sockaddr {
        self.union.as_sockaddr()
    }

    pub fn ifr_ifindex(&self) -> c_int {
        self.union.as_int()
    }

    pub fn ifr_media(&self) -> c_int {
        self.union.as_int()
    }

    pub fn ifr_flags(&self) -> c_short {
        self.union.as_short()
    }
}
```

We ended up with two structs. We have `IfReq` that represents the memory layout of the C struct `ifreq`. We will implement a method on `IfReq` for each type of `ioctl` request. We also have the `IfRequnion` struct that handles the various types the `ifr_ifru` union might be. We will create a method to for each type we need to handle. This is less work than creating a specialized struct for each type in the union and provides a better interface than doing the type conversion in `IfReq`.

Here is a more complete working [example](https://github.com/hjr3/carp-rs/blob/5d56a62b1a698949a7252db637d3fbeadbb62e3b/src/mac.rs). This is still a bit of a work in progress, but the tests pass and the code incorporates the above concepts discussed.

## Warning

The above approach is not without problems. In the case of `ifreq`, we were fortunate that `ifr_name` was 16 bytes and was aligned on a word boundary. If `ifr_name` was not aligned to a 4 byte word boundary, then we will run into a problem. Our `union` type is `[u8; 24]` which has an alignment of a single byte. This is not the same alignment as a type of size 24 bytes. Here is a short example to illustrate this point. If we have a C struct with the following union:

```C
struct foo {
    short x;
    union {
        int;
    } y;
}
```

The above `foo` struct has a size of 8 bytes. Two bytes for `x`, two more bytes for padding and four bytes for `y`. If we tried to write this in Rust:

```rust
#[repr(C)]
pub struct Foo {
    x: u16,
    y: [u8; 4],
}
```

The above `Foo` struct is only 6 bytes. Two bytes for x and then we can fit the first two `u8` elements of `y` in the same 4 byte _word_ as `x`. This subtle difference may cause problems when being passed to a C function that is expecting a struct of 8 bytes.

Until Rust natively supports unions, this sort of FFI is difficult to get right. Good luck, but be careful!

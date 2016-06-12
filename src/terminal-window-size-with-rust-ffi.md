---
layout: post
title: "Terminal Window Size With Rust FFI"
tags:
- rustlang
- ffi
status: publish
type: post
published: true
---

I  was writing some code in Rust and wanted to get the size of my terminal. This is currently [not implemented](https://github.com/rust-lang/rust/blob/470118f3e915cdc8f936aca0640b28a7a3d8dc6c/src/libstd/sys/unix/tty.rs#L44-46) in Rust though. I decided to read up on [The Foreign Function Interface Guide](http://static.rust-lang.org/doc/master/book/ffi.html) to figure out how to do it myself. The Foreign Function Interface (FFI) is how Rust code interfaces with native C code. I also found a great [Stack Overflow post](http://stackoverflow.com/a/1022961/775246) that showed me how to write native C to get the terminal size. Based on my research, I needed to do three things in order to get my terminal size:

   * Create a `winsize` struct in Rust.
   * Use or externalize the `ioctl` C function.
   * Use or externalize the `STDOUT_FILENO` and `TIOCGWINSZ` constants.

## Winsize Struct

Creating the `winsize` struct in Rust is pretty straight forward as Rust has structs too. I first needed to find the definition of `winsize` in C, so I did some googling and found the [sys/ioctl.h source](http://unix.superglobalmegacorp.com/Net2/newsrc/sys/ioctl.h.html). When defining the struct, we must tell Rust to represent the struct as a C struct using `#[repr(C)]`. If you read the FFI Guide, then you may be wondering about `#[repr(C, packed)]`. I talk about packing in more detail at the end of the [post](#to-pack-or-not). The struct members within `winsize` are all `unsigned short`. The C `unsigned short` is represented in Rust as `c_ushort` in the `libc` Rust module. We now have:

{% highlight rust %}
use libc::c_ushort;

#[repr(C)]
struct winsize {
    ws_row: c_ushort, /* rows, in characters */
    ws_col: c_ushort, /* columns, in characters */
    ws_xpixel: c_ushort, /* horizontal size, pixels */
    ws_ypixel: c_ushort /* vertical size, pixels */
} 
{% endhighlight %}

## ioctl

Now I need to figure out what to do about the `ioctl` function. Checking out the Rust docs leads me to the [ioctl function signature](http://doc.rust-lang.org/libc/funcs/bsd44/fn.ioctl.html) but I notice that this signature does not look like a variadic function (no varargs). I guess I have to externalize it in my code as a variadic function. I decided to check the Rust source to see if I could find an example of a variadic function and I stumbled in the [definition of ioctl](https://github.com/rust-lang/rust/blob/5b3cd3900ceda838f5798c30ab96ceb41f962534/src/libstd/sys/unix/c.rs#L78). This definition is variadic, so I guess rustdoc does not show this. Strange.

I have read that `ws_xpixel` and `ws_ypixel` are not used. I also have no use for them. I still opted to include them in my struct definition as I have no idea what `ioctl` is doing to that struct.

I have used this word _externalized_ a few times already, so maybe I should now define it. To _externalize_ something is to make that somethings C representation accessible to Rust code. You normally do this with function signatures, constants and global variables. Note that we did not externalize `winsize`, but instead copied the definition from C to Rust. We cannot externalize `winsize` as Rust needs to directly manage the definition and memory related to that struct.

## The Constants

Finally, I need to deal with my constants. I was pretty sure `STDOUT_FILENO` would already be in Rust. Sure enough, `libc::STDOUT_FILENO` exists. I was not so lucky with `TIOCGWINSZ`. The `TIOCGWINSZ` constant acts as a command to `ioctl`. If you read the source of `sys/ioctl.h`, you will notice the value of the commands is based on some rules that encode information to `ioctl`. There is a fair amount of bit twiddling going on to generate these values. Even if we do the bitwise math by hand, we should still check our work. To do that, I wrote a simple C program that would tell us the proper hex value of `TIOCGWINSZ`:

{% highlight C %}
#include <sys/ioctl.h>
#include <stdio.h>
#include <unistd.h>

int main (int argc, char **argv)
{
    printf("0x%x", TIOCGWINSZ);
    return 0;
}
{% endhighlight %}

Using this value I can create the same constant in Rust:

{% highlight rust %}
const TIOCGWINSZ: c_ulong = 0x40087468;
{% endhighlight %}

## Putting It All Together

My function for `get_winsize` now looks like this:

{% highlight rust %}
fn get_winsize() -> IoResult<(isize, isize)> {
    let w = winsize { ws_row: 0, ws_col: 0, ws_xpixel: 0, ws_ypixel: 0 };
    let r = unsafe { ioctl(STDOUT_FILENO, TIOCGWINSZ, &w) };
     
    match r {
        0 => Ok((w.ws_col as isize, w.ws_row as isize)),
        _ => {
            return Err(standard_error(ResourceUnavailable))
        }
    }
} 
{% endhighlight %}

I initialize my variable containing a `winsize` struct with values of zero, just like I would `memset(w, 0, sizeof(winsize))` in C. In order to use the externalized `ioctl` function, we have to wrap the code in `unsafe {}` blocks. This informs Rust this code is not to be checked by the compiler for safety. The `ioctl` function follows the C convention of returning a `0` for success and a `-1` for an error. If an error occurs, I decided to throw an existing `IoResult` error already in Rust. I need to spend a little more time to externalize the `errno` global variable in C so I can get the exact error. If the function is successful, I return the width and height as a tuple.

Here is a [gist](https://gist.github.com/hjr3/0cbe1ac2f10e6e3df96a) of the complete program, including a simple test. This puts all the peices discussed above together and will properly calculate the terminal window size when executed.

## To Pack Or Not

If you see a struct defined with `__attribute__((__packed__))` then you need to use `#[repr(C, packed)]`. Example:

{% highlight C %}
struct __attribute__((__packed__)) foo {
    char first;
    int second;
};
{% endhighlight %}

A packed C struct, usually only found in kernel development, is not _padded_. If you are not familiar with _padding_ in C, then you may not understand what `#[repr(C, packed)]` does. When defining a struct in C, the struct members are aligned to _word boundaries_. A _word_ is the natural address boundary for a given architecture. For example, on a 32-bit machine a word is 4 bytes. If a struct member does not align to a word boundary, the compiler will insert padding after the variable. A struct like

{% highlight C %}
struct foo {
    char first; // 1 byte
    int second; // 4 bytes
};
{% endhighlight %}

is not 5 bytes in size, but 8 bytes due to padding. Here is how the same struct looks after the compiler has added padding:

{% highlight C %}
struct foo {
    char first; // 1 byte
    char padding[3]; // 3 bytes
    int second; // 4 bytes
};
{% endhighlight %}

I found a [Stack Overflow post](http://stackoverflow.com/a/4306269/775246) the explains it in even greater detail. Also, check out the [Data Structure Alignment](http://en.wikipedia.org/wiki/Data_structure_alignment) article on Wikipedia.

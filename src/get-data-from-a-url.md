---
layout: post
title: "Get Data From A URL In Rust"
tags:
- rustlang
status: publish
type: post
published: true
---

**Tested on Rust 1.3**

Here is a high level of example of how to make a HTTP GET request to some URL. To make the example a little more interesting, the URL will have a json response body. We will parse the body and pluck some values from the parsed json.

There are a number of crates we could use to make an HTTP GET request, but I am partial to [curl][curl crate]. The curl library should be familiar to a wide set of audiences and libcurl is rock solid. Also, I think the Rust interface to curl is really easy to read and use. I am going to request the [HauteLook][HauteLook] API root because that is where I work and it will return [Hal][Hal] json.

```rust
use curl::http;

let url = "https://www.hautelook.com/api";
 let resp = http::handle()
     .get(url)
     .exec()
     .unwrap_or_else(|e| {
         panic!("Failed to get {}; error is {}", url, e);
     });
```

A few things to point out. The curl crate allows the functions to be chained together so it reads really nice. We can map the methods directly to the curl C interface:

   * `http::handle()` -> `curl_easy_init()`
   * `get(url)` -> `curl_easy_setopt(handle, CURLOPT_URL, url);`
   * `exec()` -> `curl_easy_perform(handle);`

The C interface would normally require us to explicitly close the handle, but Rust does this automatically for us. In Rust, we also need to unwrap the `Result<Response, ErrCode>` returned by the call to `exec()`. Rather than just use `unwrap()`, we can use `unwrap_or_else()` and generate a more user-friendly error message. I will be using `unwrap_or_else()` throughout this example.

Now that we have a response, we need to parse the json. Again, there are a number of crates we can use for this task. Let us choose [serde_json][serde_json crate] as that looks to be the successor to [rustc_serialize][rustc_serialize crate]. Before we start parsing json, we need to get at the response body. In curl, `resp.get_body()` will return a reference to a slice of unsigned 8 bit intgers `&[u8]`. We need to turn those bytes into a [unicode string slice][std::str].

```rust
let body = std::str::from_utf8(resp.get_body()).unwrap_or_else(|e| {
    panic!("Failed to parse response from {}; error is {}", url, e);
});
```

Now that we have our string slice, we can attempt to parse than string into a json `Value` type. This type will allow us to access specific fields within the json data.

```rust
let json: Value = serde_json::from_str(body).unwrap_or_else(|e| {
    panic!("Failed to parse json; error is {}", e);
});
```

Let us take a look at the json response before we look at the code to pluck values from it. Without going into specifics about Hal or hypermedia, we have a json object that contains one key named `_links`. This key `_links` has a number of [link relations][IANA] that correspond to an object that contains an `href`.

```json
{
    "_links": {
        "http://hautelook.com/rels/events": {
            "href": "https://www.hautelook.com/v4/events"
        },
        "http://hautelook.com/rels/image-resizer": {
            "href": "https://www.hautelook.com/resizer/{width}x{height}/{imgPath}",
            "templated": true
        },
        "http://hautelook.com/rels/login": {
            "href": "https://www.hautelook.com/api/login"
        },
        "http://hautelook.com/rels/login/soft": {
            "href": "https://www.hautelook.com/api/login/soft"
        },
        "http://hautelook.com/rels/members": {
            "href": "https://www.hautelook.com/v4/members"
        },
        "http://hautelook.com/rels/search2": {
            "href": "https://www.hautelook.com/api/search2/catalog"
        },
        "profile": {
            "href": "https://www.hautelook.com/api/doc"
        },
        "self": {
            "href": "https://www.hautelook.com/api"
        }
    }
}
```

Let us write some code to print out each link relation with the corresponding href value. This will involve us first getting `_links` and then iterating over the link releations inside of `_links`.

```rust
let links = json.as_object()
    .and_then(|object| object.get("_links"))
    .and_then(|links| links.as_object())
    .unwrap_or_else(|| {
        panic!("Failed to get '_links' value from json");
    });

for (rel, link) in links.iter() {
    let href = link.find("href")
        .and_then(|value| value.as_string())
        .unwrap_or_else(|| {
            panic!("Failed to get 'href' value from within '_links'");
        });

    println!("{} -> {}", rel, href);
}
```

In serde, the `Value` type represents all possible json values. Before we can do something meaningful, we must convert the value to a more specific json type. Since our json starts out as an object with one key, we need to first use the `as_object()` function. The `as_object()` function will convert the `Value` into a `BTreeMap` type. We can then use the `get` function that comes with `BTreeMap` to get at our link relations. I am using the `and_then()` funtion avoid dealing with `unwrap()` over and over. I could have also written the code to get `links` like this:

```rust
let oject = json.as_object().unwrap();
let links_value = object.get("_links").unwrap();
let links = links.as_object().unwrap();
```

Since `links` is just a BTreeMap, we can iterate over all the key value pairs using `links.iter()`. The link relation, `rel`,  is the key and the `link` is the value. I am using the `find()` function to get the `href` out of the `link`. The `find()` function basically combines `as_object()` and `get()`. In order to get the actual URL string, we need to use the `as_string()` function. All the functions to convert `Value` to a more specific type are [here][serde functions]. There are also some more advanced functions like `lookup()` and `search()`.

Here is the code in its entirety:

```rust
extern crate curl;
extern crate serde_json;

use curl::http;
use serde_json::Value;

pub fn main() {

    let url = "https://www.hautelook.com/api";
    let resp = http::handle()
        .get(url)
        .exec()
        .unwrap_or_else(|e| {
            panic!("Failed to get {}; error is {}", url, e);
        });

    if resp.get_code() != 200 {
        println!("Unable to handle HTTP response code {}", resp.get_code());
        return;
    }

    let body = std::str::from_utf8(resp.get_body()).unwrap_or_else(|e| {
        panic!("Failed to parse response from {}; error is {}", url, e);
    });

    let json: Value = serde_json::from_str(body).unwrap_or_else(|e| {
        panic!("Failed to parse json; error is {}", e);
    });

    let links = json.as_object()
        .and_then(|object| object.get("_links"))
        .and_then(|links| links.as_object())
        .unwrap_or_else(|| {
            panic!("Failed to get '_links' value from json");
        });

    for (rel, link) in links.iter() {
        let href = link.find("href")
            .and_then(|value| value.as_string())
            .unwrap_or_else(|| {
                panic!("Failed to get 'href' value from within '_links'");
            });

        println!("{} -> {}", rel, href);
    }
}
```

We now have all the knowledge we need to work with URLs that return a json response. I put the complete [working example][working example] on github.

[curl crate]: https://crates.io/crates/curl
[HauteLook]: https://www.hautelook.com
[Hal]: http://stateless.co/hal_specification.html
[serde_json crate]: https://crates.io/crates/serde_json
[rustc_serialize crate]: https://crates.io/crates/rustc-serialize
[std::str]: https://doc.rust-lang.org/nightly/std/str/index.html
[IANA]: http://www.iana.org/assignments/link-relations/link-relations.xhtml
[serde functions]: https://github.com/serde-rs/json/blob/e950b51a773a48281ad943c1bbf8c67fc266804a/json/src/value.rs#L147
[working example]: https://github.com/hjr3/rust-get-data-from-url

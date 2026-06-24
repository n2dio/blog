#import "/lib/template.typ": post
#show: post.with(
  title: "Hello, n2d",
  date: "2026-06-24",
  tags: ("meta", "typst"),
  summary: "Why this blog exists, and how it's built entirely in Typst.",
)

Welcome to the n2d blog. This whole site is written in #link("https://typst.app")[Typst] — no Markdown, no Node toolchain, just `.typ` files compiled to static HTML.

= Why Typst

Typst gives real typesetting: footnotes, math, references, and proper control over layout — while still reading like lightweight markup. Inline code like `cargo build` and full blocks both work out of the box.

= Highlighted code

Fenced blocks are syntax-highlighted at build time, so the page needs zero JavaScript:

```rust
fn main() {
    let greeting = "hello, n2d";
    for word in greeting.split(", ") {
        println!("{word}");
    }
}
```

Math works too, when you need it — rendered as native MathML, no JavaScript:

$ sum_(k=1)^n k = (n (n + 1)) / 2 $

That's the whole idea — write prose and code together, get a clean static page out.

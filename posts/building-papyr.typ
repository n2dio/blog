#import "/lib/template.typ": post, post-link
#show: post.with(
  title: "Building papyr: a blog engine in one Rust binary",
  date: "2026-06-24",
  tags: ("papyr", "rust", "typst", "meta"),
  summary: "This blog is built by papyr — a single Rust binary that links Typst as a library to turn .typ files into a static site. Here's how it works.",
  toc: true,
)

I wanted to write this blog in #link("https://typst.app")[Typst] instead of
Markdown, keep it minimal and professional, and have real syntax-highlighted
code. I also didn't want a Node toolchain, a pile of plugins, or a separate
static-site generator bolted on top. So the blog is built by its own tool:
*papyr*, a single self-contained Rust binary.

= The idea

Typst is a typesetting system — normally it produces PDFs. But recent versions
ship an (experimental) HTML export backend, and that's enough to build a blog:
write posts as `.typ` files, compile them to HTML, and stitch the result into a
static site.

The first version did exactly that with a shell script calling the `typst` CLI,
plus `jq` and a little Python for the index and feed. It worked, but it shelled
out constantly and compiled every post twice. So I rewrote it as one program
that links Typst directly as a library.

= One compile pass

papyr implements Typst's `World` trait over the project directory, then compiles
each post #emph[once] — and reads its metadata out of the very same compiled
document via introspection. No second pass, no `typst query`:

```rust
let world = SiteWorld::new(&shared, &path, None)?;
let doc = typst::compile::<HtmlDocument>(&world).output?;

let html = typst_html::html(&doc, &HtmlOptions { pretty: true })?;
let meta = query_frontmatter(&doc); // <frontmatter> label → JSON
```

Each post carries a small metadata block that the template adds automatically,
so titles, dates, and tags come straight out of the document — no front-matter
parsing, no database.

= Highlighted code, no JavaScript

Code blocks are highlighted at *build time*: Typst emits the colored spans
directly into the HTML, so the page ships zero client-side JavaScript. The code
you're reading was rendered this way. Code blocks stay on a dark surface in both
light and dark mode, because the syntax colors are baked in at build time.

= Math is native now

Typst 0.15 renders math as native #link("https://developer.mozilla.org/en-US/docs/Web/MathML")[MathML],
which means equations are accessible, selectable, scale with the text, and
follow the page color automatically. Inline like $e^(i pi) + 1 = 0$, or as a
block:

$ integral_0^1 x^2 dif x = 1/3 $

No images, no SVG, no script.

= Batteries, not plumbing

A build isn't just one HTML file per post. From the same pass papyr also wires
the whole site together: a reverse-chronological index and per-tag pages,
prev/next links between posts, heading anchors and an opt-in table of contents,
an RSS feed, a `sitemap.xml` and `robots.txt`, and the social/SEO `<head>` tags
(OpenGraph, Twitter card, canonical URL) every page wants. It checks its own
internal links while it's at it, so a renamed post can't quietly leave a dead
link behind.

Posts can also pull in #link("https://typst.app/universe")[Typst Universe]
packages — `#import "@preview/cetz:0.3.1"` is fetched and cached on the first
build — so the full Typst ecosystem is available without changing anything about
how the site is built.

= Serve and watch, built in

The same binary serves the site and rebuilds it when files change — an
#link("https://github.com/tokio-rs/axum")[axum] static server plus a file
watcher — so there's no Caddy and no separate watcher process:

```sh
papyr serve   # build, serve http://localhost:8080, rebuild on change
```

= Try it

papyr scaffolds a fresh site for you:

```sh
papyr init my-blog
cd my-blog
papyr serve
```

For the very first post on this blog, see #post-link("hello-world")[Hello, n2d].

That's the whole thing: write Typst, get a clean static site — prose, code, and
math together, out of one small binary.

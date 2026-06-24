#import "/lib/template.typ": post
#show: post.with(
  title: "Building a static blog with Typst's HTML export",
  date: "2026-06-20",
  tags: ("typst", "web", "build"),
  summary: "How Typst's experimental HTML export turns prose and code into a clean static site — and where the rough edges are.",
)

Typst is best known for typesetting PDFs, but recent versions ship an experimental HTML export backend. That's enough to build a real blog without reaching for Markdown.

= The build pipeline

Each post is a `.typ` file. A small build script extracts metadata with `typst query`, compiles every page, and stitches together the index and feed.

```bash
for f in posts/*.typ; do
  slug=$(basename "$f" .typ)
  typst compile --features html --format html "$f" "site/posts/$slug.html"
done
```

= Metadata without a database

A single `metadata` element per post, tagged with a label, is enough for the build to read titles, dates, and tags back out:

```python
# conceptually, what `typst query` gives us per file:
meta = {
    "title": "Building a static blog with Typst",
    "date": "2026-06-20",
    "tags": ["typst", "web", "build"],
}
```

= The rough edges

HTML export is still marked experimental, and not every layout feature maps cleanly to HTML. Math used to be the sharpest edge — it was dropped unless you wrapped it in `html.frame` — but as of Typst 0.15 it renders as native MathML, so equations come through accessible and selectable with no workaround. For a text-and-code blog, it's already more than enough.

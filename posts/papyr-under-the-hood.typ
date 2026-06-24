#import "/lib/template.typ": post, post-link
#show: post.with(
  title: "Inside papyr: the engine under the hood",
  date: "2026-06-24",
  tags: ("papyr", "rust", "typst", "internals"),
  summary: "A deep dive into how papyr works: implementing Typst's World, getting HTML and metadata from a single compile, passing data in and out of the document, and shipping it all as one dependency-light binary.",
  toc: true,
   line-numbers: true,
)

The #post-link("building-papyr")[overview post] said _what_ papyr is: one Rust
binary that links Typst as a library and turns a directory of `.typ` files into
this site. This one opens the lid. Everything below is real code from the
engine, trimmed to its essentials — the same code that built the page you're
reading.

= The shape of the program

papyr is a single binary with a deliberately small dependency set. The whole
thing leans on a handful of crates:

```toml
[dependencies]
typst         = "=0.15.0"   # the compiler, as a library
typst-html    = "=0.15.0"   # the HTML export backend
typst-kit     = { version = "=0.15.0", features = [
    "embedded-fonts", "emit-diagnostics", "system-packages" ] }
comemo        = "0.4"       # Typst's memoization cache
chrono        = { version = "0.4", default-features = false, features = ["clock", "std"] }
serde_json    = "1"
serde_yaml_ng = "0.10"
regex         = "1"
clap          = { version = "4", features = ["derive"] }
axum          = "0.8"       # serve
tower-http    = { version = "0.7", features = ["fs", "trace"] }
notify        = "8"         # watch
ureq          = "3"         # fetch Typst Universe packages (rustls, no openssl)
```

The Typst crates are pinned to an exact `=0.15.0` — HTML export is still
officially experimental, so papyr upgrades in lockstep rather than drifting.
The source is a dozen small modules, but the spine is four: `world` (feed Typst
a filesystem), `render` (compile one file to HTML _and_ its metadata), `build`
(assemble everything into `site/`), and `serve` (host it and watch for changes).
The rest are focused helpers — `dates`, `feed`, `head`, `toc`, `links`, `text`,
`scaffold` (`papyr init`), and `main` (the `clap` CLI).

= Implementing Typst's `World`

The Typst compiler is pure: it never touches the filesystem or the clock on its
own. Instead it asks a `World` for everything — source files, fonts, the current
date. To compile anything you implement that trait. papyr backs it with the
project directory, and splits the work into two structs by cost.

The expensive half is built once per run. Loading fonts is the slow part, so it
lives in a `Shared` value that every per-file compile borrows. It also carries
the package store and a small per-build read cache, so any one file or font is
only ever touched once:

```rust
/// Expensive, reusable state, built once per build: fonts, the project root,
/// the package store, and read caches (recreated each build, so they can't go
/// stale within one).
pub struct Shared {
    pub root: PathBuf,
    fonts: FontStore,
    packages: SystemPackages,                  // Typst Universe, on demand
    sources: Mutex<HashMap<FileId, Source>>,   // parsed-source cache
    bytes: Mutex<HashMap<FileId, Bytes>>,      // raw-bytes cache
}
```

The cheap half is created fresh for every file. All it builds is a `Library`
with HTML export switched on (and optional `inputs`, more on those later); the
shared state is just borrowed. Construction is fallible rather than panicking —
a bad main path is a build error, not a crash:

```rust
/// A World for one main file. Cheap to construct: borrows the shared
/// state, only builds a fresh Library.
pub struct SiteWorld<'a> {
    shared: &'a Shared,
    main: FileId,
    library: LazyHash<Library>,
}

impl<'a> SiteWorld<'a> {
    pub fn new(shared: &'a Shared, main_rel: &str, inputs: Option<Dict>)
        -> Result<Self, String>
    {
        let mut builder = Library::builder()
            .with_features([Feature::Html].into_iter().collect());
        if let Some(dict) = inputs {
            builder = builder.with_inputs(dict);
        }
        let vpath = VirtualPath::new(main_rel)
            .map_err(|e| format!("invalid path {main_rel:?}: {e}"))?;
        let main = FileId::new(RootedPath::new(VirtualRoot::Project, vpath));
        Ok(SiteWorld { shared, main, library: LazyHash::new(builder.build()) })
    }
}
```

The trait methods that matter are `file` and `today`. `file` is where Typst
meets the disk: it serves a cached copy if it has read this id before, then —
for a project path — resolves it against the root and confines the read there,
or — for a `@preview/...` package path — hands off to the package store, which
downloads from #link("https://typst.app/universe")[Typst Universe] on first use
and reads from the standard Typst cache thereafter. `today` returns `None`:
builds must not depend on the wall clock, so the same sources always produce the
same site.

```rust
impl World for SiteWorld<'_> {
    fn file(&self, id: FileId) -> FileResult<Bytes> {
        if let Some(bytes) = self.shared.bytes.lock().unwrap().get(&id) {
            return Ok(bytes.clone());             // already read this build
        }
        let path = match id.root() {
            VirtualRoot::Project => id.vpath()
                .realize(&self.shared.root)        // confine reads to the project
                .map_err(|_| FileError::AccessDenied)?,
            VirtualRoot::Package(spec) => {        // fetch + cache from the Universe
                let pkg = self.shared.packages.obtain(spec).map_err(FileError::Package)?;
                id.vpath().realize(pkg.path()).map_err(|_| FileError::AccessDenied)?
            }
        };
        let data = std::fs::read(&path).map_err(|e| FileError::from_io(e, &path))?;
        let bytes = Bytes::new(data);
        self.shared.bytes.lock().unwrap().insert(id, bytes.clone());
        Ok(bytes)
    }

    fn today(&self, _: Option<Duration>) -> Option<Datetime> {
        None   // deterministic builds: no dependence on the clock
    }
    // library(), book(), main(), source(), font() are the obvious wrappers
}
```

The downloader behind that is a thin `ureq` (rustls) implementation of
typst-kit's `Downloader` trait, so package support adds an HTTPS client but no
native openssl dependency. That's the whole bridge between Typst and the outside
world; everything else is built on top of it.

= One compile, two outputs

Each post needs two things out of Typst: the rendered HTML, and its metadata
(title, date, tags) for the index and feed. The naïve approach compiles twice —
once for HTML, once to query the metadata. papyr compiles *once* and reads both
out of the same document.

The `render` module is the core of the build. Its `compile` helper takes a file
to an `HtmlDocument`, serializes that to an HTML string, and injects the
stylesheet link. Two thin wrappers sit on top: `render_page` for the listing and
standalone pages, and `render_post`, which — from the very same `doc` — also
pulls out the frontmatter. A post's metadata is required, so a missing block is
an error rather than a silent default:

```rust
fn render_post(shared: &Shared, main_rel: &str) -> Res<(String, FrontMatter)> {
    let (html, doc) = compile(shared, main_rel, None)?;          // one compile

    // Same `doc`: no second pass, no `typst query` subprocess.
    let frontmatter = query_frontmatter(&doc)
        .map(serde_json::from_value)
        .transpose()?
        .ok_or_else(|| format!("{main_rel}: missing <frontmatter> metadata"))?;

    Ok((html, frontmatter))
}
```

The metadata travels inside the document. The shared `post` template emits a
`metadata` element and tags it with a Typst label, `<frontmatter>`:

```typ
#let post(title: "", date: "", tags: (), summary: "", toc: false, body) = {
  // A labelled metadata element the engine can find after compiling.
  [#metadata((title: title, date: date, tags: tags, summary: summary, toc: toc)) <frontmatter>]
  // ... then the actual page chrome and `body` ...
}
```

After compiling, papyr asks the document's introspector for that label and reads
the `value` field straight off the matching element. Typst's own introspection
machinery does the work that a second `typst query` pass would otherwise cost:

```rust
fn query_frontmatter(doc: &HtmlDocument) -> Option<serde_json::Value> {
    let label = Label::new(PicoStr::intern("frontmatter"))?;
    let hits = doc.introspector().query(&Selector::Label(label)); // search the doc
    let value: Value = hits.first()?.field_by_name("value").ok()?; // the metadata
    serde_json::to_value(value).ok()
}
```

The JSON drops cleanly into a `serde` struct, so the rest of the build works
with a plain `FrontMatter` and never thinks about Typst values again.

= Passing data in and out of the document

The listing pages — the home page, each tag page, the tags index — aren't
hand-written. They're Typst templates that need to *know about every post*. That
means data has to cross the Rust/Typst boundary in both directions.

*Out of Rust:* once every post is compiled, the build sorts the collected
metadata newest-first — by _parsed timestamp_, not raw string, so two posts on
the same day still order by time — and writes it (slug included) to
`build/posts.json`:

```rust
// Reverse-chronological; unparseable dates sort last, each parsed once.
posts.sort_by_cached_key(|p| std::cmp::Reverse(dates::parse(&p.date)));
fs::write(build_dir.join("posts.json"), serde_json::to_vec_pretty(&posts)?)?;
```

The listing templates just read that file with Typst's own `json` loader and
loop over it — no special API, the engine and the templates meet at a JSON file:

```typ
#let posts = json("/build/posts.json")
#for p in posts [
  // ... render a list item: title link, date, tags, summary ...
]
```

*Into Typst:* one template, `gen/tag.typ`, has to produce a *different* page for
every tag. Rather than generate N templates, papyr compiles the one template N
times, injecting values through the `Library` inputs each time — those are
exactly the `inputs` that `SiteWorld::new` threads into the library. Tags are
_slugified_ for safe URLs (`Machine Learning` → `machine-learning`), so it
passes both the `slug` (the page's filename and the value to filter on) and a
display `name`; distinct tags that slugify to the same value simply share a page:

```rust
for (slug, name) in &tag_pages {
    let mut inputs = Dict::new();
    inputs.insert("slug".into(), Value::Str(slug.as_str().into()));
    inputs.insert("name".into(), Value::Str(name.as_str().into()));
    let html = render::render_page(&shared, "gen/tag.typ", Some(inputs))?;
    write_page(&out.join("tags").join(format!("{slug}.html")), &html)?;
}
```

On the Typst side those arrive as `sys.inputs`, so the template filters the post
list down to its own tag — slugifying each post's tags the same way to compare:

```typ
#let slug = sys.inputs.at("slug")
#let name = sys.inputs.at("name")
#let posts = json("/build/posts.json").filter(p => p.tags.map(slugify).contains(slug))
```

That `slugify` exists in both Rust and Typst, and the two have to agree or a tag
link would 404; the build-time link checker (below) is exactly what guarantees
they do. `json` out, `sys.inputs` in: the same two mechanisms Typst already gives
you, used to wire a static site together.

= Dates and timestamps

A post's `date` can be a plain date or a full timestamp, and one parse feeds
three things: ordering, the RSS `<pubDate>`, and the `<time datetime>` attribute.
An earlier version hand-rolled Zeller's congruence to dodge a date dependency
entirely — but once `date` could carry a time and an offset (so same-day posts
order correctly, and `papyr new` can stamp _now_), a small, well-tested date
library earned its keep. papyr pulls in a trimmed `chrono` (`default-features =
false`, just `clock` + `std`) and leans on it for the fiddly parts.

`parse` is deliberately lenient — RFC-3339 with an offset, a naive date-time
(assumed UTC), or a bare date (midnight UTC) — and returns a timezone-aware
instant, or `None` for anything it doesn't recognize:

```rust
pub fn parse(s: &str) -> Option<DateTime<FixedOffset>> {
    if let Ok(dt) = DateTime::parse_from_rfc3339(s) {
        return Some(dt);                              // 2026-06-24T14:30:00+02:00
    }
    // ... "%Y-%m-%d %H:%M:%S" and a few siblings, assumed UTC ...
    let nd = NaiveDate::parse_from_str(s, "%Y-%m-%d").ok()?;       // date only
    Some(Utc.from_utc_datetime(&nd.and_hms_opt(0, 0, 0)?).fixed_offset())
}
```

Everything else falls out of that one instant: the feed formats it as RFC-2822,
the sort orders by it, and — crucially — none of it panics. An unparseable date
is reported as a build warning and passed through to the feed verbatim rather
than taking the whole build down with it.

= Highlighting, math, and the stylesheet link

The code colors and the math on this page both fall out of Typst at build time:
fenced blocks become inline-styled HTML spans, and `$...$` becomes native MathML.
That story is in the #post-link("building-papyr")[overview]; here it's worth
noting two small seams the engine smooths over.

First, Typst prints an "HTML export is experimental" warning on every single
compile. Real warnings should always show, but that one would bury them, so the
build filters just that message and lets everything else through. Second, the
template can't easily add a `<link>` into `<head>`, so after rendering papyr
splices the stylesheet in with a one-shot string replace:

```rust
fn inject_css(html: &str) -> String {
    html.replacen(
        "</head>",
        "    <link rel=\"stylesheet\" href=\"/style.css\">\n  </head>",
        1,
    )
}
```

= From compiled HTML to a finished page

Compiling gives papyr a post's body; a few string passes turn it into the page
you actually read — all at build time, all zero-JS. Typst emits bare
`<h2>`/`<h3>` tags, so papyr rewrites each to add an `id` and a hover anchor and,
when a post opts in with `toc: true` and has at least two headings, injects a
collapsible `<details>` table of contents before the first one. Because the
posts are already sorted, it knows each one's neighbors, so it splices a
prev/next nav block in just before `</main>`:

```rust
fn inject_post_nav(html: &str, older: Option<&PostMeta>, newer: Option<&PostMeta>) -> String {
    // ... build <a class="prev"> / <a class="next"> from the neighbors ...
    html.replacen("</main>", &format!("{nav}</main>"), 1)
}
```

Finally, every page gets a block of `<head>` metadata spliced in before
`</head>` — `description`, a canonical URL, OpenGraph and Twitter-card tags,
light/dark `theme-color`, and RSS autodiscovery — and the build as a whole writes
`feed.xml`, `sitemap.xml`, and `robots.txt` alongside the pages. None of it needs
a plugin; it's all small, testable string work over the HTML papyr already holds.

= Serve and watch, in one process

`papyr serve` is the same build plus a static server and a file watcher, all in
the one binary — no Caddy, no separate watch process. It builds once (the `false`
is `--strict`: a serve loop warns about broken links rather than dying on them),
spawns a background thread to watch and rebuild, then serves `site/` with an
`axum` `ServeDir`:

```rust
pub fn serve(root: &Path, port: u16) -> Res<()> {
    build::build(root, false)?;                 // build up front (non-strict)

    let watch_root = root.to_path_buf();        // watch + rebuild in the background
    std::thread::spawn(move || { let _ = watch_loop(&watch_root); });

    let site = root.join("site");
    let rt = tokio::runtime::Runtime::new()?;
    rt.block_on(async move {
        let app = Router::new().fallback_service(
            ServeDir::new(&site).append_index_html_on_directories(true),
        );
        let addr = SocketAddr::from(([127, 0, 0, 1], port));
        let listener = tokio::net::TcpListener::bind(addr).await?;
        axum::serve(listener, app).await?;
        Ok(())
    })
}
```

The watch loop uses `notify` over the source directories (`posts`, `pages`,
`lib`, `gen`, `assets`) plus `config.yaml`. File changes arrive in bursts — a
single save can fire several events — so it blocks for the first change, sleeps
briefly, then drains whatever piled up before doing exactly one rebuild:

```rust
loop {
    rx.recv()?;                                  // block until something changes
    std::thread::sleep(Duration::from_millis(200));
    while rx.try_recv().is_ok() {}               // debounce: drain the burst
    println!("› change detected — rebuilding");
    if let Err(e) = build::build(root, false) { eprintln!("build error: {e}"); }
}
```

That constant rebuilding is also why a build never writes `site/` in place: it
renders into a staging directory and swaps it in with a rename at the very end.
A reader who reloads mid-rebuild always gets a whole site — the previous one
until the instant the new one is ready — and a build that fails partway leaves
the last good `site/` untouched.

= Catching broken links before you ship them

Because posts link to each other by slug, a renamed or deleted post leaves a
dead link. papyr catches those at build time. Before swapping the new output
into place, it walks the staged HTML, pulls every site-internal `href` with a
small regex, and checks that each one resolves to a real file:

```rust
fn internal_hrefs(html: &str) -> Vec<String> {
    static RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#"href="(/[^"]*)""#).unwrap());
    RE.captures_iter(html)
        .filter_map(|c| {
            let raw = &c[1];
            if raw.starts_with("//") { return None; }   // protocol-relative → external
            Some(raw.split(['#', '?']).next().unwrap_or(raw).to_string())
        })
        .collect()
}
```

Anything that doesn't map to a file on disk gets reported — so a typo'd
`post-link`, or a tag whose Rust and Typst slugs disagree, is a warning at build
time rather than a 404 a reader finds for you. In CI you can make it a hard stop:
`papyr build --strict` fails the build (before publishing) if any internal link
is broken.

= One binary, no surprises

Two last touches make papyr genuinely self-contained. The starter site that
`papyr init` writes — template, listing pages, CSS, code theme, fonts, and the
example post and pages — is baked *into* the executable with `include_str!` and
`include_bytes!`, so scaffolding a new blog needs nothing but the binary:

```rust
const TEMPLATE: &str   = include_str!("../lib/template.typ");
const GEN_INDEX: &str  = include_str!("../gen/index.typ");
const GEN_TAG: &str    = include_str!("../gen/tag.typ");
const STYLE: &str      = include_str!("../assets/style.css");
const CODE_THEME: &str = include_str!("../assets/code-theme.tmTheme");
const FONTS: &[(&str, &[u8])] = &[
    ("assets/fonts/ibm-plex-sans-400.woff2",
     include_bytes!("../assets/fonts/ibm-plex-sans-400.woff2")),
    // ... the rest of the self-hosted fonts ...
];
```

And because `serve` rebuilds on every keystroke, the build ends by bounding
Typst's memoization cache so a long watch session doesn't grow without limit —
the cached results stay valid because Typst keys them on content hashes:

```rust
comemo::evict(10);   // keep recent compiles cached, drop the rest
```

That's the engine end to end: implement `World` over a directory (and the
package cache), compile each file once for both its HTML and its metadata, move
data across the boundary as JSON and `sys.inputs`, post-process the result into
finished pages with navigation, anchors, and social tags, and wrap it all in a
binary that serves, watches, swaps in each rebuild atomically, checks its own
links, and carries its own scaffold. Write Typst, get a static site — and now
you know exactly what happens in between.

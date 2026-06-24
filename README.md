# n2d blog

The source for **n2d.io** — a blog written in [Typst](https://typst.app) and
built by [papyr](../papyr), a minimal Typst static-blog engine. This repo is
just the content and theme; the engine lives in its own project.

## Build & serve

Install papyr once (it puts `papyr` on your `PATH`):

```sh
cargo install --path ../papyr
```

Then, from this directory:

```sh
papyr serve        # build, serve http://localhost:8080, rebuild on change
papyr build        # build the static site into ./site
papyr new my-post  # scaffold posts/my-post.typ
papyr clean        # remove build artifacts
```

Add `-v` for verbose logging.

## Layout

| Path | Purpose |
|------|---------|
| `config.yaml` | Site identity: title, tagline, author, URL, description. |
| `posts/*.typ` | Blog posts (filename → `/posts/<slug>.html`). |
| `pages/*.typ` | Standalone pages (about, imprint). |
| `lib/template.typ` | Theme: `post`/`page` show-rules, nav + footer, link helpers. |
| `gen/*.typ` | Index, tag, and tags-index listing pages. |
| `assets/` | `style.css`, the dark `code-theme.tmTheme`, and self-hosted fonts. |

For how to write posts, link between them, use math, etc., see the
[papyr README](../papyr/README.md).

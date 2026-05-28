# Building the Journey Engine docs

This folder is the [MkDocs](https://www.mkdocs.org/) source for the Journey
Engine documentation site, built with the
[Material for MkDocs](https://squidfunk.github.io/mkdocs-material/) theme.

> This file is a build note for maintainers. It is **not** published as a site
> page (it is listed under `exclude_docs` in `mkdocs.yml`). The repository's
> top-level `README.md` is a separate file.

## Prerequisites

- Python 3.9+ (3.13 is what this was built and verified against)

## Build it locally

From the **repository root** (where `mkdocs.yml` lives):

```bash
# 1. Create and activate an isolated virtual environment
python3 -m venv .venv-docs
source .venv-docs/bin/activate        # Windows: .venv-docs\Scripts\activate

# 2. Install the pinned toolchain
pip install -r requirements-docs.txt

# 3. Live preview with hot reload at http://localhost:8000
mkdocs serve

# 4. Build the static site into ./site/
mkdocs build

# 5. Build the way CI does — warnings (broken links, missing nav entries)
#    become errors. The site must build clean under --strict.
mkdocs build --strict
```

`mkdocs serve` watches the `docs/` tree and rebuilds on save, so it is the
fastest way to write and proofread pages. The generated `site/` directory is
build output and is git-ignored.

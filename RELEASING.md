# Releasing Journey Engine Core

Maintainer playbook for cutting a release, publishing the docs, and listing on
the Godot Asset Library. This file is for maintainers — it is **not** part of the
published documentation site.

Repo: <https://github.com/thetimothyp/godot-journey-engine-core>

The flow, in order:

1. [Bump the version](#1-bump-the-version)
2. [Pre-flight checks](#2-pre-flight-checks)
3. [Cut a GitHub Release](#3-cut-a-github-release)
4. [Publish the docs to GitHub Pages](#4-publish-the-docs-to-github-pages)
5. [Submit / update the Asset Library entry](#5-submit--update-the-asset-library-entry)

---

## 1. Bump the version

The engine uses [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`.

- **MAJOR** — a breaking change to the public API (the
  [API Reference](docs/reference/api.md) surface or authorable resource fields).
- **MINOR** — new backward-compatible features.
- **PATCH** — backward-compatible bug fixes.

> **Pre-1.0:** while the version is `0.y.z`, the API is allowed to change between
> minor versions. Move to `1.0.0` when you're ready to promise API stability.

The version lives in **three places that must stay in sync**:

| Where | What to change |
| --- | --- |
| `addons/journey_engine_core/journey_runtime.gd` | `const VERSION := "X.Y.Z"` |
| `addons/journey_engine_core/plugin.cfg` | `version="X.Y.Z"` |
| `docs/about/changelog.md` | Add a new `## X.Y.Z — YYYY-MM-DD` section |

!!! note
    `JourneyConfig.save_version` is **independent** of the engine version. Only
    bump `save_version` when the on-disk **save format** changes in a breaking
    way (and add a migration step) — never just because you cut a release. See
    the [save/load guide](docs/guides/save-and-load.md) ("Versioning & migration").

After editing, sanity-check the runtime constant matches:

```bash
grep VERSION addons/journey_engine_core/journey_runtime.gd
grep version addons/journey_engine_core/plugin.cfg
```

Commit the bump (don't tag yet — that happens in step 3, after checks pass):

```bash
git add -A
git commit -m "release: bump version to X.Y.Z"
```

---

## 2. Pre-flight checks

Run everything before tagging. All must pass.

```bash
# Godot tests (headless). Adjust the path to your Godot 4.6 binary.
GODOT=/Applications/Godot.app/Contents/MacOS/Godot

# A clean editor import must be error-free (catches parse errors, broken paths).
"$GODOT" --headless --editor --quit --path . 2>&1 | grep -i error || echo "import clean"

# Programmatic test scenes (these print PASS/FAIL and self-terminate).
for scene in test_export_sanity test_validate test_eval_mutate test_blackboard test_save_load; do
  "$GODOT" --headless --path . "res://tests/$scene.tscn"
done

# Docs must build clean under --strict (broken links/anchors fail the build).
source .venv-docs/bin/activate   # see docs/README.md to create this venv
mkdocs build --strict
```

If anything fails, fix it and amend the bump commit before continuing.

---

## 3. Cut a GitHub Release

### 3a. Tag and push

Use an **annotated** tag named `vX.Y.Z`:

```bash
git tag -a vX.Y.Z -m "Journey Engine Core vX.Y.Z"
git push origin main --follow-tags
```

`--follow-tags` pushes the commit and the annotated tag together. Confirm the tag
landed on the remote:

```bash
git ls-remote --tags origin | grep vX.Y.Z
```

### 3b. Build the addon zip (optional but recommended)

Ship a zip containing **only** the addon, with the `addons/` path preserved so a
user can extract it straight into their project root:

```bash
zip -r journey-engine-core-vX.Y.Z.zip addons/journey_engine_core
```

(Leave `sample_game/`, `tests/`, and `docs/` out of the artifact — they aren't
needed at runtime. Keep the `.uid` files in; Godot 4 uses them.)

### 3c. Create the release

=== "With the `gh` CLI"

    Requires the [GitHub CLI](https://cli.github.com/) (`brew install gh`) and
    `gh auth login`.

    ```bash
    # Notes pulled from the annotated tag message:
    gh release create vX.Y.Z --title "vX.Y.Z" --notes-from-tag \
        journey-engine-core-vX.Y.Z.zip

    # …or write notes from the changelog section instead of the tag:
    gh release create vX.Y.Z --title "vX.Y.Z" \
        --notes "$(sed -n '/## X.Y.Z/,/## /p' docs/about/changelog.md)" \
        journey-engine-core-vX.Y.Z.zip
    ```

=== "With the web UI"

    1. Go to **Releases → Draft a new release**:
       <https://github.com/thetimothyp/godot-journey-engine-core/releases/new>
    2. Choose the existing tag `vX.Y.Z`.
    3. Title `vX.Y.Z`; paste the matching section from
       [`docs/about/changelog.md`](docs/about/changelog.md) as the notes.
    4. Attach `journey-engine-core-vX.Y.Z.zip` (optional).
    5. **Publish release.**

---

## 4. Publish the docs to GitHub Pages

The docs build into a static site that `mkdocs gh-deploy` pushes to a `gh-pages`
branch. The canonical URL is already set as `site_url` in `mkdocs.yml`:
<https://thetimothyp.github.io/godot-journey-engine-core/>.

### First time only — enable Pages

After the first `gh-deploy` creates the `gh-pages` branch, go to **repo Settings →
Pages → Build and deployment → Source: _Deploy from a branch_**, branch
`gh-pages`, folder `/ (root)`, and save.

### Each release

```bash
source .venv-docs/bin/activate        # the docs venv (see docs/README.md)
mkdocs gh-deploy --force
```

`gh-deploy` builds the site and force-pushes it to the `gh-pages` branch on
`origin`. It does **not** touch your `main` working tree. Give Pages a minute,
then check the site is live at the URL above.

!!! tip "Build strictly first"
    `gh-deploy` doesn't accept `--strict`, so run `mkdocs build --strict` first
    (it's already in the [pre-flight checks](#2-pre-flight-checks)) to catch
    broken links before publishing.

??? note "Optional: versioned docs with `mike`"
    If you later want to keep docs for multiple versions side by side, add
    [`mike`](https://github.com/jimporter/mike) (`pip install mike`) and deploy
    with `mike deploy --push X.Y latest` instead of `gh-deploy`. Not needed for a
    single-version site.

---

## 5. Submit / update the Asset Library entry

The [Godot Asset Library](https://godotengine.org/asset-library/) lets users
install the addon from inside the editor's **AssetLib** tab. An entry points at
this GitHub repo at a specific commit/tag and downloads the repo zip at that ref.

!!! info "How installs look"
    AssetLib downloads the **whole repo** at the chosen commit, then shows the
    user a file tree to install. Because everything ships under
    `addons/journey_engine_core/`, the addon installs cleanly; the user can
    uncheck `sample_game/`, `tests/`, and `docs/` in the install dialog. (There's
    no per-file filter on the library side — the `addons/` layout is what keeps
    installs tidy.)

### First submission

1. Sign in at <https://godotengine.org/> and go to **Submit Asset**:
   <https://godotengine.org/asset-library/asset/edit> → _Submit_.
2. Fill in:
    - **Asset name:** Journey Engine Core
    - **Category:** Tools (or Scripts)
    - **Godot version:** 4.6
    - **Repository host:** GitHub · **Repository URL:** the repo URL above
    - **Issues URL:** the repo's `/issues`
    - **Version string:** `X.Y.Z` · **Commit / Git ref:** the `vX.Y.Z` tag's
      commit SHA (`git rev-list -n1 vX.Y.Z`)
    - **License:** MIT
    - **Download URL:** auto-derived from the repo + commit for GitHub hosts
    - **Icon URL:** a raw URL to an icon in the repo (e.g. `icon.svg`)
    - **Description:** adapt the top of [`README.md`](README.md)
3. Submit. A Godot moderator reviews first-time submissions before it goes live.

### Updating for a new version

1. Open your asset's edit page (linked from your library profile).
2. Bump the **version string** to the new `X.Y.Z` and update the **commit** to the
   new tag's SHA (`git rev-list -n1 vX.Y.Z`).
3. Submit the edit. Updates are typically reviewed faster than first submissions.

---

## Quick reference

```text
1. Edit VERSION in journey_runtime.gd + plugin.cfg + changelog.md → commit
2. Headless tests + mkdocs build --strict
3. git tag -a vX.Y.Z -m "..." && git push origin main --follow-tags
   → gh release create vX.Y.Z (+ addon zip)
4. mkdocs gh-deploy --force
5. AssetLib: update version + commit SHA (git rev-list -n1 vX.Y.Z)
```

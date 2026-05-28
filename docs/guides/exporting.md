# Exporting

Journey Engine is plain GDScript with no native dependencies, so it exports
wherever Godot 4 exports — including the browser. The one thing worth
understanding is how the [stochastic pool](stochastic-pool.md) finds its events
inside an exported build.

## Why exporting "just works"

When Godot exports, it bakes your `.tres`/`.res` files into the PCK (or, for Web,
into the packed data the WASM build loads). The pool index scans
`config.event_pool_dir` using `DirAccess` over the **`res://` virtual
filesystem**, not the OS filesystem — and that virtual filesystem is exactly what
the PCK exposes. The scan also recognizes the `.remap` pointer files Godot
generates when it strips resources into the export, so it resolves them back to
the real resource.

The upshot: the same directory-scan code path runs identically in the editor and
in an exported build. The bundled sample game was verified end-to-end this way,
including a full Web/WASM browser playthrough where the pool builds correctly
from the baked data.

!!! tip "Verify your pool before shipping"
    Add a tiny headless check that builds a `JourneyPoolIndex` from your pool
    directory and asserts the expected events resolve — running it before export
    catches a misconfigured `event_pool_dir` or a stray bad `.tres` before it
    becomes a runtime `empty pool` error. The sample's `tests/test_export_sanity`
    scene is a working template.

## Web / WASM

The sample game targets the **Compatibility renderer** specifically so it Web
exports cleanly. To export and run locally:

1. Install the Web export templates (**Editor → Manage Export Templates**).
2. **Project → Export → Add… → Web**, then **Export Project** to a folder (the
   sample uses `build/web/`).
3. Browsers won't run a WASM build off `file://` — serve it over HTTP:

    ```bash
    cd build/web
    python3 -m http.server 8000
    # open http://localhost:8000
    ```

### Saves in the browser

Under `user://`, browser builds persist to **IndexedDB**, so
[save/load](save-and-load.md) works without code changes — the sample's save and
load buttons work in-browser. Two browser realities to keep in mind:

!!! warning "Browser persistence caveats"
    - IndexedDB is **per-origin** and can be cleared by the user (or by private
      browsing). Treat browser saves as convenient, not durable.
    - A tab closing mid-write can truncate a save. Save at natural beats (after
      an event resolves), not continuously.

## Mobile

There's nothing engine-specific to do for mobile exports — the runtime is
presentation-agnostic GDScript and the pool scan works against the PCK the same
way it does on desktop and Web. Standard Godot Android/iOS export rules apply
(export templates, signing, etc.); the engine adds no native requirements. As
always, keep saves to natural checkpoints since a mobile app can be suspended or
killed at any time.

## Pre-export checklist

- [ ] `config.event_pool_dir` points at the folder your pool `.tres` files
      actually live in.
- [ ] Every pool event has a unique, non-empty `id`
      ([run the validator](validation.md)).
- [ ] A headless pool-build check passes (template:
      `tests/test_export_sanity`).
- [ ] For Web: renderer is Compatibility, and you serve the build over HTTP.

See also: [Stochastic Pool](stochastic-pool.md) for the scan internals ·
[Save & Load](save-and-load.md) for the `user://` contract.

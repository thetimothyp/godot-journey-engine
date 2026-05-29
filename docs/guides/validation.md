# Validation

The authoring validator inspects a `JourneyConfig` and reports problems —
**before** you run. It is pure inspection: it never mutates resources, the
Blackboard, or runtime state, never instantiates Nodes, and never prints. The
caller decides what to do with the results.

## Running it

The simplest entry point returns a flat list of human-readable strings, each
prefixed `[ERROR]` or `[WARNING]`. An empty list means clean.

```gdscript
if OS.is_debug_build():
    var issues: Array[String] = JourneyRuntime.validate(config)
    for line in issues:
        push_warning(line)
```

!!! tip "Validate in debug builds only"
    The walk has a cost, and shipping players don't need it. Gate the call behind
    `OS.is_debug_build()` as above — the bundled `sample_game/` does exactly this
    in `_ready()`.

## What it checks

| Check | Severity | Notes |
| --- | --- | --- |
| `start_event_id` is empty | **Error** | A journey can't begin without one. |
| Resource def `min_value > max_value` | **Error** | Invalid bounds. |
| Resource def `default_value` outside `[min, max]` | **Error** | The seed value can't be clamped sanely. |
| Event with an empty `id` | **Error** | Surfaced from the index build; every indexed event needs a stable id. |
| Duplicate event `id` | **Error** | Surfaced from the index build; ambiguous identity. |
| **Unresolved routing id** (`start_event_id` / `target_event_id` / boundary id) | **Error** | The id has no event behind it — the route dead-ends. See below. |
| Condition/consequence references an **undeclared resource key** | **Warning** | Almost always a typo against `resource_defs`. |
| Dead/unfinished choice (no target id, no pool, no consequences) | **Warning** | Catches half-authored nodes; see below. |

!!! note "Validation needs a built event index"
    Routing is by id, so `validate(config, event_index)` resolves ids and runs
    per-event checks against the index. `JourneyRuntime.validate(config)` builds
    one from `config.events_dir` for you. Called with no index, only config-level
    checks (empty `start_event_id`, resource bounds) run and a note is appended.

!!! note "Flag keys are never flagged"
    Conditions and consequences that reference *flags* (`HAS_FLAG`, `NOT_FLAG`,
    `SET_FLAG`, `TOGGLE_FLAG`) never produce undeclared-key warnings — flags are
    created lazily by design and have no "declared" set to check against. Only
    *resource* keys are checked against `resource_defs`.

### The dead-choice warning

A choice with an **empty** `target_event_id`, **no** `continue_to_pool`, and
**no** consequences is reported as a warning. This shape is a legitimate "bare
end of journey" button, but it's far more often an unfinished node. The warning
catches the unfinished case; to mark a terminal choice as deliberate, give it any
consequence (e.g. a `SET_FLAG` recording the ending). The sample's ending events
do this — their final "close the book" choice sets an `ending_*` flag.

### The unresolved-id error

Routing is id-based (see [Routing](../concepts/routing.md#routing-is-by-id-every-event-is-independently-loadable)),
so the one structural way a route can break is a **dangling id** — a
`target_event_id`, `start_event_id`, or boundary `*_event_id` with no matching
event in the index (a typo, or a deleted/renamed event). `validate()` resolves
every routing id against the index and reports each miss as an **error** naming
the offender:

```text
[ERROR] event 'evt_madness' choice[0] target_event_id 'evt_ending_routr' does not resolve to an indexed event
```

Fix it by correcting the id or adding the missing event under `events_dir`.
(Routing *cycles* are no longer an error — id-based routes are always
serializable, so a loop-back is a supported shape.)

## Validate is not enough on its own — round-trip from disk

`validate()` inspects events held in memory (the live or an in-memory index). The
authoritative "would this ship?" check also proves the content survives a real
trip to and from disk in a fresh load context — catching an unloadable event file
or a dangling id that only an honest disk build reveals.

The engine ships that check as `JourneyLoadCheck` (`tests/journey_load_check.gd`).
It loads your config from disk with `CACHE_MODE_IGNORE` (never the cached
in-memory instance), builds the event index straight from `events_dir`, and
asserts every event file loads and every routing id resolves:

```gdscript
var problems: Array[String] = JourneyLoadCheck.check("res://my_game/config.tres")
if not problems.is_empty():
    for p in problems:
        push_error(p)   # content is unloadable / has a dangling id — do not ship
```

A pre-ship gate (or CI) should require **both** `validate()` *and*
`JourneyLoadCheck.check()` to come back clean. The bundled
`tests/test_export_sanity.gd` runs the round-trip over `sample_game/` before
export for exactly this reason.

## What validation needs an index for

`JourneyValidator.validate()` does **not** scan a directory itself — the author
may be inspecting a config whose `events_dir` isn't valid yet. The convenient
`JourneyRuntime.validate(config)` wrapper builds the index from `config.events_dir`
for you (reusing the live one if a journey is active), so id resolution and
per-event checks always run. If you call the typed `JourneyValidator.validate`
directly with no index, only config-level checks run and the result includes the
notice `events not indexed — pass a built JourneyEventIndex …`.

Duplicate/empty-id problems are detected while the index is built (loud
`push_error` + recorded), and `validate()` surfaces them in its typed result.

## Deterministic output

Given identical input, `validate()` returns an identical message list — resource
defs in declaration order, events id-sorted (as the index sorts them), build
problems sorted by message. This makes it safe to assert on in CI or diff across
runs.

See also: [Authoring Content](authoring-content.md) ·
[Resources & Events](../concepts/resources-and-events.md) ·
[API Reference](../reference/api.md#validateconfig-arraystring).

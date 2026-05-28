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
| `start_event` is null | **Error** | A journey can't begin without one. |
| Resource def `min_value > max_value` | **Error** | Invalid bounds. |
| Resource def `default_value` outside `[min, max]` | **Error** | The seed value can't be clamped sanely. |
| Event with an empty `id` | **Error** | Saves and the pool index need stable ids. |
| Duplicate event `id` (across the reachable graph + pool) | **Error** | Ambiguous identity. |
| Condition/consequence references an **undeclared resource key** | **Warning** | Almost always a typo against `resource_defs`. |
| Dead/unfinished choice (null target, no pool, no consequences) | **Warning** | Catches half-authored nodes; see below. |

!!! note "Flag keys are never flagged"
    Conditions and consequences that reference *flags* (`HAS_FLAG`, `NOT_FLAG`,
    `SET_FLAG`, `TOGGLE_FLAG`) never produce undeclared-key warnings — flags are
    created lazily by design and have no "declared" set to check against. Only
    *resource* keys are checked against `resource_defs`.

### The dead-choice warning

A choice with **no** `target_event`, **no** `continue_to_pool`, and **no**
consequences is reported as a warning. This shape is a legitimate "bare end of
journey" button, but it's far more often an unfinished node. The warning catches
the unfinished case; to mark a terminal choice as deliberate, give it any
consequence (e.g. a `SET_FLAG` recording the ending). The sample's ending events
do this — their final "close the book" choice sets an `ending_*` flag.

## The pool isn't validated unless it's built

`validate()` does **not** trigger a pool directory scan — the author may be
inspecting a config whose `event_pool_dir` isn't valid yet. So:

- If a journey is active and the pool index is already built, pool events are
  included in the walk.
- Otherwise, the result includes a notice: `pool was not validated — pass a built
  JourneyPoolIndex to include pool events`.

The sample filters that one notice out as expected noise:

```gdscript
var filtered: Array[String] = []
for line in issues:
    if line.find("pool was not validated") == -1:
        filtered.append(line)
if not filtered.is_empty():
    _show_toast("validate(): %d issue(s) — see Output" % filtered.size())
```

Note that duplicate/empty ids *within the pool directory itself* are already
caught loudly at load time by the pool index, independent of `validate()`.

## Deterministic output

Given identical input, `validate()` returns an identical message list — resource
defs in declaration order, events in collection order, duplicate-id messages
sorted by id. This makes it safe to assert on in CI or diff across runs.

See also: [Authoring Content](authoring-content.md) ·
[Resources & Events](../concepts/resources-and-events.md) ·
[API Reference](../reference/api.md#validateconfig-arraystring).

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
| **`target_event` reference cycle** | **Error** | Unserializable — cannot be loaded from disk. See below. |

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

### The `target_event` cycle error

`choice.target_event` is an eager object reference that Godot serializes as a
hard `ext_resource` / `SubResource` pointer. A **directed cycle** in that
reference graph (A → B → C → A) cannot be saved and loaded by Godot's resource
format — the content is **unloadable from disk** even though the in-memory
object graph is perfectly legal (which is why every other check can pass while
the game still can't boot). See
[Routing → `target_event` is an eager reference](../concepts/routing.md#target_event-is-an-eager-object-reference-never-form-a-cycle).

`validate()` walks the hard-reference graph — `start_event` ∪ boundary events
∪ pool events (when a built index is supplied), following **only**
`choice.target_event` edges — and reports the first cycle it finds as an
**error** naming the concrete loop:

```text
[ERROR] target_event reference cycle: evt_response → evt_day_dispatcher → evt_event → evt_response
        — a target_event reference cycle cannot be saved or loaded by Godot's
        resource format … Break the loop with a continue_to_pool choice, or
        restructure so the loop-back carries no serialized reference.
```

`continue_to_pool` loop-backs and `pool_conditions` / `pool_tags_filter` are
**not** followed as edges — they carry no serialized reference and are the
correct, cycle-free way to express a day-loop or return-to-hub. Fix a reported
cycle by converting its loop-back edge to a `continue_to_pool` choice.

## Validate is not enough on its own — round-trip from disk

`validate()` inspects the **in-memory** object graph. So does the usual runtime
smoke test (`start_new_journey` runs on objects you built in memory). Neither
proves the content can be **read back from disk** — the exact gap a
`target_event` cycle slips through. The canonical "would this ship?" check is a
real disk round-trip in a fresh load context.

The engine ships that check as `JourneyLoadCheck` (`tests/journey_load_check.gd`).
It loads your config from disk with `CACHE_MODE_IGNORE` (never the cached
in-memory instance), walks `start_event` ∪ boundaries ∪ the pool dir, and
asserts every reachable resource loads non-null with no parse error:

```gdscript
var problems: Array[String] = JourneyLoadCheck.check("res://my_game/config.tres")
if not problems.is_empty():
    for p in problems:
        push_error(p)   # content is unloadable as authored — do not ship
```

A pre-ship gate (or CI) should require **both** `validate()` *and*
`JourneyLoadCheck.check()` to come back clean. The bundled
`tests/test_export_sanity.gd` runs the round-trip over `sample_game/` before
export for exactly this reason.

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

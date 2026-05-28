# The Stochastic Pool

The pool is how Journey Engine produces variety: instead of routing to a fixed
event, a choice can request a **weighted random pull** from a directory of
tagged, eligible events. This guide covers how the pool is built, how candidates
are filtered, and how selection stays deterministic.

## Routing a choice into the pool

Set the choice's routing fields (see [Routing](../concepts/routing.md)):

```gdscript
var choice := JourneyChoice.new()
choice.button_text = "Take to the road."
choice.continue_to_pool = true          # request a pull (target_event must be null)
choice.pool_tags_filter = ["road"]      # scope: only events tagged "road"; empty => all
```

Adapted from the sample's `evt_road_begins.tres`, this drops the player into a
stream of random "road" encounters.

## The pool directory

Pool events are `.tres`/`.res` files under `config.event_pool_dir`. On the first
pull (lazily, so a game that never enters the pool pays no cost), the engine
recursively scans that directory and indexes every `JourneyEvent` by its tags.

!!! warning "Every pool event needs a unique, non-empty `id`"
    Duplicate ids and empty ids are **skipped with a `push_error`** naming the
    offending file — a single bad event can't take down the build. The
    [validator](validation.md) catches these at authoring time too.

The scan is export-safe: it uses `DirAccess` on the `res://` virtual filesystem
and understands the `.remap` pointers Godot creates when baking resources into a
PCK — so the pool works identically in the editor and in exported Web/WASM
builds. See [Exporting](exporting.md).

## How a candidate is selected

When a `continue_to_pool` choice fires, selection runs in four steps:

1. **Scope** — the union of events whose tags match `pool_tags_filter` (or *all*
   events if the filter is empty). An event with two matching tags is **deduped**
   so it doesn't double its odds.
2. **Filter** — within scope, keep an event only if:
    - it is `repeatable`, **or** its `id` is not in `seen_ids`; **and**
    - its `pool_conditions` group passes against the current Blackboard.
3. **Empty?** — if no candidate survives, return nothing → `journey_error`
   (see below).
4. **Weighted pick** — otherwise choose one by `weight` (see next section).

### Event eligibility fields

These `JourneyEvent` fields control pool behavior:

| Field | Effect |
| --- | --- |
| `event_tags` | Which `pool_tags_filter` scopes include this event. |
| `weight` | Relative selection odds (default `100`). |
| `repeatable` | If `false`, dropped from future pulls once seen. |
| `pool_conditions` | A `JourneyConditionGroup` gating eligibility (null ⇒ always eligible). |

The sample pool illustrates each:

- `evt_road_bandit` — `weight = 200`, `repeatable = true` (a common, recurring
  danger).
- `evt_road_camp` — `repeatable = true` (you can rest more than once).
- `evt_road_ally` — `pool_conditions = ALL[HAS_FLAG helped_stranger]`: only
  eligible if you helped the stranger earlier (an **event-level** flag chain).
- `evt_road_inn` — `pool_conditions = ALL[road_progress >= 30]`: only appears
  once you've travelled far enough, and routes to the ending.

## Weighted selection and determinism

Selection is a cumulative-weight roll drawn **exclusively** from the Blackboard's
seeded RNG (`blackboard.rng`) — never a global `randf()` or a fresh generator.
That's the contract that makes runs reproducible: same seed + same choices ⇒ same
pulls, which is what lets [save/load](save-and-load.md) resume the exact run.

!!! note "Weight edge cases"
    - **Negative weights** clamp to `0`.
    - If **all** candidates have weight `≤ 0`, the engine warns and falls back to
      a uniform pick rather than failing — a non-empty candidate set always
      yields an event. (Authors sometimes set `weight = 0` expecting exclusion;
      the warning surfaces that mismatch. To truly exclude an event, gate it with
      `pool_conditions` or `repeatable`, not weight.)

## Empty pools

If filtering leaves no candidate, the engine emits:

```text
journey_error: "empty pool for tags: [...]"
```

The journey does **not** advance and does **not** crash — it simply can't move
from this choice, which surfaces as a dev-visible error. Common causes:

- The tag filter matches no events (typo in `pool_tags_filter` or `event_tags`).
- Every matching event is non-repeatable and already seen.
- Every matching event's `pool_conditions` currently fail.

Design pools so at least one repeatable event always matches the tags you pull
with, and the pool can't dead-end.

## Hot-reloading the pool in the editor

If you add or edit pool events while iterating, `JourneyRuntime.rebuild_pool()`
rebuilds the index from `event_pool_dir`, re-reading from disk (it uses
`CACHE_MODE_REPLACE` so stale cached resources aren't returned).

See also: [Routing](../concepts/routing.md) · [Authoring Content](authoring-content.md)
· [Save & Load](save-and-load.md) for how the RNG stream is preserved.

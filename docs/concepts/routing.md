# Routing

When the player makes a choice, `process_choice` does two things in order:

1. **Applies the choice's consequences** to the Blackboard (clamped), emitting a
   `resource_changed` / `flag_changed` signal for each value that actually
   changed (using the post-clamp stored value).
2. **Routes to the next event** using a strict precedence.

This page is about step 2: how the engine decides what happens next.

## Routing precedence

The engine evaluates these in order and takes the **first** that applies:

```text
1. Forced boundary route   (a resource transitioned to min/max with a route set)
2. Deterministic target    (choice.target_event_id is non-empty)
3. Stochastic pool pull     (choice.continue_to_pool is true)
4. End the journey          (none of the above)
```

So a boundary route always wins over the choice's own `target_event_id`, which
always wins over a pool pull. If nothing routes, the journey ends on the current
event and `journey_ended` fires.

### Deterministic vs. stochastic, side by side

The difference is entirely in how you fill out the choice's **Routing** fields.

=== "Deterministic route"

    Set `target_event_id` to a specific event's `id`. Always goes there.

    ```gdscript
    var choice := JourneyChoice.new()
    choice.button_text = "Help the stranger."
    choice.target_event_id = &"evt_road_begins"   # always routes here
    # continue_to_pool stays false; pool_tags_filter unused
    ```

    *Use for:* authored branches, story beats, endings — anywhere you want a
    known next event.

=== "Stochastic pool pull"

    Leave `target_event_id` empty and set `continue_to_pool = true`. Optionally
    scope the pull with tags.

    ```gdscript
    var choice := JourneyChoice.new()
    choice.button_text = "Take to the road."
    choice.continue_to_pool = true
    choice.pool_tags_filter = ["road"]      # pull a weighted random "road" event
    ```

    *Use for:* the variable middle of a run — random encounters drawn from a
    [tagged pool](../guides/stochastic-pool.md).

!!! note "`target_event_id` beats `continue_to_pool`"
    If a choice has **both** a non-empty `target_event_id` and
    `continue_to_pool = true`, the deterministic target wins and the pool is never
    consulted. The pool branch only runs when `target_event_id` is empty.

### Routing is by id — every event is independently loadable

All routes are **`StringName` ids**, not object references: `target_event_id`,
`config.start_event_id`, and the boundary `*_event_id` fields are resolved at
runtime against the **event index** (every event under `config.events_dir`,
keyed by `id`). Because no event holds a hard pointer to another, each event
`.tres` loads independently, and routing graphs — including loops — are always
serializable. (Game-id routing is the norm for narrative engines for exactly
this reason; it's also why saves and the pool already resolve by id.)

!!! tip "Loops are fine"
    A day-loop or return-to-hub is a normal, supported shape: an event can route
    back to an earlier one by id, or loop through the pool with `continue_to_pool`
    (a plain bool). There is no serialization hazard to avoid. Use
    `continue_to_pool` + `pool_conditions` when you want the loop-back to draw a
    *varied* next event, and a direct `target_event_id` when you want a *fixed* one.

!!! warning "A dangling id dead-ends"
    The one way id routing breaks is a `target_event_id` (or start/boundary id)
    with **no event behind it** — a typo, or an event you deleted/renamed. At
    runtime the engine emits `journey_error("… did not resolve to an indexed
    event")` and does not advance. Catch these before running:
    [`validate()`](../guides/validation.md) reports every unresolved id as an
    error, and `JourneyLoadCheck` confirms it from a fresh disk load.

## Forced boundary routes

Each `JourneyResourceDef` can name a `bottom_out_event_id` (fired at `min_value`)
and a `top_out_event_id` (fired at `max_value`). These **override** the choice's
own routing — the classic use is "sanity reaches 0 → forced madness event".

!!! warning "Boundary routes fire on *transition*, not presence"
    A boundary route fires only when this batch of consequences **moves** the
    value onto the boundary — i.e. it was off the boundary before and lands on it
    after. A value that was *already* at `min_value` does **not** re-trigger.

    This matters: without it, a no-op choice on an event reached *because* a
    resource bottomed out would re-fire the same boundary route forever (an
    infinite loop). The transition rule is what lets the player continue past a
    bottom-out event.

    | Before | Consequence | After | Fires? |
    | --- | --- | --- | --- |
    | 10 | `SUBTRACT 10` | 0 (= min) | ✅ yes — transition onto min |
    | 0 | no-op | 0 | ❌ no — already at min |
    | 0 | `SUBTRACT 5` (clamps) | 0 | ❌ no — already at min |
    | 0 | `ADD 5` | 5 | ❌ no — left the boundary |

### When two resources bottom out at once

If a single batch transitions **multiple** resources onto a boundary, the engine
fires the route of the **first** one in `resource_defs` declaration order and
ignores the rest. So the order you list resources in the config is also their
boundary-route priority.

## Ending a journey

A journey ends when a processed choice has no forced route, an empty
`target_event_id`, and `continue_to_pool` false. The engine emits `journey_ended(ending_event)`
where `ending_event` is the event the terminal choice belonged to — your UI uses
it to show an ending screen.

## When routing can't resolve

- **Empty pool.** A `continue_to_pool` choice whose filtered pool has no eligible
  candidate emits `journey_error("empty pool for tags: …")` and does **not**
  advance — the journey simply stays put rather than crashing. See
  [Stochastic Pool](../guides/stochastic-pool.md#empty-pools).
- **Unresolved id.** A `target_event_id` / `start_event_id` / boundary id with no
  matching event in the index emits `journey_error("… did not resolve to an
  indexed event")` and does **not** advance. [`validate()`](../guides/validation.md)
  catches these before you run.
- **Null route.** A route resolving to a null event emits
  `journey_error("route resolved to null")`.

Both are loud, recoverable, and never crash the game.

See also: [Stochastic Pool](../guides/stochastic-pool.md) for how pool candidates
are filtered and weighted · [Resources & Events](resources-and-events.md) for the
routing fields on each type.

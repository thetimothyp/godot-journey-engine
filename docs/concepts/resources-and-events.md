# Resources & Events

All Journey Engine content is built from seven `Resource` types. They nest: a
`JourneyConfig` points at events, events hold choices, choices hold conditions
and consequences. Everything is editable in the Godot inspector — this page
describes what each type is and how they fit together. For the click-by-click
authoring workflow, see [Authoring Content](../guides/authoring-content.md).

## How the types nest

```text
JourneyConfig
├── resource_defs: [JourneyResourceDef]      # the schema for numeric state
├── initial_flags: { String: bool }
├── start_event_id: StringName               # resolved against the event index ┐
└── events_dir: "res://my_game/"             # scanned recursively for events    │
                                              ▼
                                       JourneyEvent  (one .tres per event, keyed by id)
                                       ├── narrative_text, background_texture, ambient_audio
                                       ├── id, event_tags, weight, repeatable, pool_eligible
                                       ├── pool_conditions: JourneyConditionGroup
                                       └── choices: [JourneyChoice]
                                                          │
                                                          ▼
                                                   JourneyChoice
                                                   ├── button_text
                                                   ├── visibility: JourneyConditionGroup
                                                   ├── consequences: [JourneyConsequence]
                                                   ├── target_event_id: StringName  ── resolved against the index
                                                   ├── continue_to_pool: bool
                                                   └── pool_tags_filter: [String]
```

A `JourneyConditionGroup` (used for both `visibility` and `pool_conditions`)
holds an `ALL`/`ANY` list of `JourneyCondition`s.

## JourneyConfig

The per-game configuration object. One per game; passed to
`start_new_journey()`.

| Field | Type | Notes |
| --- | --- | --- |
| `resource_defs` | `Array[JourneyResourceDef]` | The numeric-resource schema. |
| `initial_flags` | `Dictionary` (`String → bool`) | Flags set true/false at journey start. |
| `start_event_id` | `StringName` | Id of the first event. **Required** — an empty start id is a validation error. |
| `events_dir` | `String` | Directory scanned **recursively** for all events (deterministic + pool), indexed by id. Default `res://events/`. |
| `rebuild_index_in_editor` | `bool` | Studio hot-reload hint. |
| `save_encryption_key` | `String` | Empty ⇒ plaintext saves; non-empty ⇒ password-encrypted. |
| `save_version` | `int` | Migration anchor; bump on breaking save-format changes. |

## JourneyResourceDef

Declares one bounded numeric resource. The engine clamps every write to
`[min_value, max_value]` and seeds the Blackboard with `default_value` (also
clamped).

| Field | Type | Notes |
| --- | --- | --- |
| `key` | `String` | The resource name, e.g. `"gold"`. |
| `default_value` | `float` | Starting value. Should sit within the bounds. |
| `min_value` | `float` | Lower bound (default `0.0`). |
| `max_value` | `float` | Upper bound (default `100.0`). |
| `bottom_out_event_id` | `StringName` | Id of the event fired when a write **transitions** the value down to `min_value`. |
| `top_out_event_id` | `StringName` | Optional. Id of the event fired when a write transitions up to `max_value`. |

Boundary routes are a powerful authoring tool — "sanity hits 0 → madness event".
See [Routing](routing.md#forced-boundary-routes) for the exact (transition, not
presence) firing rule.

## JourneyEvent

A narrative node: what the player reads, plus the choices they can take. Every
event lives as a `.tres` under `events_dir` and is reached **by id** — as a
choice's `target_event_id`, the config's `start_event_id`, a boundary route, or a
stochastic pool pull (`pool_eligible` events).

| Field | Type | Notes |
| --- | --- | --- |
| `narrative_text` | `String` | The body text (multiline). |
| `background_texture` | `Texture2D` | Optional presentation payload — the engine never displays it; your UI does. |
| `ambient_audio` | `AudioStream` | Optional presentation payload. |
| `id` | `StringName` | Stable identity used by saves, the event index, and all routing. **Must be unique and non-empty** for any routing target or pool event. |
| `pool_eligible` | `bool` | If `true`, the event is a candidate for stochastic pool pulls. Deterministic-only events leave it `false`. |
| `event_tags` | `Array[String]` | Tags for pool filtering. |
| `weight` | `int` | Selection weight in the pool (default `100`). |
| `pool_conditions` | `JourneyConditionGroup` | Eligibility gate for pool inclusion. |
| `repeatable` | `bool` | If `false`, excluded from future pool pulls once seen. |
| `choices` | `Array[JourneyChoice]` | The choices offered. |

## JourneyChoice

A button the player can press. Carries its visibility gate, the consequences it
applies, and how it routes.

| Field | Type | Notes |
| --- | --- | --- |
| `button_text` | `String` | The label (multiline). |
| `visibility` | `JourneyConditionGroup` | Gate for *showing* the choice. **Null ⇒ always visible.** |
| `consequences` | `Array[JourneyConsequence]` | State changes applied when chosen. |
| `target_event_id` | `StringName` | Deterministic route by id; takes precedence over a pool pull. |
| `continue_to_pool` | `bool` | If `true` **and** `target_event_id` is empty, request a stochastic pool pull. |
| `pool_tags_filter` | `Array[String]` | Tag scope for that pull; empty ⇒ all events. |

A choice with an empty `target_event_id`, no `continue_to_pool`, and no consequences is a
**terminal** choice — it ends the journey. (The validator warns on this shape in
case it was unfinished; add any consequence to silence it for a deliberate "end"
button.)

## JourneyCondition

A single typed comparison against the Blackboard. The `op` enum:

| `Op` | Value | Meaning |
| --- | --- | --- |
| `GT` | 0 | resource `>` `value` |
| `GTE` | 1 | resource `>=` `value` (the default) |
| `LT` | 2 | resource `<` `value` |
| `LTE` | 3 | resource `<=` `value` |
| `EQ` | 4 | resource `==` `value` |
| `NEQ` | 5 | resource `!=` `value` |
| `HAS_FLAG` | 6 | flag `key` is `true` |
| `NOT_FLAG` | 7 | flag `key` is `false` (or unset) |

| Field | Type | Notes |
| --- | --- | --- |
| `key` | `String` | Resource or flag name. |
| `op` | `Op` | The comparison (default `GTE`). |
| `value` | `float` | Right-hand side. **Ignored** for `HAS_FLAG` / `NOT_FLAG`. |

## JourneyConditionGroup

A single level of `ALL`/`ANY` over a list of conditions.

| `Logic` | Value | Meaning |
| --- | --- | --- |
| `ALL` | 0 | every condition must pass (the default) |
| `ANY` | 1 | at least one must pass |

| Field | Type | Notes |
| --- | --- | --- |
| `logic` | `Logic` | `ALL` or `ANY`. |
| `conditions` | `Array[JourneyCondition]` | The conditions. |

!!! tip "Empty and null groups pass"
    A **null** group (e.g. an unset `visibility`) passes — the choice is always
    visible. An **empty** group passes too, for both `ALL` and `ANY` (vacuous
    truth). This is deliberate anti-footgun behavior: forgetting to add
    conditions never hides content.

## JourneyConsequence

A single typed mutation applied to the Blackboard. The `Operation` enum:

| `Operation` | Value | Effect |
| --- | --- | --- |
| `ADD` | 0 | resource `+= value` (the default) |
| `SUBTRACT` | 1 | resource `-= value` |
| `SET_VALUE` | 2 | resource `= value` |
| `SET_FLAG` | 3 | flag `= flag_value` |
| `TOGGLE_FLAG` | 4 | flag `= not flag` |

| Field | Type | Notes |
| --- | --- | --- |
| `operation` | `Operation` | The mutation (default `ADD`). |
| `key` | `String` | Resource or flag name. |
| `value` | `float` | Amount for `ADD` / `SUBTRACT` / `SET_VALUE`. |
| `flag_value` | `bool` | Used by `SET_FLAG` only (default `true`). |

Numeric consequences are **clamped** to the target resource's bounds. A numeric
consequence against an undeclared key is skipped with a warning — the engine
never auto-creates an unbounded resource.

See also: [Authoring Content](../guides/authoring-content.md) for the
inspector workflow · [Routing](routing.md) for how `target_event_id` /
`continue_to_pool` / boundary routes interact.

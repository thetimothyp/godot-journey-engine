# The Blackboard

The **Blackboard** is the single object holding all mutable run state. The
runtime owns one (`JourneyRuntime.blackboard`) and passes it everywhere internal
logic needs to read or change state. It is a plain `RefCounted` data container —
no logic, no signals.

## What's inside

| Field | Type | Holds |
| --- | --- | --- |
| `resources` | `Dictionary` (`String → float`) | Bounded numbers. Bounds come from `JourneyResourceDef`; the engine clamps on every write. |
| `flags` | `Dictionary` (`String → bool`) | Booleans. Created lazily — a missing flag reads as `false`. |
| `metadata` | `Dictionary` (`String → Variant`) | Engine bookkeeping (see below) plus any custom keys you set. |
| `rng` | `RandomNumberGenerator` | The seeded RNG that drives every stochastic pool pull. |

### Engine-owned metadata keys

The engine maintains these keys in `metadata`. They are the **only** metadata
preserved across [save/load](../guides/save-and-load.md):

| Key | Type | Meaning |
| --- | --- | --- |
| `current_event_id` | `String` | The id of the event currently shown. Stored as a string (not an object) so renaming a `.tres` can't corrupt a save. |
| `turn_counter` | `int` | How many events have been entered this run. |
| `seen_ids` | `Array[String]` | Every event id entered — drives non-repeatable pool filtering. |
| `history` | `Array[String]` | Ring buffer of recent event ids, capped at 200. |
| `rng_seed` | `int` | The seed the RNG was initialized with. |

!!! warning "Custom metadata does not survive a save"
    You can write your own keys into `metadata` for within-session use, and read
    them back via `JourneyRuntime.get_metadata(key)`. But saves serialize **only**
    the engine-owned keys above — anything else is dropped on load. If you need
    persistent custom state, model it as a resource or a flag.

## The single mutation path

This is the most important rule about the Blackboard:

!!! danger "Never write the Blackboard directly"
    Game code must **never** mutate `JourneyRuntime.blackboard.resources`,
    `.flags`, or `.metadata`. All state change flows through a choice's
    **consequences**, applied by the runtime inside `process_choice`. That single
    path is what guarantees clamping, boundary-route detection, change signals,
    and deterministic, save-safe state.

To change state, author a `JourneyConsequence` on a choice (see
[Resources & Events](resources-and-events.md)). To *read* state, use the
runtime's convenience accessors — never reach into the dictionaries yourself:

```gdscript
var gold: float = JourneyRuntime.get_resource("gold")   # 0.0 if missing
var helped: bool = JourneyRuntime.has_flag("helped_stranger")  # false if missing
var turn: int = int(JourneyRuntime.get_metadata("turn_counter"))
```

## Initialization

`start_new_journey(config, seed)` initializes the Blackboard from your
`JourneyConfig`:

- Each declared resource is seeded to its `default_value`, **clamped** into
  `[min_value, max_value]`.
- `initial_flags` from the config are copied in.
- The RNG is seeded: a non-zero `seed` is deterministic; `seed = 0` calls
  `randomize()`. Either way the chosen seed is recorded in `metadata["rng_seed"]`.
- `turn_counter`, `current_event_id`, `history`, and `seen_ids` are primed.

## Missing-key read policy

The Blackboard never auto-creates entries. Reads of missing keys follow a fixed
policy:

- **Missing resource key in a condition** → treated as `0.0`, **with a warning**
  (likely an author typo against the declared resource set).
- **Missing flag key** → `false`, **no warning** (flags are created lazily by
  design).
- **Consequences never auto-create an undeclared resource** — a numeric
  consequence against a key with no `JourneyResourceDef` is skipped with a
  warning.

The [validator](../guides/validation.md) flags undeclared-key references at
authoring time so these warnings rarely surprise you at runtime.

See also: [Resources & Events](resources-and-events.md) ·
[Routing](routing.md) · [Save & Load](../guides/save-and-load.md).

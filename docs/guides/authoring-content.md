# Authoring Content

The [Quick Start](../getting-started/quick-start.md) built content in code to
stay self-contained, but that gets tedious fast. The intended workflow is
**authoring `.tres` resources in the Godot inspector** — no code. Every Journey
Engine type is a `Resource` with a `class_name`, so they all appear in the
**Create New Resource** dialog and edit like any built-in resource.

This guide walks the inspector workflow using content adapted from the bundled
`sample_game/`.

## The authoring loop

1. Create a folder layout (a common one):

    ```text
    res://my_game/
    ├── config.tres
    ├── events/        # deterministic, hand-linked events
    └── pool/          # stochastic pool events (event_pool_dir points here)
    ```

2. Create events as `.tres` files.
3. Create one `JourneyConfig` declaring resources and pointing at the start event
   and the pool directory.
4. [Validate](validation.md) and run.

## Creating an event

**FileSystem → right-click your `events/` folder → Create New… → Resource →
`JourneyEvent`.** In the inspector:

- **Presentation:** write `narrative_text`; optionally set `background_texture` /
  `ambient_audio` (the engine just carries these — your UI displays them).
- **System:** set a unique, non-empty `id` (e.g. `evt_start`). Add `event_tags`,
  `weight`, `repeatable`, and `pool_conditions` if it's a pool event (see the
  [Stochastic Pool guide](stochastic-pool.md)).
- **Choices:** size the `choices` array and create a `JourneyChoice` in each slot.

### Adding a choice with a consequence

Inside a choice, set `button_text`, then size the `consequences` array and add a
`JourneyConsequence`. For example, the sample's opening "help the stranger"
choice sets a flag and routes to the next event:

```gdscript
# Equivalent of sample_game/events/evt_start.tres — "Help the stranger" choice.
var conseq := JourneyConsequence.new()
conseq.operation = JourneyConsequence.Operation.SET_FLAG   # value 3 in the inspector
conseq.key = "helped_stranger"
# flag_value defaults to true

var choice := JourneyChoice.new()
choice.button_text = "Help the stranger fix their wagon."
choice.consequences = [conseq]
choice.target_event = evt_road_begins      # deterministic route
```

!!! tip "Enum fields show as dropdowns"
    In the inspector, `operation`, `op`, and `logic` render as named dropdowns —
    you don't type the integer. The numbers (e.g. `SET_FLAG = 3`) only appear in
    the raw `.tres` text; they're listed in
    [Resources & Events](../concepts/resources-and-events.md) for reference.

## Gating a choice with conditions (visibility)

A choice's `visibility` is a `JourneyConditionGroup`. **Null visibility ⇒ always
shown.** To gate, add a group and conditions. The sample's bandit event shows a
"pay them off" choice only if the player can afford it:

```gdscript
# Equivalent of the "Pay them off (-30 gold)" choice on evt_road_bandit.tres.
var can_afford := JourneyCondition.new()
can_afford.key = "gold"
can_afford.op = JourneyCondition.Op.GTE     # value 1 in the inspector
can_afford.value = 30.0

var gate := JourneyConditionGroup.new()
gate.logic = JourneyConditionGroup.Logic.ALL  # default
gate.conditions = [can_afford]

var pay := JourneyChoice.new()
pay.button_text = "Pay them off (-30 gold)."
pay.visibility = gate
# ... consequences: SUBTRACT 30 gold, etc.
```

When the player has less than 30 gold, the engine simply omits this choice from
the `event_changed` choice list — your UI never sees it.

## Building the JourneyConfig

Create one `JourneyConfig` resource. Adapted from `sample_game/config.tres`:

- **`resource_defs`** — one `JourneyResourceDef` per number. The sample declares
  `gold` (0–999, default 50), `sanity` (0–100, default 50, `bottom_out_event =
  evt_madness`), `rations` (0–200, default 100), and `road_progress` (0–100).
- **`initial_flags`** — e.g. `{ "started": true }`.
- **`start_event`** — the first event (`evt_start`).
- **`event_pool_dir`** — `res://my_game/pool/`.
- **Save settings** — `save_encryption_key` (empty ⇒ plaintext) and
  `save_version` (start at 1).

```gdscript
# Equivalent shape of sample_game/config.tres, in code.
var sanity := JourneyResourceDef.new()
sanity.key = "sanity"
sanity.default_value = 50.0
sanity.min_value = 0.0
sanity.max_value = 100.0
sanity.bottom_out_event = evt_madness       # sanity hits 0 -> forced route

var config := JourneyConfig.new()
config.resource_defs = [gold, sanity, rations, road_progress]
config.initial_flags = { "started": true }
config.start_event = evt_start
config.event_pool_dir = "res://my_game/pool/"
```

## Flag chains: a later event paying off an earlier choice

A common narrative pattern is "a choice early on changes what's available later."
You don't need code — just a `SET_FLAG` consequence early and a `HAS_FLAG`
condition later. The sample does exactly this with `helped_stranger`:

- `evt_start`: the "help the stranger" choice does `SET_FLAG helped_stranger`.
- `evt_road_merchant`: a bonus choice has `visibility = ALL[HAS_FLAG
  helped_stranger]`, so it only appears if you helped.
- `evt_road_ally`: its `pool_conditions = ALL[HAS_FLAG helped_stranger]`, so the
  whole event is only eligible for the pool if you helped.

The same flag thus gates a *choice* in one place and an *event's eligibility* in
another — see the [Stochastic Pool guide](stochastic-pool.md) for the latter.

## Routing a loop: use `continue_to_pool`, not a `target_event` ring

When your story loops — a day-loop, a return-to-hub — express the loop-back with
a `continue_to_pool` choice, **not** by pointing `target_event` back at an
earlier event. `target_event` is an eager object reference that Godot serializes
as a hard pointer, and **a cycle of those cannot be loaded from disk** (it
passes in-memory validation and the smoke test, then fails to boot in a shipped
build). `continue_to_pool` is a plain bool with no serialized reference, so it
loops safely; gate which events come back with each event's `pool_conditions`.
See [Routing](../concepts/routing.md#target_event-is-an-eager-object-reference-never-form-a-cycle).

## Author-time safety net

Before you run, call [`validate()`](validation.md) on your config. It catches
null start events, bad resource bounds, duplicate/empty event ids, undeclared
resource keys (typos), dead/unfinished choices, and **`target_event` reference
cycles** (which are unloadable from disk) — pure inspection, no run required.

`validate()` and the runtime smoke test both run on the **in-memory** object
graph, so neither proves your content can be read back from disk. The
authoritative "would this ship?" check is a real disk round-trip — run
`JourneyLoadCheck.check("res://my_game/config.tres")` and require it to come
back with zero problems alongside a clean `validate()`. See
[Validation → round-trip from disk](validation.md#validate-is-not-enough-on-its-own-round-trip-from-disk).

See also: [Resources & Events](../concepts/resources-and-events.md) for the full
field reference · [Validation](validation.md) · [Routing](../concepts/routing.md).

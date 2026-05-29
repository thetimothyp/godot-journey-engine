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
    res://my_game/        # events_dir points at this tree (scanned recursively)
    ├── config.tres
    ├── events/        # deterministic, id-linked events
    └── pool/          # stochastic pool events (pool_eligible = true)
    ```

    `events_dir` is scanned **recursively** and indexes every `JourneyEvent`
    under it by `id`; the `events/` vs `pool/` split is just for your own
    organization — whether an event can be drawn at random is the per-event
    `pool_eligible` flag, not its folder.

2. Create events as `.tres` files, each with a unique `id`.
3. Create one `JourneyConfig` declaring resources, the `start_event_id`, and the
   `events_dir`.
4. [Validate](validation.md) and run.

## Creating an event

**FileSystem → right-click your `events/` folder → Create New… → Resource →
`JourneyEvent`.** In the inspector:

- **Presentation:** write `narrative_text`; optionally set `background_texture` /
  `ambient_audio` (the engine just carries these — your UI displays them).
- **System:** set a unique, non-empty `id` (e.g. `evt_start`) — every routing
  target is referenced by this id. For a pool event, tick `pool_eligible` and add
  `event_tags`, `weight`, `repeatable`, and `pool_conditions` (see the
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
choice.target_event_id = &"evt_road_begins"   # deterministic route, by id
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
  `gold` (0–999, default 50), `sanity` (0–100, default 50, `bottom_out_event_id =
  &"evt_madness"`), `rations` (0–200, default 100), and `road_progress` (0–100).
- **`initial_flags`** — e.g. `{ "started": true }`.
- **`start_event_id`** — the first event's id (`&"evt_start"`).
- **`events_dir`** — `res://my_game/` (the tree that holds all your events).
- **Save settings** — `save_encryption_key` (empty ⇒ plaintext) and
  `save_version` (start at 1).

```gdscript
# Equivalent shape of sample_game/config.tres, in code.
var sanity := JourneyResourceDef.new()
sanity.key = "sanity"
sanity.default_value = 50.0
sanity.min_value = 0.0
sanity.max_value = 100.0
sanity.bottom_out_event_id = &"evt_madness"   # sanity hits 0 -> forced route, by id

var config := JourneyConfig.new()
config.resource_defs = [gold, sanity, rations, road_progress]
config.initial_flags = { "started": true }
config.start_event_id = &"evt_start"
config.events_dir = "res://my_game/"
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

## Routing a loop

When your story loops — a day-loop, a return-to-hub — just route back by id.
Routes are `StringName` ids resolved against the event index, so a loop is a
normal, supported shape with no serialization hazard: point a choice's
`target_event_id` at an earlier event for a *fixed* loop-back, or set
`continue_to_pool = true` (gating eligibility with `pool_conditions`) for a
*varied* one. See [Routing](../concepts/routing.md#routing-is-by-id-every-event-is-independently-loadable).

## Author-time safety net

Before you run, call [`validate()`](validation.md) on your config. It catches an
empty `start_event_id`, bad resource bounds, duplicate/empty event ids,
**unresolved routing ids** (a `target_event_id`/start/boundary id with no event
behind it), undeclared resource keys (typos), and dead/unfinished choices — pure
inspection, no run required.

`validate()` checks events held in memory. The authoritative "would this ship?"
check also proves they survive a real disk load — run
`JourneyLoadCheck.check("res://my_game/config.tres")` and require it to come
back with zero problems alongside a clean `validate()`. See
[Validation → round-trip from disk](validation.md#validate-is-not-enough-on-its-own-round-trip-from-disk).

See also: [Resources & Events](../concepts/resources-and-events.md) for the full
field reference · [Validation](validation.md) · [Routing](../concepts/routing.md).

# API Reference

The public API is the **`JourneyRuntime`** Autoload. Everything game code needs —
lifecycle, state reads, persistence, validation — is on this one object. The
other `journey_core/` classes are internal machinery the runtime drives; they're
documented at the bottom as [advanced surface](#advanced-internal-surface).

All signatures below are verified against
`journey_core/journey_runtime.gd`; the [accuracy checklist](#accuracy-checklist)
at the end maps each entry to its source line.

## Properties

### `blackboard: Blackboard`

The current run's state container. **Read-only by contract** — never write to
`blackboard.resources`, `.flags`, or `.metadata` directly. Use the
[accessor methods](#state-access) to read, and choice consequences to write.
(See [Blackboard](../concepts/blackboard.md).)

## Lifecycle

### `start_new_journey(config, seed=0) -> void`

```gdscript
func start_new_journey(config: JourneyConfig, seed: int = 0) -> void
```

Begins a new run. Initializes the Blackboard from `config` (resources at clamped
defaults, initial flags, primed metadata), seeds the RNG, emits
`journey_started`, then enters `config.start_event` (emitting `event_changed`).

| Param | Type | Notes |
| --- | --- | --- |
| `config` | `JourneyConfig` | The game config. A null config emits `journey_error`. |
| `seed` | `int` | RNG seed. Non-zero ⇒ deterministic; `0` (default) ⇒ randomized. |

Emits `journey_error("no start_event")` if `config.start_event` is null.

### `process_choice(choice) -> void`

```gdscript
func process_choice(choice: JourneyChoice) -> void
```

The single write path. Applies `choice.consequences` to the Blackboard (clamped),
emits `resource_changed` / `flag_changed` for each value that actually changed
(post-clamp), then routes to the next event per the
[routing precedence](../concepts/routing.md#routing-precedence) — emitting
`event_changed` for the next event or `journey_ended` for a terminal choice.

| Param | Type | Notes |
| --- | --- | --- |
| `choice` | `JourneyChoice` | The chosen choice. Null, or calling before `start_new_journey`, emits `journey_error`. |

## State access

These are convenience reads. They never warn and never mutate. (The condition
[missing-key warning policy](../concepts/blackboard.md#missing-key-read-policy)
applies inside condition evaluation, not to these accessors.)

### `get_resource(key) -> float`

```gdscript
func get_resource(key: String) -> float
```

Returns the resource value for `key`, or `0.0` if missing (no warning).

### `has_flag(key) -> bool`

```gdscript
func has_flag(key: String) -> bool
```

Returns the flag value for `key`, or `false` if missing.

### `get_metadata(key) -> Variant`

```gdscript
func get_metadata(key: String) -> Variant
```

Returns the metadata value for `key`, or `null` if missing. Useful keys:
`turn_counter`, `current_event_id`, `seen_ids`, `history`, `rng_seed`.

## Persistence

Both require an active journey (the save settings live on the config). Both
return a Godot `Error` int.

### `save_game(slot="savegame") -> int`

```gdscript
func save_game(slot: String = "savegame") -> int
```

Serializes the Blackboard to `user://<slot>.dat` (plaintext, or encrypted if
`config.save_encryption_key` is set). Returns `OK`, or `ERR_UNCONFIGURED` if no
journey is active, or a file/write error.

### `load_game(slot="savegame") -> int`

```gdscript
func load_game(slot: String = "savegame") -> int
```

Restores the Blackboard from `user://<slot>.dat` and re-enters the saved event
(re-emitting `event_changed`; **no** per-resource signals fire — repaint the HUD
manually). Atomic: rolls back on failure.

| Return | Meaning |
| --- | --- |
| `OK` | Restored. |
| `ERR_UNCONFIGURED` | No active journey. |
| `ERR_FILE_NOT_FOUND` | Slot doesn't exist. |
| `ERR_INVALID_DATA` | Corrupt save, newer `save_version`, or unresolvable current event. |

See [Save & Load](../guides/save-and-load.md) for the full contract.

## Authoring & dev

### `validate(config) -> Array[String]`

```gdscript
func validate(config: JourneyConfig) -> Array[String]
```

Runs the authoring [validator](../guides/validation.md) and returns a flat list
of `[ERROR]`/`[WARNING]`-prefixed strings (empty = clean). If a journey is active
and the pool index is built, pool events are included; otherwise the result notes
the pool wasn't validated. Intended for `OS.is_debug_build()` use.

### `rebuild_pool() -> void`

```gdscript
func rebuild_pool() -> void
```

Rebuilds the stochastic pool index from `config.event_pool_dir`, re-reading from
disk (editor/Studio hot-reload hook). Safe to call before the first pool pull.

## Signals

Your UI's entire view of the journey. Subscribe in `_ready()`; the data inside is
inert.

| Signal | Parameters | Fires when |
| --- | --- | --- |
| `event_changed` | `event: JourneyEvent, choices: Array[JourneyChoice]` | A new event is entered (including on load). `choices` is already visibility-filtered. |
| `resource_changed` | `key: String, old_value: float, new_value: float` | A resource changed during `process_choice`. `new_value` is the post-clamp stored value. |
| `flag_changed` | `key: String, value: bool` | A flag changed during `process_choice`. |
| `journey_started` | *(none)* | `start_new_journey` begins a run, before the first event. |
| `journey_ended` | `ending_event: JourneyEvent` | A terminal choice ended the run. |
| `journey_error` | `message: String` | A recoverable problem (null/empty inputs, empty pool, null route). Never crashes. |

```gdscript
func _ready() -> void:
    JourneyRuntime.event_changed.connect(_on_event_changed)
    JourneyRuntime.resource_changed.connect(_on_resource_changed)
    JourneyRuntime.flag_changed.connect(_on_flag_changed)
    JourneyRuntime.journey_started.connect(_on_journey_started)
    JourneyRuntime.journey_ended.connect(_on_journey_ended)
    JourneyRuntime.journey_error.connect(_on_journey_error)
```

## Authorable resource types

The data types you author (`JourneyConfig`, `JourneyEvent`, `JourneyChoice`,
`JourneyCondition`, `JourneyConditionGroup`, `JourneyConsequence`,
`JourneyResourceDef`) are pure data — fields only, no methods. Their complete
field and enum reference is on
[Resources & Events](../concepts/resources-and-events.md).

## Advanced / internal surface

These classes live in `journey_core/` and are driven by the runtime. Game code
normally never touches them — they're listed so you know what's internal and what
the few directly-useful entry points are.

| Class | Role | Direct use? |
| --- | --- | --- |
| `Blackboard` | Run-state container | Read via accessors only — never write directly. |
| `JourneySequenceManager` | Routing brain (start/process/enter/end) | **Internal.** Owned by the runtime. |
| `JourneyPoolIndex` | Pool scan + weighted selection | Useful in headless export-sanity checks (build + `find_by_id`). |
| `JourneySaveManager` | Serialize / write / read / migrate | **Internal.** Use `save_game`/`load_game`. |
| `JourneyValidator` | Authoring checks | `JourneyValidator.validate(config, pool)` returns typed `{severity, message}` dicts if you want richer output than the string list. |
| `JourneyEvaluator` | Pure condition evaluation (static) | **Internal.** `eval_condition` / `eval_group`. |
| `JourneyMutator` | Pure consequence application (static) | **Internal.** The single mutation primitive. |

!!! danger "Don't route around the runtime"
    `JourneyMutator` and `Blackboard` could technically let you change state
    outside `process_choice` — doing so bypasses change signals, boundary-route
    detection, and the save-safety guarantees. The
    [single mutation path](../concepts/blackboard.md#the-single-mutation-path) is
    not optional.

## Accuracy checklist

Every public method and signal above, with the source file and line it was
verified against. Spot-check any row against the code.

| Symbol | Source | Line |
| --- | --- | --- |
| `blackboard: Blackboard` | `journey_core/journey_runtime.gd` | 31 |
| `start_new_journey(config, seed=0)` | `journey_core/journey_runtime.gd` | 40 |
| `process_choice(choice)` | `journey_core/journey_runtime.gd` | 47 |
| `get_resource(key)` | `journey_core/journey_runtime.gd` | 58 |
| `has_flag(key)` | `journey_core/journey_runtime.gd` | 61 |
| `get_metadata(key)` | `journey_core/journey_runtime.gd` | 64 |
| `save_game(slot="savegame")` | `journey_core/journey_runtime.gd` | 73 |
| `load_game(slot="savegame")` | `journey_core/journey_runtime.gd` | 101 |
| `validate(config)` | `journey_core/journey_runtime.gd` | 157 |
| `rebuild_pool()` | `journey_core/journey_runtime.gd` | 172 |
| `signal event_changed(event, choices)` | `journey_core/journey_runtime.gd` | 20 |
| `signal resource_changed(key, old_value, new_value)` | `journey_core/journey_runtime.gd` | 21 |
| `signal flag_changed(key, value)` | `journey_core/journey_runtime.gd` | 22 |
| `signal journey_started()` | `journey_core/journey_runtime.gd` | 23 |
| `signal journey_ended(ending_event)` | `journey_core/journey_runtime.gd` | 24 |
| `signal journey_error(message)` | `journey_core/journey_runtime.gd` | 25 |
| `Blackboard` fields (resources/flags/metadata/rng) | `journey_core/blackboard.gd` | 11–25 |
| `JourneyCondition.Op` enum | `journey_core/journey_condition.gd` | 6 |
| `JourneyConsequence.Operation` enum | `journey_core/journey_consequence.gd` | 6 |
| `JourneyConditionGroup.Logic` enum | `journey_core/journey_condition_group.gd` | 7 |
| `JourneyValidator.validate(config, pool_index=null)` | `journey_core/validator.gd` | 29 |
| `JourneyPoolIndex.find_by_id(id_str)` | `journey_core/pool_index.gd` | 137 |

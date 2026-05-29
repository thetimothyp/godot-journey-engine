# API Reference

The public API is the **`JourneyRuntime`** Autoload. Everything game code needs —
lifecycle, state reads, persistence, validation — is on this one object. The
other `addons/journey_engine_core/` classes are internal machinery the runtime drives; they're
documented at the bottom as [advanced surface](#advanced-internal-surface).

All signatures below are verified against
`addons/journey_engine_core/journey_runtime.gd`; the [accuracy checklist](#accuracy-checklist)
at the end maps each entry to its source line.

## Constants

### `VERSION: String`

The engine version, [SemVer](https://semver.org)-formatted (currently `"0.2.0"`).
Read `JourneyRuntime.VERSION` to assert compatibility at runtime. It is
independent of [`JourneyConfig.save_version`](../guides/save-and-load.md#versioning-migration),
which tracks only the on-disk save format.

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
defaults, initial flags, primed metadata), seeds the RNG, builds the event index
from `config.events_dir`, emits `journey_started`, then resolves
`config.start_event_id` and enters that event (emitting `event_changed`).

| Param | Type | Notes |
| --- | --- | --- |
| `config` | `JourneyConfig` | The game config. A null config emits `journey_error`. |
| `seed` | `int` | RNG seed. Non-zero ⇒ deterministic; `0` (default) ⇒ randomized. |

Emits `journey_error("no start_event_id")` if it's empty, or `journey_error("start_event_id '…' did not resolve to an indexed event")` if no event under `events_dir` has that id.

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
of `[ERROR]`/`[WARNING]`-prefixed strings (empty = clean). Builds (or reuses) an
event index from `config.events_dir` so id resolution and per-event checks run.
Intended for `OS.is_debug_build()` use.

!!! warning "Pair it with a disk round-trip"
    `validate()` checks events held in memory. Before shipping, also run
    `JourneyLoadCheck.check("res://…/config.tres")` (`tests/journey_load_check.gd`)
    and require zero problems — it proves every event file loads from a fresh disk
    context and every routing id resolves. See
    [Validation → round-trip from disk](../guides/validation.md#validate-is-not-enough-on-its-own-round-trip-from-disk).

### `rebuild_index() -> void`

```gdscript
func rebuild_index() -> void
```

Rebuilds the event index from `config.events_dir`, re-reading from disk
(editor/Studio hot-reload hook). Safe to call before the first pool pull.

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

These classes live in `addons/journey_engine_core/` and are driven by the runtime. Game code
normally never touches them — they're listed so you know what's internal and what
the few directly-useful entry points are.

| Class | Role | Direct use? |
| --- | --- | --- |
| `Blackboard` | Run-state container | Read via accessors only — never write directly. |
| `JourneySequenceManager` | Routing brain (start/process/enter/end) | **Internal.** Owned by the runtime. |
| `JourneyEventIndex` | Event scan + id resolution + weighted pool selection | Useful in headless export-sanity checks (build + `find_by_id`). |
| `JourneySaveManager` | Serialize / write / read / migrate | **Internal.** Use `save_game`/`load_game`. |
| `JourneyValidator` | Authoring checks | `JourneyValidator.validate(config, event_index)` returns typed `{severity, message}` dicts if you want richer output than the string list. |
| `JourneyLoadCheck` | Disk round-trip "would this ship?" check | `JourneyLoadCheck.check(config_path)` — pair with `validate()` before shipping. |
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
| `VERSION` | `addons/journey_engine_core/journey_runtime.gd` | 23 |
| `blackboard: Blackboard` | `addons/journey_engine_core/journey_runtime.gd` | 37 |
| `start_new_journey(config, seed=0)` | `addons/journey_engine_core/journey_runtime.gd` | 46 |
| `process_choice(choice)` | `addons/journey_engine_core/journey_runtime.gd` | 53 |
| `get_resource(key)` | `addons/journey_engine_core/journey_runtime.gd` | 64 |
| `has_flag(key)` | `addons/journey_engine_core/journey_runtime.gd` | 67 |
| `get_metadata(key)` | `addons/journey_engine_core/journey_runtime.gd` | 70 |
| `save_game(slot="savegame")` | `addons/journey_engine_core/journey_runtime.gd` | 79 |
| `load_game(slot="savegame")` | `addons/journey_engine_core/journey_runtime.gd` | 107 |
| `validate(config)` | `addons/journey_engine_core/journey_runtime.gd` | 162 |
| `rebuild_index()` | `addons/journey_engine_core/journey_runtime.gd` | 182 |
| `signal event_changed(event, choices)` | `addons/journey_engine_core/journey_runtime.gd` | 26 |
| `signal resource_changed(key, old_value, new_value)` | `addons/journey_engine_core/journey_runtime.gd` | 27 |
| `signal flag_changed(key, value)` | `addons/journey_engine_core/journey_runtime.gd` | 28 |
| `signal journey_started()` | `addons/journey_engine_core/journey_runtime.gd` | 29 |
| `signal journey_ended(ending_event)` | `addons/journey_engine_core/journey_runtime.gd` | 30 |
| `signal journey_error(message)` | `addons/journey_engine_core/journey_runtime.gd` | 31 |
| `Blackboard` fields (resources/flags/metadata/rng) | `addons/journey_engine_core/blackboard.gd` | 11–25 |
| `JourneyCondition.Op` enum | `addons/journey_engine_core/journey_condition.gd` | 6 |
| `JourneyConsequence.Operation` enum | `addons/journey_engine_core/journey_consequence.gd` | 6 |
| `JourneyConditionGroup.Logic` enum | `addons/journey_engine_core/journey_condition_group.gd` | 7 |
| `JourneyValidator.validate(config, event_index=null)` | `addons/journey_engine_core/validator.gd` | 39 |
| `JourneyEventIndex.find_by_id(id_str)` | `addons/journey_engine_core/event_index.gd` | 189 |
| `JourneyLoadCheck.check(config_path)` | `tests/journey_load_check.gd` | 32 |

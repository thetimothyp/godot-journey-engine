**Author:** AI Collaborator
**Date:** May 27, 2026
**Status:** Design — for implementation
**Scope:** Core Engine only (MIT, free tier). Journey Graph Studio is **out of scope** but is a first-class consumer of everything here; design decisions that affect it are flagged **[Studio]**.
**Companion:** Journey Engine PRD, Revision 2.

---

## 1. Goals, Non-Goals, and Constraints

### 1.1 Goals

1. A pure-GDScript, Godot 4.x runtime that drives choice-and-consequence games from native `.tres` resources with zero external dependencies.
2. A central Blackboard holding all mutable playthrough state, with bounded numeric resources and boolean flags.
3. A typed condition/consequence evaluation engine built from `Resource` sub-objects (no string parsing, no stringly-typed dictionaries).
4. Deterministic and stochastic (tag-indexed, condition-filtered, weighted) event routing.
5. Signal-based, fully decoupled presentation ("Dumb-UI").
6. Save/load of flat primitive state, with opt-in obfuscation.

### 1.2 Non-Goals (v1)

- Journey Graph Studio (separate plugin, separate doc).
- The Starter UI Kit (separate optional package, separate doc). The *core* ships no presentation. The kit's two architectural constraints are recorded in §5.6 because they protect the engine's Presentation Contract, but the kit itself is not part of core scope.
- An economy/pricing layer, combat system, or any genre-specific mechanic. The engine supplies *state and routing*; games supply *rules*.
- Nested boolean condition trees (single-level `ALL`/`ANY` only).
- Computed/Blackboard-driven encounter weights (static weights only).
- Networking, multiplayer, or server-authoritative state.
- Localization framework (text is authored in resources; i18n is the game's concern, though §10.3 keeps the door open).

### 1.3 Hard Constraints

- **GDScript only.** No C#, no GDExtension. Must run on Web/WASM and mobile exports unmodified.
- **Godot 4.x** (target 4.3+ for stable typed `Array[T]` export behavior).
- **Determinism on demand.** Given a fixed RNG seed and identical Blackboard state, stochastic selection must be reproducible (required for save/load integrity and testing).
- **[Studio] Editor-authorable.** Every resource must be fully constructable and editable in the Godot inspector with no code, because Studio will later generate exactly these resources. If the inspector can't express it, Studio can't either.

---

## 2. System Overview

```
                         ┌─────────────────────────────┐
                         │     JourneyRuntime (Autoload)│
                         │  ┌───────────────────────┐  │
   .tres resources ─────►│  │ Blackboard            │  │
   (loaded on demand)    │  │  resources / flags    │  │
                         │  │  metadata / rng       │  │
                         │  └───────────────────────┘  │
                         │  ┌───────────────────────┐  │
                         │  │ Evaluator             │  │ ◄── JourneyCondition(Group)
                         │  │ Mutator               │  │ ◄── JourneyConsequence
                         │  │ SequenceManager       │  │ ◄── JourneyEvent / Choice
                         │  │ PoolIndex             │  │
                         │  │ SaveManager           │  │
                         │  └───────────────────────┘  │
                         └──────────────┬──────────────┘
                                        │ signals
                                        ▼
                         ┌─────────────────────────────┐
                         │  Developer's UI (Dumb-UI)    │
                         └─────────────────────────────┘
```

`JourneyRuntime` is the only Autoload and the only public entry point for game code. Internal collaborators (Evaluator, Mutator, SequenceManager, PoolIndex, SaveManager) are plain `RefCounted` helpers owned by the runtime. This keeps the public API a single, discoverable surface while letting the implementation stay modular and unit-testable.

**Design rationale for the helper split:** an earlier option was to put everything as methods directly on the Autoload. Rejected because (a) a 1500-line singleton is untestable in isolation, and (b) the Evaluator/Mutator are pure functions of `(resource, blackboard)` — keeping them as injectable helpers lets us unit-test them headlessly without instantiating the Autoload or a SceneTree.

---

## 3. Resource Layer (Data Model)

All gameplay data are `Resource` subclasses with `class_name` declarations so they appear in the inspector's "New Resource" dialog and in typed exports. Every class is designed to round-trip losslessly through `.tres` and through the save serializer.

### 3.1 Class hierarchy

```
Resource
├── JourneyConfig            # one per game; global rules + system settings
├── JourneyResourceDef       # schema for ONE numeric resource (bounds, defaults)
├── JourneyEvent             # a node: presentation + tags + pool eligibility + choices
├── JourneyChoice            # a button: visibility + consequences + routing
├── JourneyCondition         # one comparison
├── JourneyConditionGroup    # ALL/ANY over conditions
└── JourneyConsequence       # one mutation
```

### 3.2 `JourneyCondition`

```
extends Resource
class_name JourneyCondition

enum Op { GT, GTE, LT, LTE, EQ, NEQ, HAS_FLAG, NOT_FLAG }

@export var key: String = ""        # resource key OR flag key
@export var op: Op = Op.GTE
@export var value: float = 0.0      # ignored for HAS_FLAG / NOT_FLAG
```

Semantics: numeric ops read `blackboard.resources[key]`; `HAS_FLAG`/`NOT_FLAG` read `blackboard.flags[key]`. Missing-key handling is defined in §4.3 (this is a real correctness trap and is specified, not left to chance).

### 3.3 `JourneyConditionGroup`

```
extends Resource
class_name JourneyConditionGroup

enum Logic { ALL, ANY }

@export var logic: Logic = Logic.ALL
@export var conditions: Array[JourneyCondition] = []
```

- Empty group ⇒ **passes** (vacuous truth). This is intentional: an event/choice with no conditions is always eligible. Documented because the opposite default ("empty = never") is a plausible and dangerous misreading.
- `ALL` over empty = true; `ANY` over empty = true as well (we treat "no constraints" identically regardless of logic flag, to avoid an authoring footgun where flipping the dropdown on an empty group silently disables content).

**[Studio]** No nesting in v1. The model could later add an optional `Array[JourneyConditionGroup] subgroups` field; existing `.tres` files would deserialize with an empty subgroups array and behave identically. This forward-compatibility is why grouping is its own resource rather than two loose fields on the choice.

### 3.4 `JourneyConsequence`

```
extends Resource
class_name JourneyConsequence

enum Operation { ADD, SUBTRACT, SET_VALUE, SET_FLAG, TOGGLE_FLAG }

@export var operation: Operation = Operation.ADD
@export var key: String = ""
@export var value: float = 0.0      # numeric ops only
@export var flag_value: bool = true # SET_FLAG only
```

`ADD`/`SUBTRACT`/`SET_VALUE` mutate `resources[key]` and are clamped to the resource's configured bounds (§4.4). `SET_FLAG` sets `flags[key] = flag_value`; `TOGGLE_FLAG` inverts it.

### 3.5 `JourneyChoice`

```
extends Resource
class_name JourneyChoice

@export_multiline var button_text: String = ""
@export var visibility: JourneyConditionGroup       # null ⇒ always visible
@export var consequences: Array[JourneyConsequence] = []

@export_group("Routing")
@export var target_event: JourneyEvent              # deterministic route (takes precedence)
@export var continue_to_pool: bool = false          # if true and no target, request stochastic pull
@export var pool_tags_filter: Array[String] = []    # optional tag scope for the pull
```

Routing precedence is explicit and total (§5.2): a non-null `target_event` always wins; otherwise `continue_to_pool` triggers a stochastic pull; otherwise the journey is treated as ended (a terminal choice). Defining this precedence in the data model — rather than by convention — prevents ambiguous nodes.

### 3.6 `JourneyEvent`

```
extends Resource
class_name JourneyEvent

@export_group("Presentation")
@export_multiline var narrative_text: String = ""
@export var background_texture: Texture2D
@export var ambient_audio: AudioStream

@export_group("System")
@export var id: StringName = &""        # stable identity; see §3.8
@export var event_tags: Array[String] = []
@export var weight: int = 100           # static selection weight (PRD §3.4)
@export var pool_conditions: JourneyConditionGroup  # eligibility for stochastic pool
@export var repeatable: bool = false    # may this event recur in one playthrough?
@export var choices: Array[JourneyChoice] = []
```

Note `weight` replaces the PRD's `absolute_priority` naming — same concept, clearer intent, and avoids implying a sort order. Default 100 gives authors integer headroom to make events relatively rarer/commoner without decimals.

### 3.7 `JourneyResourceDef` and `JourneyConfig`

```
extends Resource
class_name JourneyResourceDef

@export var key: String = ""
@export var default_value: float = 0.0
@export var min_value: float = 0.0
@export var max_value: float = 100.0
@export var bottom_out_event: JourneyEvent          # fired when value hits min_value
@export var top_out_event: JourneyEvent             # optional; fired at max_value
```

```
extends Resource
class_name JourneyConfig

@export var resource_defs: Array[JourneyResourceDef] = []
@export var initial_flags: Dictionary = {}          # String -> bool
@export var start_event: JourneyEvent

@export_group("Pool")
@export var event_pool_dir: String = "res://events/"
@export var rebuild_pool_in_editor: bool = true     # [Studio] hot-reload hook

@export_group("Save")
@export var save_encryption_key: String = ""        # empty ⇒ plaintext
@export var save_version: int = 1                   # migration anchor (§7.4)
```

**[Studio]** `JourneyConfig` deliberately concentrates all global authored settings in one resource. Studio will read it to populate dropdowns (e.g., offering known resource keys when authoring a condition) and write back to it. Keeping it a single resource keeps that integration simple. (The PRD flagged that this resource does two jobs; we accept that for v1 and note §10.1 as the split path if it grows.)

### 3.8 Identity and references

Two referencing strategies coexist deliberately:

- **Direct object references** (`target_event: JourneyEvent`, `bottom_out_event`) — used for authored, deterministic links. Godot stores these as sub-resource or `ext_resource` paths in `.tres`, and the editor makes them drag-and-droppable. This is the ergonomic default.
- **Stable string `id`** — used for save/load and for pool membership. At runtime we never serialize a live event into a save; we serialize its `id`. This decouples saves from file paths so that moving or renaming a `.tres` doesn't corrupt existing saves, as long as `id` is preserved.

**Invariant:** every `JourneyEvent` in the pool directory must have a unique non-empty `id`. The PoolIndex validates this at load and pushes an error naming the duplicates. **[Studio]** Studio will auto-assign ids on node creation; manual authors get a validation pass (§8.1) they can run.

---

## 4. Blackboard

### 4.1 Shape

```
class Blackboard:
    var resources: Dictionary = {}     # String -> float
    var flags: Dictionary = {}         # String -> bool
    var metadata: Dictionary = {}      # String -> Variant (turn_counter, current_event_id, history…)
    var rng := RandomNumberGenerator.new()
```

Implemented as an inner class / `RefCounted` rather than free-floating dictionaries on the Autoload, so the whole state object can be passed to the Evaluator/Mutator and snapshotted for save in one move.

### 4.2 Initialization

On `start_new_journey()`:

1. For each `JourneyResourceDef`, set `resources[key] = clamp(default_value, min, max)`.
2. Copy `config.initial_flags` into `flags`.
3. Seed `rng` — either from a provided seed (deterministic/testing) or `randomize()` (normal play). The seed is stored in `metadata` so it persists into saves.
4. Set `metadata.turn_counter = 0`, clear history.
5. Route to `config.start_event` via the SequenceManager.

### 4.3 Missing-key policy (correctness-critical)

This is the most common source of silent narrative bugs, so it is specified rather than emergent:

- **Condition read on a missing resource key:** treated as `0.0`, AND a runtime warning is pushed (`push_warning`) naming the key and the owning event id. Rationale: failing soft keeps a game playable, but the warning surfaces author typos. We do *not* fail hard, because a hard crash on a typo in one of thousands of events is a worse player experience than a soft-false branch.
- **Condition read on a missing flag key:** absent flag = `false`. `HAS_FLAG` ⇒ false, `NOT_FLAG` ⇒ true. No warning (absence of a flag is a normal, expected state — flags are set lazily).
- **Consequence on a missing resource key:** if the key matches a `JourneyResourceDef`, the resource was initialized, so this can't happen post-init. If it matches no def, the mutation is **skipped** with a warning. We never auto-create undeclared resources, because an undeclared resource has no bounds and would silently escape clamping.

### 4.4 Clamping and bottom/top-out

After any numeric consequence:

1. Look up the resource's `JourneyResourceDef`.
2. `resources[key] = clamp(new_value, def.min_value, def.max_value)`.
3. If clamped result `== min_value` and `def.bottom_out_event` is set, enqueue a **pending forced route** to that event.
4. Symmetric handling for `max_value` / `top_out_event`.

Forced routes are *enqueued*, not executed mid-consequence, so that a choice applying several consequences finishes its whole batch before any bottom-out fires. The SequenceManager drains at most one pending forced route after consequence application, preferring the *first* triggered (lowest resource def index) for determinism. This ordering rule is explicit because "sanity and rations both hit zero on the same choice" is a real case and must resolve identically every run.

---

## 5. Sequence Manager (Routing)

### 5.1 Public flow

```
start_new_journey()
  └─► _enter_event(start_event)

process_choice(choice)
  ├─ apply consequences (Mutator)  ──► may enqueue forced route (§4.4)
  ├─ if forced route pending: _enter_event(forced)        [highest priority]
  ├─ elif choice.target_event:     _enter_event(target)   [deterministic]
  ├─ elif choice.continue_to_pool: _enter_event(pool_pull(choice.pool_tags_filter))
  └─ else:                         _end_journey()          [terminal choice]
```

### 5.2 `_enter_event(event)`

1. Guard against null (a route resolved to nothing ⇒ emit `journey_error`, do not crash).
2. Update `metadata.current_event_id`, increment `turn_counter`, append to history (capped ring buffer; §10.2).
3. Mark event seen (for non-`repeatable` pool exclusion).
4. Compute the **visible choice list**: for each choice, evaluate `choice.visibility` against the Blackboard; include only those that pass.
5. Emit `event_changed(event, visible_choices)`.

The visible-choice computation lives here (not in the UI) so every front-end gets identical filtering for free — central to the Dumb-UI contract.

### 5.3 Signals (the public reactive surface)

```
signal event_changed(event: JourneyEvent, choices: Array[JourneyChoice])
signal resource_changed(key: String, old_value: float, new_value: float)
signal flag_changed(key: String, value: bool)
signal journey_started()
signal journey_ended(ending_event: JourneyEvent)   # the terminal event, for ending screens
signal journey_error(message: String)               # soft failures, for dev tooling/telemetry
```

`resource_changed`/`flag_changed` fire per mutation so HUD elements can animate individual deltas without diffing whole dictionaries. They fire *after* clamping, reporting the actual stored value.

### 5.4 Why routing precedence is data, not policy

A choice could in principle specify both a `target_event` and `continue_to_pool`. Rather than forbid it (which the inspector can't enforce), we define a total precedence order (forced > target > pool > end). Authors get predictable behavior; **[Studio]** Studio can render the effective route by applying the same precedence, and can warn on contradictory combinations without needing to block them.

### 5.5 Presentation Contract (the engine/UI boundary)

The engine is **presentation-agnostic**: it computes *what is true now* and broadcasts it via signals carrying inert data; it never instantiates a Node, never touches the SceneTree, and never assumes a UI exists. The same logic runs identically behind a polished animated front end, a command-line harness (§8.2), or no presentation at all. This section formalizes the boundary so front-end authors — and the Starter UI Kit (§5.6) — build against a contract, not against implementation detail.

**The division of responsibility:**

- **Engine owns *what*:** the active event, its asset *references* (`background_texture`, `ambient_audio`), the filtered list of currently-visible choices, and all resource/flag values. It transports asset references as inert handles — it hands you "this event wants this texture," never "display it this way."
- **Presentation owns *how* and *when*:** all visuals, animation, transitions, cutscenes, sprite work, text reveal, audio playback, and — critically — **all timing and sequencing**. None of this is state the engine tracks.

**The timing caveat (the one real sharp edge).** The engine is synchronous and fire-and-forget. `process_choice()` applies consequences and emits `event_changed` immediately; it does **not** wait for your transitions, cutscenes, or animations to finish. The engine has no timeline, no animation queue, and no `await`-this-animation facility — by deliberate non-goal, to keep the core tiny and genre-neutral. Consequences of this, which every front end must honor:

1. **Input gating is the front end's job.** Don't call `process_choice()` again until your own presentation is ready. Gate it behind an "is presenting" flag in your UI; the engine will not gate it for you.
2. **"Animate, then advance" lives in your layer.** If you want a consequence animation to play before the next event appears, run the animation in your `event_changed`/`resource_changed` handler and defer the *next* `process_choice()` until it completes. The engine has already moved on internally; your UI controls the visible pace.
3. **Signals report post-clamp truth.** `resource_changed` fires after clamping with the actual stored value, so HUD animations animate to real values, never to a value the engine will immediately correct.

This is the only place where "the engine handles it" would be an overpromise. The engine gives you the state-change events to hang behavior off; orchestrating that behavior in time is yours. Stated plainly so no front end assumes a sequencing facility that does not exist.

### 5.6 Starter UI Kit — architectural requirements (core-adjacent)

The Starter UI Kit is a separate, optional, free package (full design in its own doc), but two of its properties are *architectural constraints* that belong here because they protect the Presentation Contract and must not be violated by the kit or by anything that grows from it.

**Constraint 1 — Widgets subscribe to the engine, never to each other.** The kit is not "a UI"; it is a set of independent widgets (dialogue panel, choice list, resource HUD, background/audio, ending screen), each of which subscribes to `JourneyRuntime` signals on its own and owns one slice of the screen. **No kit component may `preload`, reference, or call another kit component.** Swappability is then a property that cannot break: deleting the HUD cannot affect the dialogue panel because they were never connected — they are two independent listeners on the same signal bus. This is the §5.5 Dumb-UI contract applied *recursively within* the kit.

**Constraint 2 — One widget = one scene = one script, wired only at a thin root.** A `JourneyView` root scene instances the widgets side by side and wires *nothing* between them. It is the explicit "delete me and write your own" seam. Replacing a widget means swapping one scene out of `JourneyView` and deleting nothing else; gutting the kit means emptying `JourneyView`.

These constraints are enforceable mechanically (a dependency check: no kit script may reference another kit script — §8.1 of the kit doc). They are recorded here because if a future contributor "just quickly" lets the HUD read the dialogue widget's state, the kit silently stops being swappable, and the engine's central DX promise erodes. The constraint is the feature.

---

## 6. Stochastic Pool

### 6.1 Index build

`PoolIndex` scans `config.event_pool_dir` once:

```
for each .tres under dir (recursive):
    load as JourneyEvent (skip non-events)
    assert unique non-empty id  → else push_error, skip
    for tag in event.event_tags:
        by_tag[tag].append(event)
    all_events.append(event)
```

Built lazily on first pull (or eagerly at `start_new_journey` — configurable). In editor with `rebuild_pool_in_editor`, the index exposes a `rebuild()` that game-side dev tools or **[Studio]** can call after writing new resources.

**Web/WASM note:** `DirAccess` enumeration of `res://` works in exported builds because resources are baked into the PCK; we rely on `ResourceLoader` paths, not OS filesystem calls, so this is export-safe. Verified as an explicit test target (§8.2) because directory scanning is a classic source of "works in editor, breaks in export" bugs.

### 6.2 Candidate selection (one pull)

```
1. scope = union of by_tag[t] for t in requested_tags   (or all_events if none requested)
2. candidates = [e in scope where
       (e.repeatable or e.id not in seen) and
       evaluate(e.pool_conditions, blackboard) ]
3. if candidates empty:  emit journey_error("empty pool for tags …"); return null
4. weighted pick over candidates using e.weight and blackboard.rng
```

### 6.3 Weighted pick (deterministic)

Standard cumulative-weight roll using `blackboard.rng.randi_range`/`randf`. Because the RNG is part of saved state and seeded explicitly, a reloaded save that makes the same choices reproduces the same pulls. Weights are static ints (PRD §3.4 / §6 deferral). The selection function is isolated and pure (`(candidates, rng) -> event`) for unit testing with a fixed seed.

### 6.4 Empty-pool handling

An empty candidate set is an authoring error, not a player-facing crash. We emit `journey_error` and return null; `_enter_event(null)` then surfaces the error. Optionally, `JourneyConfig` may later define a `fallback_event` for graceful degradation (noted, not in v1).

---

## 7. Save / Load

### 7.1 What gets serialized

Only the Blackboard, reduced to primitives:

```
{
  "save_version": int,
  "rng_state": int,                  # rng.state, to resume the exact stream
  "rng_seed": int,
  "resources": { String: float },
  "flags": { String: bool },
  "metadata": {                      # primitives only
      "current_event_id": String,
      "turn_counter": int,
      "seen_ids": [String],
      "history": [String],
  }
}
```

No `JourneyEvent`/`Resource` objects are ever written. `current_event_id` is the event's stable `id` (§3.8); on load we resolve it back through the PoolIndex / a direct lookup. This is why `id` exists.

### 7.2 Write path

`store_var(dict)` to `user://<slot>.dat`, plaintext or `open_encrypted_with_pass` per `config.save_encryption_key` (PRD §5). `store_var` with `full_objects=false` (default) guarantees we *cannot* accidentally embed an object — a deliberate safety: if a non-primitive sneaks into the dict, the write fails loudly rather than baking a brittle object reference into saves.

### 7.3 Load path

1. Open (encrypted iff key set), `get_var`.
2. Check `save_version`; run migrations if older (§7.4).
3. Restore resources/flags/metadata.
4. Restore `rng.state`.
5. Resolve `current_event_id` → event; re-enter it (re-emits `event_changed` so UI rebuilds). Loading is just "restore Blackboard, then re-enter current event" — the same code path as normal routing, so no special UI restore logic is needed.

### 7.4 Versioning and migration

`save_version` is stamped on every save. On load, a `_migrate(dict, from_version)` ladder upgrades old saves step-by-step to current. v1 ships the scaffold (identity migration) even though there's nothing to migrate yet, so that the *first* breaking change has a place to live and shipped games don't strand player saves. This is cheap now and expensive to retrofit, hence included in v1.

---

## 8. Validation, Errors, and Testing

### 8.1 Authoring validation (`validate()` utility)

A dev-only function games can call in `_ready` under `OS.is_debug_build()`:

- Duplicate or empty event `id`s.
- Choices whose `target_event` is null AND `continue_to_pool` false AND no consequences → likely a dead/unfinished node (warn).
- Conditions/consequences referencing resource keys with no `JourneyResourceDef` (warn — catches typos).
- Resource defs with `min > max` or `default` outside bounds (error).
- `start_event` null (error).

**[Studio]** This same validator is what Studio will run on save; defining it in the core means Studio reuses it rather than reimplementing rules, keeping the two in lockstep.

### 8.2 Test strategy

Pure helpers (Evaluator, Mutator, weighted-pick, migration ladder) are unit-tested headlessly with constructed Blackboards and resources — no SceneTree, no Autoload. Targets:

- Every condition operator incl. missing-key policy (§4.3).
- Clamping + bottom/top-out enqueue ordering with simultaneous triggers (§4.4).
- Routing precedence matrix (forced/target/pool/end) (§5.1).
- Deterministic pull reproducibility under fixed seed; empty-pool error.
- Save→load round-trip equality, incl. rng-stream continuity (make N pulls, save, reload, make N more, compare against a no-save control run).
- **Export smoke test:** pool index build under a Web/WASM export (§6.1), run in CI if feasible, else a documented manual checklist.

Recommended harness: GUT (Godot Unit Test) — pure GDScript, CI-friendly. Kept as a dev dependency, not shipped in the MIT package.

---

## 9. Public API Summary (game-facing)

```
# Lifecycle
JourneyRuntime.start_new_journey(config: JourneyConfig, seed := 0) -> void
JourneyRuntime.process_choice(choice: JourneyChoice) -> void

# State access (read-only helpers; mutation only via consequences)
JourneyRuntime.get_resource(key: String) -> float
JourneyRuntime.has_flag(key: String) -> bool
JourneyRuntime.get_metadata(key: String) -> Variant

# Persistence
JourneyRuntime.save_game(slot := "savegame") -> Error
JourneyRuntime.load_game(slot := "savegame") -> Error

# Dev
JourneyRuntime.validate(config: JourneyConfig) -> Array[String]   # messages; empty = clean
JourneyRuntime.rebuild_pool() -> void                              # [Studio]/editor

# Signals: event_changed, resource_changed, flag_changed,
#          journey_started, journey_ended, journey_error
```

Game code never writes the Blackboard directly. All mutation flows through consequences applied by `process_choice`, so every state change passes clamping, bottom-out checks, and signal emission uniformly. This is the single most important API invariant: **there is exactly one mutation path.**

---

## 10. Open Questions & Future Hooks

1. **Config split (§3.7):** if `JourneyConfig` accretes more subsystems, split save settings into `JourneySaveConfig`. Forward-compatible via an optional `@export var save_config` that falls back to inline fields.
2. **History buffer size:** unbounded history bloats saves over long playthroughs. v1 caps `history` at a configurable ring buffer (default 200) and stores `turn_counter` separately for true length. Confirm the cap doesn't break any intended "review my whole journey" feature; if it does, history becomes opt-in unbounded.
3. **Localization:** narrative text is authored inline on events. If i18n is needed, the forward-compatible path is to treat `narrative_text` as a key into Godot's translation system rather than literal text — no schema change required, only an author convention plus a `tr()` call in the (developer's) UI. Documented so we don't paint ourselves out of it.
4. **[Studio] Computed weights / nested conditions:** both were deferred (PRD §6, §3.3). The resource model leaves room for both as additive fields; revisit only when a shipping game demands them, and weigh the Studio-UI cost first.
5. **Concurrent forced routes:** current rule fires one bottom-out per choice batch (lowest def index). If games need *all* triggered endings to compose (rare), this becomes a documented limitation rather than a silent one.

---

## 11. Build Order (implementation sequence)

1. Resource classes: `JourneyCondition` → `JourneyConsequence` → `JourneyConditionGroup` → `JourneyChoice` → `JourneyEvent` → `JourneyResourceDef` → `JourneyConfig`.
2. `Blackboard` + initialization.
3. `Evaluator` (conditions) and `Mutator` (consequences) as pure helpers + their unit tests.
4. `SequenceManager` deterministic routing + `_enter_event` + signals; minimal test scene proving the loop end-to-end.
5. `PoolIndex` + stochastic pull + weighted pick + tests.
6. `SaveManager` + versioning + round-trip tests.
7. `validate()` utility.
8. Export smoke test (Web/WASM) and a small sample game exercising every feature.

Each step is independently testable and leaves the engine in a runnable state, so the sample game can grow alongside the engine rather than waiting for the end.
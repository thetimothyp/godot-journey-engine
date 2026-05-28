# Project Name: Journey Engine

!!! note "Product requirements doc — for the *why*, not the API"
    This PRD captures product intent and rationale. For accurate, current API and
    behavior details, prefer the [API Reference](../api.md) and
    [Concepts](../../concepts/overview.md) — they're verified against the shipped
    code in `journey_core/`. Where this document and the code disagree, the code
    wins; see the divergence notes on the
    [Engineering Design](engineering-design.md) page.

**Author:** AI Collaborator
**Date:** May 27, 2026
**Status:** Baseline Document — Revision 2
**Revision note:** This version incorporates decisions from architecture review. Substantive changes are summarized in §0 and marked **[NEW in R2]** inline.

---

## 0. Revision 2 Changelog

This revision resolves three previously-underspecified areas and adds two foundational features, based on a validation pass against a representative target game (a rogue-lite merchant RPG).

1. **Condition/Consequence data shape — RESOLVED.** Conditions and consequences are now first-class `Resource` subclasses (`JourneyCondition`, `JourneyConsequence`), not dictionaries or parsed strings. This is what makes the visual editor authorable and keeps evaluation type-safe. (§3.3)
2. **Condition grouping — ADDED to v1.** A minimal `JourneyConditionGroup` resource introduces `ALL`/`ANY` logic so authors can express "available if rich OR well-liked" without duplicating choices. Deep recursive boolean trees remain out of scope for v1. (§3.3)
3. **Pool filtering performance — RESOLVED.** The stochastic manager pre-indexes the event pool by tag at load into an in-memory dictionary, rather than re-scanning the folder on every roll. (§3.4)
4. **Choice/encounter weights — kept STATIC for v1 (deliberately deferred).** State-reactive encounter frequency is achieved through pool *eligibility conditions*, not computed weight formulas. Continuous weight-by-Blackboard-value is explicitly a post-v1 feature, implementable as project-side code where a specific game needs it. (§3.4, §6)
5. **Save encryption — RESOLVED and reframed.** Encryption is opt-in, off by default, keyed from `JourneyConfig`, and documented as anti-tamper obfuscation rather than security. State serializes to pure primitives. (§5)

---

## 1. Executive Summary & Core Concept

### 1.1 Product Vision

Journey Engine is a data-driven, state-reactive game framework developed natively for **Godot 4.x** using **GDScript**. It is optimized for choice-and-consequence text RPGs, survival simulators, and narrative resource-management games where player decisions dramatically warp the world state.

By abandoning external runtimes (like C# or native DLLs), Journey Engine integrates directly into the standard Godot ecosystem. It leverages Godot's native Custom Resource (`.tres`) architecture, enabling zero-configuration deployment, lightweight memory footprints, and instant platform compatibility (including Web/WASM and mobile) right out of the box.

```
┌──────────────────────────────────────────────────────────┐
│                    GODOT 4.x ENGINE                        │
│                                                            │
│  ┌─────────────────────────┐  ┌───────────────────────┐   │
│  │   Journey Graph Studio  │  │ Journey Core Runtime  │   │
│  │ (Premium Visual Plugin) │  │  (Autoload Singleton) │   │
│  └────────────┬────────────┘  └───────────┬───────────┘   │
└───────────────┼───────────────────────────┼───────────────┘
                │ (Compiles UI Nodes to)     │ (Reads / Mutates)
                ▼                            ▼
        ┌───────────────────────────────────────────┐
        │        Native Godot Resources (.tres)     │
        │    (Highly-Optimized Gameplay Objects)    │
        └───────────────────────────────────────────┘
```

### 1.2 Target Audience & Monetization Model

The target audience consists of Indie Game Developers, Narrative Designers, and Solo Creators who love the simplicity of GDScript and want to build mechanically deep, travel-focused or event-driven survival games without writing custom database, save, or condition-tracking engines from scratch.

- **The Core Engine (Free / Open Source — MIT):** Contains the runtime singleton, structural base classes (`JourneyEvent`, `JourneyChoice`, `JourneyCondition`, `JourneyConsequence`, `JourneyConditionGroup`), and state evaluation code. Developers can build full games manually using Godot's built-in inspector.
- **Journey Graph Studio (Premium Plugin — $45 One-Time Purchase):** A custom visual workspace built using Godot's native `GraphEdit` control nodes. It sits inside the editor and lets creators visually map events, connections, choices, and resource impacts, auto-compiling the graph directly into native Godot resource files.

---

## 2. Architectural Blueprint

The Journey Engine divides its structural components cleanly to maintain a modular workflow:

```
┌──────────────────────────────────────────────────────────┐
│                      1. DATA LAYER                         │
│  • JourneyConfig.tres (Defines custom game resources)      │
│  • JourneyEvent.tres (Visual text, choices, asset links)   │
│  • JourneyChoice / Condition / Consequence sub-resources   │
└───────────────────────────┬────────────────────────────────┘
                            ▼
┌──────────────────────────────────────────────────────────┐
│                   2. LOGIC LAYER (CORE)                    │
│  • JourneyRuntime.gd (Autoload Singleton / Blackboard)     │
│  • Condition & Consequence Evaluator (GDScript Match)      │
│  • Tag-Indexed Stochastic Pool Manager                     │
└───────────────────────────┬────────────────────────────────┘
                            ▼ (Emits Signal / Native Object)
┌──────────────────────────────────────────────────────────┐
│                 3. PRESENTATION LAYER                      │
│  • Developer's Custom Game UI Scenes                       │
│  • Dynamic Button Spawner & Property Data Bindings         │
└──────────────────────────────────────────────────────────┘
```

---

## 3. Core Engine Functional Specifications

### 3.1 The Global Blackboard (`JourneyRuntime.gd`)

The engine runs as a global Autoload Singleton in Godot. It maintains the in-memory state of the current playthrough:

- **Resources Dictionary:** Stores key-value pairings of numeric values. Each resource respects strict boundaries configured via a data schema (e.g., `gold`, `rations`, `sanity`). Global indices such as a Chaos/Stability tracker are stored here as ordinary numeric resources — no special-casing required.
- **Flags Dictionary:** Stores boolean variables tracking player milestones and narrative history (e.g., `saved_thirsty_man = true`).
- **Runtime Metadata:** Tracks operational variables like `current_event`, `turn_counter`, and engine history logs.

### 3.2 Native Resource Architecture

Rather than storing structural story nodes in raw JSON, data is written into native Godot objects inheriting from `Resource`. This allows Godot to automatically handle disk caching, thread-safe asynchronous loading, and direct variable linking in the inspector.

### Core Custom Resources:

1. **`JourneyConfig`**: Defines global rules for resources, their limits (`min_value`, `max_value`), and what event triggers if a resource bottoms out (e.g., if `sanity == 0`, immediately launch the `evt_madness_breakdown` resource). Also holds save-system settings (§5).
2. **`JourneyChoice`**: Houses a visibility requirement (a `JourneyConditionGroup`), a list of `JourneyConsequence` mutations, and the targeted route destination.
3. **`JourneyEvent`**: Bundles textual presentation content, user interface layout keys (textures, audio streams), pool eligibility conditions, environmental/biome tags, and a collection of `JourneyChoice` resources.
4. **`JourneyCondition`** **[NEW in R2]**: A single typed comparison — a key, an operator, and a value.
5. **`JourneyConsequence`** **[NEW in R2]**: A single typed mutation — an operation, a target key, and a value.
6. **`JourneyConditionGroup`** **[NEW in R2]**: An ordered list of `JourneyCondition`s plus an `ALL`/`ANY` logic flag.

```
extends Resource
class_name JourneyEvent

@export_group("Presentation")
@export_multiline var narrative_text: String
@export var background_texture: Texture2D
@export var ambient_audio: AudioStream

@export_group("System Architecture")
@export var event_tags: Array[String]
@export var absolute_priority: int = 0           # static selection weight (see §3.4)
@export var pool_conditions: JourneyConditionGroup  # eligibility for stochastic pool
@export var choices: Array[JourneyChoice]
```

### 3.3 Rule & Mutation Evaluation Engine

**[REVISED in R2]** Conditions and consequences are structured sub-resources rather than dictionaries or string expressions. This preserves inspector editing, type safety, and — critically — gives Journey Graph Studio concrete objects to author. The evaluator resolves each via a GDScript `match` on the operator enum.

```
extends Resource
class_name JourneyCondition

enum Op { GT, GTE, LT, LTE, EQ, NEQ, HAS_FLAG, NOT_FLAG }

@export var key: String            # "gold" or "saved_thirsty_man"
@export var op: Op = Op.GTE
@export var value: float = 0.0     # ignored for flag operators
```

```
extends Resource
class_name JourneyConditionGroup

enum Logic { ALL, ANY }            # ALL = AND, ANY = OR

@export var logic: Logic = Logic.ALL
@export var conditions: Array[JourneyCondition]
```

- **Condition Operators:** `GT` (>), `GTE` (>=), `LT` (<), `LTE` (<=), `EQ` (==), `NEQ` (!=), `HAS_FLAG`, `NOT_FLAG`.
- **Consequence Operations:** `ADD`, `SUBTRACT`, `SET_VALUE`, `SET_FLAG`, `TOGGLE_FLAG`. Consequences mutate Blackboard state on button selection and respect the `min_value`/`max_value` bounds from `JourneyConfig`.
- **Grouping (v1 scope):** A choice's visibility is governed by a single `JourneyConditionGroup` (`ALL`of conditions, or `ANY`of conditions). This covers the overwhelming majority of authoring needs — "rich AND brave" or "rich OR well-liked." **Out of v1 scope:** arbitrarily nested boolean trees (groups within groups). The resource model can extend to nesting later without breaking existing content, but it is deliberately excluded to keep the visual editor comprehensible.

### 3.4 Dynamic Sequence Manager

Controls the pacing and routing of event delivery, transitioning seamlessly between two processing modes:

1. **Deterministic Processing:** When a player's choice links directly to a specific target `JourneyEvent`, the engine loads and serves that resource instantly.
2. **Stochastic Processing (Pool-Based):** When an event returns a generic route continuation signal, the manager selects from a pool of candidate events.

**[REVISED in R2] Pool indexing.** On startup (or first pool access), the manager scans the event folder **once**, loads each `JourneyEvent`, and builds an in-memory `Dictionary` mapping `tag → Array[JourneyEvent]`. A stochastic pull then: (a) gathers candidates from the relevant tag bucket(s), (b) filters that narrowed set by each event's `pool_conditions` against the current Blackboard, and (c) runs a weighted probability roll over survivors. The folder is never re-scanned per roll. An editor-only "rebuild index" hook supports content hot-reload during development.

**[CLARIFIED in R2] Weighting is static in v1.** The roll uses each event's static `absolute_priority` as its weight. State-reactive encounter frequency — e.g. "more monster attacks when chaos is high" — is expressed through **eligibility**: gate dangerous events behind a `pool_conditions` group such as `chaos GTE 60`, so they only enter the candidate set when the world warrants it. Continuous weight scaling (weight = f(Blackboard value)) is **not** a v1 engine feature; see §6 for the rationale and the recommended project-side approach.

---

## 4. Godot Integration & UI Workflow

### 4.1 The Dumb-UI Pattern Integration

The engine uses standard Godot **Signals** to broadcast changes. The presentation layer remains entirely decoupled — it listens for updates and refreshes its nodes passively:

```
# Inside the Developer's Main Game View Scene Script

func _ready():
    JourneyRuntime.event_changed.connect(_on_journey_event_changed)
    JourneyRuntime.start_new_journey()

func _on_journey_event_changed(current_event: JourneyEvent, options: Array[JourneyChoice]):
    $NarrativeLabel.text = current_event.narrative_text
    $BackgroundView.texture = current_event.background_texture

    # Rebuild custom buttons cleanly
    _clear_choice_container()
    for option in options:
        var btn = ChoiceButtonScene.instantiate()
        btn.text = option.button_text
        btn.pressed.connect(func(): JourneyRuntime.process_choice(option))
        $ButtonContainer.add_child(btn)
```

### 4.2 Journey Graph Studio (Visual Interface)

The visual editor adds a dedicated tab to the upper Godot panel workspace.

```
┌──────────────────────────────────────────────────────────┐
│ [2D]  [3D]  [Script]  [JOURNEY STUDIO]                     │
├──────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────┐   │
│  │  GraphEdit Canvas Workspace                        │   │
│  │                                                    │   │
│  │  ┌─────────────────────┐    ┌───────────────────┐  │   │
│  │  │ GraphNode: Event    │    │ GraphNode: Choice │  │   │
│  │  │                     │────►                   │  │   │
│  │  │ [Text Box Input   ] │    │ [Add Condition  ] │  │   │
│  │  │ [Drag/Drop Texture] │    │ [Add Consequence] │  │   │
│  │  └─────────────────────┘    └───────────────────┘  │   │
│  └────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────┘
```

- **Visual Graph Engine:** Built purely using Godot's built-in control UI elements (`GraphEdit` and `GraphNode`).
- **Authoring sub-resources:** "Add Condition" / "Add Consequence" buttons instantiate the corresponding sub-resource and expose its typed `@export` fields (operator dropdowns, key fields, value spinners). The `ALL`/`ANY` toggle on a choice surfaces as a single dropdown — the deliberate ceiling on grouping UI (§3.3).
- **Automated Compilation Workflow:** On Save, the interface runs a custom serialization routine that generates distinct `.tres` files to a designated game folder and links the resource paths together automatically.

---

## 5. State Preservation (Save / Load)

**[REVISED in R2]**

- **Flat primitive state.** Because all live state resides in flat dictionaries of numbers, booleans, and strings, the runtime serializes the world by writing pure primitives. Object references (including resource instances) are stored as their resource **paths**, never as live objects, keeping saves portable and tolerant of content updates.
- **Opt-in encryption, off by default.** `JourneyConfig` exposes a `save_encryption_key: String`. When empty (the default), saves write as plaintext via `FileAccess.open` — far easier to debug during development. When set, saves use `FileAccess.open_encrypted_with_pass` to `user://savegame.dat`.
- **Honest framing.** Client-side save encryption is **anti-tamper obfuscation, not security.** The key ships inside the exported binary and can be extracted by a determined player; its purpose is to deter casual save-file editing, not to protect secrets. Documentation must state this so developers don't build trust assumptions on it.

```
func save_game(slot := "savegame") -> void:
    var path := "user://%s.dat" % slot
    var key := config.save_encryption_key
    var file := (
        FileAccess.open(path, FileAccess.WRITE) if key.is_empty()
        else FileAccess.open_encrypted_with_pass(path, FileAccess.WRITE, key)
    )
    file.store_var(_serialize_state())   # _serialize_state returns only primitives
```

---

## 6. Non-Functional Requirements & Performance

- **Zero Engine Overhead:** By relying exclusively on lightweight GDScript and custom resource allocations, memory footprint increases remain negligible, preserving Godot's fast boot speeds.
- **Pool scalability:** The tag index (§3.4) keeps stochastic selection cheap even at thousands of events, because condition evaluation runs only over a pre-narrowed candidate set rather than the whole library.
- **Deliberately deferred — computed weights:** Continuous, Blackboard-driven encounter weighting was evaluated for v1 and **excluded**. Rationale: (1) most stochastic pulls want fixed designer-intended frequencies; (2) state-reactive frequency is already achievable via pool eligibility conditions; (3) a weight-formula feature imposes per-candidate per-step evaluation cost and, more importantly, forces a formula-authoring UI into Journey Graph Studio, which is exactly where narrative engines bloat into unusability. Games that genuinely require continuous weight scaling should implement it as a small project-side runtime extension layered on the Dumb-UI pattern, not in the shared engine.
- **Editor-UI as the gating constraint:** Every export field added to a core resource becomes a control a non-technical designer must understand on the GraphEdit canvas. Feature inclusion is judged primarily by authoring-UI cost, not runtime cost.

---

## 7. Validation Against a Representative Target Game

The R2 feature set was checked against a rogue-lite merchant RPG (travel → encounter → choice → mutate → advance, with a hidden Chaos/Stability index, persistent flag-driven narrative chains, and four cumulative-state endings). Result: **fully buildable with no architectural conflicts.** Two items require game-specific code rather than engine features, and are correctly out of engine scope:

- **Dynamic item pricing** (one item's price = base × f(stability)): there is no economy layer in the engine by design. Implement as either per-tier shop choices gated by conditions, or as project-side GDScript reading the Blackboard. Engine provides the state; the game provides the pricing rule.
- **Automatic ending selection** among Good/Bad/Neutral by a basket of resources: implement as a silent "ending router" event whose auto-resolving choices carry compound `JourneyConditionGroup` conditions and route to the matching ending. The final "Terminal Choice" twist is simply one event with condition-gated choices.
# Journey Engine (Core)

A **presentation-agnostic, studio-authorable narrative-journey runtime for
Godot 4 / GDScript.** You author your story as Godot resources — events,
choices, conditions, consequences — and the engine handles state, routing,
randomness, and saves. It never touches your UI, so you keep full control of how
the journey looks and feels.

> **Status:** core runtime complete and verified, including a playable Web/WASM
> sample game. No tagged release yet.

## What you build with it

A run-based, choice-driven journey: the player moves event to event, each choice
mutates bounded resources (gold, sanity, rations…) and flips flags, and the
engine routes to the next event — **deterministically** by design, or by pulling
a **weighted random event** from a tagged pool. Saves resume the exact run,
including the random stream. Your UI just listens to signals.

## Features

- **Inspector-authorable content** — every type is a Godot `Resource`; write a
  whole game with no code.
- **Bounded resources + flags** — numeric state clamped to declared bounds, plus
  lazy boolean flags, all on a single Blackboard with one sanctioned write path.
- **Conditions & consequences** — 8 comparison operators and 5 mutation
  operations, grouped with `ALL`/`ANY` logic.
- **Routing** — deterministic targets, forced boundary routes (e.g. "sanity hits
  0 → madness"), and stochastic pool pulls, with a strict precedence.
- **Stochastic pool** — export-safe directory scan, tag filtering, and
  deterministic weighted selection from a seeded RNG.
- **Save/load** — primitives-only serialization, RNG-state continuity (loaded
  runs reproduce the same pulls), optional encryption, and a versioned migration
  scaffold.
- **Authoring validator** — pure-inspection checks for null start events, bad
  bounds, duplicate/empty ids, undeclared-key typos, and dead choices.
- **No native dependencies** — plain GDScript; exports anywhere Godot 4 does,
  browser included.

## Requirements

- **Godot 4.6.x** (GDScript only). The sample game targets the Compatibility
  renderer so it Web-exports cleanly.

## Install

1. Copy the `addons/journey_engine_core/` folder into your project's `addons/`
   directory.
2. Enable **Journey Engine Core** in **Project → Project Settings → Plugins**.
   The plugin registers the **`JourneyRuntime`** autoload for you — that's the
   whole setup.

> Prefer to wire it by hand? Skip the plugin and add the autoload yourself
> (Node Name `JourneyRuntime`, path
> `res://addons/journey_engine_core/journey_runtime.gd`). The runtime script
> intentionally has **no** `class_name` — that would collide with the autoload's
> global — so always reach it through the `JourneyRuntime` identifier.

See [Installation](docs/getting-started/installation.md) for the full walkthrough.

## Quick taste

Your UI subscribes to signals and drives the engine with a single call:

```gdscript
func _ready() -> void:
    JourneyRuntime.event_changed.connect(_on_event_changed)
    JourneyRuntime.journey_ended.connect(_on_journey_ended)
    JourneyRuntime.start_new_journey(my_config, 12345)  # fixed seed = reproducible

func _on_event_changed(event: JourneyEvent, choices: Array[JourneyChoice]) -> void:
    # `choices` is already visibility-filtered — just render it.
    _set_narrative(event.narrative_text)
    for choice in choices:
        var btn := Button.new()
        btn.text = choice.button_text
        btn.pressed.connect(func(): JourneyRuntime.process_choice(choice))
        _choices_box.add_child(btn)
```

The full runnable walkthrough is the
[Quick Start](docs/getting-started/quick-start.md).

## Documentation

Comprehensive docs live in [`docs/`](docs/) and build into a searchable site
with [MkDocs](https://www.mkdocs.org/) + Material:

```bash
python3 -m venv .venv-docs && source .venv-docs/bin/activate
pip install -r requirements-docs.txt
mkdocs serve          # live preview at http://localhost:8000
```

Highlights: [Concepts](docs/concepts/overview.md) ·
[API Reference](docs/reference/api.md) ·
[Stochastic Pool](docs/guides/stochastic-pool.md) ·
[Save & Load](docs/guides/save-and-load.md) ·
[Exporting](docs/guides/exporting.md) ·
[Troubleshooting](docs/reference/troubleshooting.md).

## Project layout

```text
addons/journey_engine_core/  # the engine: plugin + runtime + resource types (copy into your game)
sample_game/                 # a complete playable journey exercising every feature
tests/                       # headless + manual test scenes
docs/                        # MkDocs documentation source
mkdocs.yml                   # docs site config
```

The bundled `sample_game/` consumes only the public API and is the reference
implementation of the [Dumb-UI / presentation contract](docs/concepts/presentation-contract.md).

## Releasing

Maintainers: see [RELEASING.md](RELEASING.md) for the version-bump, GitHub
Release, GitHub Pages, and Asset Library procedures.

## License

[MIT](LICENSE).

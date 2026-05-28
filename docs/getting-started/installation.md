# Installation

Journey Engine is a small set of GDScript files plus one Autoload. There is no
GDExtension, no compiled binary, and no third-party dependency — if your project
runs Godot 4.6, it can run Journey Engine.

## Requirements

| Requirement | Detail |
| --- | --- |
| Godot | 4.6.x stable |
| Language | GDScript only |
| Renderer | Compatibility (the engine is renderer-agnostic; the sample game targets Compatibility for Web export) |

The core runtime lives entirely in `addons/journey_engine_core/`. It is **presentation-agnostic**:
no class in that folder instantiates a Node, touches the SceneTree, or assumes a
UI exists. See the [Presentation Contract](../concepts/presentation-contract.md).

## 1. Add the addon files

Copy the `addons/journey_engine_core/` folder into your project's `addons/`
directory. It contains the runtime, the resource classes you author against, and
the small editor plugin that wires everything up:

- `plugin.cfg` / `plugin.gd` — the editor plugin (registers the autoload on enable).
- `journey_runtime.gd` — the single public API (the autoload).
- `blackboard.gd`, `sequence_manager.gd`, `pool_index.gd`, `save_manager.gd`,
  `validator.gd`, `evaluator.gd`, `mutator.gd` — the internals.
- `journey_*.gd` — the authorable resource types
  (`JourneyConfig`, `JourneyEvent`, `JourneyChoice`, `JourneyCondition`,
  `JourneyConditionGroup`, `JourneyConsequence`, `JourneyResourceDef`).

Each resource class declares a `class_name`, so once the files are in your
project they appear automatically in the editor's **Create New Resource** dialog.

## 2. Enable the plugin

Open **Project → Project Settings → Plugins** and toggle **Journey Engine Core**
on. That's it — the plugin registers the **`JourneyRuntime`** autoload for you, so
there's no manual setup step.

!!! warning "The autoload name is always `JourneyRuntime`"
    Game code calls the engine through the global `JourneyRuntime` identifier.
    The runtime script intentionally has **no** `class_name` — that would collide
    with the autoload's auto-registered global (`Class 'JourneyRuntime' hides an
    autoload singleton`). Always reach it through the autoload, not as a class.

??? note "Prefer to register the autoload by hand?"
    You can skip the plugin and add the autoload yourself — the runtime is plain
    GDScript with no editor dependency.

    === "Editor"

        **Project → Project Settings → Globals → Autoload**, then:

        - **Path:** `res://addons/journey_engine_core/journey_runtime.gd`
        - **Node Name:** `JourneyRuntime`
        - Leave **Enable** (the global singleton) checked.

    === "project.godot"

        Add the entry directly under the `[autoload]` section:

        ```ini
        [autoload]

        JourneyRuntime="*res://addons/journey_engine_core/journey_runtime.gd"
        ```

        The leading `*` enables the singleton global. (The bundled sample game
        ships this entry *and* enables the plugin; the plugin detects the existing
        autoload and leaves it alone, so the two never conflict.)

## 3. Verify

With the Autoload registered, the project should load error-free and
`JourneyRuntime` should be reachable from any script. A quick smoke check:

```gdscript
func _ready() -> void:
    print(JourneyRuntime)            # -> the runtime node
    print(JourneyRuntime.blackboard) # -> a Blackboard instance
```

You're ready to build a journey. The [Quick Start](quick-start.md) takes you from
here to a clickable two-event journey running in the editor.

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

The core runtime lives entirely in `journey_core/`. It is **presentation-agnostic**:
no class in that folder instantiates a Node, touches the SceneTree, or assumes a
UI exists. See the [Presentation Contract](../concepts/presentation-contract.md).

## 1. Add the engine files

Copy the `journey_core/` folder into your project (anywhere under `res://`). It
contains the runtime and the resource classes you author against:

- `journey_runtime.gd` — the single public API (registered as an Autoload).
- `blackboard.gd`, `sequence_manager.gd`, `pool_index.gd`, `save_manager.gd`,
  `validator.gd`, `evaluator.gd`, `mutator.gd` — the internals.
- `journey_*.gd` — the authorable resource types
  (`JourneyConfig`, `JourneyEvent`, `JourneyChoice`, `JourneyCondition`,
  `JourneyConditionGroup`, `JourneyConsequence`, `JourneyResourceDef`).

Each resource class declares a `class_name`, so once the files are in your
project they appear automatically in the editor's **Create New Resource** dialog.

## 2. Register the Autoload

The runtime must be registered as an Autoload named **`JourneyRuntime`**. This is
the one setup step you cannot skip.

!!! warning "The Autoload name must be exactly `JourneyRuntime`"
    Game code calls the engine through the global `JourneyRuntime` identifier.
    The script intentionally has **no** `class_name` — that would collide with
    the Autoload's auto-registered global (`Class 'JourneyRuntime' hides an
    autoload singleton`). Register it under this exact name and reach it through
    the Autoload, not as a class.

=== "Editor"

    **Project → Project Settings → Globals → Autoload**, then:

    - **Path:** `res://journey_core/journey_runtime.gd`
    - **Node Name:** `JourneyRuntime`
    - Leave **Enable** (the global singleton) checked.

=== "project.godot"

    Add the entry directly under the `[autoload]` section:

    ```ini
    [autoload]

    JourneyRuntime="*res://journey_core/journey_runtime.gd"
    ```

    The leading `*` enables the singleton global. This is exactly how the bundled
    sample game registers it.

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

# UI Kit — Install

The kit is pure runtime `Control` nodes — **there is no plugin to enable**. Install
is "copy the folder, instance one scene."

## 1. Have the core installed

The kit needs the `JourneyRuntime` autoload, so install
[`journey_engine_core`](../getting-started/installation.md) first and enable its
plugin. (The core's plugin is what registers the autoload; the kit registers
nothing.)

## 2. Copy the kit

Copy `addons/journey_engine_ui_kit/` into your project's `addons/` folder. That's it
— no autoload, no `plugin.cfg`, no editor restart.

## 3. Add a `JourneyStageView`

The kit's assembled view is **`JourneyStageView`** — the visual-first scheme
(background + character sprite focus; see [Stage view](stage-view.md)). Instance
**`res://addons/journey_engine_ui_kit/JourneyStageView.tscn`** into your scene,
select it, and in the Inspector:

1. Assign your **`config`** (a `JourneyConfig`).
2. Add your **HUD bindings** (see below).
3. Assign a **`stage_book`** to stage sprites/speakers per event ([details](stage-view.md#staging-events-the-stage-book)).
4. Optionally set a **seed**, **Theme**, **SFX** streams, and animation knobs.

With `autostart` on (the default), the journey begins when the scene runs.

```gdscript
# Building it in code instead of instancing the scene:
var view := preload("res://addons/journey_engine_ui_kit/JourneyStageView.tscn").instantiate()
view.config = preload("res://my_game/config.tres")
view.stage_book = preload("res://my_game/stage_book.tres")
view.seed = 12345
add_child(view)   # autostart begins the journey
```

!!! tip "Want a different layout?"
    `JourneyStageView` is just a thin root that arranges the kit's
    [components](components.md) — each is an independent, layout-agnostic signal
    subscriber. To build a text-forward or otherwise different layout, arrange the
    same components in your own root scene; nothing in the kit forces the stage layout.

## HUD bindings

The HUD hardcodes no resource names. You declare what it shows with an array of
`JourneyHudBinding` resources on `JourneyStageView.hud_bindings`. Each binding:

| Field | Meaning |
| --- | --- |
| `key` | Blackboard key to read. |
| `label_format` | printf-style format, e.g. `"Gold: %d"`. |
| `icon` | *(optional)* `Texture2D` shown left of the label. |
| `is_metadata` | If `true`, read via `get_metadata(key)` (e.g. `turn_counter`) instead of `get_resource(key)`. |

A typical four-row HUD: `gold`, `sanity`, `rations` (resources) and `turn_counter`
(metadata). The bundled demo at `res://sample_game/journey_stage_demo.tscn` is wired
exactly this way — open it for a working reference.

## Running the demo

The project's `sample_game/journey_stage_demo.tscn` instances `JourneyStageView`
against the sample game's `config.tres` and `stage_book.tres`. It is the project's
main scene, so **F5** runs it; the original raw Dumb-UI sample
(`sample_game/main.tscn`) is still there and runs via **F6**.

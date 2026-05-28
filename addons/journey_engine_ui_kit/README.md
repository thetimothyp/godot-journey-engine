# Journey Engine — UI Starter Kit

A drop-in, themeable presentation layer for the
[Journey Engine](../journey_engine_core/) core. It turns the engine's six signals
into a complete, animated front end: a background + foreground character-sprite
stage, narrative with text-reveal pacing, a config-driven resource HUD, choices
(with optional locked/greyed entries), save/load, an ending overlay, an audio layer,
and scene transitions — all wired together in a one-line `JourneyStageView`.

> **Optional & one-way.** This addon depends on `journey_engine_core`, never the
> reverse. A core-only project is unaffected if you don't install the kit. The core
> stays presentation-agnostic; the kit talks to it **only** through the public
> `JourneyRuntime` API (`process_choice` is the single write; `get_resource` /
> `has_flag` / `get_metadata` are the only reads).

## Install

1. Install `addons/journey_engine_core` and enable its plugin (registers the
   `JourneyRuntime` autoload). The kit needs the autoload present.
2. Copy `addons/journey_engine_ui_kit/` into your project. **No plugin to enable** —
   the kit is pure runtime `Control` nodes, no autoload, no editor tooling.
3. Instance **`JourneyStageView.tscn`**, assign your `JourneyConfig` to its `config`,
   add your HUD `bindings` and a `stage_book`, and run.

```gdscript
# Or build it in code:
var view := preload("res://addons/journey_engine_ui_kit/JourneyStageView.tscn").instantiate()
view.config = preload("res://my_game/config.tres")
view.stage_book = preload("res://my_game/stage_book.tres")
add_child(view)   # autostart begins the journey
```

## Components

Each is an independent `Control`/`Node` that subscribes to `JourneyRuntime` signals
on its own and can be used standalone — so you can also arrange your own layout
instead of using `JourneyStageView`:

| Component | Role |
| --- | --- |
| `JourneyBackgroundLayer` | Displays `background_texture`; crossfades + idle motion. |
| `JourneyForegroundLayer` | Stages per-event character sprite(s) from a `JourneyStageBook`. |
| `JourneyNarrativePanel` | Renders `narrative_text`; owns text-reveal pacing (instant / fade / typewriter). |
| `JourneyChoiceList` | Renders choices (optionally showing locked ones greyed); **the only caller of `process_choice`**; owns the input lock. |
| `JourneyResourceHud` | Config-driven `key → label` read-out (no hardcoded resources). |
| `JourneySaveLoadBar` | Save / Load / Restart; repaints the HUD after load. |
| `JourneyEndingOverlay` | Shows the ending on `journey_ended`. |
| `JourneyAudioLayer` | Loops per-event `ambient_audio`; plays UI SFX from exported slots. |
| `JourneyTransitionLayer` | Full-view fade / wipe between events. |
| `JourneyStageView` | Assembles them all (visual-first layout) and exposes one-line config. |

## Customizing assets

The addon ships **placeholder** visuals (generated gradients) and **no audio**. Your
real assets live in **your** folders and are wired via exported properties / event
fields, so kit updates never clobber them:

- **Per-event background** → set `JourneyEvent.background_texture` on your event `.tres`.
- **Per-event ambient audio** → set `JourneyEvent.ambient_audio` on your event `.tres`.
- **Per-event sprite / speaker** → add an entry to a `JourneyStageBook` (keyed by `event.id`).
- **UI chrome (theme)** → duplicate `assets/theme/journey_stage_theme.tres` into
  `res://<your_game>/ui/` and assign it to `JourneyStageView.theme`. Don't edit the addon copy.
- **UI SFX** → assign your `AudioStream`s to `JourneyStageView`'s exported SFX slots
  (see `assets/sfx/README.md`).
- **Resource icons** → optional per-binding `icon` on a `JourneyHudBinding`.

Full guide: **docs → UI Kit**.

## License

MIT (same as the engine). Shipped placeholders are original / CC0 — see
[`CREDITS.md`](CREDITS.md).

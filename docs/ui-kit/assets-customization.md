# UI Kit — Assets & customization

The guiding principle:

!!! abstract "The addon ships defaults; your assets live in your folders"
    The kit bundles **placeholders** so it works out of the box. Your real
    backgrounds, audio, theme, and icons live in **your** game's folders and are
    wired in through **exported properties** or **event fields** — never by editing
    files inside `addons/journey_engine_ui_kit/`. That way a kit update can't clobber
    your content.

## What ships in the addon

```
addons/journey_engine_ui_kit/assets/
  backgrounds/   placeholder_dawn|dusk|night.tres   (generated gradients — not art)
  sprites/       placeholder_icon.tres              (generated radial gradient)
                 placeholder_figure_a|b.tres        (generated stand-in figures)
  sfx/           README.md                          (NO audio ships; empty slots)
  theme/         journey_stage_theme.tres           (default stage Theme)
```

Everything bundled is **original / CC0** and clearly named `placeholder_*`. The kit
ships **no audio** — authoring real SFX is out of scope, so the SFX slots are empty
and silent until you fill them. See the addon's `CREDITS.md`.

## Supplying your own assets

### Per-event background

Set **`JourneyEvent.background_texture`** on the event's `.tres`. `JourneyBackgroundLayer`
displays it and crossfades from the previous event's background. Any `Texture2D`
works — an imported image, a gradient, a viewport texture. The bundled demo assigns
the placeholder gradients to `evt_start` and `evt_road_begins` to show the path.

### Per-event ambient audio

Set **`JourneyEvent.ambient_audio`** on the event's `.tres`. `JourneyAudioLayer` plays
it looped and crossfades between events. Enable looping in the file's import settings
(or rely on the layer setting the stream's `loop` property when present).

### UI chrome (theme)

**Duplicate** `assets/theme/journey_stage_theme.tres` into your own folder (e.g.
`res://my_game/ui/`), restyle it, and assign it to **`JourneyStageView.theme`**.
Because the theme is applied at the `JourneyStageView` root, it cascades to every
component. Do **not** edit the addon's copy — a kit update would overwrite it.

### UI SFX

Drop your `.wav`/`.ogg` files in your game folder and assign them to
`JourneyStageView`'s exported SFX slots (`sfx_button_hover`, `sfx_button_press`,
`sfx_choice_confirm`, `sfx_save`, `sfx_load`, `sfx_ending`). Empty slots stay silent.
Details in
`addons/journey_engine_ui_kit/assets/sfx/README.md`.

### Resource icons

Give a `JourneyHudBinding` an **`icon`** (`Texture2D`) to show it left of that row's
label.

## Why outside the addon?

Keeping your assets in your own folders means:

- **Updates are safe.** Re-installing or upgrading the kit replaces only
  `addons/journey_engine_ui_kit/` — your art, audio, and theme are untouched.
- **Attribution stays clear.** Licensed or third-party files live with *your* project
  and *your* credits, not mixed into the MIT addon.

See also: [Components](components.md) · [Authoring Content](../guides/authoring-content.md)
for how the `JourneyEvent` fields are set.

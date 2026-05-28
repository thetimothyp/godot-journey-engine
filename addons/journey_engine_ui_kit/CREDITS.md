# Credits & attribution

The Journey Engine UI Starter Kit is **MIT-licensed** (same as the engine).

## Shipped assets

All assets bundled with this addon are **original and CC0** (public-domain
equivalent), authored as Godot resources — there is no third-party art or audio to
attribute:

- `assets/backgrounds/placeholder_*.tres` — **placeholder** backgrounds generated
  from Godot `GradientTexture2D` gradients. Not hand-drawn art; intended to be
  replaced (set `JourneyEvent.background_texture`).
- `assets/sprites/placeholder_icon.tres` — **placeholder** HUD icon, a generated
  radial gradient.
- `assets/sprites/placeholder_figure_a.tres` / `_b.tres` — **placeholder** foreground
  figures, generated vertical gradients. Not character art; intended to be replaced
  (reference your own `Texture2D` from a `JourneyStageBook` entry).
- `assets/theme/journey_stage_theme.tres` — default stage `Theme` built from Godot
  `StyleBoxFlat` resources.

## Audio

**No audio files ship with this kit.** The SFX slots are intentionally empty (see
`assets/sfx/README.md`). Any audio you add is your own and governed by its own
license.

## Using your own assets

When you replace the placeholders with your own (or third-party CC0/licensed)
assets, track their attribution in your **game's** credits — keep licensed files in
your game folders, not inside this addon.

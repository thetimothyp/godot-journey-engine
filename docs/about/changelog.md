# Changelog

This project follows [Keep a Changelog](https://keepachangelog.com/) conventions
and [Semantic Versioning](https://semver.org/). The engine version is exposed at
runtime as `JourneyRuntime.VERSION`.

## Unreleased

### Added

- **UI Starter Kit** (`addons/journey_engine_ui_kit/`) — an optional, themeable
  presentation layer that turns the engine's signals into a complete animated front
  end. Independent `Control` components (narrative with text-reveal pacing, a
  config-driven resource HUD, choices, save/load, ending overlay, a background layer
  with crossfade + idle motion, an audio layer with per-event ambient + UI SFX slots,
  and a fade/wipe transition layer), assembled into a one-line **`JourneyView`** with
  a default Theme and placeholder assets. Strict one-way dependency on the core; no
  autoload or plugin to enable. See the [UI Kit](../ui-kit/overview.md) docs.
- **Stage presentation scheme** — a second assembled view, **`JourneyStageView`**
  (visual-first, *Sort the Court* style: full-screen background + foreground character
  sprite as the focus, slim resource bar, short dialogue strip, horizontal choice
  row). Adds `JourneyForegroundLayer` and a kit-side **`JourneyStageBook`** (maps
  `event.id` → sprite[s]/speaker, no core change), a stage theme with outlined text +
  scrims, placeholder figures, and a `journey_stage_demo.tscn` (now the project's main
  scene). `JourneyChoiceList` gained a `vertical_layout` toggle (horizontal button
  rows) — backward-compatible. See [UI Kit → Stage view](../ui-kit/stage-view.md).
- A `JourneyView` demo (`sample_game/journey_view_demo.tscn`) wired to the sample
  config; the original Dumb-UI sample remains at `sample_game/main.tscn`.

## 0.1.0 — 2026-05-28

Initial release. The core runtime is feature-complete:

- **Resource model** — `JourneyConfig`, `JourneyEvent`, `JourneyChoice`,
  `JourneyCondition`, `JourneyConditionGroup`, `JourneyConsequence`,
  `JourneyResourceDef` (all inspector-authorable).
- **Blackboard** — bounded resources, lazy flags, engine-owned metadata, seeded
  RNG; single mutation path.
- **Evaluation & mutation** — 8 condition operators, 5 consequence operations,
  clamping to declared bounds, missing-key policy.
- **Routing** — deterministic targets, forced boundary routes (transition-based),
  and stochastic pool pulls, with a strict precedence.
- **Stochastic pool** — export-safe directory scan, tag indexing, weighted
  deterministic selection from the seeded RNG.
- **Save/load** — primitives-only serialization, RNG-state continuity, optional
  encryption, versioned migration scaffold.
- **Validation** — pure-inspection authoring checks (`validate()`).
- **Sample game** — a complete playable journey exercising every feature,
  verified in the editor and as a Web/WASM export.
- **Packaging** — shipped as the `addons/journey_engine_core/` Godot addon with
  an editor plugin that registers the `JourneyRuntime` autoload on enable.
- **Documentation** — full MkDocs + Material site under `docs/`.

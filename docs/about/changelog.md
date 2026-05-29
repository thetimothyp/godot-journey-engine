# Changelog

This project follows [Keep a Changelog](https://keepachangelog.com/) conventions
and [Semantic Versioning](https://semver.org/). The engine version is exposed at
runtime as `JourneyRuntime.VERSION`.

## Unreleased

### Added

- **`target_event` cycle detection in `validate()`** — the authoring validator
  now walks the `choice.target_event` hard-reference graph (seeded from
  `start_event` ∪ boundary events ∪ pool events) and reports any directed cycle
  as an **error** naming the concrete loop. A `target_event` cycle is an eager
  object reference that Godot serializes as an `ext_resource`/`SubResource`
  pointer, and a cyclic chain of those **cannot be loaded from disk** — yet it
  is legal in memory, so it previously passed `validate()` and the runtime smoke
  test while being unloadable in a shipped build. Loop-backs must use
  `continue_to_pool` (a bool, no serialized reference); `continue_to_pool` /
  `pool_conditions` / boundary routes are *not* treated as graph edges. Additive
  and non-breaking — no content format change. See
  [Validation](../guides/validation.md) and
  [Routing](../concepts/routing.md#target_event-is-an-eager-object-reference-never-form-a-cycle).
- **`JourneyLoadCheck`** (`tests/journey_load_check.gd`) — the canonical "would
  this ship?" disk round-trip check. Loads a config from disk in a fresh context
  (`CACHE_MODE_IGNORE`), walks `start_event` ∪ boundaries ∪ the pool dir, and
  asserts every reachable resource loads non-null with no parse error — the
  load-time companion to the in-memory `validate()`. Wired into
  `tests/test_export_sanity.gd` as a pre-export gate.

## 0.2.0 — 2026-05-28

### Added

- **UI Starter Kit** (`addons/journey_engine_ui_kit/`) — an optional, themeable
  presentation layer that turns the engine's signals into a complete animated front
  end. Independent, layout-agnostic `Control` components: a background layer
  (crossfade + idle motion), a **foreground sprite layer** (per-event character[s] +
  speaker, from a kit-side `JourneyStageBook` keyed by `event.id` — no core change),
  narrative with text-reveal pacing, a config-driven resource HUD, choices (with
  optional locked/greyed entries), save/load, an ending overlay, an audio layer
  (per-event ambient + UI SFX slots), and a fade/wipe transition layer. Assembled into
  a one-line **`JourneyStageView`** — a visual-first, *Sort the Court*-style layout
  (background + character sprite focus; slim resource bar, short dialogue strip,
  horizontal choice row) — with a stage Theme (outlined text + scrims for readability
  over art) and placeholder assets. Strict one-way dependency on the core; no autoload
  or plugin to enable. Demo: `sample_game/journey_stage_demo.tscn` (the project's main
  scene); the raw Dumb-UI sample remains at `sample_game/main.tscn`. See the
  [UI Kit](../ui-kit/overview.md) docs.
- **Locked choices** — `JourneyChoiceList.show_locked_choices` renders choices that
  fail their visibility as disabled/greyed buttons (e.g. "Pay 30 gold" when you can't
  afford it) by diffing the visibility-passing subset against the full `event.choices`
  — no visibility re-evaluation in the UI, no core change. On by default in the stage
  view.

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

# Changelog

This project follows [Keep a Changelog](https://keepachangelog.com/) conventions
and [Semantic Versioning](https://semver.org/). The engine version is exposed at
runtime as `JourneyRuntime.VERSION`.

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

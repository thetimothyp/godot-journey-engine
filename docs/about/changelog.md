# Changelog

No tagged releases yet. This page is a stub — populate it when you cut the first
release.

## Unreleased

The core runtime is feature-complete. Implemented capabilities:

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

When you tag a release, follow [Keep a Changelog](https://keepachangelog.com/)
conventions and a versioning scheme (e.g. [SemVer](https://semver.org/)).

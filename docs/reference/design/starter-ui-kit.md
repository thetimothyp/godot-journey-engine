# Starter UI Kit (planned)

!!! note "Not yet written"
    This page is a placeholder. The Starter UI Kit design document hasn't been
    authored yet — this stub exists so the navigation and cross-references are in
    place for when it lands.

The **Starter UI Kit** is a planned, separately-packaged set of `Control` nodes
that consume the Journey Engine the "right" way: independent signal subscribers
for narrative, HUD, and choices, with `process_choice` as the only write into the
engine, and strict no-cross-reference rules between the panels.

Until it ships, the bundled **`sample_game/`** is the reference implementation of
the same pattern. It is a *sample*, not the kit — it follows the spirit (Dumb-UI
subscribers, single write path, UI-owned pacing) without the stricter packaging
the kit will add. See:

- [The Presentation Contract](../../concepts/presentation-contract.md) — the
  rules any UI (sample or kit) must follow.
- [Quick Start](../../getting-started/quick-start.md) — a minimal Dumb UI built
  from scratch.

When the Starter UI Kit design is written, it belongs here alongside the
[PRD](prd.md) and [Engineering Design](engineering-design.md).

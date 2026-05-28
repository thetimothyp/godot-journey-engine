# UI Kit — Overview

The **UI Starter Kit** is an optional second addon, `addons/journey_engine_ui_kit/`,
that turns the engine's six signals into a complete, animated front end you can drop
in with one node. Where the [core](../index.md) is deliberately
[presentation-agnostic](../concepts/presentation-contract.md), the kit is the
presentation: it renders narrative, choices, and a configurable HUD, plays the
per-event background and audio payloads the core has always carried, and animates
the transitions between events.

!!! abstract "What the kit gives you"
    - A one-line assembled view — **`JourneyStageView`** (visual-first, Sort-the-Court
      style: a background + character sprite are the focus) — that starts a journey
      from your config.
    - Independent, reusable, layout-agnostic `Control` components (background,
      foreground sprites, narrative, choices, HUD, save/load, ending, audio,
      transition) — arrange your own layout if the stage scheme isn't your style.
    - Client-side **animation** — text reveal, entrance/exit, idle motion, and scene
      transitions — that never makes the engine wait.
    - A default **Theme** and **placeholder assets** so it looks decent immediately,
      plus a clear path to swap in your own art, audio, and styling.

## One-way, optional, contract-respecting

The kit depends on the core; **the core never depends on the kit**. This is a hard
architectural rule:

- **Optional.** A core-only project is unaffected if you don't install the kit. The
  kit is a separate addon folder with no autoload and no editor plugin.
- **One-way.** The kit talks to the engine *only* through the public `JourneyRuntime`
  API. It honors the [Presentation Contract](../concepts/presentation-contract.md) to
  the letter:
    - **`process_choice` is the single write.** Only `JourneyChoiceList` calls it.
    - **Reads go through accessors** — `get_resource` / `has_flag` / `get_metadata`.
      The kit never touches `JourneyRuntime.blackboard`.
    - **Choices arrive pre-filtered.** The kit renders the choices `event_changed`
      hands it and never re-checks visibility. (It can optionally also show the
      *filtered-out* choices greyed/locked — by diffing against the full
      `event.choices`, not by re-evaluating anything. See [Components](components.md).)
    - **The kit owns pacing.** The engine advances only on `process_choice` and never
      blocks; all animation is sequenced client-side.

## Where to go next

- [Install](install.md) — get a `JourneyStageView` on screen.
- [Components](components.md) — what each piece does and its exported knobs.
- [Animations](animations.md) — the entrance/exit/idle/transition model and how it
  sequences against `process_choice`.
- [Stage view](stage-view.md) — the visual-first scheme (background + character
  sprite focus) and the stage book that maps events to sprites/speakers.
- [Assets & customization](assets-customization.md) — swap in your backgrounds,
  audio, theme, and icons without ever editing the addon.

# Starter UI Kit

!!! success "Shipped"
    The Starter UI Kit now ships as the `addons/journey_engine_ui_kit/` addon. For
    end-user documentation see the **[UI Kit](../../ui-kit/overview.md)** section —
    [overview](../../ui-kit/overview.md), [install](../../ui-kit/install.md),
    [components](../../ui-kit/components.md), [animations](../../ui-kit/animations.md),
    and [assets & customization](../../ui-kit/assets-customization.md).

The **Starter UI Kit** is an optional, separately-packaged set of `Control`
components that consume the Journey Engine the "right" way: independent signal
subscribers for narrative, HUD, choices, background, audio, and transitions, with
`process_choice` as the single write into the engine and reads only through the
public accessors. It adds a background/audio/animation layer that finally presents
the `JourneyEvent.background_texture` / `ambient_audio` payloads plus per-event
foreground sprites (a kit-side stage book), and assembles everything into a one-line
`JourneyStageView` (a visual-first, Sort-the-Court-style layout).

## Design notes

- **One-way dependency.** The kit depends on `journey_engine_core`; the core never
  depends on the kit and stays presentation-agnostic. The kit is *optional* — a
  core-only project is unaffected.
- **Pacing is client-side.** Because the engine advances only on `process_choice`
  and never blocks, the kit sequences all animation around that one synchronous
  call (see [Animations](../../ui-kit/animations.md)).
- **Defaults ship; user assets live outside the addon.** Placeholders and a default
  Theme ship in the addon; real backgrounds/audio/theme/icons live in the user's
  folders and are wired via exported properties or `JourneyEvent` fields.

## Presentation-Contract questions surfaced while building it

Building a real animated UI is the best way to find gaps in the
[Presentation Contract](../../concepts/presentation-contract.md). Building the kit
surfaced these (the core remains frozen throughout):

1. **Disabled-vs-hidden choices — RESOLVED kit-side, no core change.** The worry was
   that `event_changed` delivers only the visibility-*passing* choices, so a front
   end couldn't show a greyed-out *"Pay 30 gold (locked)"* affordance. But the signal
   *also* carries the event, and the engine builds its visible subset from the **same
   `JourneyChoice` instances** in `event.choices`. So the kit renders the full
   `event.choices` and disables those **not** in the visible subset — a pure identity
   diff, never a visibility re-evaluation (the engine stays the single source of
   truth). This shipped as `JourneyChoiceList.show_locked_choices`. **Residual gap:**
   the engine exposes no human-readable *reason* a choice is locked ("needs 30 gold");
   surfacing one would need a core field on `JourneyChoice` (e.g. `locked_hint`) or
   the UI introspecting the condition group — left for discussion, not implemented.
2. **No pre-transition / "about to leave event" signal.** Only the `process_choice`
   caller knows a change is imminent, so non-orchestrating components (background,
   audio) can't independently play an *exit* before the swap. The kit works around it
   by funnelling the sequence through `ChoiceList`; a `journey_will_change` signal
   would decouple it. Minor, and arguably at odds with "the engine doesn't gate" — so
   listed for discussion rather than recommended.

See the [PRD](prd.md) and [Engineering Design](engineering-design.md) for the core's
design.

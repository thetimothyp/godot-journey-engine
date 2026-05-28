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
the `JourneyEvent.background_texture` / `ambient_audio` payloads, and assembles
everything into a one-line `JourneyView`.

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

## Open Presentation-Contract questions surfaced while building it

Building a real animated UI is the best way to find gaps in the
[Presentation Contract](../../concepts/presentation-contract.md). Two surfaced; both
are **proposals for discussion**, not implemented (the core remains frozen):

1. **Disabled-vs-hidden choices.** `event_changed` delivers only the
   visibility-*passing* choices, and there is no public "would this choice be
   visible?" read. So a front end **cannot** show a greyed-out *"Pay 30 gold
   (locked)"* affordance — a common narrative-UI idiom. Options to weigh: an optional
   second channel carrying the failing choices (with the reason), or a public
   `evaluate_visibility(choice) -> bool` accessor. Either must preserve "filtering
   lives in the engine" — the UI still wouldn't decide visibility, only render the
   locked state the engine reports.
2. **No pre-transition / "about to leave event" signal.** Only the `process_choice`
   caller knows a change is imminent, so non-orchestrating components (background,
   audio) can't independently play an *exit* before the swap. The kit works around it
   by funnelling the sequence through `ChoiceList`; a `journey_will_change` signal
   would decouple it. Minor, and arguably at odds with "the engine doesn't gate" — so
   listed for discussion rather than recommended.

See the [PRD](prd.md) and [Engineering Design](engineering-design.md) for the core's
design.

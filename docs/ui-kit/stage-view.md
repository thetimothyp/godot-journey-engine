# UI Kit — Stage view (visual-first scheme)

The kit's assembled view is **`JourneyStageView`** — a *visual-first* layout, à la
**Sort the Court**: a full-screen background + a foreground character sprite are the
focus, with the narrative and choices **present but subordinate** — a slim resource
bar on top, a short dialogue strip and a row of choice buttons along the bottom.

It's built entirely from the kit's [components](components.md), which are independent
and layout-agnostic — so if the stage scheme isn't your style, arrange the same
components in your own root scene.

```text
┌───────────────────────────────┐
│ ♦12  ♥8  ⚑5         [S][L][R] │  slim resource bar
│                               │
│            ╱▔▔▔╲              │
│           (  ◕  )   sprite     │  background + foreground
│            ╲___╱    over bg    │  are the focus
│ Traveler:                     │  speaker (from the stage book)
│ ┌───────────────────────────┐ │
│ │ "The bridge is out ahead." │ │  short narrative strip
│ └───────────────────────────┘ │
│ [ Ford the river ][ Turn back ]│  choices as a button row
└───────────────────────────────┘
```

It honors the [Presentation Contract](../concepts/presentation-contract.md) like any
kit front end — `JourneyChoiceList` is the sole `process_choice` caller, reads go
through the accessors, and animation is sequenced client-side so the engine never
waits.

## Use it

Instance **`res://addons/journey_engine_ui_kit/JourneyStageView.tscn`**, then in the
Inspector set:

1. **`config`** — your `JourneyConfig`.
2. **`hud_bindings`** — your resource read-out ([details](install.md#hud-bindings)).
3. **`stage_book`** — a `JourneyStageBook` mapping events to sprites/speakers (below).

`transition_kind` defaults to **`NONE`** here: the background crossfade and the sprite
restaging carry the change between events, rather than a full-screen wipe. Set it to
`FADE`/`WIPE` for a harder cut.

The bundled demo is `res://sample_game/journey_stage_demo.tscn` (the project's main
scene — **F5** runs it from anywhere).

## Staging events: the stage book

The core's `JourneyEvent` carries a `background_texture` and `ambient_audio`, but **no
foreground sprite or speaker** — those are presentation/direction concerns. The kit
keeps them out of the core in a **`JourneyStageBook`**: a resource that maps
`event.id → staging`, assigned on the stage view (or directly on a
`JourneyForegroundLayer`). Keying by the stable `event.id` means it never breaks saves.

| Resource | Fields |
| --- | --- |
| `JourneyStageBook` | `entries: Array[JourneyStageEntry]` |
| `JourneyStageEntry` | `event_id` (matches `JourneyEvent.id`), `speaker`, `sprites: Array[JourneySpritePlacement]` |
| `JourneySpritePlacement` | `texture`, `anchor` (`CENTER`/`LEFT`/`RIGHT`), `offset`, `enter` (`FADE`/`SLIDE_UP`/`SLIDE_SIDE`), `flip_h`, `height_ratio` |

An event with **no entry** simply shows no sprite — staging is fully optional and
incremental. The `sprites` array supports **multiple figures** per event (multi-actor
scenes) without any data change; the default uses a single figure.

!!! tip "A note on where this could live"
    A *single* primary sprite is the same kind of payload as `background_texture`,
    which already rides on the event. `JourneyForegroundLayer` therefore reads an
    `event.get("foreground_texture")` field **first if one ever exists** (it doesn't
    today — `get()` returns null safely), then falls back to the stage book. So if the
    engine ever adds a `foreground_texture` field for author convenience, it works with
    no kit change — while richer staging (speaker, anchors, multiple sprites,
    choreography) stays in the book where it belongs.

## Locked choices

The stage view shows **locked choices** by default (`show_locked_choices`): a choice
whose visibility fails right now appears as a **disabled, greyed** button instead of
vanishing — e.g. the sample's *"Pay them off (-30 gold)"* renders locked when you
can't afford it. The kit knows which to lock by diffing the visibility-passing subset
against the full `event.choices` (both arrive in `event_changed`) — it never
re-evaluates visibility, so the engine stays the single source of truth. Set
`show_locked_choices = false` to hide unavailable choices instead.

A human-readable *reason* ("needs 30 gold") is **not** shown — that would require a
core field on the choice or introspecting its condition group; the locked button just
carries the choice's own text, greyed. See the
[design note](../reference/design/starter-ui-kit.md).

## Readability over art

Text sitting on top of arbitrary background art needs help to stay legible. The stage
view applies **`journey_stage_theme.tres`** by default: outlined text
(`font_outline_color` + `outline_size`) and translucent dark **scrim** panels behind
the narrative strip. As always, **duplicate the theme into your own folder** to
restyle — don't edit the addon copy. See
[Assets & customization](assets-customization.md).

## What's deferred

The first cut keeps choreography simple on purpose: one primary sprite, `CENTER`/
`LEFT`/`RIGHT` anchors, `FADE`/`SLIDE_UP`/`SLIDE_SIDE` entrances, and a subtle idle
bob. Per-character expressions, multi-sprite timing, and *Reigns*-style swipe cards are
intentionally left for later — the data shape already accommodates multi-actor scenes.

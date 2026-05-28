# UI Kit — Animations

The kit covers four kinds of motion, all configurable and all **client-side** — the
engine never waits on any of them.

| Kind | Owner | What it does |
| --- | --- | --- |
| **Entrance** | NarrativePanel, ChoiceList | Text reveals (fade/typewriter); choice buttons fade in, optionally staggered. |
| **Exit / transition** | TransitionLayer (driven by ChoiceList) | Covers the view (fade-through-color or wipe) while the next event swaps in underneath. |
| **Idle** | BackgroundLayer | A slow looping zoom/drift so a static background stays alive. |
| **Per-event crossfade** | BackgroundLayer, AudioLayer | Background images and ambient audio crossfade as events change. |

## Why pacing is the kit's job

The [Presentation Contract](../concepts/presentation-contract.md) is blunt about it:
the engine **advances only on `process_choice`** and **never blocks, waits, or
gates input**. By the time `event_changed` fires, the engine has *already* moved on.
So the kit sequences everything itself, around that one synchronous call.

A subtlety worth internalizing: `process_choice` emits its signals **synchronously**.
The moment `ChoiceList` calls it, `resource_changed`/`flag_changed` and then
`event_changed` (or `journey_ended`) fire and every component re-renders — all before
`process_choice` returns. The kit uses that to its advantage: it hides the swap under
a transition cover.

## Sequencing against `process_choice`

`JourneyChoiceList` is the sole orchestrator (it's also the only caller of
`process_choice`). On a button press:

```text
press
  │  lock input
  ├─ await transition.play_out()        # cover the view (fade / wipe)
  │
  ├─ JourneyRuntime.process_choice()    # SYNCHRONOUS:
  │     → resource_changed / flag_changed  (HUD updates, under the cover)
  │     → event_changed                    (narrative, choices, background, audio
  │                                          all re-render, under the cover)
  │
  ├─ await transition.play_in()         # lift the cover onto the new content
  └─ entrance animation → unlock input  # buttons fade/stagger in; input re-enabled
```

If no `TransitionLayer` is assigned it degrades gracefully to
`lock → process_choice → entrance → unlock`: the new content simply animates in
without a cover. Either way the engine is none the wiser — it did its one synchronous
step and returned; the kit spent the surrounding time animating.

Entrance, idle, and crossfade animations are **independent** per component and need
no orchestration — only the exit/transition ordering does, because only the
`process_choice` caller knows a change is about to happen.

## Tuning

Most knobs are exported on `JourneyStageView` (and on each component for standalone use):

- **Reveal** — `reveal_mode` (`INSTANT`/`FADE`/`TYPEWRITER`), `reveal_duration`.
- **Transition** — `transition_kind` (`FADE`/`WIPE`/`NONE`), `transition_duration`.
- **Choices** — `entrance_duration`, `entrance_stagger`.
- **Background idle** — `background_idle_motion`, plus `idle_zoom` / `idle_drift` /
  `idle_period` on the layer.

Set `transition_kind = NONE` and `reveal_mode = INSTANT` for a snappy, motion-free UI;
turn them up for a slower, atmospheric feel.

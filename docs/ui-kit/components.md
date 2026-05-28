# UI Kit — Components

Every component is an independent `Control`/`Node` that connects to `JourneyRuntime`
signals in its own `_ready()`. You can use any one alone, or let `JourneyView`
assemble them. They never reference each other except for the few collaborator
hooks noted below, which `JourneyView` wires for you.

| Class | Base | Subscribes to |
| --- | --- | --- |
| `JourneyView` / `JourneyStageView` | `Control` | *(assemblers; start the journey)* |
| `JourneyNarrativePanel` | `PanelContainer` | `event_changed` |
| `JourneyChoiceList` | `BoxContainer` | `event_changed`, `journey_ended` |
| `JourneyForegroundLayer` | `Control` | `event_changed` |
| `JourneyResourceHud` | `HBoxContainer` | `journey_started`, `resource_changed`, `event_changed` |
| `JourneySaveLoadBar` | `HBoxContainer` | *(button-driven)* |
| `JourneyEndingOverlay` | `Control` | `journey_ended`, `journey_started` |
| `JourneyBackgroundLayer` | `Control` | `event_changed` |
| `JourneyAudioLayer` | `Node` | `event_changed` |
| `JourneyTransitionLayer` | `Control` | *(driven by `ChoiceList`; optional `event_changed`)* |

## JourneyNarrativePanel

Renders `event.narrative_text` and owns the **text-reveal pacing**.

- `reveal_mode` — `INSTANT`, `FADE`, or `TYPEWRITER` (reveals characters via
  `RichTextLabel.visible_ratio`).
- `reveal_duration`, `reveal_easing`, `reveal_transition`.
- Emits `reveal_finished` when the reveal completes.

## JourneyChoiceList

Builds a `Button` per choice from the **already-filtered** `choices` array and is the
**only caller of `process_choice`** in the kit. It owns the input lock during a
transition.

- `entrance_duration`, `entrance_stagger` — staggered fade-in of the buttons.
- `vertical_layout` — stack choices vertically (default; reading layout) or lay them
  out as a horizontal button row (`false`; stage layout).
- Collaborators (set by an assembler or via `NodePath`): `transition_layer`,
  `audio_layer`.
- On press it runs the [transition sequence](animations.md#sequencing-against-process_choice);
  on `journey_ended` it clears and locks.

## JourneyResourceHud

A configurable read-out driven by `bindings: Array[JourneyHudBinding]` — no resource
names are hardcoded. See [Install → HUD bindings](install.md#hud-bindings).

- Full repaint on `journey_started` and on `repaint()` (used after a load).
- A single label update on `resource_changed` (optional count-up via `animate_changes`).
- Metadata bindings (e.g. `turn_counter`) refresh on `event_changed`, since the
  engine changes metadata without a per-value signal.

## JourneySaveLoadBar

Save / Load / Restart buttons calling `save_game` / `load_game` /
`start_new_journey`.

- `config`, `seed`, `save_slot`; `show_save` / `show_load` / `show_restart`.
- Emits `loaded` after a successful `load_game` so the HUD repaints — load
  bulk-restores the Blackboard and fires **no** `resource_changed` signals (see
  [Save & Load](../guides/save-and-load.md)). `event_changed` *does* re-fire, so
  narrative, choices, and background rebuild for free.
- Emits `status(message)` for an optional toast (`JourneyView` shows one).

## JourneyEndingOverlay

Hidden until `journey_ended`, then fades in with the ending event's text and a
"Begin again" button; hides again on `journey_started`. Restarts via its `config`,
and also emits `restart_requested` if you prefer to drive the restart yourself.

## JourneyBackgroundLayer

Displays `event.background_texture` and **crossfades** between events; a null payload
crossfades to `default_texture` (a placeholder ships with the kit). Optional **idle
motion** — a slow looping zoom/drift (`idle_zoom`, `idle_drift`, `idle_period`) — keeps
a static image alive.

## JourneyForegroundLayer

Stages foreground character sprite(s) in front of the background — the visual focus
of the [stage view](stage-view.md). On `event_changed` it resolves staging for the
event from a `JourneyStageBook` (sprite[s], anchors, speaker, entrance), animates the
sprite(s) in (`FADE`/`SLIDE_UP`/`SLIDE_SIDE`), and applies a subtle idle bob. No
staging entry → no sprite. Emits `staged(speaker)` so the view can show a speaker
line. Reads only the inert event payload. See [Stage view](stage-view.md) for the
data shape.

## JourneyAudioLayer

Plays `event.ambient_audio` **looped** with a crossfade between events, and exposes
**UI SFX slots** (`sfx_button_hover`, `sfx_button_press`, `sfx_choice_confirm`,
`sfx_save`, `sfx_load`, `sfx_ending`). All slots are empty by default — a missing
stream is a silent no-op. See [Assets & customization](assets-customization.md).

## JourneyTransitionLayer

A full-view scene transition — `FADE` (through a color), `WIPE`, or `NONE` — exposing
two await-able halves, `play_out()` and `play_in()`. `ChoiceList` drives these around
the `process_choice` call; see [Animations](animations.md).

## JourneyView / JourneyStageView

The assemblers. Each instantiates and lays out the components above, applies a default
`Theme` (cascades to every child), forwards its exported config/animation/SFX values,
wires the collaborator references, and — with `autostart` — calls `start_new_journey`.
These are the **only** places components reference one another.

- **`JourneyView`** — the text-forward *reading* layout (narrative column + side
  choices).
- **`JourneyStageView`** — the visual-first layout (background + foreground sprite
  focus; HUD bar, dialogue strip, horizontal choice row). Adds a `stage_book` export.
  See [Stage view](stage-view.md).

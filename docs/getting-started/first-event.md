# Author Your First Event (with the UI Kit)

!!! tip "New here, and not a programmer? Start on this page"
    This is the **no-code** path: you'll build a complete event entirely in the
    Godot inspector. You don't need the [Quick Start](quick-start.md)'s GDScript
    at all.

The [Quick Start](quick-start.md) built a journey in code to show the engine
loop. This page is the **real authoring workflow**: you create one event entirely
as inspector resources — **no code** — and watch the UI Kit present it. By the
end you'll have configured everything a single event touches:

- the event itself (narrative + a stable id),
- its **background** image and **ambient audio**,
- its **choices** and the **consequences** they apply,
- how it joins the **stochastic pool**,
- and which **sprite** appears, **where**, and **how it animates in**.

!!! note "Before you start"
    Install both halves first: the
    [core engine](installation.md) (enable its plugin — that registers the
    `JourneyRuntime` autoload) and the [UI Kit](../ui-kit/install.md) (just copy
    the folder). This walkthrough also assumes the bundled `sample_game/` is in
    your project, because we'll build on its config, pool, and demo scene.

## What we're building

We'll author the sample's **bandit encounter** — a random "road" event. It's a
good teaching example because it exercises every system at once:

```text
evt_road_bandit  (a pool event, tagged "road")
├─ "Two bandits step out from the trees, knives drawn."   ← narrative
├─ background image + ambient audio                       ← presentation (on the event)
├─ choice: "Pay them off (-30 gold)."   shown only if gold ≥ 30
├─ choice: "Fight them off (-15 sanity)."
└─ a Bandit sprite, entering from the left                ← staging (in the stage book)
```

Everything below matches the shipped `sample_game/pool/evt_road_bandit.tres` and
`sample_game/stage_book.tres`, so you can open those side by side to check your work.

## 1. Create the event

In the **FileSystem** dock, right-click your pool folder
(`res://sample_game/pool/`) → **Create New… → Resource → `JourneyEvent`**. Name it
`evt_road_bandit.tres`. In the Inspector set:

| Field | Value | Why |
| --- | --- | --- |
| `narrative_text` | *"Two bandits step out from the trees, knives drawn."* | The body text your UI shows. |
| `id` | `evt_road_bandit` | A **stable, unique** name. Saves and the pool index key off it — never leave it blank. |

That's a complete (if empty-handed) event already. The remaining steps add its
presentation and choices.

!!! tip "These are just `.tres` files"
    Every Journey type is a Godot `Resource`, so it appears in **Create New
    Resource** and edits like any built-in. You never write code to author
    content. The full field reference lives in
    [Resources & Events](../concepts/resources-and-events.md#journeyevent).

## 2. Set the background and ambient audio

These two live **on the event** (the UI Kit's
[`JourneyBackgroundLayer`](../ui-kit/components.md) and `JourneyAudioLayer` read
them straight off it):

- **`background_texture`** — drag in any `Texture2D`. The kit ships three
  placeholders under
  `addons/journey_engine_ui_kit/assets/backgrounds/` (`placeholder_dawn`,
  `placeholder_dusk`, `placeholder_night`) — use `placeholder_dusk.tres` for a
  tense roadside mood. Leave it empty and the background simply crossfades to the
  view's default.
- **`ambient_audio`** — an `AudioStream` looped while the event is shown. The kit
  ships **no audio** (see `assets/sfx/README.md`), so point this at a sound you
  import yourself, or leave it empty for silence.

!!! info "Why these are on the event, not the stage book"
    Text, background, and ambient audio are the event's own payload. The **stage
    book** (Step 5) only handles foreground **sprites and the speaker name**.
    Knowing which knob lives where is half the battle — see
    [Stage view](../ui-kit/stage-view.md#staging-events-the-stage-book).

## 3. Add the choices and their consequences

Size the event's **`choices`** array to `2` and create a `JourneyChoice` in each.

### Choice A — "Pay them off", but only if you can afford it

1. `button_text` → *"Pay them off (-30 gold)."*
2. **Gate it.** Set `visibility` to a new `JourneyConditionGroup`, add one
   `JourneyCondition`: `key = "gold"`, `op = GTE`, `value = 30`. Now the choice
   only appears when the player has at least 30 gold — the engine filters it out
   otherwise, so your UI never sees it. (Null visibility ⇒ always shown.)
3. **Apply consequences.** Size `consequences` to `2`:
    - `JourneyConsequence`: `operation = SUBTRACT`, `key = "gold"`, `value = 30`
    - `JourneyConsequence`: `operation = ADD` (the default), `key = "road_progress"`, `value = 10`
4. **Route it.** Tick `continue_to_pool = true` and set `pool_tags_filter = ["road"]` —
   after paying, draw the next random road event.

### Choice B — "Fight them off"

Same shape, no gate: `button_text` → *"Fight them off (-15 sanity)."*, consequences
`SUBTRACT 15 sanity` + `ADD 10 road_progress`, and the same
`continue_to_pool` / `["road"]` routing.

!!! tip "Enum fields are dropdowns"
    `operation`, `op`, and `logic` show as named dropdowns in the inspector — you
    pick `SUBTRACT`, not a number. (The raw integers only appear in the `.tres`
    text.) Full enum tables: [Resources & Events](../concepts/resources-and-events.md#journeyconsequence).

How a choice decides what happens next — boundary routes, `target_event`, the
pool, or ending — is the [Routing precedence](../concepts/routing.md#routing-precedence).

## 4. Make it a pool event

This event has no fixed predecessor — it's pulled at random. Three things make
that work, and you've nearly done them already:

1. **Location.** The file lives under the config's `event_pool_dir`
   (`res://sample_game/pool/`). The engine scans that folder on the first pull.
2. **Tags.** Set `event_tags = ["road", "danger"]`. A `continue_to_pool` choice
   filtering on `["road"]` (like the two above) can now draw this event.
3. **Selection knobs.** Set `weight = 200` (twice the default `100`, so bandits
   are common) and `repeatable = true` (it can recur across a run).

!!! tip "Iterating on pool events"
    Adding or editing pool files while the game runs? Call
    `JourneyRuntime.rebuild_pool()` to re-scan from disk. The full mechanics —
    candidate filtering, weighting, and determinism — are in the
    [Stochastic Pool guide](../guides/stochastic-pool.md#how-a-candidate-is-selected).

## 5. Stage the sprite (the stage book)

Foreground sprites and the speaker name are **presentation direction**, so they
live in a separate `JourneyStageBook` keyed by `event.id` — not on the event.
The sample's is `sample_game/stage_book.tres`. Open it and add an entry:

1. Grow its `entries` array and add a `JourneyStageEntry`:
    - `event_id` → `evt_road_bandit` (must match the event's `id` exactly)
    - `speaker` → `"Bandit"` (shown as the speaker line; empty ⇒ no speaker)
2. In that entry, add one `JourneySpritePlacement` to `sprites`:

    | Field | Value | Effect |
    | --- | --- | --- |
    | `texture` | `placeholder_figure_a.tres` | The sprite image. |
    | `anchor` | `LEFT` | Stands on the left; vertical sits on the floor. |
    | `enter` | `SLIDE_SIDE` | Slides in from the side. |
    | `flip_h` | `true` | Faces inward. |
    | `height_ratio` | `0.7` | 70% of the view height. |

That's it — keying by the stable `id` means staging never breaks across saves,
and an event with **no** entry simply shows no sprite (staging is fully optional).
The `sprites` array takes **multiple** placements for multi-character scenes. See
[Stage view](../ui-kit/stage-view.md#staging-events-the-stage-book) and the entrance/idle
options in [Animations](../ui-kit/animations.md).

## 6. Run it

The demo scene `res://sample_game/journey_stage_demo.tscn` is the project's main
scene, so press **F5**. Travel the road (your bandit event is common and
repeatable), and you'll see every piece you configured land in its place:

```text
┌───────────────────────────────┐
│ ♦ gold  ♥ sanity  …   [S][L][R]│  HUD ← your consequences move these
│            ╱▔▔╲                │
│   sprite ▶(  ◕ )                │  stage book → Bandit, left, slid in
│ Bandit:                        │  speaker ← stage book
│ "Two bandits step out…"        │  narrative ← the event
│ [Pay them off][Fight them off] │  choices ← the event (Pay hidden if gold < 30)
└───────────────────────────────┘
```

If a choice you expected is missing, its `visibility` is failing right now (try
the "Pay them off" choice with under 30 gold) — that's the engine filtering, not
a bug. The kit can also show such choices **locked/greyed** instead of hidden; see
[Locked choices](../ui-kit/stage-view.md#locked-choices).

!!! tip "Catch mistakes before you run"
    In a debug build, call `JourneyRuntime.validate(config)` to flag typos like an
    undeclared resource key, a duplicate `id`, or an unfinished choice — pure
    inspection, no run needed. See [Validation](../guides/validation.md).

## Where each piece lives — the one-screen summary

| To change… | Edit… |
| --- | --- |
| narrative text, background image, ambient audio | the **`JourneyEvent`** |
| which choices exist, what they cost, where they route | the event's **`JourneyChoice`** list |
| whether/how the event appears at random | the event's **pool fields** + its folder (`event_pool_dir`) |
| the character sprite, its position, entrance, and speaker name | the **`JourneyStageBook`** entry |
| HUD rows, theme, transition style, SFX | the **`JourneyStageView`** in your scene ([install](../ui-kit/install.md#hud-bindings)) |

## Where to go next

- **Branch on earlier choices.** Set a flag in one event and gate a later choice
  or whole event on it — [Authoring Content → flag chains](../guides/authoring-content.md).
- **Reskin it.** Swap the theme, fonts, and placeholder art —
  [Assets & customization](../ui-kit/assets-customization.md).
- **Different layout.** The stage view is just assembled components; rearrange
  them in your own scene — [Components](../ui-kit/components.md).
- **Persist runs.** Wire Save / Load — [Save & Load](../guides/save-and-load.md).

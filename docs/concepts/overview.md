# Concepts Overview

Journey Engine models a **run**: a player moving from event to event, making
choices that change a small bundle of state, until the journey ends. This page
gives you the mental model and the data-flow loop; the rest of this section
drills into each piece.

## The mental model

Five ideas carry the whole engine:

- **[Blackboard](blackboard.md)** — all mutable run state in one object: numeric
  resources, boolean flags, free-form metadata, and a seeded RNG.
- **[Resources & Events](resources-and-events.md)** — the authorable data.
  `JourneyResourceDef` declares a bounded number (gold, sanity…); `JourneyEvent`
  is a narrative node with `JourneyChoice`s; conditions gate, consequences mutate.
- **[Routing](routing.md)** — how a choice decides the next event: forced
  boundary routes, then deterministic targets, then a stochastic pool pull, then
  end-of-journey.
- **Single mutation path** — game code *never* writes the Blackboard directly.
  Every state change flows through a choice's consequences applied by the runtime.
- **[Presentation contract](presentation-contract.md)** — the core never touches
  your UI. It emits signals; your UI listens. You own all rendering and pacing.

## The data-flow loop

Everything the engine does is this loop. The player sees an event, picks a
choice, the engine mutates state and routes, and a new event is emitted.

```text
                    start_new_journey(config, seed)
                                 │
                                 ▼
                      ┌────────────────────┐
                      │  Blackboard.init   │  resources@defaults, flags,
                      │  (clamped, seeded) │  rng seeded, metadata primed
                      └────────────────────┘
                                 │
              ┌──────────────────┴───────────────────────┐
              │              _enter_event                 │
              │  • bump turn / history / seen_ids         │
              │  • filter choices by visibility           │
              └──────────────────┬───────────────────────┘
                                 │ emits
                                 ▼
                   ◇ signal: event_changed(event, visible_choices)
                                 │
                    ┌────────────┴────────────┐
                    │  YOUR UI (signals only)  │  renders narrative + buttons,
                    │  owns all pacing         │  owns reveal timing / input lock
                    └────────────┬────────────┘
                                 │ player clicks a choice
                                 ▼
                    JourneyRuntime.process_choice(choice)
                                 │
              ┌──────────────────┴───────────────────────┐
              │   apply consequences (Mutator, clamped)   │
              │   ◇ resource_changed / flag_changed       │  (per actual change,
              │   detect boundary transitions             │   post-clamp values)
              └──────────────────┬───────────────────────┘
                                 │ routing precedence (§ Routing)
                                 ▼
        forced boundary route ? ──▶ deterministic target ? ──▶ pool pull ? ──▶ end
                                 │                                              │
                                 └───────────────▶ _enter_event ◀──────────────┘
                                                       │
                                                       ▼
                                  (loop) OR ◇ signal: journey_ended(ending_event)
```

Read it as a cycle: each `event_changed` waits for your UI to call
`process_choice`, which applies state changes and decides where to go next —
either re-entering the loop with a new `event_changed`, or emitting
`journey_ended`.

## Design principles you'll feel

These invariants hold at every step and explain a lot of the engine's behavior:

- **Studio-authorable.** Every data type is a Godot `Resource` fully editable in
  the inspector — no code required to write content.
- **Deterministic.** A fixed RNG seed plus identical state always produces
  identical stochastic results. This is what makes [save/load](../guides/save-and-load.md)
  resume the *exact* run.
- **Presentation-agnostic core.** Nothing in `journey_core/` instantiates a Node
  or assumes a UI. The runtime is a Node only because Autoloads must be.
- **Loud about author mistakes.** Missing keys, undeclared resources, and empty
  pools surface as warnings/errors rather than silent no-ops. The
  [validator](../guides/validation.md) catches most of these before runtime.

Next: start with the [Blackboard](blackboard.md), the state every other concept
reads and writes.

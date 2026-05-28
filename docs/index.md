# Journey Engine

Journey Engine is a **presentation-agnostic narrative-journey runtime for Godot
4 / GDScript**. You author your story as Godot resources — events, choices,
conditions, consequences — and the engine handles state, routing, randomness,
and saves. It never touches your UI, so you keep full control of how the journey
looks and feels.

!!! abstract "What you'll build"
    A run-based, choice-driven journey: the player moves event to event, each
    choice mutates bounded resources (gold, sanity, rations…) and flips flags,
    and the engine routes to the next event — deterministically by design, or by
    pulling a weighted random event from a tagged pool. Saves resume the exact
    run, including the random stream. Your UI just listens to signals.

[Get Started](getting-started/installation.md){ .md-button .md-button--primary }
[Concepts](concepts/overview.md){ .md-button }
[API Reference](reference/api.md){ .md-button }

# The Presentation Contract

Journey Engine's core is **presentation-agnostic**. No class in `journey_core/`
instantiates a Node, adds children, touches the SceneTree, or assumes a UI
exists. This is a hard invariant, and it shapes how you integrate the engine.

## The contract

!!! abstract "What the engine promises — and expects"
    - **The engine never reaches into your UI.** It does not create labels,
      buttons, or scenes. Its only output is **signals**, and the data inside
      those signals is inert (events, choice arrays, primitives).
    - **You drive the engine with one call.** All player input flows back through
      `process_choice(choice)`. That is the single write path.
    - **You own all rendering and pacing.** The engine advances *only* when you
      call `process_choice`. It never blocks, waits, animates, or gates input.

`JourneyRuntime` is a `Node` purely because Godot Autoloads must be Nodes — not
because it does anything in the scene tree. It must not be given children or
asked to render.

## The signal bus

Your UI subscribes to six signals. Treat them as the complete API surface for
"what is happening in the journey":

| Signal | Fires when |
| --- | --- |
| `journey_started()` | A new journey begins (before the first event). |
| `event_changed(event, choices)` | A new event is entered. `choices` is already visibility-filtered. |
| `resource_changed(key, old, new)` | A resource changed value (post-clamp). |
| `flag_changed(key, value)` | A flag changed value. |
| `journey_ended(ending_event)` | A terminal choice ended the run. |
| `journey_error(message)` | A recoverable problem (empty pool, null route, bad call). |

Exact parameter types are in the [API Reference](../reference/api.md#signals).

## "Dumb UI": render what you're handed

The intended pattern is a **Dumb UI** — independent listeners that render exactly
what the signals deliver and never inspect engine internals or the Blackboard
directly.

```gdscript
func _on_event_changed(event: JourneyEvent, choices: Array[JourneyChoice]) -> void:
    _set_narrative(event.narrative_text)
    for choice in choices:                 # already filtered — don't re-check visibility
        var btn := Button.new()
        btn.text = choice.button_text
        btn.pressed.connect(_on_choice_pressed.bind(choice))
        _choices_box.add_child(btn)

func _on_choice_pressed(choice: JourneyChoice) -> void:
    JourneyRuntime.process_choice(choice)  # the only write into the engine
```

Two consequences of the contract worth internalizing:

- **Choice filtering lives in the engine.** `event_changed` hands you only the
  choices whose `visibility` passes *right now*. Every front end gets identical
  filtering for free — never re-implement it in the UI.
- **Reads go through the public accessors.** For HUD values, call
  `get_resource(key)`, `has_flag(key)`, `get_metadata(key)` — never read
  `JourneyRuntime.blackboard.*` directly. (See [Blackboard](blackboard.md).)

## You own pacing

Because the engine advances only on `process_choice`, *you* decide the tempo. A
typical pattern: fade the narrative in over a fraction of a second and keep the
choice buttons disabled until the reveal finishes. The engine doesn't care that
buttons aren't shown yet — it isn't waiting on anything.

```gdscript
func _on_event_changed(event: JourneyEvent, choices: Array[JourneyChoice]) -> void:
    _set_narrative(event.narrative_text)
    _lock_input(true)                      # UI-owned input gate
    var tween := create_tween()
    tween.tween_property(_narrative, "modulate:a", 1.0, 0.25)
    tween.tween_callback(func() -> void:
        _populate_choices(choices)
        _lock_input(false))
```

This pattern is exactly what the bundled `sample_game/` uses. Because the engine
never blocks, a player clicking during the fade is handled client-side (ignored
until the reveal finishes) — the engine is none the wiser.

## After a load, repaint manually

Loading a save bulk-restores the Blackboard rather than mutating it through
consequences, so **no** `resource_changed` signals fire for the restored values.
Your load handler should repaint the HUD by reading the public accessors:

```gdscript
func _refresh_hud_full() -> void:
    _gold_label.text = "Gold: %d" % int(JourneyRuntime.get_resource("gold"))
    _sanity_label.text = "Sanity: %d" % int(JourneyRuntime.get_resource("sanity"))
```

`event_changed` *does* re-fire on load (so your narrative and choices rebuild
automatically) — it's only the per-resource signals that don't. See
[Save & Load](../guides/save-and-load.md).

See also: [Concepts Overview](overview.md) for the full data-flow loop ·
[API Reference](../reference/api.md) for exact signatures.

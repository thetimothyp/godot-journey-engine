# Quick Start

!!! tip "Not a coder? You may want the other path"
    This page builds the journey in **GDScript** to show the engine loop. If your
    goal is to **build a game without writing code**, skip to
    **[Author Your First Event](first-event.md)** — the same engine, authored
    entirely in the inspector.

This page takes you from an empty project to a **clickable two-event journey**
running in the editor. Every snippet is copy-pasteable and uses the real engine
API. To keep it self-contained and reproducible, we build the content in code;
in a real game you'd author the same data as `.tres` resources in the inspector
(see [Authoring Content](../guides/authoring-content.md)).

!!! note "Before you start"
    Complete [Installation](installation.md) first — in particular, the
    `addons/journey_engine_core/` files must be in your project and the **`JourneyRuntime`**
    Autoload must be registered. Nothing below works without that Autoload.

## The plan

A tiny journey with two events:

```
evt_start ──"Take the gold"──▶ (gold +50) ──▶ evt_road
evt_start ──"Leave it"──────▶ (sanity +5) ──▶ evt_road
evt_road  ──"Rest here"─────▶ end journey
```

## 1. Create the scene

Make a new scene with a **Control** root, add a **VBoxContainer** child named
`UI`, and attach the script below to the Control root. Save the scene (e.g.
`res://quickstart.tscn`) and set it as the main scene, or just run it with
**F6**.

## 2. The script

This single script builds the config and events, starts the journey, and renders
it. It writes the engine's data types directly so you can see exactly what each
field does.

```gdscript
extends Control

@onready var _ui: VBoxContainer = $UI

# Events built in code, collected so we can hand them to the runtime to index.
var _events: Array[JourneyEvent] = []

func _ready() -> void:
    # 1. Subscribe to the engine's signals (the only way the engine talks back). (1)
    JourneyRuntime.event_changed.connect(_on_event_changed)
    JourneyRuntime.resource_changed.connect(_on_resource_changed)
    JourneyRuntime.journey_ended.connect(_on_journey_ended)
    JourneyRuntime.journey_error.connect(func(msg): push_error(msg))

    # 2. Build the journey content (normally authored as .tres in the inspector).
    var config := _build_config()

    # 3. Start. Routing is by id against an event index; here we pass our events
    #    in memory (a real game points config.events_dir at a folder of .tres
    #    instead). The fixed seed makes random pulls reproducible across runs. (2)
    JourneyRuntime.start_new_journey(config, 12345, _events)

# --- Content (built in code here; author as .tres resources in real projects) ---

func _build_config() -> JourneyConfig:
    # Two resources with bounds + defaults. Mutations are clamped to [min, max].
    var gold := JourneyResourceDef.new()
    gold.key = "gold"
    gold.default_value = 0.0
    gold.min_value = 0.0
    gold.max_value = 999.0

    var sanity := JourneyResourceDef.new()
    sanity.key = "sanity"
    sanity.default_value = 50.0
    sanity.min_value = 0.0
    sanity.max_value = 100.0

    # The second event, reached deterministically from the first.
    var road := JourneyEvent.new()
    road.id = &"evt_road"
    road.narrative_text = "The crossroads is behind you. The road runs on."
    var rest := JourneyChoice.new()
    rest.button_text = "Rest here. (ends the journey)"
    # Empty target_event_id, no continue_to_pool, no consequences => terminal choice.
    road.choices = [rest]

    # The opening event with two choices, both routing to `road`.
    var start := JourneyEvent.new()
    start.id = &"evt_start"
    start.narrative_text = "A coin purse lies in the dust at the crossroads."

    var take := JourneyChoice.new()
    take.button_text = "Take the gold. (+50 gold)"
    take.consequences = [_add("gold", 50.0)]
    take.target_event_id = &"evt_road"            # deterministic route, by id

    var leave := JourneyChoice.new()
    leave.button_text = "Leave it. (+5 sanity)"
    leave.consequences = [_add("sanity", 5.0)]
    leave.target_event_id = &"evt_road"

    start.choices = [take, leave]

    # Collect the events so start_new_journey can index them by id.
    _events = [start, road]

    var config := JourneyConfig.new()
    config.resource_defs = [gold, sanity]
    config.start_event_id = &"evt_start"
    return config

func _add(key: String, amount: float) -> JourneyConsequence:
    var c := JourneyConsequence.new()
    c.operation = JourneyConsequence.Operation.ADD
    c.key = key
    c.value = amount
    return c

# --- Signal handlers (your "Dumb UI") ---

func _on_event_changed(event: JourneyEvent, choices: Array[JourneyChoice]) -> void:
    # event_changed delivers the event AND the already-visibility-filtered
    # choices — render exactly what you're handed. (3)
    for child in _ui.get_children():
        child.queue_free()

    var label := Label.new()
    label.text = event.narrative_text
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _ui.add_child(label)

    for choice in choices:
        var btn := Button.new()
        btn.text = choice.button_text
        btn.pressed.connect(_on_choice.bind(choice))
        _ui.add_child(btn)

func _on_choice(choice: JourneyChoice) -> void:
    # The single write path: hand the chosen JourneyChoice back to the engine. (4)
    JourneyRuntime.process_choice(choice)

func _on_resource_changed(key: String, old_value: float, new_value: float) -> void:
    print("%s: %s -> %s" % [key, old_value, new_value])

func _on_journey_ended(ending_event: JourneyEvent) -> void:
    for child in _ui.get_children():
        child.queue_free()
    var label := Label.new()
    label.text = "The journey ends at '%s'." % String(ending_event.id)
    _ui.add_child(label)
```

1. The runtime never reaches into your scene. All output is signals; all input is
   `process_choice`. This is the [Presentation Contract](../concepts/presentation-contract.md).
2. Pass `0` (the default) instead to randomize the seed each run. A fixed seed
   means identical state + identical choices reproduce identical random pulls —
   the basis of [save/load determinism](../guides/save-and-load.md).
3. `event_changed` hands you only the choices whose `visibility` condition group
   passes right now. You never filter choices yourself — the engine does it so
   every UI behaves identically.
4. `process_choice` applies the choice's consequences (clamped), emits
   `resource_changed` / `flag_changed` for what actually changed, then routes to
   the next event. See [Routing](../concepts/routing.md).

## 3. Run it

Press **F6**. You should see the opening narrative and two buttons. Clicking
either prints the resource change to the Output panel, advances to the second
event, and the **Rest here** button ends the journey.

That's the entire loop: `start_new_journey` → render `event_changed` →
`process_choice` → render the next `event_changed` → `journey_ended`.

## Where to go next

- **Author content properly.** Building events in code gets tedious fast. The
  intended workflow is authoring `.tres` resources in the inspector —
  see [Authoring Content](../guides/authoring-content.md).
- **Understand the moving parts.** Read the [Concepts overview](../concepts/overview.md)
  for the mental model and data-flow loop.
- **Add randomness.** Route a choice into a weighted, tagged event pool with the
  [Stochastic Pool guide](../guides/stochastic-pool.md).
- **Persist runs.** Wire up [Save & Load](../guides/save-and-load.md).
- **Full API.** Every method and signal is in the [API Reference](../reference/api.md).

extends Control

## Throwaway dumb-UI for Step 4: a Label (narrative) and a VBoxContainer (choice
## buttons), wired to JourneyRuntime signals only. Lives in tests/ — core stays
## presentation-agnostic (§5.5). Demonstrates the Dumb-UI contract from §4.1:
## the UI never reads or writes the Blackboard, it only subscribes to signals
## and calls process_choice on the choice instances handed back to it.
##
## Step 6 additions (transient test scaffolding):
##   S — save to slot "test"
##   L — load from slot "test"
## Save prints the serialize() dict so primitives-only shape can be confirmed
## without parsing the binary .dat file.

const TEST_CONFIG_PATH := "res://tests/test_config.tres"
const SEED := 12345
const SAVE_SLOT := "test"

@onready var _narrative: Label = $Layout/Narrative
@onready var _choices: VBoxContainer = $Layout/Choices
@onready var _log: Label = $Layout/Log

func _ready() -> void:
	JourneyRuntime.event_changed.connect(_on_event_changed)
	JourneyRuntime.resource_changed.connect(_on_resource_changed)
	JourneyRuntime.flag_changed.connect(_on_flag_changed)
	JourneyRuntime.journey_started.connect(_on_journey_started)
	JourneyRuntime.journey_ended.connect(_on_journey_ended)
	JourneyRuntime.journey_error.connect(_on_journey_error)

	var config: JourneyConfig = load(TEST_CONFIG_PATH)
	if config == null:
		push_error("game_view: could not load %s" % TEST_CONFIG_PATH)
		return
	JourneyRuntime.start_new_journey(config, SEED)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: InputEventKey = event
	if k.keycode == KEY_S:
		_save()
	elif k.keycode == KEY_L:
		_load()

func _save() -> void:
	# Print the serialize() output so the primitives-only shape can be inspected
	# without parsing the binary user://test.dat. (Step-6 manual test point 3.)
	# save_version is a constant of the test config; using 1 here just for the
	# print preview — the actual save uses config.save_version internally.
	var dict: Dictionary = JourneySaveManager.serialize(JourneyRuntime.blackboard, 1)
	print("[save] serialized preview: %s" % dict)
	print("[save] rng.state pre-save = %d" % JourneyRuntime.blackboard.rng.state)
	var err: int = JourneyRuntime.save_game(SAVE_SLOT)
	print("[save] err=%d slot=%s path=user://%s.dat" % [err, SAVE_SLOT, SAVE_SLOT])
	_log.text = "Saved (err=%d)" % err

func _load() -> void:
	var err: int = JourneyRuntime.load_game(SAVE_SLOT)
	print("[load] err=%d slot=%s rng.state post-load = %d" % [
		err, SAVE_SLOT, JourneyRuntime.blackboard.rng.state])
	_log.text = "Loaded (err=%d)" % err

# --- Signal handlers ---

func _on_event_changed(event: JourneyEvent, choices: Array[JourneyChoice]) -> void:
	var turn: int = int(JourneyRuntime.get_metadata("turn_counter"))
	var cur_id: String = str(JourneyRuntime.get_metadata("current_event_id"))
	# Full state snapshot per event_changed makes round-trip / RNG-continuity
	# comparison straightforward for the Step-6 manual test.
	print("[event_changed] id=%s turn=%d visible_choices=%d resources=%s flags=%s" % [
		cur_id, turn, choices.size(),
		JourneyRuntime.blackboard.resources, JourneyRuntime.blackboard.flags])
	_narrative.text = event.narrative_text
	for child in _choices.get_children():
		child.queue_free()
	for choice in choices:
		var btn := Button.new()
		btn.text = choice.button_text
		btn.pressed.connect(_on_choice_pressed.bind(choice))
		_choices.add_child(btn)

func _on_choice_pressed(choice: JourneyChoice) -> void:
	print("[choice_pressed] %s" % choice.button_text)
	JourneyRuntime.process_choice(choice)

func _on_resource_changed(key: String, old_value: float, new_value: float) -> void:
	print("[resource_changed] %s: %s → %s" % [key, old_value, new_value])

func _on_flag_changed(key: String, value: bool) -> void:
	print("[flag_changed] %s = %s" % [key, value])

func _on_journey_started() -> void:
	print("[journey_started]")

func _on_journey_ended(ending_event: JourneyEvent) -> void:
	var label: String = "<null>" if ending_event == null else String(ending_event.id)
	print("[journey_ended] ending_event=%s" % label)
	for child in _choices.get_children():
		child.queue_free()
	_log.text = "Journey ended."

func _on_journey_error(message: String) -> void:
	print("[journey_error] %s" % message)
	_log.text = "Error: %s" % message

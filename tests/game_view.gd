extends Control

## Throwaway dumb-UI for Step 4: a Label (narrative) and a VBoxContainer (choice
## buttons), wired to JourneyRuntime signals only. Lives in tests/ — core stays
## presentation-agnostic (§5.5). Demonstrates the Dumb-UI contract from §4.1:
## the UI never reads or writes the Blackboard, it only subscribes to signals
## and calls process_choice on the choice instances handed back to it.

const TEST_CONFIG_PATH := "res://tests/test_config.tres"
const SEED := 12345

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

# --- Signal handlers ---

func _on_event_changed(event: JourneyEvent, choices: Array[JourneyChoice]) -> void:
	var turn: int = int(JourneyRuntime.get_metadata("turn_counter"))
	var cur_id: String = str(JourneyRuntime.get_metadata("current_event_id"))
	print("[event_changed] id=%s turn=%d visible_choices=%d" % [cur_id, turn, choices.size()])
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

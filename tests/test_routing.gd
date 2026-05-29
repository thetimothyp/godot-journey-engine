extends Node

## End-to-end routing integration test for id-based routing. Drives the sample
## game through the public JourneyRuntime API (no UI) and proves every routing
## kind resolves by id against the event index:
##   - start_event_id → evt_start
##   - deterministic target_event_id (the "help" choice) → evt_road_begins
##   - continue_to_pool pulls a pool-eligible event
##   - the journey reaches a terminal ending without any journey_error
##
## process_choice is synchronous (enter_event emits event_changed inline), so we
## capture the latest event/choices in signal handlers and drive a simple loop —
## no frame awaits. A fixed seed keeps the pool stream reproducible.

const SAMPLE_CONFIG := "res://sample_game/config.tres"
const SEED := 13371
const STEP_CAP := 300

var _failures: int = 0
var _event: JourneyEvent = null
var _choices: Array = []
var _ended: bool = false
var _ended_event: JourneyEvent = null
var _errors: Array[String] = []

func _ready() -> void:
	print("[test_routing] starting…")
	var config: JourneyConfig = load(SAMPLE_CONFIG)
	if config == null:
		push_error("test_routing: cannot load %s" % SAMPLE_CONFIG)
		_finish()
		return

	JourneyRuntime.event_changed.connect(_on_event_changed)
	JourneyRuntime.journey_ended.connect(_on_journey_ended)
	JourneyRuntime.journey_error.connect(_on_journey_error)

	JourneyRuntime.start_new_journey(config, SEED)

	_expect(_event != null and String(_event.id) == "evt_start",
		"start_event_id resolved to evt_start (got %s)" % (String(_event.id) if _event else "<none>"))

	# Deterministic route: take the choice whose target_event_id is evt_road_begins.
	var help_choice: JourneyChoice = null
	for c in _choices:
		if String(c.target_event_id) == "evt_road_begins":
			help_choice = c
			break
	_expect(help_choice != null, "found a choice targeting evt_road_begins by id")
	if help_choice != null:
		JourneyRuntime.process_choice(help_choice)
		_expect(_event != null and String(_event.id) == "evt_road_begins",
			"deterministic target_event_id routed to evt_road_begins (got %s)" % String(_event.id))

	# continue_to_pool: evt_road_begins' only choice pulls from the pool.
	var pre_pool_id := String(_event.id)
	if not _choices.is_empty():
		JourneyRuntime.process_choice(_choices[0])
	_expect(_event != null and String(_event.id) != pre_pool_id,
		"continue_to_pool pulled a new event (got %s)" % String(_event.id))
	_expect(_event != null and _event.pool_eligible,
		"the pulled event is pool_eligible")

	# Drive the rest to a terminal ending, always taking the first visible choice.
	var steps := 0
	while not _ended and steps < STEP_CAP:
		if _choices.is_empty():
			break
		JourneyRuntime.process_choice(_choices[0])
		steps += 1

	_expect(_ended, "journey reached a terminal ending within %d steps (took %d)" % [STEP_CAP, steps])
	_expect(_ended_event != null and String(_ended_event.id).begins_with("evt_end"),
		"ended on an ending event (got %s)" % (String(_ended_event.id) if _ended_event else "<none>"))
	_expect(_errors.is_empty(), "no journey_error during playthrough (got: %s)" % str(_errors))

	_finish()

func _on_event_changed(event: JourneyEvent, choices: Array[JourneyChoice]) -> void:
	_event = event
	_choices = choices

func _on_journey_ended(ending_event: JourneyEvent) -> void:
	_ended = true
	_ended_event = ending_event

func _on_journey_error(message: String) -> void:
	_errors.append(message)

func _finish() -> void:
	if _failures == 0:
		print("[test_routing] PASS (all checks)")
	else:
		print("[test_routing] FAIL: %d check(s) failed" % _failures)

func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("  [ok] %s" % msg)
	else:
		_failures += 1
		printerr("  [FAIL] %s" % msg)

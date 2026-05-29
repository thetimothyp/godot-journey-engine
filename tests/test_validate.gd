extends Node

## Programmatic test for JourneyValidator + JourneyRuntime.validate under
## id-based routing.
##
## Covers:
##   1. CLEAN: good test_config.tres (+ disk-built index) returns no errors
##   2. EMPTY START: start_event_id == "" → ERROR
##   3. BAD BOUNDS: min>max AND default-out-of-range → two ERRORs
##   4. TYPO RESOURCE KEY: condition + consequence on undeclared resource →
##      WARNINGs; HAS_FLAG / SET_FLAG references do NOT warn
##   5. DUPLICATE / EMPTY IDs: surfaced from the index build → ERRORs
##   6. DEAD CHOICE: no target id + no pool + no consequences → WARNING; adding
##      a consequence clears it
##   7. STABLE ORDER: two runs on the same input → identical message lists
##   8. RUNTIME FLATTENING: JourneyRuntime.validate → [ERROR]/[WARNING] strings
##   9. UNKNOWN IDS: start / target / boundary id that doesn't resolve → ERROR
##  10. CONTINUE_TO_POOL LOOP: an id-resolving loop-back via the pool → clean
##  11. DISK ROUND-TRIP: JourneyLoadCheck over the migrated test content → clean
##
## The CLEAN case loads the real test_config.tres and builds the index from the
## real tests/journey/ tree, so drift between fixture and validator is caught.

const TEST_CONFIG_PATH := "res://tests/test_config.tres"
const TEST_EVENTS_DIR := "res://tests/journey/"

var _failures: int = 0

func _ready() -> void:
	print("[test_validate] starting…")
	var clean_config: JourneyConfig = load(TEST_CONFIG_PATH)
	if clean_config == null:
		push_error("test_validate: cannot load %s" % TEST_CONFIG_PATH)
		_finish()
		return

	_test_clean(clean_config)
	_test_empty_start(clean_config)
	_test_bad_bounds(clean_config)
	_test_typo_resource_key(clean_config)
	_test_duplicate_and_empty_ids(clean_config)
	_test_dead_choice(clean_config)
	_test_stable_order(clean_config)
	_test_runtime_flattening(clean_config)
	_test_unknown_ids(clean_config)
	_test_pool_loop_validates_clean(clean_config)
	_test_disk_round_trip_tests()
	_finish()

func _finish() -> void:
	if _failures == 0:
		print("[test_validate] PASS (all checks)")
	else:
		print("[test_validate] FAIL: %d check(s) failed" % _failures)

func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("  [ok] %s" % msg)
	else:
		_failures += 1
		printerr("  [FAIL] %s" % msg)

# --- Tests ---

func _test_clean(config: JourneyConfig) -> void:
	print("[1] CLEAN config produces no errors")
	var index := JourneyEventIndex.new()
	index.build(TEST_EVENTS_DIR)
	var msgs: Array = JourneyValidator.validate(config, index)
	var errs: Array = JourneyValidator.errors_only(msgs)
	_expect(errs.is_empty(), "no errors on clean config (got %d: %s)" % [errs.size(), str(errs)])

func _test_empty_start(config: JourneyConfig) -> void:
	print("[2] EMPTY start_event_id → ERROR")
	var c: JourneyConfig = _shallow_copy(config)
	c.start_event_id = &""
	var msgs: Array = JourneyValidator.validate(c, _index([]))
	_expect(_has_message(msgs, JourneyValidator.SEVERITY_ERROR, "start_event_id is empty"),
		"error message names empty start_event_id (got: %s)" % _stringify(msgs))

func _test_bad_bounds(config: JourneyConfig) -> void:
	print("[3] BAD BOUNDS → two distinct ERRORs")
	var c: JourneyConfig = _shallow_copy(config)
	var bad_minmax := JourneyResourceDef.new()
	bad_minmax.key = "bad_minmax"
	bad_minmax.min_value = 100.0
	bad_minmax.max_value = 0.0
	bad_minmax.default_value = 0.0
	var bad_default := JourneyResourceDef.new()
	bad_default.key = "bad_default"
	bad_default.min_value = 0.0
	bad_default.max_value = 100.0
	bad_default.default_value = 500.0
	c.resource_defs = c.resource_defs.duplicate()
	c.resource_defs.append(bad_minmax)
	c.resource_defs.append(bad_default)
	var msgs: Array = JourneyValidator.validate(c, _index([]))
	_expect(_has_message(msgs, JourneyValidator.SEVERITY_ERROR, "bad_minmax"),
		"min>max error names 'bad_minmax'")
	_expect(_has_message(msgs, JourneyValidator.SEVERITY_ERROR, "bad_default"),
		"out-of-range default error names 'bad_default'")

func _test_typo_resource_key(config: JourneyConfig) -> void:
	print("[4] TYPO'D resource key warns; flag key does NOT warn")
	var c := JourneyConfig.new()
	c.resource_defs = config.resource_defs  # 'gold' / 'sanity' / 'rations' declared
	c.start_event_id = &"evt_typo_test"
	var ev := JourneyEvent.new()
	ev.id = &"evt_typo_test"
	var choice := JourneyChoice.new()
	choice.button_text = "Go"
	var vis_group := JourneyConditionGroup.new()
	var flag_cond := JourneyCondition.new()
	flag_cond.op = JourneyCondition.Op.HAS_FLAG
	flag_cond.key = "any_flag"
	var typo_cond := JourneyCondition.new()
	typo_cond.op = JourneyCondition.Op.GTE
	typo_cond.key = "goldd"
	typo_cond.value = 1.0
	vis_group.conditions = [flag_cond, typo_cond]
	choice.visibility = vis_group
	var bad_con := JourneyConsequence.new()
	bad_con.operation = JourneyConsequence.Operation.ADD
	bad_con.key = "manna"
	bad_con.value = 5.0
	var flag_con := JourneyConsequence.new()
	flag_con.operation = JourneyConsequence.Operation.SET_FLAG
	flag_con.key = "any_other_flag"
	flag_con.flag_value = true
	choice.consequences = [bad_con, flag_con]
	ev.choices = [choice]

	var msgs: Array = JourneyValidator.validate(c, _index([ev]))
	_expect(_has_message(msgs, JourneyValidator.SEVERITY_WARNING, "goldd"),
		"typo'd 'goldd' produces WARNING")
	_expect(_has_message(msgs, JourneyValidator.SEVERITY_WARNING, "manna"),
		"undeclared 'manna' consequence produces WARNING")
	_expect(not _has_message(msgs, JourneyValidator.SEVERITY_WARNING, "any_flag"),
		"HAS_FLAG 'any_flag' does NOT produce a warning")
	_expect(not _has_message(msgs, JourneyValidator.SEVERITY_WARNING, "any_other_flag"),
		"SET_FLAG 'any_other_flag' does NOT produce a warning")

func _test_duplicate_and_empty_ids(config: JourneyConfig) -> void:
	print("[5] DUPLICATE and EMPTY ids → ERRORs (surfaced from index build)")
	# Two events sharing an id + one empty-id event. The index records both as
	# build problems; the validator surfaces them.
	var dupe1 := JourneyEvent.new()
	dupe1.id = &"evt_dupe"
	var dupe2 := JourneyEvent.new()
	dupe2.id = &"evt_dupe"
	var empty_id := JourneyEvent.new()
	empty_id.id = &""

	var c := JourneyConfig.new()
	c.resource_defs = config.resource_defs
	c.start_event_id = &"evt_dupe"
	var events: Array[JourneyEvent] = [dupe1, dupe2, empty_id]
	var msgs: Array = JourneyValidator.validate(c, _index(events))
	_expect(_has_message(msgs, JourneyValidator.SEVERITY_ERROR, "evt_dupe"),
		"duplicate-id error names 'evt_dupe'")
	_expect(_has_message(msgs, JourneyValidator.SEVERITY_ERROR, "empty id"),
		"empty-id error fires")

func _test_dead_choice(config: JourneyConfig) -> void:
	print("[6] DEAD choice warns; adding a consequence clears the warning")
	var c := JourneyConfig.new()
	c.resource_defs = config.resource_defs
	c.start_event_id = &"evt_dead"
	var ev := JourneyEvent.new()
	ev.id = &"evt_dead"
	var dead := JourneyChoice.new()
	dead.button_text = "Dead end"
	# no target_event_id + continue_to_pool default false + no consequences
	ev.choices = [dead]

	var msgs_before: Array = JourneyValidator.validate(c, _index([ev]))
	_expect(_has_message(msgs_before, JourneyValidator.SEVERITY_WARNING, "dead/unfinished"),
		"dead-choice WARNING fires before consequence")

	var con := JourneyConsequence.new()
	con.operation = JourneyConsequence.Operation.SET_FLAG
	con.key = "journey_complete"
	con.flag_value = true
	dead.consequences = [con]
	var msgs_after: Array = JourneyValidator.validate(c, _index([ev]))
	_expect(not _has_message(msgs_after, JourneyValidator.SEVERITY_WARNING, "dead/unfinished"),
		"dead-choice WARNING clears after consequence added")

func _test_stable_order(config: JourneyConfig) -> void:
	print("[7] STABLE ordering — two runs produce identical message lists")
	var c: JourneyConfig = _shallow_copy(config)
	c.start_event_id = &""  # produce at least one error
	var run1: Array = JourneyValidator.validate(c, _index([]))
	var run2: Array = JourneyValidator.validate(c, _index([]))
	_expect(_stringify(run1) == _stringify(run2),
		"two runs produce identical output (n=%d)" % run1.size())

func _test_runtime_flattening(config: JourneyConfig) -> void:
	print("[8] JourneyRuntime.validate flattens to [ERROR]/[WARNING]-prefixed strings")
	var c: JourneyConfig = _shallow_copy(config)
	c.start_event_id = &""
	c.events_dir = ""  # no index built → config-level checks still fire start_event_id
	var msgs: Array[String] = JourneyRuntime.validate(c)
	var has_error_prefix := false
	for m in msgs:
		if m.begins_with("[ERROR] "):
			has_error_prefix = true
			break
	_expect(has_error_prefix, "at least one [ERROR]-prefixed string (got: %s)" % str(msgs))

func _test_unknown_ids(config: JourneyConfig) -> void:
	print("[9] UNKNOWN start/target/boundary ids → ERRORs naming the dangling id")
	# evt_a (start, resolves) routes to evt_missing (does not); a boundary route
	# points at evt_ghost (does not).
	var a := JourneyEvent.new()
	a.id = &"evt_a"
	var go := JourneyChoice.new()
	go.button_text = "onward"
	go.target_event_id = &"evt_missing"
	a.choices = [go]

	var c := JourneyConfig.new()
	c.resource_defs = config.resource_defs.duplicate()
	var rd := JourneyResourceDef.new()
	rd.key = "boundary"
	rd.min_value = 0.0
	rd.max_value = 10.0
	rd.default_value = 5.0
	rd.bottom_out_event_id = &"evt_ghost"
	c.resource_defs.append(rd)
	c.start_event_id = &"evt_a"

	var msgs: Array = JourneyValidator.validate(c, _index([a]))
	_expect(_has_message(msgs, JourneyValidator.SEVERITY_ERROR, "evt_missing"),
		"dangling target_event_id 'evt_missing' is an ERROR")
	_expect(_has_message(msgs, JourneyValidator.SEVERITY_ERROR, "evt_ghost"),
		"dangling bottom_out_event_id 'evt_ghost' is an ERROR")

	# Dangling START id, on its own.
	var c2 := JourneyConfig.new()
	c2.resource_defs = config.resource_defs
	c2.start_event_id = &"evt_nope"
	var msgs2: Array = JourneyValidator.validate(c2, _index([a]))
	_expect(_has_message(msgs2, JourneyValidator.SEVERITY_ERROR, "evt_nope"),
		"dangling start_event_id 'evt_nope' is an ERROR")

func _test_pool_loop_validates_clean(config: JourneyConfig) -> void:
	print("[10] id-resolving loop-back via continue_to_pool → no errors")
	# start → hub; hub loops back to the pool via continue_to_pool (a bool, no
	# id reference). Every routing id resolves, so this is clean.
	var start := JourneyEvent.new()
	start.id = &"evt_loop_start"
	var hub := JourneyEvent.new()
	hub.id = &"evt_loop_hub"
	var go := JourneyChoice.new()
	go.button_text = "enter hub"
	go.target_event_id = &"evt_loop_hub"
	start.choices = [go]
	var loop := JourneyChoice.new()
	loop.button_text = "another day"
	loop.continue_to_pool = true
	var con := JourneyConsequence.new()
	con.operation = JourneyConsequence.Operation.SET_FLAG
	con.key = "looped"
	con.flag_value = true
	loop.consequences = [con]
	hub.choices = [loop]

	var c := JourneyConfig.new()
	c.resource_defs = config.resource_defs
	c.start_event_id = &"evt_loop_start"
	var errs: Array = JourneyValidator.errors_only(JourneyValidator.validate(c, _index([start, hub])))
	_expect(errs.is_empty(), "continue_to_pool loop produces NO errors (got %d: %s)" % [errs.size(), str(errs)])

func _test_disk_round_trip_tests() -> void:
	print("[11] DISK ROUND-TRIP — migrated test content loads cleanly from disk")
	var problems: Array[String] = JourneyLoadCheck.check(TEST_CONFIG_PATH)
	_expect(problems.is_empty(), "test config round-trips clean (got %d: %s)" % [problems.size(), str(problems)])

# --- Utility ---

## Build a JourneyEventIndex from an in-memory event list (no disk).
func _index(events: Array[JourneyEvent]) -> JourneyEventIndex:
	var idx := JourneyEventIndex.new()
	idx.build_from_events(events)
	return idx

## Shallow-copy a JourneyConfig so tests can mutate top-level fields without
## affecting the loaded resource.
func _shallow_copy(config: JourneyConfig) -> JourneyConfig:
	var c := JourneyConfig.new()
	c.resource_defs = config.resource_defs.duplicate()
	c.initial_flags = config.initial_flags.duplicate()
	c.start_event_id = config.start_event_id
	c.events_dir = config.events_dir
	c.rebuild_index_in_editor = config.rebuild_index_in_editor
	c.save_encryption_key = config.save_encryption_key
	c.save_version = config.save_version
	return c

func _has_message(msgs: Array, severity: String, substr: String) -> bool:
	for m in msgs:
		if m is Dictionary and m.get("severity", "") == severity and String(m.get("message", "")).find(substr) != -1:
			return true
	return false

func _stringify(msgs: Array) -> String:
	var lines: Array = []
	for m in msgs:
		if m is Dictionary:
			lines.append("%s: %s" % [m.get("severity", "?"), m.get("message", "?")])
	return "\n".join(lines)

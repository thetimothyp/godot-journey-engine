extends Node

## Step-7 programmatic test for JourneyValidator + JourneyRuntime.validate.
##
## Covers (matching the manual-test checklist in the Step-7 prompt):
##   1. CLEAN: good test_config.tres returns no errors
##   2. NULL START: missing start_event → ERROR
##   3. BAD BOUNDS: min>max AND default-out-of-range → two ERRORs
##   4. TYPO RESOURCE KEY: condition + consequence on undeclared resource →
##      WARNINGs; HAS_FLAG reference does NOT warn
##   5. DUPLICATE / EMPTY IDs: two events sharing an id → ERROR; empty id → ERROR
##   6. DEAD CHOICE: null target + no pool + no consequences → WARNING; adding
##      a consequence clears it
##   7. STABLE ORDER: two runs on the same input → identical message lists
##
## Constructs configs/events programmatically — no per-case .tres files to
## maintain. The CLEAN case loads the real test_config.tres so we catch any
## drift between the authored test fixture and the validator's view.

const TEST_CONFIG_PATH := "res://tests/test_config.tres"

var _failures: int = 0

func _ready() -> void:
	# Early marker so a silent boot-and-exit is easy to spot — if you see
	# this line in the Output panel but no checks below, _ready aborted
	# somewhere (likely the config load).
	print("[test_validate] starting…")
	var clean_config: JourneyConfig = load(TEST_CONFIG_PATH)
	if clean_config == null:
		push_error("test_validate: cannot load %s" % TEST_CONFIG_PATH)
		_finish()
		return

	_test_clean(clean_config)
	_test_null_start(clean_config)
	_test_bad_bounds(clean_config)
	_test_typo_resource_key(clean_config)
	_test_duplicate_and_empty_ids(clean_config)
	_test_dead_choice(clean_config)
	_test_stable_order(clean_config)
	_test_runtime_flattening(clean_config)
	_finish()

func _finish() -> void:
	if _failures == 0:
		print("[test_validate] PASS (all checks)")
	else:
		print("[test_validate] FAIL: %d check(s) failed" % _failures)
	# Intentionally do NOT call get_tree().quit() — even with a few
	# process_frame yields, the child process terminates before the editor's
	# debugger drains stdout, so prints get eaten. Match the
	# test_blackboard/test_eval_mutate pattern: user closes the window when
	# they're done reading. (Step-8 discovery applied to all three tests.)

func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("  [ok] %s" % msg)
	else:
		_failures += 1
		printerr("  [FAIL] %s" % msg)

# --- Tests ---

func _test_clean(config: JourneyConfig) -> void:
	print("[1] CLEAN config produces no errors")
	var msgs: Array = JourneyValidator.validate(config, null)
	var errs: Array = JourneyValidator.errors_only(msgs)
	_expect(errs.is_empty(), "no errors on clean config (got %d: %s)" % [errs.size(), str(errs)])

func _test_null_start(config: JourneyConfig) -> void:
	print("[2] NULL start_event → ERROR")
	var c: JourneyConfig = _shallow_copy(config)
	c.start_event = null
	var msgs: Array = JourneyValidator.validate(c, null)
	_expect(_has_message(msgs, JourneyValidator.SEVERITY_ERROR, "start_event"),
		"error message mentions start_event (got: %s)" % _stringify(msgs))

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
	var msgs: Array = JourneyValidator.validate(c, null)
	_expect(_has_message(msgs, JourneyValidator.SEVERITY_ERROR, "bad_minmax"),
		"min>max error names 'bad_minmax'")
	_expect(_has_message(msgs, JourneyValidator.SEVERITY_ERROR, "bad_default"),
		"out-of-range default error names 'bad_default'")

func _test_typo_resource_key(config: JourneyConfig) -> void:
	print("[4] TYPO'D resource key warns; flag key does NOT warn")
	# Construct a tiny config with a single event whose visibility references
	# resource "goldd" (typo), whose consequence touches "manna" (undeclared),
	# and whose visibility also has a HAS_FLAG check that must NOT warn.
	var c := JourneyConfig.new()
	c.resource_defs = config.resource_defs  # 'gold' / 'sanity' / 'rations' declared
	var ev := JourneyEvent.new()
	ev.id = &"evt_typo_test"
	var choice := JourneyChoice.new()
	choice.button_text = "Go"
	# visibility: HAS_FLAG any_flag AND gold typo check
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
	# consequence: ADD to undeclared "manna"
	var bad_con := JourneyConsequence.new()
	bad_con.operation = JourneyConsequence.Operation.ADD
	bad_con.key = "manna"
	bad_con.value = 5.0
	# consequence: SET_FLAG on undeclared 'whatever' — must NOT warn
	var flag_con := JourneyConsequence.new()
	flag_con.operation = JourneyConsequence.Operation.SET_FLAG
	flag_con.key = "any_other_flag"
	flag_con.flag_value = true
	choice.consequences = [bad_con, flag_con]
	ev.choices = [choice]
	c.start_event = ev

	var msgs: Array = JourneyValidator.validate(c, null)
	_expect(_has_message(msgs, JourneyValidator.SEVERITY_WARNING, "goldd"),
		"typo'd 'goldd' produces WARNING")
	_expect(_has_message(msgs, JourneyValidator.SEVERITY_WARNING, "manna"),
		"undeclared 'manna' consequence produces WARNING")
	_expect(not _has_message(msgs, JourneyValidator.SEVERITY_WARNING, "any_flag"),
		"HAS_FLAG 'any_flag' does NOT produce a warning")
	_expect(not _has_message(msgs, JourneyValidator.SEVERITY_WARNING, "any_other_flag"),
		"SET_FLAG 'any_other_flag' does NOT produce a warning")

func _test_duplicate_and_empty_ids(config: JourneyConfig) -> void:
	print("[5] DUPLICATE and EMPTY ids → ERRORs")
	var c := JourneyConfig.new()
	c.resource_defs = config.resource_defs
	# start_event has duplicate id; its only choice leads to another event
	# with the same id; the resource_defs bottom_out points at a third event
	# with empty id.
	var dupe1 := JourneyEvent.new()
	dupe1.id = &"evt_dupe"
	var dupe2 := JourneyEvent.new()
	dupe2.id = &"evt_dupe"
	var empty_id := JourneyEvent.new()
	empty_id.id = &""
	var hop_choice := JourneyChoice.new()
	hop_choice.button_text = "Hop"
	hop_choice.target_event = dupe2
	dupe1.choices = [hop_choice]
	c.start_event = dupe1
	# Attach empty-id event via a resource_def boundary so the collector sees it.
	var rd := JourneyResourceDef.new()
	rd.key = "boundary"
	rd.min_value = 0.0
	rd.max_value = 10.0
	rd.default_value = 5.0
	rd.bottom_out_event = empty_id
	c.resource_defs = c.resource_defs.duplicate()
	c.resource_defs.append(rd)

	var msgs: Array = JourneyValidator.validate(c, null)
	_expect(_has_message(msgs, JourneyValidator.SEVERITY_ERROR, "evt_dupe"),
		"duplicate-id error names 'evt_dupe'")
	_expect(_has_message(msgs, JourneyValidator.SEVERITY_ERROR, "empty id"),
		"empty-id error fires")

func _test_dead_choice(config: JourneyConfig) -> void:
	print("[6] DEAD choice warns; adding a consequence clears the warning")
	var c := JourneyConfig.new()
	c.resource_defs = config.resource_defs
	var ev := JourneyEvent.new()
	ev.id = &"evt_dead"
	var dead := JourneyChoice.new()
	dead.button_text = "Dead end"
	# null target + continue_to_pool default false + no consequences
	ev.choices = [dead]
	c.start_event = ev

	var msgs_before: Array = JourneyValidator.validate(c, null)
	_expect(_has_message(msgs_before, JourneyValidator.SEVERITY_WARNING, "dead/unfinished"),
		"dead-choice WARNING fires before consequence")

	# Add a consequence; warning should disappear.
	var con := JourneyConsequence.new()
	con.operation = JourneyConsequence.Operation.SET_FLAG
	con.key = "journey_complete"
	con.flag_value = true
	dead.consequences = [con]
	var msgs_after: Array = JourneyValidator.validate(c, null)
	_expect(not _has_message(msgs_after, JourneyValidator.SEVERITY_WARNING, "dead/unfinished"),
		"dead-choice WARNING clears after consequence added")

func _test_stable_order(config: JourneyConfig) -> void:
	print("[7] STABLE ordering — two runs produce identical message lists")
	var c: JourneyConfig = _shallow_copy(config)
	c.start_event = null  # produce at least one error
	var run1: Array = JourneyValidator.validate(c, null)
	var run2: Array = JourneyValidator.validate(c, null)
	_expect(_stringify(run1) == _stringify(run2),
		"two runs produce identical output (n=%d)" % run1.size())

func _test_runtime_flattening(config: JourneyConfig) -> void:
	print("[8] JourneyRuntime.validate flattens to [ERROR]/[WARNING]-prefixed strings")
	var c: JourneyConfig = _shallow_copy(config)
	c.start_event = null
	var msgs: Array[String] = JourneyRuntime.validate(c)
	var has_error_prefix := false
	for m in msgs:
		if m.begins_with("[ERROR] "):
			has_error_prefix = true
			break
	_expect(has_error_prefix, "at least one [ERROR]-prefixed string (got: %s)" % str(msgs))

# --- Utility ---

## Shallow-copy a JourneyConfig so tests can mutate top-level fields without
## affecting the loaded resource (Resource.duplicate(false) shares sub-objects;
## we don't mutate those, only the resource_defs Array and start_event ref).
func _shallow_copy(config: JourneyConfig) -> JourneyConfig:
	var c := JourneyConfig.new()
	c.resource_defs = config.resource_defs.duplicate()
	c.initial_flags = config.initial_flags.duplicate()
	c.start_event = config.start_event
	c.event_pool_dir = config.event_pool_dir
	c.rebuild_pool_in_editor = config.rebuild_pool_in_editor
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

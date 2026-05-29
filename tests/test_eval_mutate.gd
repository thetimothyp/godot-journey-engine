extends Node

## Throwaway manual test for Step 3: confirms JourneyEvaluator and JourneyMutator
## behave per eng design §3.2-§3.4 and §4.3-§4.4. Run via F6 with this scene open.
##
## Prints "PASS"/"FAIL" per check so the run is skim-readable. Missing-key
## warnings ("mana") are expected to appear in Output around the marked lines.

const TEST_CONFIG_PATH := "res://tests/test_config.tres"

# Routing is id-based, so boundary routes are just StringName ids — the Mutator
# only checks that the id is non-empty (it returns triggered defs; the
# SequenceManager resolves the id). A literal id suffices here; no event object
# needs to exist for the trigger-detection logic under test.
const BOUNDARY_ID := &"evt_test"

func _ready() -> void:
	var config: JourneyConfig = load(TEST_CONFIG_PATH)
	if config == null:
		push_error("test_eval_mutate: could not load %s" % TEST_CONFIG_PATH)
		return

	# -------------------- 1. Init --------------------
	var bb := Blackboard.new()
	bb.initialize(config, 12345)
	print("=== Step 3 manual test ===")
	print("init resources: ", bb.resources)
	print("init flags:     ", bb.flags)
	_check("gold=100", bb.resources["gold"] == 100.0)
	_check("sanity=50", bb.resources["sanity"] == 50.0)
	_check("rations=200", bb.resources["rations"] == 200.0)
	_check("flag started=true", bb.flags.get("started", false) == true)

	# -------------------- 2. Evaluator --------------------
	print("\n--- Evaluator: numeric ops ---")
	_check("gold GTE 50 → true",  JourneyEvaluator.eval_condition(_cond("gold", JourneyCondition.Op.GTE, 50.0), bb) == true)
	_check("gold GT 100 → false", JourneyEvaluator.eval_condition(_cond("gold", JourneyCondition.Op.GT,  100.0), bb) == false)
	_check("gold EQ 100 → true",  JourneyEvaluator.eval_condition(_cond("gold", JourneyCondition.Op.EQ,  100.0), bb) == true)
	_check("gold NEQ 100 → false",JourneyEvaluator.eval_condition(_cond("gold", JourneyCondition.Op.NEQ, 100.0), bb) == false)
	_check("gold LT 200 → true",  JourneyEvaluator.eval_condition(_cond("gold", JourneyCondition.Op.LT,  200.0), bb) == true)
	_check("gold LTE 100 → true", JourneyEvaluator.eval_condition(_cond("gold", JourneyCondition.Op.LTE, 100.0), bb) == true)

	print("\n--- Evaluator: missing resource key 'mana' (expect push_warning naming 'mana') ---")
	var missing_res_result := JourneyEvaluator.eval_condition(_cond("mana", JourneyCondition.Op.GTE, 1.0), bb)
	_check("mana GTE 1 → false (missing → 0.0)", missing_res_result == false)

	print("\n--- Evaluator: flag ops ---")
	_check("HAS_FLAG started → true",   JourneyEvaluator.eval_condition(_cond("started", JourneyCondition.Op.HAS_FLAG, 0.0), bb) == true)
	_check("HAS_FLAG ghost → false (no warning)", JourneyEvaluator.eval_condition(_cond("ghost", JourneyCondition.Op.HAS_FLAG, 0.0), bb) == false)
	_check("NOT_FLAG ghost → true",     JourneyEvaluator.eval_condition(_cond("ghost", JourneyCondition.Op.NOT_FLAG, 0.0), bb) == true)
	_check("NOT_FLAG started → false",  JourneyEvaluator.eval_condition(_cond("started", JourneyCondition.Op.NOT_FLAG, 0.0), bb) == false)

	print("\n--- Evaluator: groups ---")
	_check("null group → true", JourneyEvaluator.eval_group(null, bb) == true)
	_check("empty ALL → true",  JourneyEvaluator.eval_group(_group(JourneyConditionGroup.Logic.ALL, []), bb) == true)
	_check("empty ANY → true",  JourneyEvaluator.eval_group(_group(JourneyConditionGroup.Logic.ANY, []), bb) == true)

	var pass_all := _group(JourneyConditionGroup.Logic.ALL, [
		_cond("gold", JourneyCondition.Op.GTE, 50.0),
		_cond("sanity", JourneyCondition.Op.GTE, 40.0),
	])
	_check("ALL[gold>=50, sanity>=40] → true",  JourneyEvaluator.eval_group(pass_all, bb) == true)

	var fail_all := _group(JourneyConditionGroup.Logic.ALL, [
		_cond("gold", JourneyCondition.Op.GTE, 50.0),
		_cond("sanity", JourneyCondition.Op.GTE, 60.0),
	])
	_check("ALL[gold>=50, sanity>=60] → false", JourneyEvaluator.eval_group(fail_all, bb) == false)

	var pass_any := _group(JourneyConditionGroup.Logic.ANY, [
		_cond("gold", JourneyCondition.Op.GTE, 999.0),
		_cond("sanity", JourneyCondition.Op.GTE, 40.0),
	])
	_check("ANY[gold>=999, sanity>=40] → true", JourneyEvaluator.eval_group(pass_any, bb) == true)

	# -------------------- 3. Mutator: single consequences --------------------
	print("\n--- Mutator: single consequences ---")
	var gold_before: float = bb.resources["gold"]
	JourneyMutator.apply_consequence(_con_num(JourneyConsequence.Operation.ADD, "gold", 50.0), bb, config)
	print("ADD 50 gold: %s → %s" % [gold_before, bb.resources["gold"]])
	_check("gold becomes 150", bb.resources["gold"] == 150.0)

	gold_before = bb.resources["gold"]
	JourneyMutator.apply_consequence(_con_num(JourneyConsequence.Operation.SUBTRACT, "gold", 200.0), bb, config)
	print("SUBTRACT 200 gold (raw -50): %s → %s [clamp to min]" % [gold_before, bb.resources["gold"]])
	_check("gold clamped to 0 (not -50)", bb.resources["gold"] == 0.0)

	JourneyMutator.apply_consequence(_con_flag("visited", true), bb, config)
	_check("SET_FLAG visited=true → true", bb.flags.get("visited", false) == true)
	JourneyMutator.apply_consequence(_con_toggle("visited"), bb, config)
	_check("TOGGLE_FLAG visited → false", bb.flags.get("visited", true) == false)
	JourneyMutator.apply_consequence(_con_toggle("ghost"), bb, config)
	_check("TOGGLE_FLAG ghost (absent → true)", bb.flags.get("ghost", false) == true)

	print("\n--- Mutator: undeclared resource 'mana' (expect push_warning + skip) ---")
	JourneyMutator.apply_consequence(_con_num(JourneyConsequence.Operation.ADD, "mana", 10.0), bb, config)
	_check("'mana' not added to resources", not bb.resources.has("mana"))

	# -------------------- 4. Mutator: batch + bottom-out detection --------------------
	print("\n--- Mutator: batch + bottom-out detection ---")
	# Temporarily attach a non-null event to two defs so we can prove definition-order
	# reporting when both bottom out in the same batch. In-memory only; the .tres on
	# disk is untouched.
	var sanity_def: JourneyResourceDef = _find_def(config, "sanity")
	var rations_def: JourneyResourceDef = _find_def(config, "rations")
	var gold_def: JourneyResourceDef = _find_def(config, "gold")
	sanity_def.bottom_out_event_id = BOUNDARY_ID
	rations_def.bottom_out_event_id = BOUNDARY_ID

	# Reset values so the batch is unambiguous: sanity 50 → 0 (-50), rations 200 → 0 (-200)
	bb.resources["sanity"] = 50.0
	bb.resources["rations"] = 200.0

	var batch: Array[JourneyConsequence] = [
		_con_num(JourneyConsequence.Operation.SUBTRACT, "sanity", 50.0),
		_con_num(JourneyConsequence.Operation.SUBTRACT, "rations", 250.0), # clamps to 0
	]
	var triggered: Array[JourneyResourceDef] = JourneyMutator.apply_batch(batch, bb, config)
	var triggered_keys: Array[String] = []
	for d in triggered:
		triggered_keys.append(d.key)
	print("post-batch resources: ", bb.resources)
	print("triggered keys (definition order): ", triggered_keys)

	_check("sanity clamped to 0", bb.resources["sanity"] == 0.0)
	_check("rations clamped to 0", bb.resources["rations"] == 0.0)
	# config.resource_defs order is [gold, sanity, rations] per test_config.tres,
	# and gold has no bottom_out_event, so we expect [sanity, rations].
	_check("two defs triggered", triggered.size() == 2)
	_check("definition order [sanity, rations]", triggered_keys == ["sanity", "rations"])

	# And the single-trigger case: drive only sanity to 0.
	bb.resources["sanity"] = 50.0
	bb.resources["rations"] = 200.0
	rations_def.bottom_out_event_id = &"" # only sanity will trigger
	var single_batch: Array[JourneyConsequence] = [
		_con_num(JourneyConsequence.Operation.SUBTRACT, "sanity", 50.0),
	]
	var single_triggered: Array[JourneyResourceDef] = JourneyMutator.apply_batch(single_batch, bb, config)
	var single_keys: Array[String] = []
	for d in single_triggered:
		single_keys.append(d.key)
	print("single-trigger keys: ", single_keys)
	_check("only sanity reported", single_keys == ["sanity"])

	# Top-out symmetry: set gold's top_out_event and ADD it to max.
	# Reset sanity to 50 and clear its bottom_out_event for hygiene — strictly
	# unnecessary after the Step-8 transition-vs-presence fix (the Mutator now
	# reports only TRANSITIONS, so a residue value sitting at its bound across
	# batches is silently ignored), but cheap defense-in-depth.
	sanity_def.bottom_out_event_id = &""
	bb.resources["sanity"] = 50.0
	gold_def.top_out_event_id = BOUNDARY_ID
	bb.resources["gold"] = 0.0
	var top_batch: Array[JourneyConsequence] = [
		_con_num(JourneyConsequence.Operation.ADD, "gold", 99999.0), # clamps to 999
	]
	var top_triggered: Array[JourneyResourceDef] = JourneyMutator.apply_batch(top_batch, bb, config)
	var top_keys: Array[String] = []
	for d in top_triggered:
		top_keys.append(d.key)
	print("top-out keys: ", top_keys)
	_check("gold top-out reported", top_keys == ["gold"])

	# Restore the in-memory config so we leave no surprise state for sibling tests.
	sanity_def.bottom_out_event_id = &""
	rations_def.bottom_out_event_id = &""
	gold_def.top_out_event_id = &""

	# -------------------- 4b. Mutator: transition vs presence (Step-8 regression) --------------------
	# Spec §4.4 / §5.1 specify the forced route fires when the CLAMPED RESULT
	# of a batch transitions to a boundary. A no-op choice on a value already
	# sitting at the boundary must NOT re-trigger, or the bottom_out_event
	# loops forever when its own choices don't lift the value. Regression
	# from Step 8 sample-game playthrough: evt_madness → "Stumble forward"
	# (no consequences) re-triggered sanity bottom_out indefinitely.
	print("\n--- Mutator: transition vs presence (loop guard) ---")
	sanity_def.bottom_out_event_id = BOUNDARY_ID
	# (1) Pre = boundary, no consequences → NO trigger.
	bb.resources["sanity"] = 0.0
	var noop_batch: Array[JourneyConsequence] = []
	var noop_triggered: Array[JourneyResourceDef] = JourneyMutator.apply_batch(noop_batch, bb, config)
	_check("pre=0 + no-op batch → no trigger (the loop guard)", noop_triggered.is_empty())
	# (2) Pre = boundary, SUBTRACT (stays clamped at 0) → NO trigger.
	bb.resources["sanity"] = 0.0
	var stay_at_zero_batch: Array[JourneyConsequence] = [
		_con_num(JourneyConsequence.Operation.SUBTRACT, "sanity", 5.0),
	]
	var stay_triggered: Array[JourneyResourceDef] = JourneyMutator.apply_batch(stay_at_zero_batch, bb, config)
	_check("pre=0 + SUBTRACT clamps to 0 → no trigger", stay_triggered.is_empty())
	# (3) Pre = boundary, ADD lifts off boundary → NO trigger (leaving, not entering).
	bb.resources["sanity"] = 0.0
	var lift_batch: Array[JourneyConsequence] = [
		_con_num(JourneyConsequence.Operation.ADD, "sanity", 10.0),
	]
	var lift_triggered: Array[JourneyResourceDef] = JourneyMutator.apply_batch(lift_batch, bb, config)
	_check("pre=0 + ADD lifts off → no trigger", lift_triggered.is_empty())
	_check("(post-lift) sanity == 10", bb.resources["sanity"] == 10.0)
	# (4) Pre = OFF boundary, SUBTRACT reaches it → trigger (the original transition case still works).
	bb.resources["sanity"] = 10.0
	var enter_batch: Array[JourneyConsequence] = [
		_con_num(JourneyConsequence.Operation.SUBTRACT, "sanity", 10.0),
	]
	var enter_triggered: Array[JourneyResourceDef] = JourneyMutator.apply_batch(enter_batch, bb, config)
	_check("pre=10 + SUBTRACT 10 → sanity bottom_out triggers (transition case)",
		enter_triggered.size() == 1 and enter_triggered[0].key == "sanity")
	# Top-out symmetry: pre=max, no-op → no re-trigger.
	gold_def.top_out_event_id = BOUNDARY_ID
	bb.resources["gold"] = gold_def.max_value
	var noop_top_batch: Array[JourneyConsequence] = []
	var noop_top_triggered: Array[JourneyResourceDef] = JourneyMutator.apply_batch(noop_top_batch, bb, config)
	_check("pre=max + no-op → no top-out re-trigger", noop_top_triggered.is_empty())
	# Clean up: clear the boundary events again so we leave no surprise state.
	sanity_def.bottom_out_event_id = &""
	gold_def.top_out_event_id = &""

	print("\n=== Step 3 manual test done ===")

# ---------------- builders ----------------
func _cond(key: String, op: int, value: float) -> JourneyCondition:
	var c := JourneyCondition.new()
	c.key = key
	c.op = op
	c.value = value
	return c

func _group(logic: int, conds: Array) -> JourneyConditionGroup:
	var g := JourneyConditionGroup.new()
	g.logic = logic
	var typed: Array[JourneyCondition] = []
	for c in conds:
		typed.append(c)
	g.conditions = typed
	return g

func _con_num(op: int, key: String, value: float) -> JourneyConsequence:
	var c := JourneyConsequence.new()
	c.operation = op
	c.key = key
	c.value = value
	return c

func _con_flag(key: String, value: bool) -> JourneyConsequence:
	var c := JourneyConsequence.new()
	c.operation = JourneyConsequence.Operation.SET_FLAG
	c.key = key
	c.flag_value = value
	return c

func _con_toggle(key: String) -> JourneyConsequence:
	var c := JourneyConsequence.new()
	c.operation = JourneyConsequence.Operation.TOGGLE_FLAG
	c.key = key
	return c

func _find_def(config: JourneyConfig, key: String) -> JourneyResourceDef:
	for def in config.resource_defs:
		if def.key == key:
			return def
	return null

func _check(label: String, ok: bool) -> void:
	if ok:
		print("  PASS  ", label)
	else:
		push_error("  FAIL  " + label)
		print("  FAIL  ", label)

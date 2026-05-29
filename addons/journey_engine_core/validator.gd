extends RefCounted
class_name JourneyValidator

## §8.1 authoring validator. Inspects a JourneyConfig (and optionally an
## already-built JourneyEventIndex) and returns a list of error/warning messages
## naming the offenders. PURE INSPECTION — never mutates resources, the
## Blackboard, or runtime state; never instantiates Nodes; never prints. The
## CALLER decides what to do with the messages (push_error, surface in a UI,
## write to a log). Studio [§8.1] will call this same entry on save so the rules
## live in core and stay in lockstep with the runtime.
##
## Result shape: Array of Dictionary { "severity": String, "message": String }
## where severity is SEVERITY_ERROR or SEVERITY_WARNING. Plain dicts (not a
## class) so the result is trivially serializable for Studio / logs / CI.
##
## Routing is id-based: start_event_id, choice.target_event_id, and boundary
## *_event_id are StringNames resolved against the event index. The validator's
## central structural check is therefore ID RESOLUTION — every referenced id
## must resolve to an indexed event — which REPLACES the old object-ref
## cycle-detection check (a cycle of ids is serializable and loadable, so it is
## no longer an error; a legitimate day-loop is now a supported shape). Because
## resolution and per-event checks need the index, meaningful validation
## REQUIRES a built JourneyEventIndex; called without one, only config-level
## checks run and a note is appended.
##
## Stable ordering: resource_defs in declaration order; events from the index
## (already id-sorted in JourneyEventIndex.build); index build problems sorted by
## message. Same input ⇒ same message list.

const SEVERITY_ERROR := "error"
const SEVERITY_WARNING := "warning"

## §8.1 entry. Returns Array of {severity, message} dicts; empty = clean.
## event_index optional: when null, only config-level checks run (id resolution
## and per-event rules need the index) and a note is appended; when a built index
## is passed, all events are validated and every routing id is resolved against
## it. Does NOT trigger an index build itself (author may not have set events_dir
## yet) — JourneyRuntime.validate() builds one before delegating.
static func validate(config: JourneyConfig, event_index: JourneyEventIndex = null) -> Array:
	var messages: Array = []

	if config == null:
		messages.append(_err("config is null"))
		return messages

	# §8.1: an empty start_event_id can never route — error.
	if String(config.start_event_id) == "":
		messages.append(_err("config.start_event_id is empty"))

	# §3.7 / §8.1: resource def bounds.
	_validate_resource_defs(config, messages)

	if event_index == null:
		messages.append(_warn("events not indexed — pass a built JourneyEventIndex to check id resolution and per-event rules"))
		return messages

	# §3.8: empty / duplicate ids found while building the index. Recorded there
	# (duplicates are dropped first-seen-wins, so the validator can't re-derive
	# them from all_events) and surfaced here in the typed result.
	for p in event_index.build_problems:
		messages.append(p)

	# §4.3 declared-key set: resource ops referencing keys outside this set warn
	# (typo catch). Flag ops never warn — flags are created lazily by spec (§4.3)
	# and have no "declared" concept.
	var declared_keys: Dictionary = _declared_resource_keys(config)
	for event in event_index.all_events:
		if event == null:
			continue
		_validate_event_conditions(event, declared_keys, messages)
		_validate_event_choices(event, declared_keys, messages)

	# §8.1 STRUCTURAL: every routing id must resolve to an indexed event. This is
	# the load-time guarantee that replaced cycle detection — a dangling id is the
	# one way id-based routing can break, and it surfaces here as a named error
	# (and at runtime as a journey_error) rather than a silent dead-end.
	_validate_id_resolution(config, event_index, messages)

	return messages

## Convenience: extract just the dicts with severity == SEVERITY_ERROR.
## Useful for callers that want to gate on errors but display warnings.
static func errors_only(messages: Array) -> Array:
	var out: Array = []
	for m in messages:
		if m is Dictionary and m.get("severity", "") == SEVERITY_ERROR:
			out.append(m)
	return out

# --- Helpers ---

static func _err(msg: String) -> Dictionary:
	return {"severity": SEVERITY_ERROR, "message": msg}

static func _warn(msg: String) -> Dictionary:
	return {"severity": SEVERITY_WARNING, "message": msg}

static func _declared_resource_keys(config: JourneyConfig) -> Dictionary:
	var keys: Dictionary = {}
	for def in config.resource_defs:
		if def != null and def.key != "":
			keys[def.key] = true
	return keys

static func _validate_resource_defs(config: JourneyConfig, messages: Array) -> void:
	for i in range(config.resource_defs.size()):
		var def: JourneyResourceDef = config.resource_defs[i]
		if def == null:
			messages.append(_err("resource_defs[%d] is null" % i))
			continue
		var name: String = def.key if def.key != "" else "<unnamed #%d>" % i
		if def.min_value > def.max_value:
			messages.append(_err("resource def '%s': min_value (%s) > max_value (%s)" % [name, def.min_value, def.max_value]))
		if def.default_value < def.min_value or def.default_value > def.max_value:
			messages.append(_err("resource def '%s': default_value (%s) outside [%s, %s]" % [name, def.default_value, def.min_value, def.max_value]))

## §8.1 id-resolution. Every routing id (start, boundary routes, every choice
## target across every indexed event) must resolve to an indexed event, else the
## route dead-ends at runtime. Empty ids are NOT errors here — empty means "no
## route" (a terminal choice, an unset boundary); only a NON-empty id that fails
## to resolve is flagged. Deterministic order: start, then resource_defs in
## declaration order, then events in index (id-sorted) × choice order.
static func _validate_id_resolution(config: JourneyConfig, index: JourneyEventIndex, messages: Array) -> void:
	var sid: String = String(config.start_event_id)
	if sid != "" and index.find_by_id(sid) == null:
		messages.append(_err("config.start_event_id '%s' does not resolve to an indexed event" % sid))

	for def in config.resource_defs:
		if def == null:
			continue
		var name: String = def.key if def.key != "" else "<unnamed>"
		var bid: String = String(def.bottom_out_event_id)
		if bid != "" and index.find_by_id(bid) == null:
			messages.append(_err("resource def '%s' bottom_out_event_id '%s' does not resolve to an indexed event" % [name, bid]))
		var tid: String = String(def.top_out_event_id)
		if tid != "" and index.find_by_id(tid) == null:
			messages.append(_err("resource def '%s' top_out_event_id '%s' does not resolve to an indexed event" % [name, tid]))

	for event in index.all_events:
		if event == null:
			continue
		var eid: String = String(event.id) if String(event.id) != "" else "<empty-id>"
		for ci in range(event.choices.size()):
			var choice: JourneyChoice = event.choices[ci]
			if choice == null:
				continue
			var t: String = String(choice.target_event_id)
			if t != "" and index.find_by_id(t) == null:
				messages.append(_err("event '%s' choice[%d] target_event_id '%s' does not resolve to an indexed event" % [eid, ci, t]))

# --- Per-event walks ---

static func _validate_event_conditions(event: JourneyEvent, declared_keys: Dictionary, messages: Array) -> void:
	var eid: String = String(event.id) if String(event.id) != "" else "<empty-id>"
	_walk_condition_group(event.pool_conditions, declared_keys, "event '%s' pool_conditions" % eid, messages)
	for ci in range(event.choices.size()):
		var choice: JourneyChoice = event.choices[ci]
		if choice == null:
			continue
		_walk_condition_group(choice.visibility, declared_keys, "event '%s' choice[%d] visibility" % [eid, ci], messages)

static func _walk_condition_group(group: JourneyConditionGroup, declared_keys: Dictionary, ctx: String, messages: Array) -> void:
	if group == null:
		return
	for i in range(group.conditions.size()):
		var cond: JourneyCondition = group.conditions[i]
		if cond == null:
			continue
		# §4.3: flag ops have no declared-key concept — never warn.
		if cond.op == JourneyCondition.Op.HAS_FLAG or cond.op == JourneyCondition.Op.NOT_FLAG:
			continue
		# Empty key is an authoring-in-progress signal; don't add noise here.
		# (Could become its own warning later if that proves useful.)
		if cond.key == "":
			continue
		if not declared_keys.has(cond.key):
			messages.append(_warn("%s [condition %d]: references undeclared resource key '%s'" % [ctx, i, cond.key]))

static func _validate_event_choices(event: JourneyEvent, declared_keys: Dictionary, messages: Array) -> void:
	var eid: String = String(event.id) if String(event.id) != "" else "<empty-id>"
	for ci in range(event.choices.size()):
		var choice: JourneyChoice = event.choices[ci]
		if choice == null:
			continue
		# Consequence-key typos (§4.3 declared-key policy).
		for k in range(choice.consequences.size()):
			var con: JourneyConsequence = choice.consequences[k]
			if con == null:
				continue
			# §4.3: flag ops are lazy — never warn on undeclared.
			if con.operation == JourneyConsequence.Operation.SET_FLAG or con.operation == JourneyConsequence.Operation.TOGGLE_FLAG:
				continue
			if con.key == "":
				continue
			if not declared_keys.has(con.key):
				messages.append(_warn("event '%s' choice[%d] consequence[%d]: references undeclared resource key '%s'" % [eid, ci, k, con.key]))
		# §8.1 dead-choice heuristic — WARNING (not ERROR) because a legitimate
		# terminal choice CAN have empty target + no pool + no consequences if the
		# author wanted a bare "End journey" button. But that's vanishingly rare;
		# real terminal choices almost always carry consequences (a final state
		# flip, an "ending kind" flag, etc.). The warning catches the
		# unfinished-node case without false-positiving the deliberate one — and
		# the author can suppress it by adding any consequence.
		if String(choice.target_event_id) == "" and not choice.continue_to_pool and choice.consequences.is_empty():
			messages.append(_warn("event '%s' choice[%d]: dead/unfinished — no target_event_id, no pool continuation, no consequences" % [eid, ci]))

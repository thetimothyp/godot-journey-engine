extends RefCounted
class_name JourneyValidator

## §8.1 authoring validator. Inspects a JourneyConfig (and optionally an
## already-built JourneyPoolIndex) and returns a list of error/warning
## messages naming the offenders. PURE INSPECTION — never mutates resources,
## the Blackboard, or runtime state; never instantiates Nodes; never prints.
## The CALLER decides what to do with the messages (push_error, surface in a
## UI, write to a log). Studio [§8.1] will call this same entry on save so
## the rules live in core and stay in lockstep with the runtime.
##
## Result shape: Array of Dictionary { "severity": String, "message": String }
## where severity is SEVERITY_ERROR or SEVERITY_WARNING. Plain dicts (not a
## class) so the result is trivially serializable for Studio / logs / CI.
##
## Stable ordering: resource_defs are iterated in declaration order; events
## are collected start_event-first, then BFS in choice order, then resource-
## def bottom/top-out events, then pool events (already sorted by id in
## JourneyPoolIndex.build). Same input ⇒ same message list.

const SEVERITY_ERROR := "error"
const SEVERITY_WARNING := "warning"

## §8.1 entry. Returns Array of {severity, message} dicts; empty = clean.
## pool_index optional: when null, only deterministic events reachable from
## config are validated and a note message is appended; when a built index
## is passed, its events are included in the walk. Does NOT trigger a pool
## build itself (author may not have set event_pool_dir yet).
static func validate(config: JourneyConfig, pool_index: JourneyPoolIndex = null) -> Array:
	var messages: Array = []

	if config == null:
		messages.append(_err("config is null"))
		return messages

	# §8.1: start_event null is an error.
	if config.start_event == null:
		messages.append(_err("config.start_event is null"))

	# §3.7 / §8.1: resource def bounds.
	_validate_resource_defs(config, messages)

	# §8.1 typo catch + dead-choice walk operate over an event set: start_event
	# ∪ BFS over choice.target_event ∪ resource_defs bottom/top-out ∪ pool
	# events when an index is supplied. Mirrors the Step-6 _resolve_event_id
	# walk but collects ALL reachable rather than returning the first id match
	# (different return shapes — see Step-6 follow-ups note in PROGRESS.md).
	var events: Array[JourneyEvent] = _collect_events(config, pool_index)

	# §3.8 / §8.1: empty + duplicate ids.
	_validate_ids(events, messages)

	# §4.3 declared-key set: resource ops referencing keys outside this set
	# warn (typo catch). Flag ops never warn — flags are created lazily by
	# spec (§4.3) and have no "declared" concept.
	var declared_keys: Dictionary = _declared_resource_keys(config)
	for event in events:
		if event == null:
			continue
		_validate_event_conditions(event, declared_keys, messages)
		_validate_event_choices(event, declared_keys, messages)

	if pool_index == null:
		messages.append(_warn("pool was not validated — pass a built JourneyPoolIndex to include pool events"))

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

## BFS-collect every JourneyEvent reachable for validation. Visited keyed by
## object instance_id so two events sharing a String(id) (the duplicate-id
## case) both end up in the output for _validate_ids to detect — keying by
## id_str instead would silently dedupe duplicates and hide the bug.
static func _collect_events(config: JourneyConfig, pool_index: JourneyPoolIndex) -> Array[JourneyEvent]:
	var visited: Dictionary = {}
	var out: Array[JourneyEvent] = []
	var queue: Array[JourneyEvent] = []

	if config.start_event != null:
		queue.append(config.start_event)
	for def in config.resource_defs:
		if def == null:
			continue
		if def.bottom_out_event != null:
			queue.append(def.bottom_out_event)
		if def.top_out_event != null:
			queue.append(def.top_out_event)
	if pool_index != null:
		for e in pool_index.all_events:
			queue.append(e)

	# Index-cursor BFS (avoids O(n) pop_front per step — same pattern Step-6
	# follow-up #1 used in JourneySequenceManager._resolve_event_id).
	var head: int = 0
	while head < queue.size():
		var ev: JourneyEvent = queue[head]
		head += 1
		if ev == null:
			continue
		var key: int = ev.get_instance_id()
		if visited.has(key):
			continue
		visited[key] = true
		out.append(ev)
		for choice in ev.choices:
			if choice != null and choice.target_event != null:
				queue.append(choice.target_event)

	return out

## §3.8 id-validity rules. RULES MUST MATCH the load-time checks in
## JourneyPoolIndex._ingest (empty id, duplicate id). The two implementations
## differ in shape (this is collect-then-report; _ingest is reject-on-arrival)
## but the predicates are identical — if one changes, the other must too.
## (PROGRESS.md Step-7 entry flags this as a known parallel for the eventual
## consolidation pass; not extracted to a shared helper because the call-time
## semantics genuinely differ.)
##
## Note: events caught by _ingest's filter never reach pool_index.all_events,
## so duplicates PURELY within the pool dir are detected at load time (loud
## push_error) and not re-flagged here. This validator catches duplicates
## across the deterministic+pool union — the case _ingest can't see.
static func _validate_ids(events: Array[JourneyEvent], messages: Array) -> void:
	var by_id: Dictionary = {}  # id String -> Array[JourneyEvent]
	for ev in events:
		if ev == null:
			continue
		var id_str: String = String(ev.id)
		if id_str == "":
			var path: String = ev.resource_path if ev.resource_path != "" else "<in-memory>"
			messages.append(_err("event has empty id (resource: %s)" % path))
			continue
		var list: Array = by_id.get(id_str, [])
		list.append(ev)
		by_id[id_str] = list

	# Sort keys so duplicate messages emerge in deterministic order regardless
	# of dict insertion order (Godot Dictionary preserves insertion in 4.x,
	# but sorting is the explicit contract — same input ⇒ same output).
	var ids: Array = by_id.keys()
	ids.sort()
	for id_str in ids:
		var list: Array = by_id[id_str]
		if list.size() > 1:
			messages.append(_err("duplicate event id '%s' (%d events share this id)" % [id_str, list.size()]))

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
		# terminal choice CAN have null target + no pool + no consequences if
		# the author wanted a bare "End journey" button. But that's vanishingly
		# rare; real terminal choices almost always carry consequences (a
		# final state flip, an "ending kind" flag, etc.). The warning catches
		# the unfinished-node case without false-positiving the deliberate
		# one — and the author can suppress it by adding any consequence.
		if choice.target_event == null and not choice.continue_to_pool and choice.consequences.is_empty():
			messages.append(_warn("event '%s' choice[%d]: dead/unfinished — null target, no pool continuation, no consequences" % [eid, ci]))

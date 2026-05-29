extends RefCounted
class_name JourneySequenceManager

## Routing brain for the runtime (eng §5). Owns start/process/enter/end so the
## JourneyRuntime Autoload stays a thin public surface (eng §2). RefCounted, not
## a Node — it never touches the SceneTree and never instantiates UI; all
## reactive output goes back through the runtime's signal bus (§5.5).
##
## Holds a weak-ish reference to the owning runtime so it can read the
## Blackboard and emit signals. The runtime constructs the manager and passes
## itself in.

## Cap for metadata["history"] ring buffer per §10.2 (saves grow with playthrough
## length; turn_counter tracks true length separately).
const HISTORY_CAP: int = 200

var _runtime: Node  # JourneyRuntime; typed loosely to avoid a circular class_name dep at parse time.
var _config: JourneyConfig
## Reference to the event most recently entered. The Blackboard only stores its
## id (per save-friendly §3.8), so we keep the live object here so terminal
## choices can pass it to journey_ended without an id→event lookup.
var _current_event: JourneyEvent

## §6.1 event index. Routes EVERYTHING by id — start, deterministic targets,
## boundary routes, the saved current_event_id on load, and the stochastic pool
## — so it is built EAGERLY in start_new_journey (start_event_id must resolve
## before the first _enter_event). The instance is constructed up-front so
## rebuild_index() can be called before any pull has happened.
var _event_index: JourneyEventIndex = JourneyEventIndex.new()

func _init(runtime: Node) -> void:
	_runtime = runtime

## §5.1 entry. Initialization LOGIC stays on Blackboard.initialize() — this is
## just the relocated CALL SITE the Step-2 NOTE anticipated, composed with
## start_event routing and the journey_started signal.
##
## `events` (optional): an in-memory event list. When non-empty, the event index
## is built from it instead of scanning config.events_dir — for code-first /
## procedural content and tests where events aren't on disk. Routing is still
## entirely by id against that index, so behavior is otherwise identical.
func start_new_journey(config: JourneyConfig, seed: int = 0, events: Array[JourneyEvent] = []) -> void:
	_config = config
	if config == null:
		_runtime.journey_error.emit("start_new_journey called with null config")
		return
	# Build the event index up-front: start_event_id and every deterministic
	# route resolve against it, so it must exist before the first _enter_event.
	# A fresh instance so a second journey with a different events_dir doesn't
	# reuse the prior config's loaded events.
	_event_index = JourneyEventIndex.new()
	if not events.is_empty():
		_event_index.build_from_events(events)
	elif config.events_dir != "":
		_event_index.build(config.events_dir)
	_runtime.blackboard.initialize(config, seed)
	_runtime.journey_started.emit()
	if String(config.start_event_id) == "":
		_runtime.journey_error.emit("no start_event_id")
		return
	var start_event: JourneyEvent = _event_index.find_by_id(String(config.start_event_id))
	if start_event == null:
		_runtime.journey_error.emit("start_event_id '%s' did not resolve to an indexed event (check events_dir)" % config.start_event_id)
		return
	_enter_event(start_event)

## §5.1 routing. Strict precedence: forced bottom/top-out > deterministic target
## > continue_to_pool (stochastic pull via JourneyEventIndex) > end journey.
##
## Signal emission strategy for per-mutation resource_changed/flag_changed
## (§5.3): the Mutator stays pure (no signals), so we snapshot every key
## TOUCHED by this batch BEFORE applying, then apply the whole batch via
## JourneyMutator.apply_batch, then diff post-clamp values and emit one signal
## per actual change. Reading post-clamp values from bb.resources is exactly
## what §5.3 mandates ("reporting the actual stored value"). Only keys named in
## consequences are diffed — unrelated keys aren't scanned, so cost stays O(n).
func process_choice(choice: JourneyChoice) -> void:
	if choice == null:
		_runtime.journey_error.emit("process_choice called with null choice")
		return
	if _config == null:
		_runtime.journey_error.emit("process_choice called before start_new_journey")
		return

	var bb: Blackboard = _runtime.blackboard

	# Snapshot pre-mutation values for keys this batch will touch.
	var resource_before: Dictionary = {}
	var flag_before: Dictionary = {}
	for con in choice.consequences:
		match con.operation:
			JourneyConsequence.Operation.SET_FLAG, JourneyConsequence.Operation.TOGGLE_FLAG:
				if not flag_before.has(con.key):
					flag_before[con.key] = bb.flags.get(con.key, false)
			_:
				if not resource_before.has(con.key):
					resource_before[con.key] = bb.resources.get(con.key, 0.0)

	var triggered: Array[JourneyResourceDef] = JourneyMutator.apply_batch(choice.consequences, bb, _config)

	# Diff and emit per-mutation signals using POST-CLAMP stored values (§5.3).
	for key in resource_before:
		var old_v: float = resource_before[key]
		# If the key was undeclared, the Mutator skipped it and the key may not
		# exist on the blackboard. Skip — nothing to report.
		if not bb.resources.has(key):
			continue
		var new_v: float = bb.resources[key]
		if new_v != old_v:
			_runtime.resource_changed.emit(key, old_v, new_v)
	for key in flag_before:
		var old_f: bool = flag_before[key]
		var new_f: bool = bb.flags.get(key, false)
		if new_f != old_f:
			_runtime.flag_changed.emit(key, new_f)

	# §4.4 determinism: of all boundary triggers in this batch, the FIRST (lowest
	# resource_defs index) wins. The Mutator already returns them in definition
	# order, so triggered[0] is correct.
	var forced_id: StringName = &""
	if not triggered.is_empty():
		var def: JourneyResourceDef = triggered[0]
		var v: float = bb.resources.get(def.key, 0.0)
		if v == def.max_value:
			forced_id = def.top_out_event_id
		elif v == def.min_value:
			forced_id = def.bottom_out_event_id

	# Routing precedence (§5.1, §5.4): forced > target > pool > end. All
	# deterministic routes resolve by id against the event index; an id that
	# was authored but doesn't resolve is a loud journey_error, not a silent
	# fall-through (the validator/round-trip check catch it at authoring time).
	if String(forced_id) != "":
		var forced: JourneyEvent = _event_index.find_by_id(String(forced_id))
		if forced == null:
			_runtime.journey_error.emit("boundary route '%s' did not resolve to an indexed event" % forced_id)
			return
		_enter_event(forced)
		return
	if String(choice.target_event_id) != "":
		var target: JourneyEvent = _event_index.find_by_id(String(choice.target_event_id))
		if target == null:
			_runtime.journey_error.emit("target_event_id '%s' did not resolve to an indexed event" % choice.target_event_id)
			return
		_enter_event(target)
		return
	if choice.continue_to_pool:
		_route_to_pool(choice)
		return

	# Terminal choice: end on the current event so the UI gets the ending screen.
	_end_journey(_current_event)

## §5.2 enter. Null-route guard, metadata bookkeeping, seen marking, visible-
## choice filtering, event_changed emission. Visible-choice filtering lives
## HERE so every front end gets identical filtering (Dumb-UI contract §5.5).
##
## `is_restore` (added in Step 6 for §7.3): when true, this is a load-driven
## re-entry of the SAVED current event — the UI needs an event_changed signal
## so widgets rebuild, but turn_counter / history / seen_ids must NOT advance
## (they already reflect the saved state). Skip the bookkeeping; keep the
## signal. Normal (non-restore) callers see IDENTICAL behavior to before.
func _enter_event(event: JourneyEvent, is_restore: bool = false) -> void:
	if event == null:
		_runtime.journey_error.emit("route resolved to null")
		return

	_current_event = event
	var bb: Blackboard = _runtime.blackboard
	var id_str: String = String(event.id)

	if not is_restore:
		bb.metadata["current_event_id"] = id_str
		bb.metadata["turn_counter"] = int(bb.metadata.get("turn_counter", 0)) + 1

		var history: Array = bb.metadata.get("history", [])
		history.append(id_str)
		# Ring-buffer cap per §10.2: drop oldest beyond HISTORY_CAP.
		while history.size() > HISTORY_CAP:
			history.pop_front()
		bb.metadata["history"] = history

		var seen: Array = bb.metadata.get("seen_ids", [])
		if not seen.has(id_str):
			seen.append(id_str)
		bb.metadata["seen_ids"] = seen

	var visible: Array[JourneyChoice] = []
	for choice in event.choices:
		if JourneyEvaluator.eval_group(choice.visibility, bb):
			visible.append(choice)

	_runtime.event_changed.emit(event, visible)

func _end_journey(ending_event: JourneyEvent) -> void:
	_runtime.journey_ended.emit(ending_event)

## §6.2 pool pull. The event index is normally already built (eagerly at
## start_new_journey); this rebuilds defensively if not. Empty pool →
## journey_error per §6.4; the game does NOT crash — the journey simply can't
## advance from this choice, which surfaces as a dev-visible error.
func _route_to_pool(choice: JourneyChoice) -> void:
	if not _event_index.is_built() and _config.events_dir != "":
		_event_index.build(_config.events_dir)
	var bb: Blackboard = _runtime.blackboard
	var seen: Array = bb.metadata.get("seen_ids", [])
	var event: JourneyEvent = _event_index.select(choice.pool_tags_filter, bb, seen, _config)
	if event == null:
		_runtime.journey_error.emit("empty pool for tags: %s" % str(choice.pool_tags_filter))
		return
	_enter_event(event)

## [Studio]/editor hot-reload entry point (§3.7 / §6.1). Rebuilds the event
## index from config.events_dir; safe to call before any pool pull has happened.
func rebuild_index() -> void:
	if _config == null:
		push_warning("JourneySequenceManager.rebuild_index: no active config")
		return
	_event_index.rebuild(_config.events_dir)

## Read-only accessor so JourneyRuntime can reach config.save_encryption_key /
## save_version without poking _config directly. Returns null pre-start.
func get_config() -> JourneyConfig:
	return _config

## Read-only accessor used by JourneyRuntime.validate() (§8.1) so the validator
## can resolve ids against the live index. Returns the index ONLY if it's
## already built (a journey was started or rebuild_index was called); null
## otherwise — the validator itself decides whether to build a fresh one.
func get_event_index() -> JourneyEventIndex:
	if _event_index != null and _event_index.is_built():
		return _event_index
	return null

## §7.3 post-load re-entry. Caller (JourneyRuntime.load_game) has already
## restored the Blackboard in place; we now resolve the saved
## `current_event_id` to a live JourneyEvent and re-enter it with
## `is_restore=true` so event_changed fires WITHOUT advancing turn state.
##
## Resolution: a single id lookup against the event index (see _resolve_event_id).
## Returns OK on success, ERR_INVALID_DATA if the id can't be resolved (after
## emitting journey_error for dev visibility).
func restore_after_load() -> int:
	if _config == null:
		push_error("JourneySequenceManager.restore_after_load: no active config")
		return ERR_UNCONFIGURED
	var bb: Blackboard = _runtime.blackboard
	var id_str: String = String(bb.metadata.get("current_event_id", ""))
	if id_str == "":
		_runtime.journey_error.emit("save references empty event id")
		return ERR_INVALID_DATA
	var event: JourneyEvent = _resolve_event_id(id_str)
	if event == null:
		_runtime.journey_error.emit("save references unknown event id: %s" % id_str)
		return ERR_INVALID_DATA
	_enter_event(event, true)
	return OK

## §7.3 id → event. Now a single O(1) lookup against the event index — under
## id-based routing EVERY event (deterministic and pool) is indexed by id, so
## there is no longer a deterministic-only graph to BFS. This structurally
## fixes the Step-6 findings #1/#4: events reachable only via a pool→target
## chain, or rooted at a bottom-out boundary, are now first-class index entries
## rather than nodes the old object-ref walk could miss. Builds the index
## defensively if a load somehow precedes start_new_journey. Returns null on
## genuine miss only.
func _resolve_event_id(id_str: String) -> JourneyEvent:
	if not _event_index.is_built() and _config.events_dir != "":
		_event_index.build(_config.events_dir)
	return _event_index.find_by_id(id_str)

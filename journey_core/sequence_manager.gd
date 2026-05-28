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

## §6.1 stochastic pool. Built lazily on the first pool pull (or via the
## public rebuild_pool() hook) — eager build at start_new_journey is also
## permitted by §6.1, but lazy keeps games that never enter the pool from
## paying a directory scan. The instance itself is constructed up-front so
## rebuild_pool() can be called before any pull has happened.
var _pool_index: JourneyPoolIndex = JourneyPoolIndex.new()

func _init(runtime: Node) -> void:
	_runtime = runtime

## §5.1 entry. Initialization LOGIC stays on Blackboard.initialize() — this is
## just the relocated CALL SITE the Step-2 NOTE anticipated, composed with
## start_event routing and the journey_started signal.
func start_new_journey(config: JourneyConfig, seed: int = 0) -> void:
	_config = config
	if config == null:
		_runtime.journey_error.emit("start_new_journey called with null config")
		return
	# Reset the pool index so a second journey with a different event_pool_dir
	# doesn't reuse the prior config's loaded events. Lazy rebuild on first pull.
	_pool_index = JourneyPoolIndex.new()
	_runtime.blackboard.initialize(config, seed)
	_runtime.journey_started.emit()
	if config.start_event == null:
		_runtime.journey_error.emit("no start_event")
		return
	_enter_event(config.start_event)

## §5.1 routing. Strict precedence: forced bottom/top-out > deterministic target
## > continue_to_pool (Step 5: stochastic pull via JourneyPoolIndex) > end journey.
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
	var forced: JourneyEvent = null
	if not triggered.is_empty():
		var def: JourneyResourceDef = triggered[0]
		var v: float = bb.resources.get(def.key, 0.0)
		if v == def.max_value and def.top_out_event != null:
			forced = def.top_out_event
		elif v == def.min_value and def.bottom_out_event != null:
			forced = def.bottom_out_event

	# Routing precedence (§5.1, §5.4): forced > target > pool > end.
	if forced != null:
		_enter_event(forced)
		return
	if choice.target_event != null:
		_enter_event(choice.target_event)
		return
	if choice.continue_to_pool:
		_route_to_pool(choice)
		return

	# Terminal choice: end on the current event so the UI gets the ending screen.
	_end_journey(_current_event)

## §5.2 enter. Null-route guard, metadata bookkeeping, seen marking, visible-
## choice filtering, event_changed emission. Visible-choice filtering lives
## HERE so every front end gets identical filtering (Dumb-UI contract §5.5).
func _enter_event(event: JourneyEvent) -> void:
	if event == null:
		_runtime.journey_error.emit("route resolved to null")
		return

	_current_event = event
	var bb: Blackboard = _runtime.blackboard
	var id_str: String = String(event.id)
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

## §6.2 pool pull. Lazily builds the index from config.event_pool_dir on the
## first pull. Empty pool → journey_error per §6.4; the game does NOT crash —
## the journey simply can't advance from this choice, which surfaces as a
## dev-visible error rather than a hidden no-op.
func _route_to_pool(choice: JourneyChoice) -> void:
	if not _pool_index.is_built():
		_pool_index.build(_config.event_pool_dir)
	var bb: Blackboard = _runtime.blackboard
	var seen: Array = bb.metadata.get("seen_ids", [])
	var event: JourneyEvent = _pool_index.select(choice.pool_tags_filter, bb, seen, _config)
	if event == null:
		_runtime.journey_error.emit("empty pool for tags: %s" % str(choice.pool_tags_filter))
		return
	_enter_event(event)

## [Studio]/editor hot-reload entry point (§3.7 / §6.1). Rebuilds the pool
## index from config.event_pool_dir; safe to call before any pool pull has
## happened.
func rebuild_pool() -> void:
	if _config == null:
		push_warning("JourneySequenceManager.rebuild_pool: no active config")
		return
	_pool_index.rebuild(_config.event_pool_dir)

extends Node

## The single public entry point for game code (eng §9). Registered as an
## Autoload named "JourneyRuntime" — see project setup note in PROGRESS.md.
## Owns the Blackboard and an internal SequenceManager helper; all routing /
## mutation / signal emission lives in the helper, so this file stays a thin
## API surface.
##
## NOTE: deliberately NO `class_name JourneyRuntime` — that global would
## collide with the autoload's auto-registered singleton name ("Class
## 'JourneyRuntime' hides an autoload singleton"). Game code accesses this
## script through the autoload identifier, not as a class.
##
## Presentation Contract (§5.5): this is a Node only because Autoloads must be
## Nodes. It MUST NOT instantiate UI nodes, add children, or touch the
## SceneTree. Reactive output is signals only; data inside those signals is
## inert (events, choice arrays, primitives).

## Engine version, SemVer (https://semver.org). Bump on release and keep in sync
## with addons/journey_engine_core/plugin.cfg. Games can read JourneyRuntime.VERSION
## to assert compatibility at runtime. Independent of JourneyConfig.save_version,
## which only tracks the on-disk save format.
const VERSION := "0.3.1"

# --- Signals (§5.3) — declare exactly these. ---
signal event_changed(event: JourneyEvent, choices: Array[JourneyChoice])
signal resource_changed(key: String, old_value: float, new_value: float)
signal flag_changed(key: String, value: bool)
signal journey_started()
signal journey_ended(ending_event: JourneyEvent)
signal journey_error(message: String)

## Public for the SequenceManager to read/initialize. Game code MUST NOT write
## this dictionary directly — all mutation flows through process_choice →
## Mutator (the §9 single-mutation-path invariant). Read-only convenience
## helpers (get_resource / has_flag / get_metadata) are below.
var blackboard: Blackboard = Blackboard.new()

var _seq: JourneySequenceManager

func _ready() -> void:
	_seq = JourneySequenceManager.new(self)

# --- Lifecycle (§9) ---

## `events` (optional): supply an in-memory event list to route against instead
## of scanning config.events_dir — for code-first / procedural content and tests.
## Routing is still by id against the resulting index.
func start_new_journey(config: JourneyConfig, seed: int = 0, events: Array[JourneyEvent] = []) -> void:
	if _seq == null:
		# Defensive: if a caller invokes this before _ready (e.g. another
		# autoload's _enter_tree), construct the helper on demand.
		_seq = JourneySequenceManager.new(self)
	_seq.start_new_journey(config, seed, events)

func process_choice(choice: JourneyChoice) -> void:
	if _seq == null:
		journey_error.emit("process_choice called before runtime ready")
		return
	_seq.process_choice(choice)

# --- Read-only state access (§9) ---

## Missing-key read policy (§4.3) is a *condition* policy and warns there.
## get_resource is a UI convenience read — missing key returns 0.0 with no
## warning so HUD widgets binding by string don't spam logs before init.
func get_resource(key: String) -> float:
	return float(blackboard.resources.get(key, 0.0))

func has_flag(key: String) -> bool:
	return bool(blackboard.flags.get(key, false))

func get_metadata(key: String) -> Variant:
	return blackboard.metadata.get(key, null)

# --- Persistence + dev (§9). ---

## §7.2 save. Delegates to a stateless JourneySaveManager; encryption is
## opt-in via config.save_encryption_key (empty ⇒ plaintext, PRD §5 default).
## Requires an active journey — save_encryption_key / save_version live on
## the config, which only exists after start_new_journey.
func save_game(slot: String = "savegame") -> int:
	if _seq == null or _seq.get_config() == null:
		push_warning("JourneyRuntime.save_game: no active journey (call start_new_journey first)")
		return ERR_UNCONFIGURED
	var config: JourneyConfig = _seq.get_config()
	var manager := JourneySaveManager.new()
	return manager.save(blackboard, slot, config.save_encryption_key, config.save_version)

## §7.3 load. Restores the Blackboard in place, then re-enters the saved
## current event via the SequenceManager's restore path so event_changed
## re-fires (UI rebuilds for free, no special restore code) WITHOUT advancing
## turn_counter / history / seen_ids (those already reflect the saved state).
## Pool index is built on demand inside restore_after_load — load may happen
## before any pool pull, but resolution still needs the index.
##
## Atomicity: load_into mutates the Blackboard BEFORE restore_after_load
## resolves the event id. If resolution fails (unknown id, finding #3 in the
## Step-6 code review), the Blackboard would otherwise be left "data loaded,
## no event_changed emitted" — UI shows stale event, bb holds post-load
## state, next process_choice mutates the loaded bb against pre-load
## semantics and produces nonsense. We snapshot the pre-load state and roll
## it back on any failure so the runtime stays consistent on the error path.
##
## Resource-defs forward-compat (finding #5): after a successful load_into,
## any resource declared in the CURRENT config but absent from the save
## (e.g., added in a content update before its save migration ships) is
## seeded to its clamped default — same policy Blackboard.initialize uses,
## so post-load reads see the intended baseline instead of a missing key.
func load_game(slot: String = "savegame") -> int:
	if _seq == null or _seq.get_config() == null:
		push_warning("JourneyRuntime.load_game: no active journey (call start_new_journey first)")
		return ERR_UNCONFIGURED
	var config: JourneyConfig = _seq.get_config()
	var manager := JourneySaveManager.new()

	# Pre-load snapshot for rollback on failure. Dict.duplicate(true) deep-
	# copies primitives; rng.state is an int. Cheap relative to the rest of
	# load and only paid on the load_game path.
	var rb_resources: Dictionary = blackboard.resources.duplicate(true)
	var rb_flags: Dictionary = blackboard.flags.duplicate(true)
	var rb_metadata: Dictionary = blackboard.metadata.duplicate(true)
	var rb_rng_state: int = blackboard.rng.state
	var rb_rng_seed: int = blackboard.rng.seed

	var err: int = manager.load_into(blackboard, slot, config.save_encryption_key, config.save_version)
	if err != OK:
		# load_into errors out BEFORE any bb mutation (file/version/precondition
		# checks all precede the writes), so no rollback needed here.
		return err

	# Seed any config-declared resource missing from the save with its clamped
	# default — forward-compat for content updates that add resources before a
	# v2 migration lands.
	for def in config.resource_defs:
		if not blackboard.resources.has(def.key):
			blackboard.resources[def.key] = clamp(def.default_value, def.min_value, def.max_value)

	var restore_err: int = _seq.restore_after_load()
	if restore_err != OK:
		# Roll back: load_into already mutated bb, but the routing layer can't
		# resolve the saved event. Restore pre-load state so the runtime/UI
		# stays consistent and the player can retry or start a new journey.
		blackboard.resources = rb_resources
		blackboard.flags = rb_flags
		blackboard.metadata = rb_metadata
		blackboard.rng.state = rb_rng_state
		blackboard.rng.seed = rb_rng_seed
		return restore_err
	return OK

## §8.1 dev-only authoring validator. Per §9 the public surface returns
## flattened [ERROR]/[WARNING]-prefixed strings (empty = clean). Internally
## defers to JourneyValidator.validate(config, index) — the richer typed form
## that Studio calls directly on save (§8.1 [Studio]), so the same rules govern
## both. Routing is id-based, so the validator needs a built event index to
## resolve ids and run per-event checks: we reuse the live index if a journey is
## active, else build a throwaway one from config.events_dir so authoring-time
## validate() still checks id resolution (the most important structural rule).
##
## NOTE: §8.1 intends games to invoke this in _ready under OS.is_debug_build() —
## shipping builds should not pay the walk cost. Studio (separate plugin) calls
## JourneyValidator.validate directly to get the typed dicts; this wrapper exists
## for games that want a plain string list to drop into a debug log.
func validate(config: JourneyConfig) -> Array[String]:
	var index: JourneyEventIndex = null
	if _seq != null:
		index = _seq.get_event_index()
	if index == null and config != null and config.events_dir != "":
		# No live index (validate called before start) — build a throwaway one so
		# id resolution and per-event checks can run.
		index = JourneyEventIndex.new()
		index.build(config.events_dir)
	var typed: Array = JourneyValidator.validate(config, index)
	var out: Array[String] = []
	for m in typed:
		var sev: String = String(m.get("severity", ""))
		var prefix: String = "[ERROR] " if sev == JourneyValidator.SEVERITY_ERROR else "[WARNING] "
		out.append(prefix + String(m.get("message", "")))
	return out

## [Studio]/editor hot-reload hook (§9 / §3.7). Forwards to the SequenceManager,
## which owns the event index. Safe to call before the first pool pull; the index
## itself is rebuilt against config.events_dir.
func rebuild_index() -> void:
	if _seq == null:
		push_warning("JourneyRuntime.rebuild_index: runtime not ready")
		return
	_seq.rebuild_index()

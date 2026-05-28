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

func start_new_journey(config: JourneyConfig, seed: int = 0) -> void:
	if _seq == null:
		# Defensive: if a caller invokes this before _ready (e.g. another
		# autoload's _enter_tree), construct the helper on demand.
		_seq = JourneySequenceManager.new(self)
	_seq.start_new_journey(config, seed)

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

# --- Persistence + dev (§9). Stubs for now; implemented in Steps 6–7. ---

func save_game(_slot: String = "savegame") -> int:
	push_warning("JourneyRuntime.save_game: not implemented until Step 6")
	return ERR_UNAVAILABLE

func load_game(_slot: String = "savegame") -> int:
	push_warning("JourneyRuntime.load_game: not implemented until Step 6")
	return ERR_UNAVAILABLE

func validate(_config: JourneyConfig) -> Array[String]:
	push_warning("JourneyRuntime.validate: not implemented until Step 7")
	return []

func rebuild_pool() -> void:
	push_warning("JourneyRuntime.rebuild_pool: not implemented until Step 5")

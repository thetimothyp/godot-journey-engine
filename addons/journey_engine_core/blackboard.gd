extends RefCounted
class_name Blackboard

## All mutable playthrough state in one passable object: bounded numeric resources,
## boolean flags, free-form metadata, and a seeded RNG. Pure state container — no
## mutation helpers, no evaluation, no signals. The runtime owns the single
## sanctioned write path (consequences via Mutator, Step 3).

## String -> float. Bounds are defined by JourneyResourceDef and enforced by the
## Mutator on write; the only clamp performed here is on initial values (§4.2).
var resources: Dictionary = {}
## String -> bool. Missing flag reads as false (§4.3).
var flags: Dictionary = {}
## String -> Variant. ENGINE-OWNED keys preserved across save/load:
##   current_event_id (String), turn_counter (int), seen_ids (Array[String]),
##   history (Array[String]), rng_seed (int).
## Saves serialize ONLY these (§7.1); load_into clears bb.metadata and
## restores only these keys. Custom/runtime metadata written outside this
## whitelist (e.g. transient breadcrumbs, debug counters) is intentionally
## DROPPED on every load — if a game needs persistent custom state it should
## live in resources/flags or a separate save extension (see §10.1 split
## path). Reads via JourneyRuntime.get_metadata() still work for those keys
## within a single session but won't survive a round-trip.
var metadata: Dictionary = {}
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Initialize from config per §4.2: seed resources at clamped defaults, copy
## initial flags, seed the RNG (deterministic if seed != 0, else randomize), and
## prime metadata. This is the one sanctioned bulk-write; all later mutation
## must flow through consequences.
## NOTE: Step 4 may relocate the *call site* to JourneyRuntime.start_new_journey
## so initialization composes with start_event routing, but the logic itself
## belongs to the Blackboard and stays here.
func initialize(config: JourneyConfig, seed: int = 0) -> void:
	resources.clear()
	flags.clear()
	metadata.clear()

	for def in config.resource_defs:
		resources[def.key] = clamp(def.default_value, def.min_value, def.max_value)

	for flag_key in config.initial_flags:
		flags[flag_key] = config.initial_flags[flag_key]

	if seed != 0:
		rng.seed = seed
	else:
		rng.randomize()
	metadata["rng_seed"] = rng.seed

	metadata["turn_counter"] = 0
	metadata["current_event_id"] = ""
	metadata["history"] = []
	metadata["seen_ids"] = []

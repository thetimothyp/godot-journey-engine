extends RefCounted
class_name JourneyMutator

## Pure, stateless writer over (consequence, blackboard, config). The single
## sanctioned numeric/flag mutation path for the engine (eng §9). Stays static +
## RefCounted so it is unit-testable headlessly (no Autoload, no SceneTree;
## §8.2). Applies the §4.4 clamp + bottom/top-out detection rules.
##
## NOTE: This helper only MUTATES. It does NOT emit signals and it does NOT
## route. Per-mutation resource_changed/flag_changed signals are wired in Step 4
## around these calls inside JourneyRuntime. Routing on bottom/top-out is also
## Step 4 (SequenceManager); apply_batch only DETECTS and REPORTS boundary
## triggers, leaving the choice of which to fire to the SequenceManager.

## Apply one consequence to the blackboard. Numeric ops clamp to the matching
## JourneyResourceDef's bounds; a numeric op against a key with no matching def
## is SKIPPED with a push_warning (missing-key policy §4.3 — never auto-create
## an undeclared, unbounded resource).
static func apply_consequence(con: JourneyConsequence, bb: Blackboard, config: JourneyConfig) -> void:
	match con.operation:
		JourneyConsequence.Operation.SET_FLAG:
			bb.flags[con.key] = con.flag_value
			return
		JourneyConsequence.Operation.TOGGLE_FLAG:
			bb.flags[con.key] = not bb.flags.get(con.key, false)
			return
		_:
			var def: JourneyResourceDef = _find_resource_def(config, con.key)
			if def == null:
				push_warning("JourneyMutator: consequence targets undeclared resource key '%s'; skipping mutation (no JourneyResourceDef means no bounds)" % con.key)
				return
			var current: float = bb.resources.get(con.key, 0.0)
			var raw: float = current
			match con.operation:
				JourneyConsequence.Operation.ADD:       raw = current + con.value
				JourneyConsequence.Operation.SUBTRACT:  raw = current - con.value
				JourneyConsequence.Operation.SET_VALUE: raw = con.value
			bb.resources[con.key] = clamp(raw, def.min_value, def.max_value)

## Apply an ordered batch of consequences, then detect (don't route) any
## resource defs that ended sitting at a boundary with a forced-route event
## configured. Per §4.4:
##  - Apply EVERY consequence first (batch completes before any forced route).
##  - Scan resource_defs in DEFINITION ORDER for clamped value == min_value with
##    a bottom_out_event set, or == max_value with a top_out_event set.
##  - Return the triggered defs in definition order.
##
## The Step 4 SequenceManager will route to the FIRST returned def's event
## (lowest def index) and ignore the rest — that's the deterministic rule for
## "sanity and rations both hit zero on the same choice." Detection here,
## routing there.
##
## Float equality at boundaries: we compare with == against def.min_value /
## def.max_value directly. clamp() forces an exact assignment to the bound, so
## the stored value is bit-identical to the bound; no epsilon needed.
static func apply_batch(consequences: Array[JourneyConsequence], bb: Blackboard, config: JourneyConfig) -> Array[JourneyResourceDef]:
	for con in consequences:
		apply_consequence(con, bb, config)

	var triggered: Array[JourneyResourceDef] = []
	for def in config.resource_defs:
		if not bb.resources.has(def.key):
			continue
		var v: float = bb.resources[def.key]
		if v == def.min_value and def.bottom_out_event != null:
			triggered.append(def)
		elif v == def.max_value and def.top_out_event != null:
			triggered.append(def)
	return triggered

static func _find_resource_def(config: JourneyConfig, key: String) -> JourneyResourceDef:
	for def in config.resource_defs:
		if def.key == key:
			return def
	return null

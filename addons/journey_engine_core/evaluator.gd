extends RefCounted
class_name JourneyEvaluator

## Pure, stateless reader over (resource, blackboard). Evaluates JourneyConditions
## and JourneyConditionGroups against a Blackboard with no side effects beyond the
## missing-key warnings mandated by §4.3. Kept static + RefCounted so unit tests
## can drive it with constructed resources and a bare Blackboard — no Autoload,
## no SceneTree (eng §2, §8.2).
##
## NOTE: This helper only READS. The single sanctioned write path is the Mutator
## (Step 3 sibling) wired through JourneyRuntime in Step 4.

## Evaluate a single condition. Missing-key policy per §4.3:
##  - Missing resource key on a numeric op → treat as 0.0 AND push_warning.
##  - Missing flag key → false (HAS_FLAG → false, NOT_FLAG → true), no warning.
static func eval_condition(c: JourneyCondition, bb: Blackboard) -> bool:
	match c.op:
		JourneyCondition.Op.HAS_FLAG:
			return bb.flags.get(c.key, false) == true
		JourneyCondition.Op.NOT_FLAG:
			return bb.flags.get(c.key, false) == false
		_:
			var lhs: float
			if bb.resources.has(c.key):
				lhs = bb.resources[c.key]
			else:
				var owning_id: String = ""
				if bb.metadata != null and bb.metadata.has("current_event_id"):
					owning_id = str(bb.metadata["current_event_id"])
				if owning_id != "":
					push_warning("JourneyEvaluator: condition references missing resource key '%s' (event '%s'); treating as 0.0" % [c.key, owning_id])
				else:
					push_warning("JourneyEvaluator: condition references missing resource key '%s'; treating as 0.0" % c.key)
				lhs = 0.0
			match c.op:
				JourneyCondition.Op.GT:  return lhs >  c.value
				JourneyCondition.Op.GTE: return lhs >= c.value
				JourneyCondition.Op.LT:  return lhs <  c.value
				JourneyCondition.Op.LTE: return lhs <= c.value
				JourneyCondition.Op.EQ:  return lhs == c.value
				JourneyCondition.Op.NEQ: return lhs != c.value
	return false

## Evaluate a group:
##  - Null group → true (no constraint; §3.5 null visibility = always).
##  - Empty group → true for BOTH ALL and ANY (§3.3 anti-footgun).
##  - ALL → every condition must pass; ANY → at least one must pass.
static func eval_group(g: JourneyConditionGroup, bb: Blackboard) -> bool:
	if g == null:
		return true
	if g.conditions.is_empty():
		return true
	if g.logic == JourneyConditionGroup.Logic.ALL:
		for c in g.conditions:
			if not eval_condition(c, bb):
				return false
		return true
	else:
		for c in g.conditions:
			if eval_condition(c, bb):
				return true
		return false

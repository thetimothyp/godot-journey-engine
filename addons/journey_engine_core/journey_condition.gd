extends Resource
class_name JourneyCondition

## A single typed comparison against the Blackboard (one resource or flag check).

enum Op { GT, GTE, LT, LTE, EQ, NEQ, HAS_FLAG, NOT_FLAG }

@export var key: String = ""
@export var op: Op = Op.GTE
## Ignored for HAS_FLAG / NOT_FLAG.
@export var value: float = 0.0

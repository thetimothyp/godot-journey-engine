extends Resource
class_name JourneyConsequence

## A single typed mutation applied to the Blackboard (numeric op or flag op).

enum Operation { ADD, SUBTRACT, SET_VALUE, SET_FLAG, TOGGLE_FLAG }

@export var operation: Operation = Operation.ADD
@export var key: String = ""
## Numeric ops only (ADD / SUBTRACT / SET_VALUE).
@export var value: float = 0.0
## SET_FLAG only.
@export var flag_value: bool = true

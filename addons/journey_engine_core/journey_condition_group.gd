extends Resource
class_name JourneyConditionGroup

## A single-level ALL/ANY group of conditions. Empty group passes (vacuous truth).

enum Logic { ALL, ANY }

@export var logic: Logic = Logic.ALL
@export var conditions: Array[JourneyCondition] = []

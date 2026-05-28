extends Resource
class_name JourneyChoice

## A choice the player can take: visibility gate, consequences, and routing.

@export_multiline var button_text: String = ""
## Null ⇒ always visible.
@export var visibility: JourneyConditionGroup
@export var consequences: Array[JourneyConsequence] = []

@export_group("Routing")
## Deterministic route; non-null takes precedence over pool pulls.
@export var target_event: JourneyEvent
## If true and target_event is null, request a stochastic pool pull.
@export var continue_to_pool: bool = false
## Optional tag scope for the pool pull; empty ⇒ all events.
@export var pool_tags_filter: Array[String] = []

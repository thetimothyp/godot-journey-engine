extends Resource
class_name JourneyChoice

## A choice the player can take: visibility gate, consequences, and routing.

@export_multiline var button_text: String = ""
## Null ⇒ always visible.
@export var visibility: JourneyConditionGroup
@export var consequences: Array[JourneyConsequence] = []

@export_group("Routing")
## Deterministic route, by event id: a non-empty id (resolved at runtime
## against the event index) takes precedence over pool pulls. Routing by id
## (not an eager JourneyEvent reference) keeps every event independently
## loadable and makes routing graphs — including legitimate day-loops —
## serializable; a cyclic chain of object references is not. Empty ⇒ no
## deterministic route.
@export var target_event_id: StringName = &""
## If true and target_event_id is empty, request a stochastic pool pull.
@export var continue_to_pool: bool = false
## Optional tag scope for the pool pull; empty ⇒ all events.
@export var pool_tags_filter: Array[String] = []

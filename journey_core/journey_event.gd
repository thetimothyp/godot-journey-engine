extends Resource
class_name JourneyEvent

## A narrative node: presentation payload + tags + pool eligibility + choices.

@export_group("Presentation")
@export_multiline var narrative_text: String = ""
@export var background_texture: Texture2D
@export var ambient_audio: AudioStream

@export_group("System")
## Stable identity used by saves and the pool index; must be unique and non-empty for pool events.
@export var id: StringName = &""
@export var event_tags: Array[String] = []
## Static selection weight for the stochastic pool.
@export var weight: int = 100
## Eligibility gate for inclusion in a stochastic pool pull.
@export var pool_conditions: JourneyConditionGroup
## If false, the event is excluded from future pool pulls after being seen.
@export var repeatable: bool = false
@export var choices: Array[JourneyChoice] = []

extends Resource
class_name JourneyEvent

## A narrative node: presentation payload + tags + pool eligibility + choices.

@export_group("Presentation")
@export_multiline var narrative_text: String = ""
@export var background_texture: Texture2D
@export var ambient_audio: AudioStream

@export_group("System")
## Stable identity used by saves, the event index, and all routing. Must be
## unique and non-empty for ANY event that is a routing target (start_event_id,
## choice.target_event_id, a boundary route) or pool-eligible.
@export var id: StringName = &""
@export var event_tags: Array[String] = []
## Static selection weight for the stochastic pool.
@export var weight: int = 100
## If true, the event is a candidate for stochastic pool pulls. Pool draws are
## scoped by this flag (not by directory); deterministic-only events leave it
## false so they're never randomly selected, even though they share the index.
@export var pool_eligible: bool = false
## Eligibility gate for inclusion in a stochastic pool pull.
@export var pool_conditions: JourneyConditionGroup
## If false, the event is excluded from future pool pulls after being seen.
@export var repeatable: bool = false
@export var choices: Array[JourneyChoice] = []

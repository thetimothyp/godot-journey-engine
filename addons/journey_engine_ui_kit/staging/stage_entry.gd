extends Resource
class_name JourneyStageEntry

## Staging for one event: which sprite(s) to show and who's speaking. Keyed by
## `event_id`, which must match a JourneyEvent.id (the stable, save-safe identity).

## Matches JourneyEvent.id.
@export var event_id: StringName = &""
## Optional speaker name shown above the narrative strip. Empty ⇒ no speaker line.
@export var speaker: String = ""
## One or more sprites for this event. The default stage uses a single figure, but
## the array supports multi-actor scenes without a data change.
@export var sprites: Array[JourneySpritePlacement] = []

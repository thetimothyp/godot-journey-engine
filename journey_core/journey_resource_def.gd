extends Resource
class_name JourneyResourceDef

## Schema for one numeric resource: key, bounds, default, and bottom/top-out routes.

@export var key: String = ""
@export var default_value: float = 0.0
@export var min_value: float = 0.0
@export var max_value: float = 100.0
## Fired when the clamped value hits min_value.
@export var bottom_out_event: JourneyEvent
## Optional; fired when the clamped value hits max_value.
@export var top_out_event: JourneyEvent

extends Resource
class_name JourneyHudBinding

## One row of the ResourceHud: which Blackboard value to show and how to label it.
##
## The kit never hardcodes gold/sanity/rations — a game declares its HUD as an
## Array[JourneyHudBinding] on JourneyStageView / JourneyResourceHud, so the same widget
## drives any resource schema. Values are read through the public accessors
## (get_resource / get_metadata) — never the Blackboard directly.

## Blackboard key to read. A resource key (read via get_resource) unless
## is_metadata is true, in which case it's a metadata key (read via get_metadata).
@export var key: String = ""

## printf-style format applied to the read value, e.g. "Gold: %d" or "HP %0.1f".
## %d coerces the float/variant to int; %s prints any metadata variant as text.
@export var label_format: String = "%s: %d"

## Optional icon shown left of the label.
@export var icon: Texture2D

## When true, read via JourneyRuntime.get_metadata(key) instead of get_resource(key)
## — lets a binding surface turn_counter or other engine metadata on the same HUD.
@export var is_metadata: bool = false

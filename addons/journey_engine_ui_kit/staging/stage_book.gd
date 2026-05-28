extends Resource
class_name JourneyStageBook

## A presentation-side map of `event.id → staging` (sprite[s] + speaker). This is the
## kit's answer to "which character/visual goes with which event" WITHOUT putting
## presentation data in the core: JourneyEvent carries the background and ambient
## audio, but foreground actors and direction live here, keyed by the same stable
## event id that saves use.
##
## Assign one of these to a JourneyStageView (or JourneyForegroundLayer). An event
## with no entry simply shows no sprite.

@export var entries: Array[JourneyStageEntry] = []

var _by_id: Dictionary = {}
var _indexed: bool = false

## Returns the entry for an event id, or null. Builds the lookup on first use and
## warns once on duplicate / empty ids (a lightweight authoring drift check, in the
## spirit of the engine's validate()).
func get_entry(event_id: StringName) -> JourneyStageEntry:
	if not _indexed:
		_build_index()
	return _by_id.get(event_id, null)

func _build_index() -> void:
	_by_id.clear()
	for entry in entries:
		if entry == null:
			continue
		if entry.event_id == &"":
			push_warning("JourneyStageBook: entry with empty event_id ignored")
			continue
		if _by_id.has(entry.event_id):
			push_warning("JourneyStageBook: duplicate event_id '%s' — later entry wins" % entry.event_id)
		_by_id[entry.event_id] = entry
	_indexed = true

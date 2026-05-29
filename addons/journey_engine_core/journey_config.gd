extends Resource
class_name JourneyConfig

## Per-game global config: resource schema, initial flags, start event, pool, save settings.

@export var resource_defs: Array[JourneyResourceDef] = []
## String -> bool.
@export var initial_flags: Dictionary = {}
## Id of the first event, resolved at runtime against the event index built
## from events_dir. Routing is id-based throughout (see JourneyChoice).
@export var start_event_id: StringName = &""

@export_group("Events")
## Recursively scanned for ALL JourneyEvents (deterministic and pool alike),
## which are indexed by id. Pool draws are scoped by JourneyEvent.pool_eligible,
## not by directory — folders are only an authoring convenience.
@export var events_dir: String = "res://events/"
## [Studio] hot-reload hook for in-editor event-index rebuilds.
@export var rebuild_index_in_editor: bool = true

@export_group("Save")
## Empty ⇒ plaintext.
@export var save_encryption_key: String = ""
## Migration anchor; bump on breaking save-format changes.
@export var save_version: int = 1

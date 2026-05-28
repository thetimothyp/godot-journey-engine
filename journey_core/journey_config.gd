extends Resource
class_name JourneyConfig

## Per-game global config: resource schema, initial flags, start event, pool, save settings.

@export var resource_defs: Array[JourneyResourceDef] = []
## String -> bool.
@export var initial_flags: Dictionary = {}
@export var start_event: JourneyEvent

@export_group("Pool")
@export var event_pool_dir: String = "res://events/"
## [Studio] hot-reload hook for in-editor pool rebuilds.
@export var rebuild_pool_in_editor: bool = true

@export_group("Save")
## Empty ⇒ plaintext.
@export var save_encryption_key: String = ""
## Migration anchor; bump on breaking save-format changes.
@export var save_version: int = 1

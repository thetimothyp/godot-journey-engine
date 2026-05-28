extends HBoxContainer
class_name JourneyResourceHud

## A configurable resource read-out. Bindings (Array[JourneyHudBinding]) declare
## which Blackboard values to show and how to label them — the kit hardcodes NO
## resource names. Values are read ONLY through the public accessors
## (get_resource / get_metadata); the Blackboard is never touched directly.
##
## Update policy mirrors the engine's signal model:
##  - journey_started / repaint(): full read of every binding.
##  - resource_changed(key,…): update just that key's label (optional count-up).
##  - event_changed: refresh metadata bindings only (e.g. turn_counter, which the
##    engine changes without a per-value signal).
## repaint() is public so a host can repaint after load_game — load bulk-restores
## the Blackboard and fires NO resource_changed signals (documented core behavior).

@export var bindings: Array[JourneyHudBinding] = []
@export var separation: int = 24

@export_group("Change animation")
## Count up/down to the new value instead of snapping. Resource bindings only.
@export var animate_changes: bool = true
@export var animate_duration: float = 0.3

## One built row: its binding + the label it writes to.
var _rows: Array[Dictionary] = []
## key -> row, for fast resource_changed updates.
var _by_key: Dictionary = {}
var _value_tweens: Dictionary = {}

func _ready() -> void:
	add_theme_constant_override("separation", separation)
	_build()
	JourneyRuntime.journey_started.connect(repaint)
	JourneyRuntime.resource_changed.connect(_on_resource_changed)
	JourneyRuntime.event_changed.connect(_on_event_changed)

func _build() -> void:
	for child in get_children():
		child.queue_free()
	_rows.clear()
	_by_key.clear()
	for binding in bindings:
		if binding == null or binding.key == "":
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		if binding.icon != null:
			var icon := TextureRect.new()
			icon.texture = binding.icon
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(20, 20)
			row.add_child(icon)
		var label := Label.new()
		row.add_child(label)
		add_child(row)
		var entry := {"binding": binding, "label": label}
		_rows.append(entry)
		_by_key[binding.key] = entry

## Full repaint — reads every binding via the public accessors.
func repaint() -> void:
	for entry in _rows:
		_write(entry, _read(entry["binding"]))

func _on_event_changed(_event: JourneyEvent, _choices: Array[JourneyChoice]) -> void:
	# Metadata (e.g. turn_counter) changes without a resource_changed signal;
	# refresh those each event. Resource rows are driven by resource_changed.
	for entry in _rows:
		if (entry["binding"] as JourneyHudBinding).is_metadata:
			_write(entry, _read(entry["binding"]))

func _on_resource_changed(key: String, old_value: float, new_value: float) -> void:
	if not _by_key.has(key):
		return
	var entry: Dictionary = _by_key[key]
	if animate_changes and animate_duration > 0.0:
		_animate_value(entry, old_value, new_value)
	else:
		_write(entry, new_value)

func _read(binding: JourneyHudBinding) -> Variant:
	if binding.is_metadata:
		return JourneyRuntime.get_metadata(binding.key)
	return JourneyRuntime.get_resource(binding.key)

func _write(entry: Dictionary, value: Variant) -> void:
	var binding: JourneyHudBinding = entry["binding"]
	var label: Label = entry["label"]
	label.text = binding.label_format % value

func _animate_value(entry: Dictionary, from_value: float, to_value: float) -> void:
	var key: String = (entry["binding"] as JourneyHudBinding).key
	if _value_tweens.has(key) and (_value_tweens[key] as Tween).is_valid():
		(_value_tweens[key] as Tween).kill()
	var t := create_tween()
	t.tween_method(func(v: float) -> void: _write(entry, v), from_value, to_value, animate_duration)
	_value_tweens[key] = t

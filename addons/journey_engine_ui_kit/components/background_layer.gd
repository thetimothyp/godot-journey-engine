extends Control
class_name JourneyBackgroundLayer

## Displays JourneyEvent.background_texture and crossfades between events, with
## optional slow idle motion (zoom/drift) so a static image still feels alive.
##
## This is the component that finally PRESENTS the background_texture payload the
## core has always carried but never drawn. It reads only the event handed in by
## event_changed — no Blackboard access. A null background crossfades to
## default_texture (a placeholder ships with the kit), or to nothing if unset.

## Shown when an event has no background_texture. The kit ships a placeholder.
@export var default_texture: Texture2D
@export var crossfade_duration: float = 0.6

@export_group("Idle motion")
@export var idle_motion: bool = true
## Peak extra zoom (0.06 = up to 6% larger) over a cycle.
@export var idle_zoom: float = 0.06
## Horizontal drift in pixels over a cycle.
@export var idle_drift: float = 18.0
## Seconds for one in-out motion cycle.
@export var idle_period: float = 14.0

var _motion: Control
var _rect_a: TextureRect
var _rect_b: TextureRect
var _active: TextureRect
var _current_texture: Texture2D
var _fade_tween: Tween
var _idle_tween: Tween

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true  # keep idle zoom from spilling past the view
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	resized.connect(_recenter_pivot)
	_recenter_pivot()
	JourneyRuntime.event_changed.connect(_on_event_changed)
	if idle_motion:
		_start_idle()

func _build() -> void:
	if _motion != null:
		return
	_motion = Control.new()
	_motion.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_motion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_motion)
	_rect_a = _make_rect()
	_rect_b = _make_rect()
	_rect_a.modulate.a = 0.0
	_rect_b.modulate.a = 0.0
	_active = _rect_a
	# Show the default immediately so the view isn't blank before the first event.
	if default_texture != null:
		_active.texture = default_texture
		_active.modulate.a = 1.0
		_current_texture = default_texture

func _make_rect() -> TextureRect:
	var r := TextureRect.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_motion.add_child(r)
	return r

func _on_event_changed(event: JourneyEvent, _choices: Array[JourneyChoice]) -> void:
	var tex: Texture2D = event.background_texture if event != null else null
	if tex == null:
		tex = default_texture
	set_background(tex)

## Crossfades to a new background. Re-passing the current texture is a no-op so
## re-entering the same event (e.g. on load) doesn't flicker.
func set_background(tex: Texture2D) -> void:
	if tex == _current_texture:
		return
	_current_texture = tex
	var incoming := _rect_b if _active == _rect_a else _rect_a
	var outgoing := _active
	incoming.texture = tex
	incoming.modulate.a = 0.0
	_active = incoming
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	_fade_tween.tween_property(incoming, "modulate:a", 1.0, crossfade_duration)
	_fade_tween.tween_property(outgoing, "modulate:a", 0.0, crossfade_duration)

func _recenter_pivot() -> void:
	if _motion != null:
		_motion.pivot_offset = size * 0.5

func _start_idle() -> void:
	if _motion == null:
		return
	if _idle_tween != null and _idle_tween.is_valid():
		_idle_tween.kill()
	var half := idle_period * 0.5
	_idle_tween = create_tween()
	_idle_tween.set_loops()
	_idle_tween.set_trans(Tween.TRANS_SINE)
	_idle_tween.set_ease(Tween.EASE_IN_OUT)
	# Zoom in + drift right, then back. pivot keeps the zoom centered.
	_idle_tween.tween_property(_motion, "scale", Vector2.ONE * (1.0 + idle_zoom), half)
	_idle_tween.parallel().tween_property(_motion, "position:x", idle_drift, half)
	_idle_tween.tween_property(_motion, "scale", Vector2.ONE, half)
	_idle_tween.parallel().tween_property(_motion, "position:x", 0.0, half)

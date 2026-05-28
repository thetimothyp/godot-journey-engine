extends Control
class_name JourneyForegroundLayer

## Stages foreground character sprite(s) in front of the background — the visual focus
## of the "stage" presentation scheme (Sort the Court style). Subscribes to
## event_changed and resolves staging for the event:
##
##   1. the assigned JourneyStageBook's entry for event.id (preferred — richer:
##      multiple sprites, anchors, speaker, entrance choreography), else
##   2. event.get("foreground_texture") as a single centered sprite. That property
##      does not exist on JourneyEvent today (get() returns null safely); this is a
##      no-rework hook so that IF the core ever adds a foreground_texture field
##      (symmetric with background_texture), it works with no kit change.
##
## No staging for an event ⇒ no sprite (graceful). Reads only the inert event payload
## — no Blackboard access. Emits `staged(speaker)` so a host (JourneyStageView) can
## show the speaker line.

@export var stage_book: JourneyStageBook
@export var entrance_duration: float = 0.4
@export var entrance_distance: float = 48.0
@export var entrance_easing: Tween.EaseType = Tween.EASE_OUT
@export var entrance_transition: Tween.TransitionType = Tween.TRANS_CUBIC

@export_group("Idle motion")
@export var idle_bob: bool = true
## Vertical bob amplitude in pixels.
@export var idle_bob_pixels: float = 6.0
@export var idle_bob_period: float = 3.2

## Horizontal inset for LEFT/RIGHT anchors, as a fraction of width.
const SIDE_INSET := 0.10

## Fired on each event with the resolved speaker ("" when none).
signal staged(speaker: String)

## Active sprites: { rect: TextureRect, placement: JourneySpritePlacement,
##                   resting: Vector2, size: Vector2, idle: Tween }
var _sprites: Array[Dictionary] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_relayout)
	JourneyRuntime.event_changed.connect(_on_event_changed)

func _on_event_changed(event: JourneyEvent, _choices: Array[JourneyChoice]) -> void:
	_clear()
	var speaker := ""
	var placements: Array[JourneySpritePlacement] = []

	var entry: JourneyStageEntry = null
	if stage_book != null and event != null:
		entry = stage_book.get_entry(event.id)
	if entry != null:
		speaker = entry.speaker
		placements = entry.sprites
	elif event != null:
		# Future core-field hook: single centered sprite if the event ever carries one.
		var fg: Variant = event.get("foreground_texture")
		if fg is Texture2D:
			var p := JourneySpritePlacement.new()
			p.texture = fg
			placements = [p]

	for placement in placements:
		if placement != null and placement.texture != null:
			_add_sprite(placement)
	staged.emit(speaker)

func _add_sprite(placement: JourneySpritePlacement) -> void:
	var rect := TextureRect.new()
	rect.texture = placement.texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.flip_h = placement.flip_h
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.modulate.a = 0.0
	add_child(rect)
	var entry := {"rect": rect, "placement": placement, "resting": Vector2.ZERO, "size": Vector2.ZERO, "idle": null}
	_sprites.append(entry)
	_layout_sprite(entry)
	_play_entrance(entry)

func _layout_sprite(entry: Dictionary) -> void:
	var placement: JourneySpritePlacement = entry["placement"]
	var tex_size: Vector2 = placement.texture.get_size()
	if tex_size.y <= 0.0:
		return
	var h: float = size.y * placement.height_ratio
	var w: float = h * (tex_size.x / tex_size.y)
	var x: float = 0.0
	match placement.anchor:
		JourneySpritePlacement.Anchor.CENTER: x = (size.x - w) * 0.5
		JourneySpritePlacement.Anchor.LEFT: x = size.x * SIDE_INSET
		JourneySpritePlacement.Anchor.RIGHT: x = size.x - w - size.x * SIDE_INSET
	var resting := Vector2(x + placement.offset.x, size.y - h + placement.offset.y)
	entry["resting"] = resting
	entry["size"] = Vector2(w, h)
	var rect: TextureRect = entry["rect"]
	rect.size = Vector2(w, h)
	rect.position = resting

func _play_entrance(entry: Dictionary) -> void:
	var rect: TextureRect = entry["rect"]
	var resting: Vector2 = entry["resting"]
	var placement: JourneySpritePlacement = entry["placement"]
	var from := resting
	match placement.enter:
		JourneySpritePlacement.Enter.SLIDE_UP:
			from = resting + Vector2(0, entrance_distance)
		JourneySpritePlacement.Enter.SLIDE_SIDE:
			var dir := -1.0 if placement.anchor == JourneySpritePlacement.Anchor.RIGHT else 1.0
			from = resting + Vector2(-dir * entrance_distance, 0)
		JourneySpritePlacement.Enter.FADE:
			from = resting
	rect.position = from
	var t := create_tween()
	t.set_parallel(true)
	t.set_ease(entrance_easing)
	t.set_trans(entrance_transition)
	t.tween_property(rect, "modulate:a", 1.0, entrance_duration)
	if from != resting:
		t.tween_property(rect, "position", resting, entrance_duration)
	t.chain().tween_callback(func() -> void: _start_idle(entry))

func _start_idle(entry: Dictionary) -> void:
	if not idle_bob or idle_bob_pixels <= 0.0:
		return
	var rect: TextureRect = entry["rect"]
	var resting: Vector2 = entry["resting"]
	var half := idle_bob_period * 0.5
	var t := create_tween()
	t.set_loops()
	t.set_ease(Tween.EASE_IN_OUT)
	t.set_trans(Tween.TRANS_SINE)
	t.tween_property(rect, "position:y", resting.y - idle_bob_pixels, half)
	t.tween_property(rect, "position:y", resting.y, half)
	entry["idle"] = t

func _relayout() -> void:
	# View resized: recompute rests, snap sprites there, restart idle from the new rest.
	for entry in _sprites:
		var idle = entry["idle"]
		if idle != null and (idle as Tween).is_valid():
			(idle as Tween).kill()
		_layout_sprite(entry)
		_start_idle(entry)

func _clear() -> void:
	for entry in _sprites:
		var idle = entry["idle"]
		if idle != null and (idle as Tween).is_valid():
			(idle as Tween).kill()
		(entry["rect"] as Node).queue_free()
	_sprites.clear()

extends Control
class_name JourneyTransitionLayer

## A full-view scene transition between events (fade-through-color or wipe). It owns
## a covering rect and exposes two await-able halves:
##   await play_out()  — cover the view (call BEFORE process_choice)
##   await play_in()   — reveal the new view (call AFTER event_changed has rendered)
##
## This is how the kit sequences animation against the engine without making the
## engine wait: ChoiceList plays out, calls JourneyRuntime.process_choice (which
## synchronously re-renders every component under the cover), then plays in. The
## engine never blocks — all pacing is client-side (Presentation Contract §5.5).
##
## Used standalone (no ChoiceList), enable auto_reveal to play_in automatically when
## event_changed fires.

enum Kind {
	NONE,  ## No transition; play_out / play_in return immediately.
	FADE,  ## Fade a solid color in, then out.
	WIPE,  ## Slide a solid color across the view (in from the left, out to the right).
}

@export var kind: Kind = Kind.FADE
@export var duration: float = 0.35
@export var color: Color = Color(0.05, 0.05, 0.07, 1.0)
@export var easing: Tween.EaseType = Tween.EASE_IN_OUT
@export var transition: Tween.TransitionType = Tween.TRANS_SINE
## When true, automatically play_in on event_changed. Leave false when a host
## (JourneyView/ChoiceList) drives the out→process_choice→in sequence itself.
@export var auto_reveal: bool = false

var _cover: ColorRect

func _ready() -> void:
	_build()
	if auto_reveal:
		JourneyRuntime.event_changed.connect(func(_e, _c) -> void: play_in())

func _build() -> void:
	if _cover != null:
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover = ColorRect.new()
	_cover.color = color
	_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP  # block clicks mid-transition
	_cover.visible = false
	_cover.modulate.a = 0.0
	add_child(_cover)

## Cover the view. Await this before swapping content.
func play_out() -> void:
	if _cover == null:
		_build()
	_cover.color = color
	if kind == Kind.NONE:
		return
	_cover.visible = true
	var t := create_tween()
	t.set_ease(easing)
	t.set_trans(transition)
	if kind == Kind.FADE:
		_cover.position = Vector2.ZERO
		_cover.modulate.a = 0.0
		t.tween_property(_cover, "modulate:a", 1.0, duration)
	else: # WIPE in from the left
		_cover.modulate.a = 1.0
		_cover.position = Vector2(-size.x, 0.0)
		t.tween_property(_cover, "position:x", 0.0, duration)
	await t.finished

## Reveal the view. Await this after the new content has rendered.
func play_in() -> void:
	if _cover == null:
		_build()
	if kind == Kind.NONE:
		return
	if not _cover.visible:
		return
	var t := create_tween()
	t.set_ease(easing)
	t.set_trans(transition)
	if kind == Kind.FADE:
		t.tween_property(_cover, "modulate:a", 0.0, duration)
	else: # WIPE out to the right
		t.tween_property(_cover, "position:x", size.x, duration)
	t.tween_callback(func() -> void: _cover.visible = false)
	await t.finished

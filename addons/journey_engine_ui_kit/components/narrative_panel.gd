extends PanelContainer
class_name JourneyNarrativePanel

## Renders JourneyEvent.narrative_text and owns the text-reveal pacing.
##
## Presentation Contract (§5.5): the engine never blocks or waits — pacing is the
## UI's to own. This panel decides how fast text appears; the engine has already
## advanced by the time event_changed fires. Subscribes to event_changed only and
## reads nothing from the Blackboard (the event payload carries the text).
##
## Drop this script on a PanelContainer, or let JourneyView build it. It wires its
## own RichTextLabel child on _ready, so it works standalone.

## How the narrative appears on each event.
enum Reveal {
	INSTANT,    ## Text shown immediately.
	FADE,       ## Whole label fades in over reveal_duration.
	TYPEWRITER, ## Characters reveal left-to-right via visible_ratio over reveal_duration.
}

@export_group("Reveal")
@export var reveal_mode: Reveal = Reveal.TYPEWRITER
## Seconds for the reveal to complete (FADE / TYPEWRITER). INSTANT ignores this.
@export var reveal_duration: float = 0.45
@export var reveal_easing: Tween.EaseType = Tween.EASE_OUT
@export var reveal_transition: Tween.TransitionType = Tween.TRANS_SINE

## Fired when the reveal finishes — ChoiceList can wait on this to gate input, the
## same "fade in, then enable buttons" pattern the sample game uses.
signal reveal_finished()

var _label: RichTextLabel
var _reveal_tween: Tween

func _ready() -> void:
	_build()
	JourneyRuntime.event_changed.connect(_on_event_changed)

func _build() -> void:
	if _label != null:
		return
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(_label)

## Public so a host can re-render the current event's text (e.g. after a load the
## host wants to re-reveal). Normal flow drives this via event_changed.
func show_narrative(text: String) -> void:
	if _label == null:
		_build()
	_kill_tweens()
	_label.clear()
	_label.append_text(text)
	_play_reveal()

func _on_event_changed(event: JourneyEvent, _choices: Array[JourneyChoice]) -> void:
	if event == null:
		return
	show_narrative(event.narrative_text)

func _play_reveal() -> void:
	match reveal_mode:
		Reveal.INSTANT:
			_label.modulate.a = 1.0
			_label.visible_ratio = 1.0
			reveal_finished.emit()
		Reveal.FADE:
			_label.visible_ratio = 1.0
			_label.modulate.a = 0.0
			_reveal_tween = create_tween()
			_reveal_tween.set_ease(reveal_easing)
			_reveal_tween.set_trans(reveal_transition)
			_reveal_tween.tween_property(_label, "modulate:a", 1.0, reveal_duration)
			_reveal_tween.tween_callback(reveal_finished.emit)
		Reveal.TYPEWRITER:
			_label.modulate.a = 1.0
			_label.visible_ratio = 0.0
			_reveal_tween = create_tween()
			_reveal_tween.set_ease(reveal_easing)
			_reveal_tween.set_trans(reveal_transition)
			_reveal_tween.tween_property(_label, "visible_ratio", 1.0, reveal_duration)
			_reveal_tween.tween_callback(reveal_finished.emit)

func _kill_tweens() -> void:
	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()

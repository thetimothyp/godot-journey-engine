extends Control
class_name JourneyEndingOverlay

## Full-view overlay shown when the run ends. Subscribes to journey_ended (renders
## the ending event's narrative_text) and journey_started (hides itself). The
## "Begin again" button restarts the journey.
##
## Restart wiring: if `config` is assigned it restarts itself via start_new_journey;
## it also emits `restart_requested` so a host can drive the restart instead. The
## ending event is the inert payload from the signal — no Blackboard access.

## Optional — assign to let the overlay restart on its own. JourneyView sets this.
@export var config: JourneyConfig
@export var seed: int = 0
@export var fade_duration: float = 0.4
@export var dim_color: Color = Color(0.04, 0.04, 0.06, 0.92)
@export var begin_again_text: String = "Begin again"

## Optional SFX collaborator (set by JourneyView). Plays sfx_ending on journey end.
var audio_layer: JourneyAudioLayer

signal restart_requested()

var _panel: ColorRect
var _label: RichTextLabel
var _button: Button
var _fade_tween: Tween

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	visible = false
	JourneyRuntime.journey_ended.connect(_on_journey_ended)
	JourneyRuntime.journey_started.connect(_on_journey_started)

func _build() -> void:
	if _panel != null:
		return
	mouse_filter = Control.MOUSE_FILTER_STOP  # swallow clicks to the view beneath
	_panel = ColorRect.new()
	_panel.color = dim_color
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 24)
	col.custom_minimum_size = Vector2(520, 0)
	center.add_child(col)

	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_label)

	_button = Button.new()
	_button.text = begin_again_text
	_button.focus_mode = Control.FOCUS_NONE
	_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_button.pressed.connect(_on_begin_again)
	col.add_child(_button)

func _on_journey_ended(ending_event: JourneyEvent) -> void:
	var body := ""
	var ending_id := "<null>"
	if ending_event != null:
		body = ending_event.narrative_text
		ending_id = String(ending_event.id)
	_label.clear()
	_label.append_text("[center][b]The road ends.[/b]\n\n%s\n\n[i](ending: %s)[/i][/center]" % [body, ending_id])
	visible = true
	if audio_layer != null:
		audio_layer.play_sfx(audio_layer.sfx_ending)
	modulate.a = 0.0
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 1.0, fade_duration)

func _on_journey_started() -> void:
	visible = false

func _on_begin_again() -> void:
	if audio_layer != null:
		audio_layer.play_sfx(audio_layer.sfx_button_press)
	restart_requested.emit()
	if config != null:
		JourneyRuntime.start_new_journey(config, seed)

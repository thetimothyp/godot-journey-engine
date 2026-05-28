extends Control
class_name JourneyStageView

## A visual-first assembled view (Sort the Court style): a full-screen background +
## foreground character sprite are the focus, while the narrative and choices are
## present but subordinate — a slim resource bar on top, a short dialogue strip and a
## row of choice buttons along the bottom.
##
## It reuses every kit component, each subscribing to JourneyRuntime independently;
## this assembler only arranges them and wires the few collaborator references. Same
## contract holds: JourneyChoiceList is the sole process_choice caller, reads go
## through accessors, the engine is never made to wait. Staging
## (which sprite/speaker per event) comes from an assigned JourneyStageBook — see
## JourneyForegroundLayer. Set `config` and `stage_book` and run.

@export_group("Journey")
@export var config: JourneyConfig
@export var seed: int = 0
@export var autostart: bool = true

@export_group("Theme")
## Applied to this node (cascades to all components) if no Theme is already set.
## Defaults to the kit's stage theme (outlined text + scrims for readability over art).
@export var default_theme: Theme

@export_group("Stage")
## Maps event.id → sprite(s) + speaker. See JourneyStageBook.
@export var stage_book: JourneyStageBook
@export var default_background: Texture2D
@export var background_idle_motion: bool = true

@export_group("HUD")
@export var hud_bindings: Array[JourneyHudBinding] = []

@export_group("Choices")
## Show choices that fail their visibility as disabled (greyed) buttons rather than
## hiding them (e.g. a "Pay 30 gold" choice locked when you can't afford it).
@export var show_locked_choices: bool = true

@export_group("Narrative")
@export var reveal_mode: JourneyNarrativePanel.Reveal = JourneyNarrativePanel.Reveal.TYPEWRITER
@export var reveal_duration: float = 0.4

@export_group("Transition")
## Stage default is NONE — the background crossfade + sprite restage carry the change,
## rather than a full-screen wipe. Set FADE/WIPE for a harder cut.
@export var transition_kind: JourneyTransitionLayer.Kind = JourneyTransitionLayer.Kind.NONE
@export var transition_duration: float = 0.35

@export_group("SFX (assign your own AudioStreams; empty = silent)")
@export var sfx_button_hover: AudioStream
@export var sfx_button_press: AudioStream
@export var sfx_choice_confirm: AudioStream
@export var sfx_save: AudioStream
@export var sfx_load: AudioStream
@export var sfx_ending: AudioStream

var background: JourneyBackgroundLayer
var foreground: JourneyForegroundLayer
var hud: JourneyResourceHud
var narrative: JourneyNarrativePanel
var choices: JourneyChoiceList
var save_load_bar: JourneySaveLoadBar
var ending_overlay: JourneyEndingOverlay
var transition: JourneyTransitionLayer
var audio: JourneyAudioLayer

var _speaker: Label
var _toast: Label
var _toast_timer: Timer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if theme == null and default_theme != null:
		theme = default_theme
	_build()
	if autostart and config != null:
		JourneyRuntime.start_new_journey(config, seed)

func _build() -> void:
	# Audio + transition first; ChoiceList needs references to them.
	audio = JourneyAudioLayer.new()
	audio.sfx_button_hover = sfx_button_hover
	audio.sfx_button_press = sfx_button_press
	audio.sfx_choice_confirm = sfx_choice_confirm
	audio.sfx_save = sfx_save
	audio.sfx_load = sfx_load
	audio.sfx_ending = sfx_ending

	transition = JourneyTransitionLayer.new()
	transition.kind = transition_kind
	transition.duration = transition_duration

	# Background, then foreground sprites in front of it.
	background = JourneyBackgroundLayer.new()
	background.default_texture = default_background
	background.idle_motion = background_idle_motion
	add_child(background)

	foreground = JourneyForegroundLayer.new()
	foreground.stage_book = stage_book
	add_child(foreground)

	# Structural overlay: top bar / flexible middle (lets the art show) / bottom block.
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	# Top: HUD (left) + save/load (right).
	var top_row := HBoxContainer.new()
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_theme_constant_override("separation", 16)
	column.add_child(top_row)

	hud = JourneyResourceHud.new()
	hud.bindings = hud_bindings
	top_row.add_child(hud)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(spacer)

	save_load_bar = JourneySaveLoadBar.new()
	save_load_bar.config = config
	save_load_bar.seed = seed
	save_load_bar.audio_layer = audio
	top_row.add_child(save_load_bar)

	# Flexible middle — empty, so the background + sprite are the focus.
	var middle := Control.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(middle)

	# Bottom block: speaker line, short narrative strip, choice button row.
	var bottom := VBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("separation", 8)
	column.add_child(bottom)

	_speaker = Label.new()
	_speaker.visible = false
	_speaker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(_speaker)
	foreground.staged.connect(_on_staged)

	narrative = JourneyNarrativePanel.new()
	narrative.reveal_mode = reveal_mode
	narrative.reveal_duration = reveal_duration
	narrative.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(narrative)

	choices = JourneyChoiceList.new()
	choices.vertical_layout = false  # horizontal row of buttons
	choices.show_locked_choices = show_locked_choices
	choices.add_theme_constant_override("separation", 12)
	choices.transition_layer = transition
	choices.audio_layer = audio
	bottom.add_child(choices)

	# Overlays on top: ending, then the transition cover above it.
	ending_overlay = JourneyEndingOverlay.new()
	ending_overlay.config = config
	ending_overlay.seed = seed
	ending_overlay.audio_layer = audio
	add_child(ending_overlay)

	add_child(transition)
	add_child(audio)

	_build_toast()
	save_load_bar.status.connect(_show_toast)
	save_load_bar.loaded.connect(_on_loaded)

func _on_staged(speaker: String) -> void:
	_speaker.text = speaker
	_speaker.visible = speaker != ""

func _build_toast() -> void:
	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 12.0
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(func() -> void: _toast.visible = false)
	add_child(_toast_timer)

func _on_loaded() -> void:
	# load_game fires no per-resource signals — repaint the HUD from the accessors.
	# event_changed DOES re-fire, so narrative / choices / background / sprites rebuild.
	ending_overlay.visible = false
	hud.repaint()

func _show_toast(message: String) -> void:
	_toast.text = message
	_toast.visible = true
	_toast_timer.start(2.5)

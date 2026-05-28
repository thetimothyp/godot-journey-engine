extends Control
class_name JourneyView

## One-line, drop-in presentation layer for the Journey Engine. Instantiates and
## lays out every kit component (background, HUD, narrative, choices, save/load,
## ending, transition, audio), wires the few kit-internal references, applies a
## default Theme, and (optionally) starts the journey.
##
## This is the ONLY place components reference each other; each component otherwise
## subscribes to JourneyRuntime signals independently. The contract still holds:
## ChoiceList is the sole caller of process_choice, all reads go through accessors,
## and the engine never waits on the kit's animations (see animations docs).
##
## Usage: add a JourneyView, assign `config` (and optionally a Theme, HUD bindings,
## SFX streams), run. To restyle, duplicate the kit Theme into your own folder and
## assign it here — never edit the addon's copy.

@export_group("Journey")
@export var config: JourneyConfig
@export var seed: int = 0
## Start the journey automatically on _ready. Turn off to drive it yourself.
@export var autostart: bool = true

@export_group("Theme")
## Applied to this node (cascades to all components) if no Theme is already set.
@export var default_theme: Theme

@export_group("HUD")
## Resource/metadata → label bindings. Empty ⇒ no HUD.
@export var hud_bindings: Array[JourneyHudBinding] = []

@export_group("Background")
@export var default_background: Texture2D
@export var background_idle_motion: bool = true

@export_group("Narrative")
@export var reveal_mode: JourneyNarrativePanel.Reveal = JourneyNarrativePanel.Reveal.TYPEWRITER
@export var reveal_duration: float = 0.45

@export_group("Transition")
@export var transition_kind: JourneyTransitionLayer.Kind = JourneyTransitionLayer.Kind.FADE
@export var transition_duration: float = 0.35

@export_group("SFX (assign your own AudioStreams; empty = silent)")
@export var sfx_button_hover: AudioStream
@export var sfx_button_press: AudioStream
@export var sfx_choice_confirm: AudioStream
@export var sfx_save: AudioStream
@export var sfx_load: AudioStream
@export var sfx_ending: AudioStream

var background: JourneyBackgroundLayer
var hud: JourneyResourceHud
var narrative: JourneyNarrativePanel
var choices: JourneyChoiceList
var save_load_bar: JourneySaveLoadBar
var ending_overlay: JourneyEndingOverlay
var transition: JourneyTransitionLayer
var audio: JourneyAudioLayer

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
	# --- Audio + transition first; ChoiceList needs references to them. ---
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

	# --- Background (behind everything). ---
	background = JourneyBackgroundLayer.new()
	background.default_texture = default_background
	background.idle_motion = background_idle_motion
	add_child(background)

	# --- Content column: HUD / body / save-load bar. ---
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)

	# HUD row (HUD on the left, save/load bar pushed to the right).
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 16)
	column.add_child(top_row)

	hud = JourneyResourceHud.new()
	hud.bindings = hud_bindings
	top_row.add_child(hud)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(spacer)

	save_load_bar = JourneySaveLoadBar.new()
	save_load_bar.config = config
	save_load_bar.seed = seed
	save_load_bar.audio_layer = audio
	top_row.add_child(save_load_bar)

	# Body: narrative (wider) + choices.
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	column.add_child(body)

	narrative = JourneyNarrativePanel.new()
	narrative.reveal_mode = reveal_mode
	narrative.reveal_duration = reveal_duration
	narrative.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	narrative.size_flags_stretch_ratio = 2.0
	body.add_child(narrative)

	var choices_panel := PanelContainer.new()
	choices_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(choices_panel)
	var choices_margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		choices_margin.add_theme_constant_override("margin_" + side, 12)
	choices_panel.add_child(choices_margin)

	choices = JourneyChoiceList.new()
	choices.add_theme_constant_override("separation", 8)
	choices.transition_layer = transition
	choices.audio_layer = audio
	choices_margin.add_child(choices)

	# --- Overlays on top: ending, then transition cover above it. ---
	ending_overlay = JourneyEndingOverlay.new()
	ending_overlay.config = config
	ending_overlay.seed = seed
	ending_overlay.audio_layer = audio
	add_child(ending_overlay)

	add_child(transition)
	add_child(audio)

	# --- Toast (save/load feedback), top-most. ---
	_build_toast()
	save_load_bar.status.connect(_show_toast)
	save_load_bar.loaded.connect(_on_loaded)

func _build_toast() -> void:
	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_toast.offset_top = -56.0
	_toast.offset_bottom = -24.0
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(func() -> void: _toast.visible = false)
	add_child(_toast_timer)

func _on_loaded() -> void:
	# load_game fires no per-resource signals — repaint the HUD from the accessors.
	# event_changed DOES re-fire, so narrative/choices/background rebuild for free.
	ending_overlay.visible = false
	hud.repaint()

func _show_toast(message: String) -> void:
	_toast.text = message
	_toast.visible = true
	_toast_timer.start(2.5)

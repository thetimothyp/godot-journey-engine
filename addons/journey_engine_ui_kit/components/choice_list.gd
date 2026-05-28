extends BoxContainer
class_name JourneyChoiceList

## Renders the already-filtered choices from event_changed and is the ONLY caller
## of JourneyRuntime.process_choice in the whole kit (the single write path,
## Presentation Contract §5). It also owns the input lock during transitions.
##
## The choices handed to event_changed are ALREADY visibility-filtered by the
## engine — this never re-checks visibility (filtering lives in core; see the
## Presentation Contract). It builds a Button per choice and animates them in.
##
## Sequencing (the heart of the kit's pacing, §5.5): the engine advances only on
## process_choice and never blocks, so on a press this does, client-side:
##   lock input → await transition.play_out() → process_choice(choice)
##   → (event_changed re-renders every component under the cover)
##   → await transition.play_in() → entrance animation → unlock.
## transition_layer / audio_layer are optional collaborators; with neither set it
## degrades to lock → process_choice → entrance → unlock.

## Stack choices vertically (reading layout, default) or in a horizontal row of
## buttons (stage layout). Extending BoxContainer instead of VBoxContainer lets the
## same component do both; true keeps the original VBox behavior.
@export var vertical_layout: bool = true

@export_group("Entrance")
@export var entrance_duration: float = 0.25
## Per-button delay so choices cascade in. 0 ⇒ all at once.
@export var entrance_stagger: float = 0.06
@export var button_focus_mode: Control.FocusMode = Control.FOCUS_NONE

@export_group("Collaborators")
## Optional. Assign in a scene, or let JourneyView wire these by reference.
@export var transition_layer_path: NodePath
@export var audio_layer_path: NodePath

## Set directly by a host (JourneyView) or resolved from the NodePaths above.
var transition_layer: JourneyTransitionLayer
var audio_layer: JourneyAudioLayer

var _input_locked: bool = false
var _transitioning: bool = false
var _entrance_tween: Tween

func _ready() -> void:
	vertical = vertical_layout
	if transition_layer == null and not transition_layer_path.is_empty():
		transition_layer = get_node_or_null(transition_layer_path) as JourneyTransitionLayer
	if audio_layer == null and not audio_layer_path.is_empty():
		audio_layer = get_node_or_null(audio_layer_path) as JourneyAudioLayer
	JourneyRuntime.event_changed.connect(_on_event_changed)
	JourneyRuntime.journey_ended.connect(_on_journey_ended)

func _on_event_changed(_event: JourneyEvent, choices: Array[JourneyChoice]) -> void:
	_rebuild(choices)
	# During a press-driven transition, _confirm() drives the reveal after play_in.
	# On the initial/non-orchestrated event, present immediately.
	if not _transitioning:
		_present()

func _on_journey_ended(_ending_event: JourneyEvent) -> void:
	_clear()
	_input_locked = true

# --- Building ---

func _rebuild(choices: Array[JourneyChoice]) -> void:
	_clear()
	for choice in choices:
		var btn := Button.new()
		btn.text = choice.button_text
		btn.focus_mode = button_focus_mode
		btn.disabled = true            # released when the entrance completes
		btn.modulate.a = 0.0           # faded out until the entrance tween
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_choice_pressed.bind(choice))
		if audio_layer != null:
			btn.mouse_entered.connect(func() -> void: audio_layer.play_sfx(audio_layer.sfx_button_hover))
		add_child(btn)

func _clear() -> void:
	if _entrance_tween != null and _entrance_tween.is_valid():
		_entrance_tween.kill()
	for child in get_children():
		child.queue_free()

# --- Presentation / pacing ---

func _present() -> void:
	# Fade the freshly-built buttons in (staggered), then unlock input.
	_input_locked = true
	var buttons := _buttons()
	if buttons.is_empty():
		_input_locked = false
		return
	_entrance_tween = create_tween()
	var i := 0
	for btn in buttons:
		_entrance_tween.parallel().tween_property(btn, "modulate:a", 1.0, entrance_duration).set_delay(i * entrance_stagger)
		i += 1
	await _entrance_tween.finished
	_set_disabled(false)
	_input_locked = false

func _on_choice_pressed(choice: JourneyChoice) -> void:
	if _input_locked:
		return
	_confirm(choice)

func _confirm(choice: JourneyChoice) -> void:
	# UI-owned input gate + client-side sequencing. The engine is none the wiser
	# that we animate around the single process_choice call.
	_input_locked = true
	_transitioning = true
	_set_disabled(true)
	if audio_layer != null:
		audio_layer.play_sfx(audio_layer.sfx_choice_confirm)

	if transition_layer != null:
		await transition_layer.play_out()

	# The single write into the engine. event_changed (or journey_ended) fires
	# synchronously here; _on_event_changed rebuilds the buttons under the cover.
	JourneyRuntime.process_choice(choice)

	if transition_layer != null:
		await transition_layer.play_in()

	_transitioning = false
	_present()

# --- Helpers ---

func _buttons() -> Array[Button]:
	var out: Array[Button] = []
	for child in get_children():
		if child is Button:
			out.append(child as Button)
	return out

func _set_disabled(disabled: bool) -> void:
	for btn in _buttons():
		btn.disabled = disabled

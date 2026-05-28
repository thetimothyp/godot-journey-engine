extends Control

## Sample-game Dumb-UI front end. Subscribes to JourneyRuntime signals (§4.1)
## and calls the public API only — never reads or writes the Blackboard, never
## reaches into journey_core internals. Three independent listeners share the
## scene tree (narrative, HUD, choices) so a future swap to a different UI
## skin requires touching only one of them.
##
## NOTE: this is a SAMPLE, not the future Starter UI Kit (which will be a
## separately-packaged Control hierarchy with stricter no-cross-reference
## rules). It follows the spirit: HUD / choices / narrative are independent
## signal subscribers, and process_choice is the only write into the engine.
##
## Pacing ownership (§5.5): a short tween fades the narrative in on
## event_changed and the choice buttons are disabled until the tween finishes
## — input is gated by the UI, not by the engine. The engine never blocks; if
## the player clicks during the fade, the click is ignored client-side.

const CONFIG_PATH := "res://sample_game/config.tres"
const SAVE_SLOT := "sample"
## A deterministic default so two fresh runs of the unmodified sample
## reproduce the same first pull — eyeballing determinism without writing a
## test. Set to 0 to opt back into RandomNumberGenerator.randomize().
const DEFAULT_SEED := 13371

@onready var _narrative: RichTextLabel = $Layout/Body/NarrativePanel/Margin/Narrative
@onready var _choices_box: VBoxContainer = $Layout/Body/ChoicesPanel/ChoicesMargin/Choices
@onready var _gold_label: Label = $Layout/Hud/Gold
@onready var _sanity_label: Label = $Layout/Hud/Sanity
@onready var _rations_label: Label = $Layout/Hud/Rations
@onready var _turn_label: Label = $Layout/Hud/Turn
@onready var _save_btn: Button = $Layout/Hud/SaveBtn
@onready var _load_btn: Button = $Layout/Hud/LoadBtn
@onready var _restart_btn: Button = $Layout/Hud/RestartBtn
@onready var _ending_overlay: Panel = $EndingOverlay
@onready var _ending_label: RichTextLabel = $EndingOverlay/EndingLabel
@onready var _ending_restart: Button = $EndingOverlay/RestartBtn
@onready var _toast: Label = $Toast
@onready var _toast_timer: Timer = $Toast/Timer

var _config: JourneyConfig
var _input_locked: bool = false
var _reveal_tween: Tween

func _ready() -> void:
	JourneyRuntime.event_changed.connect(_on_event_changed)
	JourneyRuntime.resource_changed.connect(_on_resource_changed)
	JourneyRuntime.flag_changed.connect(_on_flag_changed)
	JourneyRuntime.journey_started.connect(_on_journey_started)
	JourneyRuntime.journey_ended.connect(_on_journey_ended)
	JourneyRuntime.journey_error.connect(_on_journey_error)

	_save_btn.pressed.connect(_on_save_pressed)
	_load_btn.pressed.connect(_on_load_pressed)
	_restart_btn.pressed.connect(_start_new_run)
	_ending_restart.pressed.connect(_start_new_run)
	_toast_timer.timeout.connect(_hide_toast)

	_ending_overlay.visible = false
	_toast.visible = false

	_config = load(CONFIG_PATH) as JourneyConfig
	if _config == null:
		_show_toast("Failed to load %s" % CONFIG_PATH)
		return

	# §8.1 optional sanity check: dev-build only. Runs validate() on the
	# sample's own config; surface any authoring drift as a toast.
	if OS.is_debug_build():
		var issues: Array[String] = JourneyRuntime.validate(_config)
		# Filter out the "pool was not validated" notice — pool isn't built
		# until the first pull, and a clean dev message is just noise.
		var filtered: Array[String] = []
		for line in issues:
			if line.find("pool was not validated") == -1:
				filtered.append(line)
		if not filtered.is_empty():
			_show_toast("validate(): %d issue(s) — see Output" % filtered.size())
			for line in filtered:
				push_warning("[sample validate] %s" % line)

	_start_new_run()

func _start_new_run() -> void:
	_ending_overlay.visible = false
	JourneyRuntime.start_new_journey(_config, DEFAULT_SEED)

# --- Signal handlers ---

func _on_journey_started() -> void:
	_refresh_hud_full()

func _on_event_changed(event: JourneyEvent, visible_choices: Array[JourneyChoice]) -> void:
	_clear_choices()
	_set_narrative(event.narrative_text)
	_lock_input(true)
	# Pacing: short reveal tween before re-enabling clicks. The engine doesn't
	# care if buttons aren't shown for a frame — it advances only when
	# process_choice fires, so the UI owns the tempo (§5.5).
	if _reveal_tween:
		_reveal_tween.kill()
	_narrative.modulate.a = 0.0
	_reveal_tween = create_tween()
	_reveal_tween.tween_property(_narrative, "modulate:a", 1.0, 0.25)
	_reveal_tween.tween_callback(func() -> void:
		_populate_choices(visible_choices)
		_lock_input(false)
	)
	_turn_label.text = "Turn: %d" % int(JourneyRuntime.get_metadata("turn_counter"))

func _on_resource_changed(key: String, _old_value: float, new_value: float) -> void:
	match key:
		"gold": _gold_label.text = "Gold: %d" % int(new_value)
		"sanity": _sanity_label.text = "Sanity: %d" % int(new_value)
		"rations": _rations_label.text = "Rations: %d" % int(new_value)

func _on_flag_changed(_key: String, _value: bool) -> void:
	# Flags don't appear on the HUD in this sample; subscribed for symmetry
	# and to prove the signal arrives in browser builds. No state read here.
	pass

func _on_journey_ended(ending_event: JourneyEvent) -> void:
	_clear_choices()
	_lock_input(true)
	var label: String = "<null>"
	if ending_event != null:
		label = String(ending_event.id)
	_ending_label.text = "[center][b]The road ends.[/b]\n\n%s\n\n[i](ending: %s)[/i][/center]" % [
		ending_event.narrative_text if ending_event != null else "",
		label,
	]
	_ending_overlay.visible = true

func _on_journey_error(message: String) -> void:
	_show_toast("Error: %s" % message)

# --- Persistence buttons ---

func _on_save_pressed() -> void:
	var err: int = JourneyRuntime.save_game(SAVE_SLOT)
	if err == OK:
		_show_toast("Saved.")
	else:
		_show_toast("Save failed (err=%d)" % err)

func _on_load_pressed() -> void:
	var err: int = JourneyRuntime.load_game(SAVE_SLOT)
	if err == OK:
		_ending_overlay.visible = false
		_show_toast("Loaded.")
		_refresh_hud_full()
	else:
		_show_toast("Load failed (err=%d)" % err)

# --- View helpers ---

func _clear_choices() -> void:
	for child in _choices_box.get_children():
		child.queue_free()

func _populate_choices(visible_choices: Array[JourneyChoice]) -> void:
	for choice in visible_choices:
		var btn := Button.new()
		btn.text = choice.button_text
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_choice_pressed.bind(choice))
		_choices_box.add_child(btn)

func _on_choice_pressed(choice: JourneyChoice) -> void:
	# UI-owned input gate. Engine never blocks; if we let clicks through
	# during the reveal tween, the player could outrun the fade — visually
	# ugly but not unsafe. Still, gate it here for polish.
	if _input_locked:
		return
	JourneyRuntime.process_choice(choice)

func _lock_input(locked: bool) -> void:
	_input_locked = locked
	for child in _choices_box.get_children():
		if child is Button:
			(child as Button).disabled = locked

func _set_narrative(text: String) -> void:
	_narrative.clear()
	_narrative.append_text(text)

func _refresh_hud_full() -> void:
	# After load_game, no per-resource signals fire (the bb was bulk-restored,
	# not mutated through consequences). Read the public API directly to
	# repaint the HUD — still no Blackboard access, just get_resource().
	_gold_label.text = "Gold: %d" % int(JourneyRuntime.get_resource("gold"))
	_sanity_label.text = "Sanity: %d" % int(JourneyRuntime.get_resource("sanity"))
	_rations_label.text = "Rations: %d" % int(JourneyRuntime.get_resource("rations"))
	_turn_label.text = "Turn: %d" % int(JourneyRuntime.get_metadata("turn_counter"))

func _show_toast(message: String) -> void:
	_toast.text = message
	_toast.visible = true
	_toast_timer.start(2.5)

func _hide_toast() -> void:
	_toast.visible = false

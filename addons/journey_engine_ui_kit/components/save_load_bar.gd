extends HBoxContainer
class_name JourneySaveLoadBar

## Save / Load / Restart controls. Calls only the public lifecycle + persistence
## API (start_new_journey / save_game / load_game).
##
## Post-load repaint: load_game bulk-restores the Blackboard and fires NO
## resource_changed signals (documented core behavior — event_changed DOES re-fire,
## so narrative/choices rebuild for free, but the HUD does not). On a successful
## load this emits `loaded`, which a host wires to JourneyResourceHud.repaint().

## The config used to (re)start a journey. Required for the Restart button and for
## autostart; save/load read the active config from the runtime.
@export var config: JourneyConfig
@export var seed: int = 0
@export var save_slot: String = "savegame"

@export_group("Buttons")
@export var show_save: bool = true
@export var show_load: bool = true
@export var show_restart: bool = true

## Optional SFX collaborator (set by JourneyView or via the NodePath).
@export var audio_layer_path: NodePath
var audio_layer: JourneyAudioLayer

## Fired after a successful load_game so the HUD (and anything else) can repaint.
signal loaded()
## Human-readable result of an action, for an optional toast.
signal status(message: String)

func _ready() -> void:
	if audio_layer == null and not audio_layer_path.is_empty():
		audio_layer = get_node_or_null(audio_layer_path) as JourneyAudioLayer
	if show_save:
		_add_button("Save", _on_save)
	if show_load:
		_add_button("Load", _on_load)
	if show_restart:
		_add_button("Restart", _on_restart)

func _add_button(text: String, handler: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(handler)
	add_child(btn)

func _on_save() -> void:
	var err: int = JourneyRuntime.save_game(save_slot)
	if err == OK:
		_sfx(audio_layer.sfx_save if audio_layer != null else null)
		status.emit("Saved.")
	else:
		status.emit("Save failed (err=%d)" % err)

func _on_load() -> void:
	var err: int = JourneyRuntime.load_game(save_slot)
	if err == OK:
		_sfx(audio_layer.sfx_load if audio_layer != null else null)
		status.emit("Loaded.")
		loaded.emit()
	else:
		status.emit("Load failed (err=%d)" % err)

func _on_restart() -> void:
	if config == null:
		status.emit("Restart failed: no config assigned.")
		return
	_sfx(audio_layer.sfx_button_press if audio_layer != null else null)
	JourneyRuntime.start_new_journey(config, seed)

func _sfx(stream: AudioStream) -> void:
	if audio_layer != null:
		audio_layer.play_sfx(stream)

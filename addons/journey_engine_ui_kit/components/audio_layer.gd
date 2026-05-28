extends Node
class_name JourneyAudioLayer

## Plays per-event ambient audio (JourneyEvent.ambient_audio, looped) and UI SFX
## from configurable exported slots. The kit ships NO audio files — every slot is
## empty by default; drop your own .wav/.ogg in your game folder and assign them
## (see addons/journey_engine_ui_kit/assets/sfx/README.md). A missing stream is a
## silent no-op, so the kit runs fine with no audio wired at all.
##
## Reads only the event payload (ambient_audio) handed in by event_changed — no
## Blackboard access.

## UI SFX slots — assign AudioStreams in the inspector / via JourneyStageView. Empty ⇒ silent.
@export_group("SFX slots")
@export var sfx_button_hover: AudioStream
@export var sfx_button_press: AudioStream
@export var sfx_choice_confirm: AudioStream
@export var sfx_save: AudioStream
@export var sfx_load: AudioStream
@export var sfx_ending: AudioStream

@export_group("Buses")
## Optional audio bus names; leave "Master" if you have no custom buses.
@export var ambient_bus: StringName = &"Master"
@export var sfx_bus: StringName = &"Master"

@export_group("Ambient")
@export var ambient_crossfade: float = 0.6
## Full-volume target for ambient playback, in dB (0 = unity).
@export var ambient_volume_db: float = 0.0

const SFX_POOL_SIZE := 6
## Volume floor used while fading ambient in/out, in dB.
const SILENCE_DB := -40.0

var _ambient_a: AudioStreamPlayer
var _ambient_b: AudioStreamPlayer
var _active_ambient: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []
var _current_ambient_stream: AudioStream

func _ready() -> void:
	_build()
	JourneyRuntime.event_changed.connect(_on_event_changed)

func _build() -> void:
	if _ambient_a != null:
		return
	_ambient_a = _make_player(ambient_bus)
	_ambient_b = _make_player(ambient_bus)
	_active_ambient = _ambient_a
	for i in SFX_POOL_SIZE:
		_sfx_pool.append(_make_player(sfx_bus))

func _make_player(bus: StringName) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p

func _on_event_changed(event: JourneyEvent, _choices: Array[JourneyChoice]) -> void:
	var stream: AudioStream = event.ambient_audio if event != null else null
	set_ambient(stream)

## Crossfades to a new ambient loop. Null stops the current ambient (fade out).
## Re-passing the already-playing stream is a no-op so re-entering the same event
## (e.g. on load) doesn't restart the track.
func set_ambient(stream: AudioStream) -> void:
	if stream == _current_ambient_stream:
		return
	_current_ambient_stream = stream
	var fading_out := _active_ambient
	_fade_player(fading_out, SILENCE_DB, true)
	if stream == null:
		return
	var incoming := _ambient_b if _active_ambient == _ambient_a else _ambient_a
	_active_ambient = incoming
	_enable_loop(stream)
	incoming.stream = stream
	incoming.volume_db = SILENCE_DB
	incoming.play()
	_fade_player(incoming, ambient_volume_db, false)

func _fade_player(player: AudioStreamPlayer, to_db: float, stop_after: bool) -> void:
	if player == null:
		return
	var t := create_tween()
	t.tween_property(player, "volume_db", to_db, ambient_crossfade)
	if stop_after:
		t.tween_callback(player.stop)

## Best-effort loop: ogg/wav streams expose a `loop` property; set it when present
## so ambient beds repeat. Streams without it just play once.
func _enable_loop(stream: AudioStream) -> void:
	if stream != null and "loop" in stream:
		stream.set("loop", true)

# --- SFX ---

## Plays a one-shot SFX on a free pooled player. Null ⇒ no-op.
func play_sfx(stream: AudioStream) -> void:
	if stream == null:
		return
	if _sfx_pool.is_empty():
		_build()
	for p in _sfx_pool:
		if not p.playing:
			p.stream = stream
			p.volume_db = 0.0
			p.play()
			return
	# All busy — reuse the first (rare; SFX are short).
	var p0 := _sfx_pool[0]
	p0.stream = stream
	p0.play()

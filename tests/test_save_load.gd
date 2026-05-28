extends Node

## Step-6 programmatic round-trip test for JourneySaveManager.
##
## Covers (matching the manual-test checklist in the Step-6 prompt):
##   - Exact state restoration (resources/flags/metadata/current_event_id)
##   - RNG continuity: post-load pulls match a control run from the saved state
##   - Primitives-only serialize() shape (no Resource/Object leaks)
##   - Encryption opt-in (plaintext vs encrypted, both round-trip)
##   - Missing file → ERR_FILE_NOT_FOUND (no crash)
##   - Future-version save → ERR_INVALID_DATA (no crash)
##
## Headless: constructs its own Blackboard via Blackboard.initialize(); does
## NOT need JourneyRuntime / start_new_journey / SceneTree. Mutates state
## directly for test setup — single-mutation-path is a RUNTIME invariant, not
## a Blackboard one, so a test fixture may bypass it.

const TEST_CONFIG_PATH := "res://tests/test_config.tres"
const SEED := 12345

var _failures: int = 0

func _ready() -> void:
	var config: JourneyConfig = load(TEST_CONFIG_PATH)
	if config == null:
		push_error("test_save_load: could not load %s" % TEST_CONFIG_PATH)
		_finish()
		return

	_test_round_trip(config)
	_test_rng_continuity(config)
	_test_serialize_primitives(config)
	_test_encryption_toggle(config)
	_test_missing_file(config)
	_test_future_version(config)
	_test_rng_seed_restored(config)
	_test_missing_rng_state_rejected(config)
	_finish()

func _finish() -> void:
	if _failures == 0:
		print("[test_save_load] PASS (all checks)")
	else:
		print("[test_save_load] FAIL: %d check(s) failed" % _failures)
	# Intentionally do NOT call get_tree().quit() — on this editor setup the
	# child process terminates before the debugger drains stdout, so an auto-
	# quit eats all the per-check prints in the Output panel. Match the
	# test_blackboard/test_eval_mutate pattern: the user closes the window
	# when they're done reading. (Step-8 discovery; PROGRESS-log claims of
	# verified passes prior to this point should be re-verified now that
	# output is actually visible.)

func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("  [ok] %s" % msg)
	else:
		_failures += 1
		printerr("  [FAIL] %s" % msg)

# --- Tests ---

func _test_round_trip(config: JourneyConfig) -> void:
	print("[1] round-trip")
	var bb := Blackboard.new()
	bb.initialize(config, SEED)
	bb.resources["gold"] = 75.0
	bb.flags["helped_stranger"] = true
	bb.metadata["current_event_id"] = "evt_road_merchant"
	bb.metadata["turn_counter"] = 7
	bb.metadata["seen_ids"] = ["evt_start", "evt_road_merchant"]
	bb.metadata["history"] = ["evt_start", "evt_road_merchant"]
	# Advance rng so state diverges from initial seed.
	for i in range(5):
		bb.rng.randi()

	var saver := JourneySaveManager.new()
	var err: int = saver.save(bb, "rt", "", 1)
	_expect(err == OK, "save returned OK (err=%d)" % err)

	var bb2 := Blackboard.new()
	bb2.initialize(config, 999)  # deliberately different seed
	bb2.resources["gold"] = 1.0  # dirty values pre-load
	var err2: int = saver.load_into(bb2, "rt", "", 1)
	_expect(err2 == OK, "load_into returned OK (err=%d)" % err2)
	_expect(bb2.resources.get("gold") == 75.0, "gold restored to 75 (got %s)" % str(bb2.resources.get("gold")))
	_expect(bb2.flags.get("helped_stranger") == true, "flag restored")
	_expect(bb2.metadata.get("current_event_id") == "evt_road_merchant", "current_event_id restored")
	_expect(bb2.metadata.get("turn_counter") == 7, "turn_counter restored")
	_expect(bb2.metadata.get("seen_ids") == ["evt_start", "evt_road_merchant"], "seen_ids restored")
	_expect(bb2.rng.state == bb.rng.state, "rng.state restored exactly")

func _test_rng_continuity(config: JourneyConfig) -> void:
	print("[2] rng continuity (post-load stream matches control)")
	var bb := Blackboard.new()
	bb.initialize(config, SEED)
	# Burn a few pulls to advance state.
	var pre := [bb.rng.randi(), bb.rng.randi(), bb.rng.randi()]
	# Save state here.
	var saver := JourneySaveManager.new()
	var err: int = saver.save(bb, "rng", "", 1)
	_expect(err == OK, "save returned OK")
	# Control: continue 3 more pulls from the saved bb.
	var control := [bb.rng.randi(), bb.rng.randi(), bb.rng.randi()]
	# Reload into a fresh bb and pull 3 — must match control.
	var bb2 := Blackboard.new()
	bb2.initialize(config, 42)
	# Assert load success BEFORE checking the stream — otherwise a load failure
	# would surface as a misleading "RNG continuity broken" diagnostic instead
	# of pointing at the actual cause (finding #12).
	var load_err: int = saver.load_into(bb2, "rng", "", 1)
	_expect(load_err == OK, "rng-continuity load returned OK (err=%d)" % load_err)
	var replay := [bb2.rng.randi(), bb2.rng.randi(), bb2.rng.randi()]
	_expect(replay == control, "post-load 3 pulls match control %s == %s" % [str(replay), str(control)])

func _test_serialize_primitives(config: JourneyConfig) -> void:
	print("[3] serialize() shape is primitives-only")
	var bb := Blackboard.new()
	bb.initialize(config, SEED)
	bb.metadata["current_event_id"] = "evt_start"
	var dict: Dictionary = JourneySaveManager.serialize(bb, 1)
	# Required top-level keys.
	for k in ["save_version", "rng_state", "rng_seed", "resources", "flags", "metadata"]:
		_expect(dict.has(k), "dict has '%s'" % k)
	_expect(dict["save_version"] == 1, "save_version is 1")
	_expect(dict["resources"] is Dictionary, "resources is a Dictionary")
	_expect(dict["flags"] is Dictionary, "flags is a Dictionary")
	_expect(dict["metadata"]["current_event_id"] is String, "current_event_id is String (not Resource)")
	_expect(dict["metadata"]["history"] is Array, "history is Array of primitives")
	_expect(dict["metadata"]["seen_ids"] is Array, "seen_ids is Array of primitives")
	# No JourneyEvent / Resource anywhere.
	_expect(_dict_has_no_objects(dict), "no Object/Resource anywhere in serialized dict")

func _dict_has_no_objects(d: Variant) -> bool:
	if d is Object:
		return false
	if d is Dictionary:
		for k in d:
			if (k is Object) or not _dict_has_no_objects(d[k]):
				return false
	elif d is Array:
		for v in d:
			if not _dict_has_no_objects(v):
				return false
	return true

func _test_encryption_toggle(config: JourneyConfig) -> void:
	print("[4] encryption opt-in")
	var bb := Blackboard.new()
	bb.initialize(config, SEED)
	bb.flags["secret"] = true
	var saver := JourneySaveManager.new()
	# Plaintext
	saver.save(bb, "plain", "", 1)
	# Encrypted
	saver.save(bb, "enc", "hunter2", 1)
	# Read raw bytes to verify they differ — encrypted shouldn't trivially
	# contain the structure markers a plaintext store_var dump shows.
	var plain_bytes: PackedByteArray = FileAccess.get_file_as_bytes("user://plain.dat")
	var enc_bytes: PackedByteArray = FileAccess.get_file_as_bytes("user://enc.dat")
	_expect(plain_bytes.size() > 0, "plaintext file written (%d bytes)" % plain_bytes.size())
	_expect(enc_bytes.size() > 0, "encrypted file written (%d bytes)" % enc_bytes.size())
	_expect(plain_bytes != enc_bytes, "encrypted bytes differ from plaintext")
	# Encrypted load with correct key works.
	var bb2 := Blackboard.new()
	bb2.initialize(config, 0)
	var err: int = saver.load_into(bb2, "enc", "hunter2", 1)
	_expect(err == OK and bb2.flags.get("secret") == true, "encrypted load round-trips")

func _test_missing_file(config: JourneyConfig) -> void:
	print("[5] missing-file handling")
	var bb := Blackboard.new()
	bb.initialize(config, 0)
	var saver := JourneySaveManager.new()
	# Remove if it exists from a prior run.
	if FileAccess.file_exists("user://nope.dat"):
		DirAccess.remove_absolute("user://nope.dat")
	var err: int = saver.load_into(bb, "nope", "", 1)
	_expect(err == ERR_FILE_NOT_FOUND, "missing file returns ERR_FILE_NOT_FOUND (got %d)" % err)

func _test_rng_seed_restored(config: JourneyConfig) -> void:
	# Step-6 follow-up #6: load must restore bb.rng.seed as well as bb.rng.state,
	# so bb.rng.seed and bb.metadata['rng_seed'] don't disagree post-load.
	print("[7] rng.seed restored (not just state)")
	var bb := Blackboard.new()
	bb.initialize(config, SEED)
	var saver := JourneySaveManager.new()
	saver.save(bb, "seed", "", 1)
	var bb2 := Blackboard.new()
	bb2.initialize(config, 999)  # dirty seed differs from saved
	_expect(bb2.rng.seed == 999, "pre-load seed is dirty (999)")
	saver.load_into(bb2, "seed", "", 1)
	_expect(bb2.rng.seed == SEED, "rng.seed restored to %d (got %d)" % [SEED, bb2.rng.seed])
	_expect(int(bb2.metadata["rng_seed"]) == SEED, "metadata['rng_seed'] restored to %d" % SEED)
	_expect(bb2.rng.seed == int(bb2.metadata["rng_seed"]), "rng.seed and metadata['rng_seed'] agree")

func _test_missing_rng_state_rejected(config: JourneyConfig) -> void:
	# Step-6 follow-up #11: a save dict without rng_state would have silently set
	# state to 0; load_into now refuses it as ERR_INVALID_DATA before mutating bb.
	print("[8] missing rng_state rejected (no silent state=0)")
	# Hand-craft a save dict that's well-formed except for rng_state.
	var bad: Dictionary = {
		"save_version": 1,
		"rng_seed": 12345,
		"resources": {"gold": 1.0},
		"flags": {},
		"metadata": {"current_event_id": "evt_start", "turn_counter": 0, "seen_ids": [], "history": []},
	}
	var f := FileAccess.open("user://nornge.dat", FileAccess.WRITE)
	f.store_var(bad)
	f.close()
	var bb := Blackboard.new()
	bb.initialize(config, SEED)
	var saver := JourneySaveManager.new()
	var err: int = saver.load_into(bb, "nornge", "", 1)
	_expect(err == ERR_INVALID_DATA, "missing rng_state returns ERR_INVALID_DATA (got %d)" % err)
	_expect(bb.rng.state != 0, "bb.rng.state was NOT silently set to 0 (still %d)" % bb.rng.state)

func _test_future_version(config: JourneyConfig) -> void:
	print("[6] future-version save")
	var bb := Blackboard.new()
	bb.initialize(config, 0)
	var saver := JourneySaveManager.new()
	# Save with a future version.
	saver.save(bb, "future", "", 999)
	var bb2 := Blackboard.new()
	bb2.initialize(config, 0)
	var err: int = saver.load_into(bb2, "future", "", 1)
	_expect(err == ERR_INVALID_DATA, "future save returns ERR_INVALID_DATA (got %d)" % err)

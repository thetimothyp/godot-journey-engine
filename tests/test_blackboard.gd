extends Node

## Throwaway manual test for Step 2: confirms Blackboard.initialize() correctly
## seeds resources (with clamping), flags, RNG, and metadata from a JourneyConfig.
## Run via F6 with this scene open, or set as main scene temporarily.

const TEST_CONFIG_PATH := "res://tests/test_config.tres"

func _ready() -> void:
	var config: JourneyConfig = load(TEST_CONFIG_PATH)
	if config == null:
		push_error("test_blackboard: could not load %s" % TEST_CONFIG_PATH)
		return

	var bb := Blackboard.new()
	bb.initialize(config, 12345)

	print("--- Blackboard initialized with seed=12345 ---")
	print("resources: ", bb.resources)
	print("flags:     ", bb.flags)
	print("metadata:  ", bb.metadata)

	var bb2 := Blackboard.new()
	bb2.initialize(config, 0)
	print("--- Blackboard initialized with seed=0 (randomized) ---")
	print("metadata.rng_seed: ", bb2.metadata["rng_seed"])

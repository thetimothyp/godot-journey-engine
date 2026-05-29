extends Node

## Step-8 headless sanity check for the pool scan. Builds the JourneyPoolIndex
## against sample_game/pool/ in-editor and asserts the expected event count +
## per-id presence. Run before the Web/WASM export so a busted scan is caught
## locally rather than after a 30-second export round trip.
##
## This does NOT prove the export itself works — that's the browser
## checklist. What it DOES prove is that JourneyPoolIndex.build() over the
## sample_game/pool path:
##   - opens the dir (would push_error otherwise)
##   - finds every .tres (count matches)
##   - assigns ids without collision (every expected id resolves)
##   - tags index correctly (the "road" bucket should contain all 5)
##
## A future regression that breaks the in-editor scan would fail HERE first;
## a regression that breaks ONLY the PCK scan would fail in the browser.
## Together they fence both code paths.
##
## Same execution shape as tests/test_save_load.gd: _ready() runs the checks
## synchronously, _finish() prints + quits. No await dance — keep it boring
## and identical to the other test scenes so the editor behaves the same way
## (F6 with this tab focused; F5 will run the main scene instead).

const POOL_DIR := "res://sample_game/pool/"
const SAMPLE_CONFIG := "res://sample_game/config.tres"

## NOTE: bump this when you add/remove a sample-game pool event. Five pool
## events ship with the sample: bandit, merchant, ally, camp, inn.
const EXPECTED_POOL_COUNT := 5

const EXPECTED_IDS := [
	"evt_road_bandit",
	"evt_road_merchant",
	"evt_road_ally",
	"evt_road_camp",
	"evt_road_inn",
]

var _failures: int = 0

func _ready() -> void:
	print("[test_export_sanity] scanning %s" % POOL_DIR)
	var index := JourneyPoolIndex.new()
	index.build(POOL_DIR)

	_expect(index.is_built(), "pool index built (scan opened dir and completed)")
	_expect(index.all_events.size() == EXPECTED_POOL_COUNT,
		"expected %d events, found %d" % [EXPECTED_POOL_COUNT, index.all_events.size()])

	for id_str in EXPECTED_IDS:
		var ev: JourneyEvent = index.find_by_id(id_str)
		_expect(ev != null, "id '%s' resolves via find_by_id" % id_str)

	var road_bucket: Array = index.by_tag.get("road", [])
	_expect(road_bucket.size() == EXPECTED_POOL_COUNT,
		"'road' tag bucket has %d entries (expected %d)" % [road_bucket.size(), EXPECTED_POOL_COUNT])

	# Deterministic ordering check (§1.3): all_events sorted by String(id).
	# Cross-platform reproducibility guarantee — a regression dropping the
	# sort would break save/load determinism across machines invisibly.
	var ordered := true
	for i in range(index.all_events.size() - 1):
		if String(index.all_events[i].id) > String(index.all_events[i + 1].id):
			ordered = false
			break
	_expect(ordered, "all_events sorted by String(id) for cross-platform determinism")

	# Load-time reality gate (the "would this ship" check). The pool scan above
	# proves the pool dir indexes; this proves the WHOLE sample config — start
	# event, boundary routes, and every reachable .tres — loads non-null from a
	# FRESH disk context (no cache reuse). An unserializable target_event cycle
	# would fail here, which is the gap that let unloadable content pass the
	# in-memory validate + smoke test. See tests/journey_load_check.gd.
	print("[test_export_sanity] disk round-trip of %s" % SAMPLE_CONFIG)
	var problems: Array[String] = JourneyLoadCheck.check(SAMPLE_CONFIG)
	_expect(problems.is_empty(),
		"sample config round-trips clean from disk (got %d: %s)" % [problems.size(), str(problems)])

	_finish()

func _finish() -> void:
	if _failures == 0:
		print("[test_export_sanity] PASS (all checks)")
	else:
		print("[test_export_sanity] FAIL: %d check(s) failed" % _failures)
	# Intentionally do NOT call get_tree().quit() — the child process
	# terminates before the editor's debugger drains stdout, so an auto-quit
	# eats the prints in the Output panel. Match the working pattern in
	# test_blackboard/test_eval_mutate: user closes the window when done.

func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("  [ok] %s" % msg)
	else:
		_failures += 1
		printerr("  [FAIL] %s" % msg)

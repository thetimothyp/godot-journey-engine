extends Node

## Headless sanity check for the event-index scan. Builds the JourneyEventIndex
## against the sample game's events_dir in-editor and asserts the expected event
## count, per-id resolution, pool-eligibility split, and tag indexing. Run before
## the Web/WASM export so a busted scan is caught locally rather than after a
## 30-second export round trip.
##
## What it proves about JourneyEventIndex.build() over res://sample_game/:
##   - opens the dir and finds every event .tres (count matches), skipping the
##     config / stage book / non-event resources in the tree
##   - assigns ids without collision (every expected id resolves via find_by_id)
##   - scopes pool draws by pool_eligible (exactly the 5 pool events), not folder
##   - tags index correctly (the "road" bucket holds all 5 pool events)
##
## Then a disk round-trip (JourneyLoadCheck) proves the WHOLE config loads from a
## FRESH disk context with every routing id resolving — the "would this ship"
## gate. Same execution shape as the other test scenes: _ready() runs checks,
## _finish() prints (no auto-quit so the editor drains stdout).

const SAMPLE_CONFIG := "res://sample_game/config.tres"
## The unified events_dir: recursively covers sample_game/events/ + pool/.
const EVENTS_DIR := "res://sample_game/"

## NOTE: bump these when sample content changes. 7 deterministic + 5 pool = 12.
const EXPECTED_EVENT_COUNT := 12
const EXPECTED_POOL_ELIGIBLE := 5

const EXPECTED_IDS := [
	"evt_start", "evt_road_begins", "evt_madness", "evt_ending_router",
	"evt_end_heroic", "evt_end_tragic", "evt_end_pragmatic",
	"evt_road_bandit", "evt_road_merchant", "evt_road_ally", "evt_road_camp", "evt_road_inn",
]

var _failures: int = 0

func _ready() -> void:
	print("[test_export_sanity] scanning %s" % EVENTS_DIR)
	var index := JourneyEventIndex.new()
	index.build(EVENTS_DIR)

	_expect(index.is_built(), "event index built (scan opened dir and completed)")
	_expect(index.all_events.size() == EXPECTED_EVENT_COUNT,
		"expected %d events, found %d" % [EXPECTED_EVENT_COUNT, index.all_events.size()])
	_expect(index.build_problems.is_empty(),
		"no build problems (empty/duplicate ids): %s" % str(index.build_problems))

	for id_str in EXPECTED_IDS:
		var ev: JourneyEvent = index.find_by_id(id_str)
		_expect(ev != null, "id '%s' resolves via find_by_id" % id_str)

	# Pool-eligibility is now a per-event flag, not a folder. Exactly the 5
	# road events should be pool-eligible; the 7 deterministic events must not be.
	var eligible := 0
	for e in index.all_events:
		if e.pool_eligible:
			eligible += 1
	_expect(eligible == EXPECTED_POOL_ELIGIBLE,
		"%d events pool_eligible (expected %d)" % [eligible, EXPECTED_POOL_ELIGIBLE])

	var road_bucket: Array = index.by_tag.get("road", [])
	_expect(road_bucket.size() == EXPECTED_POOL_ELIGIBLE,
		"'road' tag bucket has %d entries (expected %d)" % [road_bucket.size(), EXPECTED_POOL_ELIGIBLE])

	# Deterministic ordering check (§1.3): all_events sorted by String(id).
	var ordered := true
	for i in range(index.all_events.size() - 1):
		if String(index.all_events[i].id) > String(index.all_events[i + 1].id):
			ordered = false
			break
	_expect(ordered, "all_events sorted by String(id) for cross-platform determinism")

	# Load-time reality gate (the "would this ship" check). Proves the WHOLE
	# config loads from a FRESH disk context (no cache reuse) and every routing id
	# — start, boundary routes, every choice target — resolves to a loaded event.
	# See tests/journey_load_check.gd.
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

func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("  [ok] %s" % msg)
	else:
		_failures += 1
		printerr("  [FAIL] %s" % msg)

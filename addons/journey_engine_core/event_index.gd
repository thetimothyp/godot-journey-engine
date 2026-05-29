extends RefCounted
class_name JourneyEventIndex

## Id-keyed catalog of EVERY JourneyEvent (deterministic and pool-eligible
## alike) + the stochastic selection logic (eng §6). All routing resolves
## through this index: start_event_id, choice.target_event_id, and boundary
## *_event_id are looked up via find_by_id, and the pool draws a weighted-random
## candidate from the subset where pool_eligible is true. Routing-by-id (not
## eager object references) is what keeps every event independently loadable and
## routing graphs serializable.
##
## RefCounted, owned by the SequenceManager; emits NO signals, never touches the
## SceneTree, never reads a global RNG — determinism (§1.3, §6.3) requires every
## roll come from blackboard.rng.
##
## Built EAGERLY on start_new_journey: start_event_id must resolve before the
## first event is entered, so a lazy-on-first-pull build is no longer viable.
## rebuild() is the [Studio]/editor hot-reload hook documented in eng §3.7/§6.1.

## All loaded events, in scan order then id-sorted. Includes deterministic
## events — find_by_id must resolve any routing target, not just pool events.
var all_events: Array[JourneyEvent] = []
## id String -> JourneyEvent, for O(1) routing resolution. Mirrors all_events.
var by_id: Dictionary = {}
## String tag -> Array[JourneyEvent]. An event with N tags appears under N
## buckets; select() dedupes the union before filtering.
var by_tag: Dictionary = {}

## Authoring problems found DURING build (empty / duplicate ids), as
## {severity, message} dicts matching JourneyValidator's shape. The index
## push_errors these AND records them here so JourneyValidator can surface them
## in its typed result — duplicates are dropped from the index (first-seen
## wins), so this is the only place a validator can learn about them.
## Sorted by message at end of build for deterministic output (§1.3).
var build_problems: Array[Dictionary] = []

var _built: bool = false

func is_built() -> bool:
	return _built

## §6.1 index build. Recursively enumerates .tres under dir_path via DirAccess
## on the res:// path — export-safe because Godot bakes resources into the PCK
## and DirAccess enumerates that virtual filesystem (not the OS one). Idempotent:
## re-calling clears and rebuilds.
##
## Indexes EVERY JourneyEvent under the tree (deterministic + pool) so any
## routing target resolves; pool draws are later scoped by pool_eligible in
## select(). Authoring invariant (§3.8): every indexed event must have a unique
## non-empty id. Duplicates / empties are push_error'd by name and skipped — not
## crashed — so a single bad file can't take down a game in production (and the
## validator names them too).
##
## _built latches true ONLY on a successful scan. Empty dir_path or a failed
## DirAccess.open leaves _built = false so the caller can retry / surface it.
##
## After-build determinism (§1.3): all_events and each by_tag bucket are sorted
## by String(event.id) so candidate ordering is content-determined, not
## filesystem-determined — required for cross-platform save/load reproducibility
## under a fixed seed.
func build(dir_path: String, cache_mode: int = ResourceLoader.CACHE_MODE_REUSE) -> void:
	all_events.clear()
	by_id.clear()
	by_tag.clear()
	build_problems.clear()
	_built = false

	if dir_path == "":
		push_error("JourneyEventIndex.build: empty dir_path")
		return

	var seen_ids: Dictionary = {}  # id String -> source path (for duplicate diagnostics)
	if not _scan_dir(dir_path, seen_ids, cache_mode):
		return  # DirAccess.open failed at the root; leave _built = false so we can retry

	_finalize_build()

## Sort for determinism and latch _built. Shared by the disk build and
## build_from_events. Cross-platform determinism (§1.3): scan order from
## DirAccess is filesystem-defined, so without the id-sort a seed that picks
## event N on one platform could pick event M on another. build_problems is
## sorted by message so the validator's surfaced output is order-stable too.
func _finalize_build() -> void:
	var id_compare := func(a: JourneyEvent, b: JourneyEvent) -> bool:
		return String(a.id) < String(b.id)
	all_events.sort_custom(id_compare)
	for tag in by_tag:
		(by_tag[tag] as Array).sort_custom(id_compare)
	build_problems.sort_custom(func(a, b): return String(a["message"]) < String(b["message"]))
	_built = true

## NOTE: Studio will call this after writing resources to refresh the index
## without a project reload. Passes CACHE_MODE_REPLACE so ResourceLoader
## re-reads from disk instead of returning the pre-edit cached instance —
## without this, a Studio "save and reload" silently keeps stale data.
func rebuild(dir_path: String) -> void:
	build(dir_path, ResourceLoader.CACHE_MODE_REPLACE)

## Build the index directly from an in-memory event list, bypassing the disk
## scan. Used by tests and any caller that already holds the events (e.g.
## validating a config under construction). Same id rules, diagnostics, and
## determinism (id-sort) as the disk build — both funnel through _register so
## the empty/duplicate-id predicates can never drift.
func build_from_events(events: Array[JourneyEvent]) -> void:
	all_events.clear()
	by_id.clear()
	by_tag.clear()
	build_problems.clear()
	_built = false
	var seen_ids: Dictionary = {}
	for event in events:
		_register(event, "<in-memory>", seen_ids)
	_finalize_build()

## Recursive directory walk. Uses DirAccess.open() on a res:// path so it works
## in exported Web/WASM builds (eng §6.1 web-safe note); we never touch the OS
## filesystem directly. Returns false iff the root open failed, so build() can
## leave _built = false and allow recovery.
func _scan_dir(dir_path: String, seen_ids: Dictionary, cache_mode: int) -> bool:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		push_error("JourneyEventIndex.build: cannot open '%s'" % dir_path)
		return false
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry == "." or entry == "..":
			entry = dir.get_next()
			continue
		var full_path: String = dir_path.path_join(entry)
		if dir.current_is_dir():
			_scan_dir(full_path, seen_ids, cache_mode)
		else:
			# In exported builds .tres files are stripped to .remap pointers;
			# accept both so the scan works in editor and PCK alike.
			if entry.ends_with(".tres") or entry.ends_with(".res") or entry.ends_with(".tres.remap") or entry.ends_with(".res.remap"):
				_ingest(full_path, seen_ids, cache_mode)
		entry = dir.get_next()
	dir.list_dir_end()
	return true

func _ingest(path: String, seen_ids: Dictionary, cache_mode: int) -> void:
	# Strip the export-time .remap suffix so ResourceLoader gets the original path.
	var load_path: String = path
	if load_path.ends_with(".remap"):
		load_path = load_path.substr(0, load_path.length() - ".remap".length())
	var res: Resource = ResourceLoader.load(load_path, "", cache_mode)
	if res == null:
		# Distinct from "not an event": null means the resource failed to load
		# (corrupted .tres, malformed sub_resource, etc). Surface it so an author
		# can find the file rather than silently losing the event.
		push_error("JourneyEventIndex.build: failed to load resource at '%s'" % load_path)
		return
	if not (res is JourneyEvent):
		return  # silently skip non-events; the tree may legitimately hold the config, stage book, etc.
	_register(res, load_path, seen_ids)

## Validate + register one event. THE single home for the empty-id and
## duplicate-id predicates (disk and in-memory builds both call it, so the rules
## can never drift). Duplicates/empties are push_error'd AND recorded in
## build_problems (the validator surfaces them — they're dropped from the index,
## so it can't re-derive them). `source` is a path or "<in-memory>" for messages.
func _register(event: JourneyEvent, source: String, seen_ids: Dictionary) -> void:
	if event == null:
		return
	var id_str: String = String(event.id)
	if id_str == "":
		var m1: String = "event at '%s' has empty id; skipped (every indexed event needs a unique non-empty id)" % source
		push_error("JourneyEventIndex.build: " + m1)
		build_problems.append({"severity": "error", "message": m1})
		return
	if seen_ids.has(id_str):
		var m2: String = "duplicate event id '%s' at '%s' (first seen at '%s'); skipped" % [id_str, source, seen_ids[id_str]]
		push_error("JourneyEventIndex.build: " + m2)
		build_problems.append({"severity": "error", "message": m2})
		return
	seen_ids[id_str] = source
	all_events.append(event)
	by_id[id_str] = event
	for tag in event.event_tags:
		var bucket: Array = by_tag.get(tag, [])
		bucket.append(event)
		by_tag[tag] = bucket

## §3.8 / §7.3 lookup. O(1) id resolution against by_id. Returns null on miss
## (or if the index isn't built yet). This is the single resolution path for
## ALL routing — start, deterministic targets, boundary routes, and the saved
## current_event_id on load — replacing the old object-ref graph walk.
func find_by_id(id_str: String) -> JourneyEvent:
	if not _built:
		return null
	return by_id.get(id_str, null)

## §6.3 cumulative-weight roll over `e.weight`. Pure and static so it is
## unit-testable with a constructed RNG and a hand-built candidate array.
##
## Uses `rng` EXCLUSIVELY (no randi()/randf() globals, no fresh RNG) — this is
## the §1.3 determinism contract that lets save/load (Step 6) reproduce the exact
## pull stream after a reload.
##
## Negative weights clamp to 0 (defensive — author error). If the candidate
## total weight is 0 we fall back to a uniform random pick rather than returning
## null, so a pool of explicitly zero-weight events still resolves; this
## preserves the §6.2 contract that a non-empty candidate set always yields an
## event.
static func weighted_pick(candidates: Array[JourneyEvent], rng: RandomNumberGenerator) -> JourneyEvent:
	if candidates.is_empty():
		return null
	var total: int = 0
	for e in candidates:
		var w: int = e.weight if e.weight > 0 else 0
		total += w
	if total <= 0:
		# Uniform fallback — all candidates have non-positive weight. Authors
		# sometimes set weight=0 expecting events to be excluded; warn loudly so
		# that intent vs behavior mismatch is visible. The fallback still resolves
		# (§6.2 contract: non-empty candidates always yield an event).
		push_warning("JourneyEventIndex.weighted_pick: all %d candidates have weight <= 0; falling back to uniform pick" % candidates.size())
		return candidates[rng.randi_range(0, candidates.size() - 1)]
	var roll: int = rng.randi_range(1, total)
	var acc: int = 0
	for e in candidates:
		var w: int = e.weight if e.weight > 0 else 0
		acc += w
		if roll <= acc:
			return e
	# Unreachable given total > 0, but keep a sane fallback.
	return candidates[candidates.size() - 1]

## §6.2 candidate selection. Pure given its arguments:
##   1. scope = union of by_tag[t] for t in requested_tags
##      (or all_events if requested_tags is empty); deduped so an event with two
##      matching tags doesn't double its odds.
##   2. candidates = events in scope where
##        e.pool_eligible AND
##        (e.repeatable or e.id not in seen_ids) AND
##        JourneyEvaluator.eval_group(e.pool_conditions, bb) is true.
##   3. Empty candidates → return null (caller emits journey_error per §6.4).
##   4. Else → weighted_pick(candidates, bb.rng).
##
## The pool_eligible gate lives in this single candidate loop so it applies to
## BOTH the all_events branch and the by_tag branch — deterministic events share
## the index (for routing resolution) but must never be drawn at random.
##
## seen_ids is the LIVE Array from blackboard.metadata["seen_ids"] populated by
## SequenceManager._enter_event; do not maintain a second seen-set here (the spec
## mandates a single source of truth, and Step 6 saves only that one).
func select(requested_tags: Array[String], bb: Blackboard, seen_ids: Array, _config: JourneyConfig) -> JourneyEvent:
	var scope: Array[JourneyEvent]
	if requested_tags.is_empty():
		scope = all_events
	else:
		scope = []
		var dedupe: Dictionary = {}
		for tag in requested_tags:
			var bucket: Array = by_tag.get(tag, [])
			for e in bucket:
				var key: String = String(e.id)
				if not dedupe.has(key):
					dedupe[key] = true
					scope.append(e)

	var candidates: Array[JourneyEvent] = []
	for e in scope:
		if not e.pool_eligible:
			continue
		var id_str: String = String(e.id)
		if not e.repeatable and seen_ids.has(id_str):
			continue
		if not JourneyEvaluator.eval_group(e.pool_conditions, bb):
			continue
		candidates.append(e)

	if candidates.is_empty():
		return null
	return weighted_pick(candidates, bb.rng)

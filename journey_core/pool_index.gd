extends RefCounted
class_name JourneyPoolIndex

## Tag-indexed catalog of pool-eligible JourneyEvents + the deterministic
## selection logic (eng §6). RefCounted, owned by the SequenceManager; emits
## NO signals, never touches the SceneTree, never reads a global RNG —
## determinism (§1.3, §6.3) requires every roll come from blackboard.rng.
##
## Built either eagerly on start_new_journey or lazily on the first pool pull;
## the SequenceManager currently builds lazily (simpler — avoids a directory
## scan if a game never enters the pool). rebuild() is the [Studio]/editor
## hot-reload hook documented in eng §3.7 / §6.1.

## All loaded pool events, in scan order.
var all_events: Array[JourneyEvent] = []
## String tag -> Array[JourneyEvent]. An event with N tags appears under N
## buckets; select() dedupes the union before filtering.
var by_tag: Dictionary = {}

var _built: bool = false

func is_built() -> bool:
	return _built

## §6.1 index build. Recursively enumerates .tres under dir_path via
## DirAccess on the res:// path — export-safe because Godot bakes resources
## into the PCK and DirAccess enumerates that virtual filesystem (not the OS
## one). Idempotent: re-calling clears and rebuilds.
##
## Authoring invariant (§3.8): every pooled JourneyEvent must have a unique
## non-empty id. Duplicates / empties are push_error'd by name and skipped —
## not crashed — so a single bad file can't take down a game in production.
##
## _built latches true ONLY on a successful scan. Empty dir_path or a failed
## DirAccess.open leaves _built = false so the lazy gate in
## SequenceManager._route_to_pool will retry the next pull (loud but
## recoverable, rather than silently latched-empty).
##
## After-build determinism (§1.3): all_events and each by_tag bucket are
## sorted by String(event.id) so candidate ordering is content-determined,
## not filesystem-determined — required for cross-platform save/load
## reproducibility under a fixed seed.
func build(dir_path: String, cache_mode: int = ResourceLoader.CACHE_MODE_REUSE) -> void:
	all_events.clear()
	by_tag.clear()
	_built = false

	if dir_path == "":
		push_error("JourneyPoolIndex.build: empty dir_path")
		return

	var seen_ids: Dictionary = {}  # id String -> source path (for duplicate diagnostics)
	if not _scan_dir(dir_path, seen_ids, cache_mode):
		return  # DirAccess.open failed at the root; leave _built = false so we can retry

	# Sort for cross-platform determinism (§1.3). Scan order from DirAccess is
	# filesystem-defined, so a seed that picks event N on one platform could
	# pick event M on another without this. Sorting by id makes ordering
	# content-determined.
	var id_compare := func(a: JourneyEvent, b: JourneyEvent) -> bool:
		return String(a.id) < String(b.id)
	all_events.sort_custom(id_compare)
	for tag in by_tag:
		(by_tag[tag] as Array).sort_custom(id_compare)

	_built = true

## NOTE: Studio will call this after writing resources to refresh the index
## without a project reload. Passes CACHE_MODE_REPLACE so ResourceLoader
## re-reads from disk instead of returning the pre-edit cached instance —
## without this, a Studio "save and reload" silently keeps stale data.
func rebuild(dir_path: String) -> void:
	build(dir_path, ResourceLoader.CACHE_MODE_REPLACE)

## Recursive directory walk. Uses DirAccess.open() on a res:// path so it
## works in exported Web/WASM builds (eng §6.1 web-safe note); we never
## touch the OS filesystem directly. Returns false iff the root open failed,
## so build() can leave _built = false and allow recovery.
func _scan_dir(dir_path: String, seen_ids: Dictionary, cache_mode: int) -> bool:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		push_error("JourneyPoolIndex.build: cannot open '%s'" % dir_path)
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
		# (corrupted .tres, malformed sub_resource, etc). Surface it so an
		# author can find the file rather than silently losing the event.
		push_error("JourneyPoolIndex.build: failed to load resource at '%s'" % load_path)
		return
	if not (res is JourneyEvent):
		return  # silently skip non-events; pool dirs may legitimately contain other resources
	var event: JourneyEvent = res
	var id_str: String = String(event.id)
	if id_str == "":
		push_error("JourneyPoolIndex.build: event at '%s' has empty id; skipped" % load_path)
		return
	if seen_ids.has(id_str):
		push_error("JourneyPoolIndex.build: duplicate event id '%s' at '%s' (first seen at '%s'); skipped" % [id_str, load_path, seen_ids[id_str]])
		return
	seen_ids[id_str] = load_path
	all_events.append(event)
	for tag in event.event_tags:
		var bucket: Array = by_tag.get(tag, [])
		bucket.append(event)
		by_tag[tag] = bucket

## §3.8 / §7.3 lookup. Linear scan over `all_events` matching by String(id).
## Returns null on miss (or if the index isn't built yet). Used on save load
## to resolve `current_event_id` back to a live JourneyEvent — events in the
## pool dir, which is most narrative content, are reachable through here.
## (Deterministic events reachable only via choice.target_event chains are
## handled by the SequenceManager's broader resolver.)
func find_by_id(id_str: String) -> JourneyEvent:
	if not _built:
		return null
	for e in all_events:
		if String(e.id) == id_str:
			return e
	return null

## §6.3 cumulative-weight roll over `e.weight`. Pure and static so it is
## unit-testable with a constructed RNG and a hand-built candidate array.
##
## Uses `rng` EXCLUSIVELY (no randi()/randf() globals, no fresh RNG) — this
## is the §1.3 determinism contract that lets save/load (Step 6) reproduce
## the exact pull stream after a reload.
##
## Negative weights clamp to 0 (defensive — author error). If the candidate
## total weight is 0 we fall back to a uniform random pick rather than
## returning null, so a pool of explicitly zero-weight events still
## resolves; this preserves the §6.2 contract that a non-empty candidate
## set always yields an event.
static func weighted_pick(candidates: Array[JourneyEvent], rng: RandomNumberGenerator) -> JourneyEvent:
	if candidates.is_empty():
		return null
	var total: int = 0
	for e in candidates:
		var w: int = e.weight if e.weight > 0 else 0
		total += w
	if total <= 0:
		# Uniform fallback — all candidates have non-positive weight. Authors
		# sometimes set weight=0 expecting events to be excluded; warn loudly
		# so that intent vs behavior mismatch is visible. The fallback still
		# resolves (§6.2 contract: non-empty candidates always yield an event).
		push_warning("JourneyPoolIndex.weighted_pick: all %d candidates have weight <= 0; falling back to uniform pick" % candidates.size())
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
##      (or all_events if requested_tags is empty); deduped so an event with
##      two matching tags doesn't double its odds.
##   2. candidates = events in scope where
##        (e.repeatable or e.id not in seen_ids) AND
##        JourneyEvaluator.eval_group(e.pool_conditions, bb) is true.
##   3. Empty candidates → return null (caller emits journey_error per §6.4).
##   4. Else → weighted_pick(candidates, bb.rng).
##
## seen_ids is the LIVE Array from blackboard.metadata["seen_ids"] populated
## by SequenceManager._enter_event; do not maintain a second seen-set here
## (the spec mandates a single source of truth, and Step 6 saves only that
## one).
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
		var id_str: String = String(e.id)
		if not e.repeatable and seen_ids.has(id_str):
			continue
		if not JourneyEvaluator.eval_group(e.pool_conditions, bb):
			continue
		candidates.append(e)

	if candidates.is_empty():
		return null
	return weighted_pick(candidates, bb.rng)

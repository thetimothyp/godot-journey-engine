extends RefCounted
class_name JourneyLoadCheck

## Canonical "WOULD THIS SHIP?" disk round-trip check.
##
## JourneyValidator.validate() inspects the in-memory object graph — where a
## target_event reference cycle is perfectly legal, which is exactly how an
## UNLOADABLE config once passed validate + the runtime smoke test (the smoke
## test also runs on in-memory objects, never round-tripped through disk). This
## helper closes that gap: it loads a JourneyConfig FROM DISK in a fresh load
## context (CACHE_MODE_IGNORE — never the in-memory instance the editor or a
## running game already holds), then walks every reachable resource and asserts
## each one loads non-null with no parse error.
##
## Two independent failure surfaces are exercised:
##   1. The config file itself (and its inline sub-resources) must parse and
##      load. A single-file SubResource target_event cycle dies HERE — the
##      whole .tres fails to parse, so ResourceLoader returns null.
##   2. Every event reachable from start_event ∪ boundary routes ∪ the pool dir
##      must load INDEPENDENTLY from its own file (the property that
##      id-based routing would guarantee structurally). Each event that lives
##      in its own file is re-loaded fresh and null-checked.
##
## Edges followed are choice.target_event only — the same hard-reference graph
## the validator's cycle check walks. continue_to_pool loop-backs carry no
## serialized reference, so they are not graph edges; pool reachability is
## covered by the separate pool-dir scan below.
##
## Returns Array[String] of problems; empty ⇒ the content loads cleanly. Pure
## inspection: never mutates state, never touches the SceneTree, never starts a
## journey. Pair it with JourneyValidator.validate() — validate for authoring
## correctness, this for load-time reality. CI / a pre-ship gate should require
## BOTH to come back clean.

const _FRESH := 4  # ResourceLoader.CACHE_MODE_IGNORE — re-read from disk, ignore cache.

## Round-trip a config given its res:// (or user://) path. This is the entry
## authors should run before shipping content.
static func check(config_path: String) -> Array[String]:
	var problems: Array[String] = []

	var config: Resource = ResourceLoader.load(config_path, "", _FRESH)
	if config == null:
		problems.append("config failed to load from disk (parse error or unserializable graph — e.g. a target_event cycle): %s" % config_path)
		return problems
	if not (config is JourneyConfig):
		problems.append("resource at %s is not a JourneyConfig" % config_path)
		return problems

	_check_deterministic_graph(config, problems)
	_check_pool_dir(config, problems)
	return problems

## Walk start_event ∪ boundary events, following choice.target_event, and
## re-load every event that owns its own file FRESH so we prove each is
## independently loadable (not merely reachable because a parent file dragged
## it in). visited keyed by instance_id; the walk terminates on cyclic graphs.
static func _check_deterministic_graph(config: JourneyConfig, problems: Array) -> void:
	var roots: Array[JourneyEvent] = []
	if config.start_event != null:
		roots.append(config.start_event)
	else:
		problems.append("config.start_event is null on disk")
	for def in config.resource_defs:
		if def == null:
			continue
		if def.bottom_out_event != null:
			roots.append(def.bottom_out_event)
		if def.top_out_event != null:
			roots.append(def.top_out_event)

	var visited: Dictionary = {}
	var queue: Array[JourneyEvent] = roots.duplicate()
	var head: int = 0
	while head < queue.size():
		var ev: JourneyEvent = queue[head]
		head += 1
		if ev == null:
			continue
		var key: int = ev.get_instance_id()
		if visited.has(key):
			continue
		visited[key] = true

		# Re-load this event independently from its own file, if it has one.
		# Inline sub-resources (path like "res://config.tres::Event_x") already
		# rode in with their owner and have no standalone file to re-check.
		var path: String = ev.resource_path
		if path != "" and not path.contains("::"):
			var reloaded: Resource = ResourceLoader.load(path, "", _FRESH)
			if reloaded == null:
				problems.append("event '%s' failed to load independently from %s" % [String(ev.id), path])

		for choice in ev.choices:
			if choice != null and choice.target_event != null:
				queue.append(choice.target_event)

## Scan config.event_pool_dir and load every .tres/.res FRESH, asserting each
## is a non-null JourneyEvent. Mirrors JourneyPoolIndex._scan_dir but with
## CACHE_MODE_IGNORE and an explicit per-file null check, so a pool file that
## only loads off a warm cache (or is silently skipped at build time) is caught.
static func _check_pool_dir(config: JourneyConfig, problems: Array) -> void:
	var dir_path: String = config.event_pool_dir
	if dir_path == "":
		return  # pool-less game; nothing to round-trip.
	if not DirAccess.dir_exists_absolute(dir_path):
		problems.append("event_pool_dir does not exist: %s" % dir_path)
		return
	_scan_pool(dir_path, problems)

static func _scan_pool(dir_path: String, problems: Array) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		problems.append("cannot open event_pool_dir: %s" % dir_path)
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry == "." or entry == "..":
			entry = dir.get_next()
			continue
		var full_path: String = dir_path.path_join(entry)
		if dir.current_is_dir():
			_scan_pool(full_path, problems)
		elif entry.ends_with(".tres") or entry.ends_with(".res"):
			var res: Resource = ResourceLoader.load(full_path, "", _FRESH)
			if res == null:
				problems.append("pool resource failed to load from disk: %s" % full_path)
			elif res is JourneyEvent and String((res as JourneyEvent).id) == "":
				problems.append("pool event has empty id on disk: %s" % full_path)
		entry = dir.get_next()
	dir.list_dir_end()

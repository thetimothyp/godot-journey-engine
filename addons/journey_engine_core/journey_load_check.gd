extends RefCounted
class_name JourneyLoadCheck

## Canonical "WOULD THIS SHIP?" disk round-trip check.
##
## JourneyValidator.validate() inspects events held in memory (the live index or
## an in-memory one). This helper proves the content survives a real trip to and
## from disk in a FRESH load context (CACHE_MODE_IGNORE — never the instances the
## editor or a running game already hold): every event file loads independently,
## and every routing id resolves against an index built purely from disk.
##
## Under id-based routing the failure mode is no longer an unserializable
## reference cycle (ids can't form one) — it is a DANGLING id (a target/start/
## boundary id with no event file behind it) or an unloadable/duplicate/empty-id
## event file. Both are caught here:
##   1. Every .tres under events_dir is loaded fresh and indexed; load failures,
##      empty ids, and duplicate ids surface as problems (via the index's
##      build_problems).
##   2. start_event_id, every resource_def boundary id, and every
##      choice.target_event_id across every indexed event must resolve to a
##      loaded event.
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
		problems.append("config failed to load from disk (parse error): %s" % config_path)
		return problems
	if not (config is JourneyConfig):
		problems.append("resource at %s is not a JourneyConfig" % config_path)
		return problems
	var cfg: JourneyConfig = config

	if cfg.events_dir == "":
		problems.append("config.events_dir is empty — no events to index")
		return problems

	# Build the index straight from disk, ignoring any warm cache. This loads
	# every event file fresh (so an unloadable file fails here) and records
	# empty/duplicate-id problems in build_problems.
	var index := JourneyEventIndex.new()
	index.build(cfg.events_dir, _FRESH)
	if not index.is_built():
		problems.append("could not build event index from events_dir: %s" % cfg.events_dir)
		return problems
	for p in index.build_problems:
		problems.append(String(p.get("message", "")))

	# Every routing id must resolve against the disk-built index.
	var sid: String = String(cfg.start_event_id)
	if sid == "":
		problems.append("config.start_event_id is empty on disk")
	elif index.find_by_id(sid) == null:
		problems.append("start_event_id '%s' does not resolve to a loaded event" % sid)

	for def in cfg.resource_defs:
		if def == null:
			continue
		var name: String = def.key if def.key != "" else "<unnamed>"
		var bid: String = String(def.bottom_out_event_id)
		if bid != "" and index.find_by_id(bid) == null:
			problems.append("resource def '%s' bottom_out_event_id '%s' does not resolve to a loaded event" % [name, bid])
		var tid: String = String(def.top_out_event_id)
		if tid != "" and index.find_by_id(tid) == null:
			problems.append("resource def '%s' top_out_event_id '%s' does not resolve to a loaded event" % [name, tid])

	for event in index.all_events:
		if event == null:
			continue
		for ci in range(event.choices.size()):
			var choice: JourneyChoice = event.choices[ci]
			if choice == null:
				continue
			var t: String = String(choice.target_event_id)
			if t != "" and index.find_by_id(t) == null:
				problems.append("event '%s' choice[%d] target_event_id '%s' does not resolve to a loaded event" % [String(event.id), ci, t])

	return problems

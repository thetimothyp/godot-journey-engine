extends RefCounted
class_name JourneySaveManager

## §7 save/load. Reduces the Blackboard to flat primitives, writes/reads via
## FileAccess (plaintext or password-encrypted per config), and ships a
## migration ladder scaffold (§7.4).
##
## RefCounted, owned by the runtime. No signals, no routing, no SceneTree —
## resolving `current_event_id` back to a JourneyEvent and re-entering it is
## the SequenceManager's job (§7.3). Keeping SaveManager free of routing makes
## it pure-data: trivially unit-testable, no Autoload dependency, no UI side
## effects.

## History ring-buffer cap (§10.2). Mirrored from JourneySequenceManager so
## load_into can re-enforce the invariant on the restored array — a tampered
## or future-migrated save with > cap entries gets trimmed here rather than
## waiting for the next _enter_event to fix it. Kept in sync with
## JourneySequenceManager.HISTORY_CAP (Step-5 follow-up #14 will centralize
## when we cross the next consolidation pass).
const HISTORY_CAP: int = 200

## §7.1 reduce the Blackboard to PRIMITIVES ONLY. No JourneyEvent / Resource /
## Node ever lands in a save. The active event lives in the dict as its String
## `id` (§3.8); on load we resolve it back. This is the entire reason `id`
## exists as a separate field from the object reference.
##
## Safety: §7.2 mandates store_var with full_objects=false (the FileAccess
## default — we never pass true anywhere in this file). With full_objects=false,
## a stray non-primitive in the dict makes store_var fail loudly rather than
## bake a brittle object reference into saves. The shape below is therefore
## the contract the writer enforces, not a hope.
static func serialize(bb: Blackboard, save_version: int) -> Dictionary:
	var meta_in: Dictionary = bb.metadata

	# Resource/flag dicts are copied (not aliased) so the returned dict can't
	# be mutated later via a back-reference to live Blackboard state.
	var resources: Dictionary = {}
	for k in bb.resources:
		resources[String(k)] = float(bb.resources[k])
	var flags: Dictionary = {}
	for k in bb.flags:
		flags[String(k)] = bool(bb.flags[k])

	var seen_in: Array = meta_in.get("seen_ids", [])
	var seen: Array = []
	for s in seen_in:
		if s is String or s is StringName:
			seen.append(String(s))
		else:
			push_warning("JourneySaveManager.serialize: non-string in seen_ids skipped: %s" % str(s))

	var hist_in: Array = meta_in.get("history", [])
	var history: Array = []
	for h in hist_in:
		if h is String or h is StringName:
			history.append(String(h))
		else:
			push_warning("JourneySaveManager.serialize: non-string in history skipped: %s" % str(h))

	# §7.1 shape exact. rng_seed lives at the top level per spec, even though
	# the Blackboard stores it inside metadata at runtime — the on-disk shape
	# is the source of truth for §7.4 migrations.
	return {
		"save_version": save_version,
		"rng_state": bb.rng.state,
		"rng_seed": int(meta_in.get("rng_seed", 0)),
		"resources": resources,
		"flags": flags,
		"metadata": {
			"current_event_id": String(meta_in.get("current_event_id", "")),
			"turn_counter": int(meta_in.get("turn_counter", 0)),
			"seen_ids": seen,
			"history": history,
		},
	}

## §7.2 write. Plaintext when `key` is empty (the PRD §5 default — easier
## debugging, no hardcoded key), password-encrypted otherwise. Returns OK on
## success or a meaningful Error (and push_errors) on failure; never crashes
## on a bad path / missing dir.
func save(bb: Blackboard, slot: String, key: String, save_version: int) -> int:
	var path: String = "user://%s.dat" % slot
	var f: FileAccess
	if key.is_empty():
		f = FileAccess.open(path, FileAccess.WRITE)
	else:
		f = FileAccess.open_encrypted_with_pass(path, FileAccess.WRITE, key)
	if f == null:
		var err: int = FileAccess.get_open_error()
		push_error("JourneySaveManager.save: cannot open '%s' for write (err=%d)" % [path, err])
		return err if err != OK else FAILED

	var dict: Dictionary = serialize(bb, save_version)
	# store_var full_objects defaults to false — a stray non-primitive fails
	# LOUDLY here rather than embedding an object reference into the save.
	f.store_var(dict)
	# store_var is void; surface a post-write failure (disk full, encryption-
	# stream error, sneaky non-primitive) by reading f.get_error() before close.
	# Without this, save() returned OK on a truncated/garbled file and the
	# caller silently lost player state.
	var write_err: int = f.get_error()
	f.close()
	if write_err != OK:
		push_error("JourneySaveManager.save: write failed for '%s' (err=%d)" % [path, write_err])
		return write_err
	return OK

## §7.3 read + restore. Mutates the passed-in Blackboard in place so the
## runtime's existing signal/routing path can re-enter the current event
## without any special UI-restore code. Re-entering the event itself is the
## SequenceManager's job — SaveManager stays free of routing/signals.
##
## Error contract:
##   ERR_FILE_NOT_FOUND  — slot doesn't exist (caller decides what to do)
##   ERR_INVALID_DATA    — save is newer than current, or its shape is wrong
##   OK                  — Blackboard restored; runtime should re-enter event
func load_into(bb: Blackboard, slot: String, key: String, current_version: int) -> int:
	var path: String = "user://%s.dat" % slot
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND

	var f: FileAccess
	if key.is_empty():
		f = FileAccess.open(path, FileAccess.READ)
	else:
		f = FileAccess.open_encrypted_with_pass(path, FileAccess.READ, key)
	if f == null:
		var err: int = FileAccess.get_open_error()
		push_error("JourneySaveManager.load_into: cannot open '%s' for read (err=%d)" % [path, err])
		return err if err != OK else FAILED

	var raw: Variant = f.get_var()
	f.close()
	if not (raw is Dictionary):
		push_error("JourneySaveManager.load_into: save at '%s' is not a Dictionary" % path)
		return ERR_INVALID_DATA
	var dict: Dictionary = raw

	var save_version: int = int(dict.get("save_version", 0))
	if save_version > current_version:
		# Don't attempt to load a save from a future version — fields we expect
		# may be reshaped, fields we don't may carry meaning.
		push_error("JourneySaveManager.load_into: save_version %d is newer than current %d" % [save_version, current_version])
		return ERR_INVALID_DATA
	if save_version < current_version:
		# _migrate mutates `dict` in place (Dictionaries are reference-typed in
		# GDScript). The dict is local to this function so the caller is
		# unaffected, but the duplicate(true) defends against a future migration
		# step that partially mutates then errors — load_into still bails on
		# the post-migrate save_version check, with no half-applied changes
		# escaping to the caller.
		dict = _migrate(dict.duplicate(true), save_version, current_version)
		if int(dict.get("save_version", 0)) != current_version:
			# Migration didn't reach the current version — _migrate already
			# push_errored; refuse to load a half-migrated dict.
			return ERR_INVALID_DATA

	# Precondition: rng_state is required for the §1.3 determinism contract.
	# A missing key would silently set state to 0 (a degenerate PCG seed) and
	# break post-load pull reproduction without surfacing a failure. Refuse
	# the load instead — corrupt/tampered/under-migrated saves fail loud.
	if not dict.has("rng_state"):
		push_error("JourneySaveManager.load_into: save at '%s' is missing required 'rng_state'" % path)
		return ERR_INVALID_DATA

	# In-place restore — preserves the bb object identity the runtime holds.
	bb.resources.clear()
	var res_in: Dictionary = dict.get("resources", {})
	for k in res_in:
		bb.resources[String(k)] = float(res_in[k])

	bb.flags.clear()
	var flags_in: Dictionary = dict.get("flags", {})
	for k in flags_in:
		bb.flags[String(k)] = bool(flags_in[k])

	var meta_in: Dictionary = dict.get("metadata", {})
	bb.metadata.clear()
	bb.metadata["current_event_id"] = String(meta_in.get("current_event_id", ""))
	bb.metadata["turn_counter"] = int(meta_in.get("turn_counter", 0))
	var seen: Array = []
	for s in meta_in.get("seen_ids", []):
		seen.append(String(s))
	bb.metadata["seen_ids"] = seen
	var history: Array = []
	for h in meta_in.get("history", []):
		history.append(String(h))
	# Re-enforce the §10.2 HISTORY_CAP invariant on restore — a tampered or
	# future-migrated save with > cap entries would otherwise violate the cap
	# until the next normal _enter_event trimmed it. Drop oldest entries first.
	while history.size() > HISTORY_CAP:
		history.pop_front()
	bb.metadata["history"] = history
	# rng_seed at top-level on disk → back into metadata at runtime per §4.2.
	bb.metadata["rng_seed"] = int(dict.get("rng_seed", 0))

	# §1.3/§7.1 determinism: restore rng.state (NOT just the seed) so the
	# stochastic pull stream resumes EXACTLY where it left off. A reloaded
	# save that makes the same choices reproduces the same pulls — this is
	# the Step-5 contract that Step 6 cashes in. Also restore rng.seed so
	# bb.rng.seed and bb.metadata["rng_seed"] stay in sync (the two sources
	# of truth disagreed when seed wasn't restored — broke any consumer that
	# reads bb.rng.seed directly, e.g. a diagnostic overlay or reseed helper).
	bb.rng.seed = int(dict["rng_seed"])
	bb.rng.state = int(dict["rng_state"])

	return OK

## §7.4 migration ladder. Steps a dict from `from_version` up to `to_version`
## one breaking version at a time. v1 ships with NO steps inside intentionally
## — the scaffold exists so the FIRST breaking save-format change in v2 has an
## obvious home (and shipped player saves never strand). Cheap now, expensive
## to retrofit, hence included in v1.
##
## NOTE: when a v2 ships, add a clause:
##     if v == 1:
##         dict = _migrate_v1_to_v2(dict)
##         v = 2
##         continue
## Each step must be self-contained so v1→v3 is the composition of v1→v2 then
## v2→v3 — never a special case. If a step is missing the ladder push_errors
## and returns the dict UN-advanced, so load_into refuses to apply it.
##
## NOTE: this function MUTATES `dict` in place (Dictionaries are reference-
## typed in GDScript). load_into already passes a dict.duplicate(true) copy so
## the caller is unaffected; external callers should do the same if they
## intend to reuse the input.
static func _migrate(dict: Dictionary, from_version: int, to_version: int) -> Dictionary:
	var v: int = from_version
	while v < to_version:
		# Add migration steps here, one per breaking version bump.
		# (No-op scaffold for v1 — see NOTE above.)
		push_error("JourneySaveManager._migrate: no migration step from v%d (target v%d); add one." % [v, to_version])
		break
	dict["save_version"] = v
	return dict

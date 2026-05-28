# Save & Load

Journey Engine serializes a run to a flat dictionary of primitives and writes it
under `user://`. A load restores the **exact** run — including the random stream,
so subsequent pool pulls reproduce what would have happened without the
save/load round-trip.

## The API

Both calls require an active journey (you must have called `start_new_journey`
first — the save settings live on the config). They return a Godot `Error` code.

```gdscript
var err := JourneyRuntime.save_game("slot1")    # default slot is "savegame"
if err == OK:
    print("saved")

var lerr := JourneyRuntime.load_game("slot1")
if lerr == OK:
    print("loaded")
```

Files are written to `user://<slot>.dat`.

| Return | Meaning |
| --- | --- |
| `OK` | Success. |
| `ERR_UNCONFIGURED` | No active journey (call `start_new_journey` first). |
| `ERR_FILE_NOT_FOUND` | `load_game`: that slot doesn't exist. |
| `ERR_INVALID_DATA` | Save is corrupt, newer than the current `save_version`, or its current event id can't be resolved. |

`load_game` is **atomic**: if restoring fails after reading the file (e.g. the
saved `current_event_id` no longer exists), the runtime rolls the Blackboard back
to its pre-load state so you're never left half-loaded.

## What gets saved

Only primitives — never a `JourneyEvent` or any other object. The current event
is stored as its string `id` and resolved back to the live event on load (this is
the entire reason `JourneyEvent.id` exists as a separate field).

The serialized shape:

```text
{
  save_version, rng_state, rng_seed,
  resources: { key: float, ... },
  flags:     { key: bool, ... },
  metadata:  { current_event_id, turn_counter, seen_ids, history },
}
```

!!! warning "Custom metadata is not saved"
    Only the engine-owned metadata keys (`current_event_id`, `turn_counter`,
    `seen_ids`, `history`, `rng_seed`) survive a round-trip. Any custom key you
    wrote into `metadata` is dropped on load. Persistent custom state belongs in
    resources or flags. (See [Blackboard](../concepts/blackboard.md).)

## Determinism across a load

The save stores `rng_state` — the RNG's *current position*, not just its seed —
and the load restores it. That's what lets the stochastic pool resume mid-stream:
load a save, make the same choices, and you get the same pulls. A save missing
`rng_state` is rejected (`ERR_INVALID_DATA`) rather than silently breaking
determinism.

## Repaint your UI after a load

Loading **bulk-restores** the Blackboard instead of mutating it through
consequences, so **no** `resource_changed` / `flag_changed` signals fire for the
restored values. `event_changed` *does* re-fire (so narrative and choices rebuild
automatically), but you must repaint any HUD bound to resources yourself:

```gdscript
func _on_load_pressed() -> void:
    var err := JourneyRuntime.load_game("slot1")
    if err == OK:
        _refresh_hud_full()        # read get_resource(...) and repaint
    else:
        _show_toast("Load failed (err=%d)" % err)
```

This is exactly what the bundled `sample_game/` does. See the
[Presentation Contract](../concepts/presentation-contract.md#after-a-load-repaint-manually).

## Encryption

Saves are plaintext by default. Set `JourneyConfig.save_encryption_key` to a
non-empty string to write password-encrypted saves instead. The same config is
used for both writing and reading, so the key must match.

=== "Plaintext (default)"

    ```gdscript
    config.save_encryption_key = ""    # easy to inspect while debugging
    ```

=== "Encrypted"

    ```gdscript
    config.save_encryption_key = "my-secret-key"
    ```

!!! warning "Encryption is anti-tamper, not security"
    A key shipped inside your game can be extracted from the binary by a
    determined player. Save encryption raises the bar against casual save-editing;
    it does **not** protect secrets. Don't store anything sensitive in a save and
    don't rely on the key staying secret.

## Versioning & migration

`JourneyConfig.save_version` anchors the save format. The loader compares a save's
version to the current one:

- **Older save** → run the migration ladder up to the current version, then load.
- **Newer save** → refuse (`ERR_INVALID_DATA`) — a save from a future version may
  have reshaped fields.

Version 1 ships with an **empty** migration ladder by design: the scaffold exists
so the first breaking change in v2 has an obvious home and shipped player saves
never strand. When you make a breaking format change, bump `save_version` and add
the corresponding migration step. Until then, leave `save_version = 1`.

See also: [Stochastic Pool](stochastic-pool.md) for the RNG contract ·
[API Reference](../reference/api.md) for exact signatures.

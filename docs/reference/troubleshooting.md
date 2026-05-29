# Troubleshooting & FAQ

Common issues, what causes them, and where to read more.

## Setup

??? question "`Invalid call. Nonexistent function 'start_new_journey' in base 'null instance'` (or `JourneyRuntime` is null)"
    The autoload isn't registered. Easiest fix: enable **Journey Engine Core** in
    **Project Settings → Plugins** — the plugin registers the `JourneyRuntime`
    autoload for you. If you registered it by hand instead, check the path is
    `res://addons/journey_engine_core/journey_runtime.gd` and the node name is
    exactly `JourneyRuntime`. See
    [Installation → Enable the plugin](../getting-started/installation.md#2-enable-the-plugin).

??? question "`Class 'JourneyRuntime' hides an autoload singleton`"
    Something added a `class_name JourneyRuntime`. The runtime script
    deliberately has **no** `class_name` because it would collide with the
    Autoload's auto-registered global. Remove the `class_name` and access the
    engine through the Autoload identifier.

## Content & routing

??? question "A choice I authored never appears"
    Its `visibility` condition group is failing right now. `event_changed` hands
    your UI only the choices whose visibility passes — filtering lives in the
    engine. Check the conditions against current state. Remember: a **null**
    visibility group means *always visible*, and an **empty** group also passes.
    See [Routing](../concepts/routing.md) and
    [Resources & Events](../concepts/resources-and-events.md).

??? question "`journey_error: empty pool for tags: [...]`"
    A `continue_to_pool` choice found no eligible event. Usual causes: a typo in
    `pool_tags_filter` vs. the events' `event_tags`; every matching event is
    non-repeatable and already seen; or every match's `pool_conditions` currently
    fail. Ensure at least one **repeatable** event always matches the tags you
    pull with. See [Stochastic Pool → Empty pools](../guides/stochastic-pool.md#empty-pools).

??? question "My pool event never gets picked even though it's eligible"
    Check its `weight`. A `weight` of `0` (or negative) contributes nothing to the
    cumulative roll. If you set `weight = 0` expecting the event to be *excluded*,
    that's not what weight does — the engine warns and falls back to uniform if
    *all* candidates are zero-weight. To exclude an event, gate it with
    `pool_conditions` or `repeatable`, not weight.

??? question "A bottom-out / top-out route fires repeatedly (or loops forever)"
    Boundary routes fire on **transition**, not presence — moving a value *onto*
    `min`/`max`, not sitting at it. If you're seeing a loop, you may be on an
    older build predating that fix, or expecting presence semantics. A no-op
    choice on an event reached via a bottom-out should *not* re-fire it. See
    [Routing → Forced boundary routes](../concepts/routing.md#forced-boundary-routes).

??? question "Two resources hit zero on the same choice — which route wins?"
    The one declared **first** in `config.resource_defs`. Boundary-route priority
    is declaration order; the rest are ignored for that batch.

??? question "`journey_error: target_event_id '…' did not resolve to an indexed event` (a choice goes nowhere)"
    The choice's `target_event_id` (or a `start_event_id` / boundary `*_event_id`)
    has **no event behind it** — a typo, or an event that isn't under
    `config.events_dir`, or one you deleted/renamed. Routing is by id, resolved
    against the event index built from `events_dir`; an id with no match dead-ends.
    Fix the id, or make sure the target event's `.tres` lives under `events_dir`
    (which is scanned recursively). Catch these before running:
    [`validate()`](../guides/validation.md#the-unresolved-id-error) reports every
    unresolved id as an error, and `JourneyLoadCheck.check()` confirms it from a
    fresh disk load. See
    [Routing → routing is by id](../concepts/routing.md#routing-is-by-id-every-event-is-independently-loadable).

??? question "A pool event is never drawn (or a deterministic event gets pulled at random)"
    Pool draws are scoped by the per-event **`pool_eligible`** flag, not by which
    folder the event sits in. An event that should appear in random pulls must have
    `pool_eligible = true` (plus matching `event_tags` / `pool_conditions`); a
    deterministic-only event must leave it `false` so it's never drawn — even
    though it shares the index for routing resolution.

## State

??? question "`condition references missing resource key '...'; treating as 0.0` warning"
    A condition names a resource that isn't in `resource_defs` — almost always a
    typo. The engine treats the read as `0.0` and warns. Run
    [`validate()`](../guides/validation.md) to catch these before runtime. (Flag
    references never warn — flags are lazy.)

??? question "My consequence didn't change anything"
    If it targets a resource with no `JourneyResourceDef`, it's skipped with a
    warning (the engine never auto-creates an undeclared resource). If it's a
    numeric op, the result may have been **clamped** to the resource's bounds —
    e.g. subtracting below `min_value` stops at `min_value`. See
    [Blackboard → Missing-key read policy](../concepts/blackboard.md#missing-key-read-policy).

## Saves

??? question "`load_game` returns a non-OK error"
    `ERR_UNCONFIGURED` = no active journey (call `start_new_journey` first);
    `ERR_FILE_NOT_FOUND` = that slot doesn't exist; `ERR_INVALID_DATA` = the save
    is corrupt, from a newer `save_version`, or its current event id can't be
    resolved. The load is atomic — a failure leaves the runtime in its pre-load
    state. See [Save & Load](../guides/save-and-load.md).

??? question "After loading, my HUD shows stale values"
    Loading bulk-restores the Blackboard, so per-resource signals don't fire.
    `event_changed` re-fires (narrative/choices rebuild) but you must repaint
    resource-bound HUD yourself by reading `get_resource(...)` in your load
    handler. See
    [Presentation Contract → After a load](../concepts/presentation-contract.md#after-a-load-repaint-manually).

??? question "Custom data I put in metadata disappeared after load"
    Only the engine-owned metadata keys survive a round-trip. Custom keys are
    dropped on load — model persistent custom state as resources or flags. See
    [Blackboard → Engine-owned metadata keys](../concepts/blackboard.md#engine-owned-metadata-keys).

## Exporting

??? question "The pool is empty in my exported / Web build but fine in the editor"
    Confirm `config.events_dir` points at a folder that actually contains the
    event `.tres` files (with `pool_eligible = true` on the pool ones) and that
    they were included in the export. The scan is export-safe (it reads the PCK's
    virtual filesystem and `.remap` pointers), so a genuine empty-in-export almost
    always means the directory path or export filter is wrong. See
    [Exporting](../guides/exporting.md).

??? question "The WASM build won't load from a file:// URL"
    Browsers block WASM over `file://`. Serve the build over HTTP
    (`python3 -m http.server` from the export folder) and open `http://localhost:8000`.
    See [Exporting → Web / WASM](../guides/exporting.md#web-wasm).

Still stuck? The [API Reference](api.md) lists exact signatures and error codes,
and the bundled `sample_game/` is a working reference for every feature.

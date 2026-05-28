# Journey Engine — Core Runtime Implementation Progress

This file is the single source of truth for implementation state. Any fresh
Claude Code session (or fresh Claude chat session) should read this file plus
the two design docs to orient before doing anything.

## Reference documents (in this repo)
- `docs/journey_engine_prd_v2.md` — product requirements (what & why)
- `docs/journey_engine_eng_design.md` — engineering design (how); §11 is the build order

## Target environment
- Godot 4.6.x stable, GDScript only, Compatibility renderer
- Core classes live in `journey_core/`
- Throwaway manual-test scaffolding lives in `tests/`

## Core invariants (must hold at every step — never violate)
- **Single mutation path:** game/test code never writes the Blackboard directly;
  all state change flows through consequences applied by the runtime. (eng §9)
- **Presentation-agnostic core:** no class in `journey_core/` instantiates a Node,
  touches the SceneTree, or assumes a UI exists. (eng §5.5)
- **Missing-key policy:** missing resource key reads as 0.0 + warning; missing flag
  reads as false (no warning); consequences never auto-create undeclared resources. (eng §4.3)
- **Studio-authorable:** every resource must be fully constructable/editable in the
  Godot inspector with no code. (eng §1.3)
- **Determinism:** fixed RNG seed + identical state ⇒ identical stochastic results. (eng §1.3)

## Build order & status
- [x] **Step 1** — Resource classes: Condition, Consequence, ConditionGroup, Choice,
      Event, ResourceDef, Config
- [x] **Step 2** — Blackboard + initialization
- [x] **Step 3** — Evaluator (conditions) + Mutator (consequences), as pure helpers + tests
- [x] **Step 4** — SequenceManager deterministic routing + `_enter_event` + signals;
      minimal test scene proving the loop end-to-end
- [ ] **Step 5** — PoolIndex + stochastic pull + weighted pick + tests
- [ ] **Step 6** — SaveManager + versioning + round-trip tests
- [ ] **Step 7** — `validate()` authoring utility
- [ ] **Step 8** — Export smoke test (Web/WASM) + small sample game exercising every feature

## Session log (append one line per completed step)
<!-- e.g. "2026-05-28 — Step 1 complete. 7 resource classes in journey_core/. Tested via inspector." -->
2026-05-28 — Step 1 complete. Created 7 resource classes in journey_core/ (JourneyCondition, JourneyConsequence, JourneyConditionGroup, JourneyChoice, JourneyEvent, JourneyResourceDef, JourneyConfig) matching eng design §3.2–§3.7. Pure data, no methods. Manual inspector verification passed: project loads error-free, all 7 types appear in New Resource dialog, enums render as dropdowns, test_condition.tres and test_event.tres saved.
2026-05-28 — Step 2 complete. Added journey_core/blackboard.gd as a RefCounted (class_name Blackboard) matching eng design §4.1 fields (resources, flags, metadata, rng) and §4.2 init (clamped defaults, copied initial_flags, deterministic-or-randomized rng with stored seed, turn_counter/current_event_id/history/seen_ids primed). No mutation/evaluation/signal logic — those land in Steps 3–4. NOTE comment flags that Step 4 may relocate the call site to JourneyRuntime, keeping the logic itself on Blackboard. Test scaffolding in tests/ (test_config.tres, test_blackboard.gd, test_blackboard.tscn) — manual run pending user verification.
2026-05-28 — Step 3 complete. Added journey_core/evaluator.gd (class_name JourneyEvaluator) and journey_core/mutator.gd (class_name JourneyMutator) as RefCounted with static methods only, per eng §2 / §8.2 (headless-testable, no SceneTree, no Autoload). Evaluator implements all 8 operators + ALL/ANY/null/empty group rules with the §4.3 missing-key policy exact (warn+0 for resource reads citing event id when available, silent-false for flags). Mutator implements ADD/SUBTRACT/SET_VALUE with §4.4 clamp to JourneyResourceDef bounds and skip+warn on undeclared keys; SET_FLAG/TOGGLE_FLAG untouched. apply_batch applies the full batch first, THEN scans config.resource_defs in definition order and RETURNS triggered defs (== min_value with bottom_out_event, or == max_value with top_out_event); routing is deferred to Step 4. No signals emitted, no metadata mutation. Manual test (tests/test_eval_mutate.gd, .tscn) run by user and all 30 checks PASS: numeric ops, missing-resource warn+0, silent-false flag, null/empty/ALL/ANY groups, ADD/SUBTRACT clamp on gold to 0, SET/TOGGLE flags, undeclared-mana consequence skipped with warn, batch reporting two defs in definition order [sanity, rations], single-trigger, and top-out symmetry.
2026-05-28 — Step 4 complete. Added journey_core/journey_runtime.gd (Node, autoload-registered as `JourneyRuntime`; NO class_name, since the autoload's auto-global collides with a class_name of the same name — "Class 'JourneyRuntime' hides an autoload singleton") as the single public surface per eng §9: blackboard ownership, the six §5.3 signals declared verbatim, get_resource/has_flag/get_metadata convenience reads, and stubbed save/load/validate/rebuild_pool. Routing brain lives in journey_core/sequence_manager.gd (class_name JourneySequenceManager, RefCounted) — start_new_journey relocates the Blackboard.initialize call site (logic stays on Blackboard, per Step-2 NOTE) and emits journey_started; process_choice snapshots touched resource/flag keys, calls JourneyMutator.apply_batch, then diffs post-clamp values to emit per-mutation resource_changed/flag_changed (keeping the Mutator pure); routing precedence is forced-bottom/top-out > target_event > continue_to_pool (currently emits a clean "Step 5" journey_error, no crash) > end-journey on the current event. _enter_event guards null, bumps turn_counter, updates current_event_id, appends to a 200-cap ring-buffer history, marks seen_ids, filters visible choices via JourneyEvaluator.eval_group (filtering lives in core per Dumb-UI contract §5.5), and emits event_changed. Autoload registered directly in project.godot ([autoload] JourneyRuntime="*res://journey_core/journey_runtime.gd"). Test scaffolding: tests/journey/{evt_start,evt_rich,evt_kind}.tres (the spec's 3-event journey, with evt_kind's "They join you" gated by ALL[HAS_FLAG helped_stranger]), tests/test_config.tres updated to point start_event at evt_start, tests/game_view.gd + .tscn as a dumb Label+VBox UI that connects all six signals and prints state changes. User verified manually: loop advances on clicks, gold gains 50 on "Take the gold" (resource_changed fires post-clamp), helped_stranger flag fires on "Help the stranger", "They join you" appears when the flag passes and disappears when its condition key is rewritten to an unset key (visibility filtering bites), and journey_ended fires on terminal choices.
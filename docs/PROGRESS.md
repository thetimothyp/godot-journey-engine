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
- [ ] **Step 2** — Blackboard + initialization
- [ ] **Step 3** — Evaluator (conditions) + Mutator (consequences), as pure helpers + tests
- [ ] **Step 4** — SequenceManager deterministic routing + `_enter_event` + signals;
      minimal test scene proving the loop end-to-end
- [ ] **Step 5** — PoolIndex + stochastic pull + weighted pick + tests
- [ ] **Step 6** — SaveManager + versioning + round-trip tests
- [ ] **Step 7** — `validate()` authoring utility
- [ ] **Step 8** — Export smoke test (Web/WASM) + small sample game exercising every feature

## Session log (append one line per completed step)
<!-- e.g. "2026-05-28 — Step 1 complete. 7 resource classes in journey_core/. Tested via inspector." -->
2026-05-28 — Step 1 complete. Created 7 resource classes in journey_core/ (JourneyCondition, JourneyConsequence, JourneyConditionGroup, JourneyChoice, JourneyEvent, JourneyResourceDef, JourneyConfig) matching eng design §3.2–§3.7. Pure data, no methods. Manual inspector verification passed: project loads error-free, all 7 types appear in New Resource dialog, enums render as dropdowns, test_condition.tres and test_event.tres saved.
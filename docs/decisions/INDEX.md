# Decision Records — Index

Full decision summaries for `docs/decisions/`. One-line index lives in `CLAUDE.md` § Reference Documents.

## ADR-001 — Architecture Overview (Phase 1)

Phase 1 architecture decisions (12 ADRs)

## ADR-002 — llama.cpp interim LLM backend

llama.cpp interim LLM backend decision

## ADR-003 — Background execution

BG execution (iOS 26 BGContinuedProcessingTask)

## ADR-004 — Multi-platform strategy

Multi-platform strategy — Accepted (Conditional GO) on #220 KMP spike; §9 GO/NO-GO synthesis (H5/H7 distribution-verification deferred)

## ADR-005 — Content safety architecture

Content safety architecture (App Store review)

## ADR-006 — Cloud API implementation details

Cloud API implementation details (Phase 3; reserved — not yet written; see ADR-005 §7.5)

## ADR-007 — DL-time demo replay (iOS lifecycle)

DL-time demo replay — iOS lifecycle (#152)

## ADR-008 — Route identity vs render-time hints

Route identity vs render-time hints (`RouteHint<T>` pattern, #245)

## ADR-009 — View testing strategy

View testing strategy (no ViewInspector / snapshot; #269)

## ADR-010 — Localization (i18n: ja/en)

Localization (i18n: ja/en) — ADR body for Step C-1 design (Status: Proposed; stub #279, body #367)

## ADR-011 — 6 GB RAM tier

6 GB RAM tier — selection criteria + Phase 2 deferral (no-go for Gemma 3 1B IT; mechanism-contract prerequisites for future candidates; #477 / PR #480 / #483)

## ADR-012 — YAML strategy post-kaml

YAML strategy post-kaml — snakeyaml-engine-kmp adoption for the shared Models layer (kaml archived; #220 D3 / T9; ADR-008 number drift)

## ADR-013 — Headless macOS simulation harness

Headless macOS simulation harness — SwiftPM source reuse for the scenario factory (#515, impl #517)

## ADR-014 — Release automation toolchain

Release automation toolchain — fastlane + ASC API Key, local-first, TestFlight-upload scope (Status: Accepted; #555)

## ADR-015 — Execution-log retention posture

Execution-log retention posture (no silent auto-delete; manual purge + advisory cap) + SQLite iCloud-backup decision (keep backed up; DatabaseQueue ⇒ no WAL sidecars) (#547)

## ADR-016 — Home redesign — bottom-tab IA

Home redesign — bottom-tab IA + deep-link tab routing (4-tab; `TabCoordinator`×4 unmodified AppRouter; `.settings`/`.sharedScenarios` removed from Route; `isSimulationOnTop` = any-tab) (Status: Accepted; #602; § Amendment 2026-06-18 re-anchors the fold on hosting + scenePhase per ADR-017; § Amendment 2026-06-20 adopts iOS 18+ structural `Tab` API — search-role morph deferred (grouped search tab; detached search-role capsule reads as in-screen search), icon-only via label-closure with device-QA-contingent label fallback, #693)

## ADR-017 — Simulation focus mode

Simulation focus mode — hide the tab bar during a run so tab-switching mid-run is impossible (#646 Phase A); § Amendment 2026-06-20 implements Phase B — opt-in cross-screen continuation via Variant 3 (ownership lift + `SuspendController` park-on-hide; progress suspended while away), `keepRunningOnLeaveEnabled` default-off, in-flight indicator on `RootTabView` overlay; iPad multi-window concurrent runs out of scope (Status: Accepted; #646/#682)

## ADR-018 — Format-preserving visual→YAML boundary sync

Format-preserving visual→YAML boundary sync — surgical scalar patch via Yams `compose`+`Mark` (value-only updates preserve comments/key order; structural & block-scalar changes + any uncertainty fall back to full serialize; reparse safety-net; `ScenarioYAMLPatcher` in Engine; supersedes #338's single-source-of-truth direction) (Status: Accepted; #725)

## ADR-019 — Raise minimum deployment target to iOS 18

Raise minimum deployment target from iOS 17 to iOS 18 — the `ModelRegistry.minRAM` 6.5 GB gate already excludes every iOS-17-bound device, so the raise costs nothing while removing `#available` branches (iOS-17 `RootTabView` fallback, `ScrollPosition.scrollTo(edge:)` for #830) (Status: Accepted; #834)

## ADR-020 — Shared-scenario backward-compat

Shared-scenario backward-compat across engine breaking changes — two-layer hybrid gate on a monotonic `ENGINE_SCHEMA_VERSION`: capability-derived `phases`⊄`PhaseType.allCases` auto-gate (flatten conditional sub-phases; CI-pinned) + declared `min_engine_version` escape hatch (tooling-computed floor, author-raisable for semantics); grey-out at index-display time; never partial-run; parse-throw safety net w/ update-guidance message; bump policy on semantic equivalence not syntactic additivity; envelope `version` repurposed for structural reshapes only; imports out-of-scope; land baseline before first release (Status: Accepted; baseline shipped #965 — D1/D2/D2a/D2b/D3-field/D4/D5; D3a derived-floor extractor + D7 + App Store deep-link deferred to first post-baseline PR, see ADR §7; #946)

## ADR-021 — Graceful degradation of LLM turn failures

Graceful degradation of LLM turn failures — per-turn containment in the six LLM handlers via a shared run-scoped `TurnFailureGate` (degrade by omission never fabrication; `lastOutputs` clear-on-skip), 3-class failure taxonomy (transient/systemic/control) with typed rethrow at the `LLMCaller` boundary, 3-consecutive-skip circuit breaker, informational `.turnSkipped` (live-only narration) + durable `degradedTurnCount` badge, `SimulationStatus` taxonomy unchanged; resume-proposal deferred to final PR (Status: Accepted; #992, PR1 baseline)

## ADR-022 — Phase/event extension contract

Phase/event extension contract — declare once in the two Models enums (no registry; preserves ADR-020 `allCases` gate + ADR-013 `EventLineMapper` canary), every Swift projection no-default exhaustive (tiered switches allowed iff the terminal tier is exhaustive; no raw-string switching), code-phase semantic core = `CodePhaseEventPayload.init?(event:)` + `defaultCodePhaseType` pair in Models, non-Swift consumers get forced-decision CI gates (demo-replay converter hard-errors on unknown events + emit-literal drift gate) or deletion (`engine.md` event listing), cross-VM fixture parity test encodes intentional live/replay asymmetry (Status: Accepted; design #993; implementation shipped as PR-A–PR-D after #992 landed)

## ADR-023 — KMP Engine migration architecture

KMP Engine migration architecture (Phase 3.0) — run-path Engine port to `commonMain` with callback-only K/N boundaries (event: `SharedEngineRunner` adapter; inference: `LLMBackend`/`StreamCallbacks`; no suspend/Flow crosses, `SuspendController` never crosses); Stage-2 two-boundary vertical slice = GO/NO-GO gate; Stage-4 cross-language parity harness (JVM per-PR + macosArm64 nightly, mechanism contract); D1 iOS switch A-with-gate (both-rung parity + H7 symbolication + TestFlight soak), D2 Data stays Swift/GRDB (SQLDelight revisit at Android scoping), D3 ~4–5 wk + 1 wk; serialization path + LLM backends stay Swift; ADR-021/-022 numbers held by #992 / PR #997 (Status: Accepted; #501)

## ADR-024 — Scenario semantic lint layer

Scenario semantic lint layer — `ScenarioSemanticLinter` (Engine) fires silent-no-op DSL traps at load time as findings (error blocks commit/run, warning never blocks; rule catalog R1–R17; linter-owned `PlaceholderAvailability` map absorbs #920's model; `pastura-harness lint` batch gate, shipped preset+gallery inventory zero-FP; warn-first promotion policy for post-v1 error rules) (Status: Accepted; #994)

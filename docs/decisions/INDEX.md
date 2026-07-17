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

Graceful degradation of LLM turn failures — per-turn containment in the six LLM handlers via a shared run-scoped `TurnFailureGate` (degrade by omission never fabrication; `lastOutputs` clear-on-skip), 3-class failure taxonomy (transient/systemic/control) with typed rethrow at the `LLMCaller` boundary, 3-consecutive-skip circuit breaker, informational `.turnSkipped` (live-only narration) + durable `degradedTurnCount` badge, `SimulationStatus` taxonomy unchanged; resume-proposal deferred to final PR. **§ Amendment 2026-07-17** (#1151) extends D2 from *failed call* to *delivered but unmappable*: `ChooseHandler.validateAction` stops falling back to `options[0]` (a live fabrication — an agent emitting `betray!` was scored as cooperating), instead normalizing (trim+lowercase, both sides) and returning the canonical option, or `nil` → drop the pairing; round-robin only (`executeIndividual` never calls it). The drop is post-`turnGate` so it emits no `.turnSkipped` and would leave `degradedTurnCount == 0` on a 100%-drop run — hence a new `.actionRejected` `SimulationEvent` case folded into the same D6 aggregate, D4 breaker explicitly untouched, `VoteHandler` deliberately not folded in (its raw ballot is already observable via `.voteResults`' `votes` dict). No schema bump — ADR-020 gates old-app-vs-new-content, this is the reverse direction and is un-gatable by construction (Status: Accepted; #992, PR1 baseline)

## ADR-022 — Phase/event extension contract

Phase/event extension contract — declare once in the two Models enums (no registry; preserves ADR-020 `allCases` gate + ADR-013 `EventLineMapper` canary), every Swift projection no-default exhaustive (tiered switches allowed iff the terminal tier is exhaustive; no raw-string switching), code-phase semantic core = `CodePhaseEventPayload.init?(event:)` + `defaultCodePhaseType` pair in Models, non-Swift consumers get forced-decision CI gates (demo-replay converter hard-errors on unknown events + emit-literal drift gate) or deletion (`engine.md` event listing), cross-VM fixture parity test encodes intentional live/replay asymmetry (Status: Accepted; design #993; implementation shipped as PR-A–PR-D after #992 landed)

## ADR-023 — KMP Engine migration architecture

KMP Engine migration architecture (Phase 3.0) — run-path Engine port to `commonMain` with callback-only K/N boundaries (event: `SharedEngineRunner` adapter; inference: `LLMBackend`/`StreamCallbacks`; no suspend/Flow crosses, `SuspendController` never crosses); Stage-2 two-boundary vertical slice = GO/NO-GO gate; Stage-4 cross-language parity harness (JVM per-PR + macosArm64 nightly, mechanism contract); D1 iOS switch A-with-gate (both-rung parity + H7 symbolication + TestFlight soak), D2 Data stays Swift/GRDB (SQLDelight revisit at Android scoping), D3 ~4–5 wk + 1 wk; serialization path + LLM backends stay Swift; ADR-021/-022 numbers held by #992 / PR #997 (Status: Accepted; #501)

## ADR-024 — Scenario semantic lint layer

Scenario semantic lint layer — `ScenarioSemanticLinter` (Engine) fires silent-no-op DSL traps at load time as findings (error blocks commit/run, warning never blocks; rule catalog R1–R20; linter-owned `PlaceholderAvailability` map absorbs #920's model; `pastura-harness lint` batch gate, shipped preset+gallery inventory zero-FP; warn-first promotion policy for post-v1 error rules) (Status: Accepted; #994)

## ADR-025 — Gallery scenario ordering

Gallery scenario ordering — replace the no-sort raw-JSON-array order (which sank newly-added scenarios to the bottom) with a client-side sort in `GalleryScenarioSearch.filter` (after category/language/query filtering): curator-pinned optional `featured` rank ascending (nil last) → `added_at` descending (raw String compare — date-only fixed-width `YYYY-MM-DD`, no `Date` parse) → `id` tie-break (total/deterministic); "New" (新着) badge for entries added <14 days, filling the Browse card's single badge slot only when install-state doesn't; popularity/DL-count ranking deferred indefinitely (needs a telemetry backend contradicting the offline/zero-cost/on-device-privacy positioning, and at ~44 items the signal ≈ list position via position bias — revisit trigger: catalog >150 via community submissions, opt-in only); random/shuffle rejected as list order (destroys spatial memory), serendipity belongs in a date-seeded / curator-driven Home surface (#89) (Status: Accepted; #1117)

## ADR-026 — LLM-dynamic Word Wolf topics (near-term no-go)

LLM-dynamic Word Wolf topic generation — near-term **No-Go**: keep the static `words:` pair; do not have the on-device model generate the majority/minority pair per playthrough. Harness-measured on Gemma 4 E2B (n≈100 × 5 categories × ja/en, 2026-07-16): a no-LLM-judge validator fails three ways — misses semantic part-of / script homographs (ja `カメ↔甲羅` 52%, `ネコ↔猫` 17%; caught 1 of ~70), false-positive-rejects good pairs (`Pen↔Pencil` via substring), and passes hallucinated non-words (`のび筆`); diversity collapses (every category dominated by 1-2 anchor pairs, ~3-5 usable distinct pairs each, so a curated ~30-pair static list wins on variety/cost/safety); and category quality is per-language (same "animals" catastrophic in ja, clean in en). General principle: LLM-generated game content must clear calibration AND diversity AND script-robustness, gated by harness measurement, else prefer static curation. Deferred (non-binding) design sketch retained for a stronger model: a non-diegetic `generate` LLM phase (structured pair → `state.variables`, not the conversation log; internal validator+retry+fallback) + `assign source_variable:`. Revisit on the LiteRT-LM migration / a successor model (ADR-002 §8.2; #496); tracked under #906 (Status: Accepted; #906)

## ADR-027 — Generic `pairwise_payoff` scoring logic

Generic `pairwise_payoff` scoring logic — move the two-player payoff matrix out of Swift (`PrisonersDilemmaLogic`'s `switch (act1, act2)` over English `cooperate`/`betray` literals) into scenario YAML (`payoff: [{when: [A, B], points: [x, y]}]`, positional match on `Pairing.action1/2`, no matching row → no points), on the `EventReactivePayoffLogic` (#931) YAML-authored-token precedent. Unblocks the last un-localized surface: `prisoners_dilemma.yaml` is `language: ja` with English options, because translating them makes every pair miss the switch and fall to `default:` → all agents scored as mutual defectors (a *latent* trap — under today's English options `default:` is reachable only as (betray,betray), where 1,1 is the correct game rule; PR2's legacy shim table must therefore keep all **four** rows). `ScoreCalcLogic.prisonersDilemma` is kept **permanently** and shrinks to a shim over the generic logic: Copy & Edit (`ScenarioDetailActionBar.swift:88-89`) clones preset YAML into `ScenarioRecord.yamlDefinition` (a text column) on TestFlight-shipped devices, and such local records never pass a gallery index, so only ADR-020's D5 parse-throw reaches them — deleting the case makes a user's own saved scenario unopenable, with no migration path. `?? "cooperate"` is removed as **dead code**, not as a bug fix (ADR-021 D2's pairing-drop guard at `ChooseHandler.swift:86` already closed it; the doc comments calling it fabrication are subjunctive rationale for that guard). Costs: an `EngineSchemaVersion` bump (expressed as "next unused integer at PR2 branch time", not pinned); ADR-022's forced switch sweep (3 sites); **2 compiler-silent `==` predicates** ADR-022's gate structurally cannot see (`ScenarioSemanticLinter+Ordering.swift:105` → R4 mis-fire; `SimulationResultCard+Model.swift:86` → result-card layout) — generalization: grep `== .<case>` when adding to any ADR-022-governed enum; both locale specs (the coverage gate fires on staging `ScoreCalcLogic.swift`, so they are engine-PR files); and new lint rules R19/R20 (ADR-024 § Amendment 2026-07-17). The `options[0]` fallback fix it depends on lives in ADR-021 § Amendment 2026-07-17, not here — it supersedes ADR-021/-002 text and belongs where a reader would look. KMP `shared/models` out of scope (frozen at `f73bc48` by design; `eventReactive` already unported; no parity gate). Side benefit: chicken / stag hunt and other variants become authorable in YAML alone (Status: Accepted; #1151)

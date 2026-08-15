# Decision Records — Index

Decision summaries for `docs/decisions/` — each entry routes into its ADR rather than restating it: mechanism, standing invariants, what is still open, and one derivation pointer per claim cluster. **Do not add a count that mirrors a mutable inventory elsewhere** — how many tokens are paired, entries excerptable, sites swept: such a mirror is invisible to a count-keyed sweep and goes stale silently, which is what happened to the ADR-028 entry repeatedly. The test for what counts as one, and the *relative*-claim variant that goes stale the same way carrying no number at all, are in the writing rule — `.claude/rules/adr-writing.md` §4, path-scoped here, so read it before adding an entry. Entries predating that rule may still carry mirrors and no list of them is kept (one would inherit the same blind spot), so confirm any number here against its ADR. `CLAUDE.md` § Reference Documents → ADR roster carries titles only and points here for the detail; its titles are kept byte-identical to this file's `## ADR-NNN — <title>` headings. `consistency-audit`'s `adr_roster_drift` is what diffs them — against each other and against the tracked `ADR-*.md` files — so the heading shape here is load-bearing, not cosmetic.

## ADR-001 — Architecture Overview (Phase 1)

Phase 1 architecture decisions (12 ADRs)

## ADR-002 — llama.cpp interim LLM backend

llama.cpp interim LLM backend decision.

Standing invariant — § "Pin Strategy": pin a specific release tag, and on a bump
pin the **measured** tag rather than the latest one. Drift alone is not a reason
to bump; a bump needs one of three named triggers (blocked capability, CVE,
llama.swift build break) and must clear that section's six-item verification
bar. No gate enforces any of it — the operator-side pairing is
`docs/security/release-checklist.md` §3.1.

Standing invariant — § Amendment 2026-08-15 (ADD-and-keep): a **same-model**
rebuild joins the catalog beside the build it replaces instead of superseding
it, naming its predecessor via `ModelDescriptor.replacesModelID`; the replaced
entry is hidden from the user-facing lists once it is neither on the device nor
the active model, but is never removed — what consumers depend on is its
**membership of `catalog`**, which the sharpest of them reach without going
through `lookup(id:)`. The supersede convention remains
the default for a genuinely different model. Gallery recommendations naming a
replaced build are satisfied app-side rather than by repointing the live feed,
via two separate questions — whether the active model is already acceptable
(state-free, either id of the pair) and which build to act on otherwise
(`recommendationTarget(for:state:)`, cheapest satisfying option, newer build on
a tie). Derivation,
the consumer list, and why the descriptor landed before its gate: that
amendment.

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

Graceful degradation of LLM turn failures — per-turn containment in the six LLM handlers via a shared run-scoped `TurnFailureGate` (degrade by omission never fabrication; `lastOutputs` clear-on-skip), 3-class failure taxonomy (transient/systemic/control) with typed rethrow at the `LLMCaller` boundary, 3-consecutive-skip circuit breaker, informational `.turnSkipped` (live-only narration) + durable `degradedTurnCount` badge, `SimulationStatus` taxonomy unchanged; resume-proposal deferred to final PR. **§ Amendment 2026-07-17** (#1151) extends D2 from *failed call* to *delivered but unmappable*: `ChooseHandler.validateAction` stops falling back to `options[0]` (a live fabrication — an agent emitting `betray!` was scored as cooperating), instead normalizing (trim+lowercase, both sides) and returning the canonical option, or `nil` → drop the pairing; round-robin only (`executeIndividual` never calls it). The drop is post-`turnGate` so it emits no `.turnSkipped` and would leave `degradedTurnCount == 0` on a 100%-drop run — hence a new `.actionRejected` `SimulationEvent` case folded into the same D6 aggregate, D4 breaker explicitly untouched, `VoteHandler` deliberately not folded in (its raw ballot is already observable via `.voteResults`' `votes` dict). No schema bump — ADR-020 gates old-app-vs-new-content, this is the reverse direction and is un-gatable by construction. **§ Amendment 2026-08-06** (#1290) reverses D7 for `empty_field` exhaustion, scoped to the **canonical primary** field: two clauses — the retry trigger keeps its all-fields scan (an empty `inner_thought` still burns budget), gaining only the declared-but-*absent* primary, without which clause 2's absent case would be unreachable (the call returns at attempt 0, so no final attempt exists to throw on); and only the exhaustion behaviour changed — throw `retriesExhausted` (→ `.turnSkipped`) iff the phase's *declared* schema carries `ScenarioConventions.primaryField(for:)` and that value is absent/empty/`"..."`. Both narrowings are load-bearing: an any-field rule would omit *delivered* content (good `statement`, empty thought), and a phase-type-only rule would fire on every turn of a pre-gate or ADR-020-imported scenario whose schema omits the canonical key (GBNF never generates an undeclared key) → 3 skips → `turnFailureLimitReached` → previously-working scenarios unrunnable. Reclassifies six phase types; `choose`'s *empty* action moves `.actionRejected` → `.turnSkipped` while *off-menu-but-delivered* stays `.actionRejected`; `narrate` excluded structurally (`primaryField` nil + the one un-gated call site). Accepted consequences: these turns now consume D4 circuit-breaker budget (systematic empty producers flip completed → `.failed`, mitigated by shipped D8 resume) and suppress the `ReviewRequestPolicy` prompt. `language_mismatch` deliberately diverges (delivered content — nothing fabricated); repair/salvage all-keys acceptance guard retained; `ReflectHandler`'s non-empty guard demoted precedent → defense-in-depth. No new event case (`.turnSkipped` already carries the semantics; `.actionRejected`'s precedent doesn't transfer since it exists *because* `.agentOutput` had rendered). Resolves the Swift/Kotlin `SCHEMA_GUARD_POSITION` divergence by deleting Kotlin's post-parse guard (no salvage/repair site exists to move it to), which disarms the parity negative control's structural arm — re-arm or record the gap is a condition of the change (Status: Accepted; #992, PR1 baseline)

## ADR-022 — Phase/event extension contract

Phase/event extension contract — declare once in the two Models enums (no registry; preserves ADR-020 `allCases` gate + ADR-013 `EventLineMapper` canary), every Swift projection no-default exhaustive (tiered switches allowed iff the terminal tier is exhaustive; no raw-string switching), code-phase semantic core = `CodePhaseEventPayload.init?(event:)` + `defaultCodePhaseType` pair in Models, non-Swift consumers get forced-decision CI gates (demo-replay converter hard-errors on unknown events + emit-literal drift gate) or deletion (`engine.md` event listing), cross-VM fixture parity test encodes intentional live/replay asymmetry (Status: Accepted; design #993; implementation shipped as PR-A–PR-D after #992 landed)

## ADR-023 — KMP Engine migration architecture

KMP Engine migration architecture (Phase 3.0) — run-path Engine port to `commonMain` with callback-only K/N boundaries (event: `SharedEngineRunner` adapter; inference: `LLMBackend`/`StreamCallbacks`; no suspend/Flow crosses, `SuspendController` never crosses); Stage-2 two-boundary vertical slice = GO/NO-GO gate; Stage-4 cross-language parity harness (JVM per-PR + macosArm64 nightly, mechanism contract); D1 iOS switch A-with-gate (both-rung parity + H7 symbolication + TestFlight soak), D2 Data stays Swift/GRDB (SQLDelight revisit at Android scoping), D3 ~4–5 wk + 1 wk (**superseded** — inherits a one-day-early sizing basis; see §12 condition 3 for what must be recorded before Stage 3 is scheduled); serialization path + LLM backends stay Swift. **§4 revised 2026-07-19** — an inventory of `Engine/**`+`LLM/**` found 3,449 lines in neither list (an undecided disposition, four mechanisms that post-dated the section, and 1,756 lines the port/stay pair could not express); §4 now carries four dispositions (`PORT`/`STAY`/`REPLACED`/`FOLDED`), two inheritance rules (sibling extensions, `LLMService` conformers) and a **deliberate absence of any catch-all** — a file no rule reaches is `UNDECIDED`, a failure state rather than a default, because a rule that always answers cannot raise an alarm and the four mechanisms that opened the gap were standalone `Engine/` types no inheritance rule could reach; coverage invariant left explicitly unenforced pending #1191. The ADR-024 linter folds into Load+validate (shared consumers; its `.error` findings gate the run inside the ported `preflightGate`); port surface is now 8,044 lines Engine+LLM — not to be confused with §12's Engine-only 8,088; ADR-021/-022 numbers held by #992 / PR #997. **§12 Amendment 2026-07-18 — Stage-2 gate verdict: GO**, with four conditions: (1) align `OutputSchema` at the head of Stage 3, Kotlin moving to Swift's shape — surface includes `from()`'s CHOOSE construction branch, the `LLMBackend.schema` passthrough (which follows the type with no edit — not a second DTO), and Swift's own ADR-021-stale rationale comment; shipped in #1193, where the Swift↔Kotlin tag form was ruled absorbed test-side (no production `KSerializer`, since nothing JSON-crosses `OutputSchema`); (2) every type mirrored into `shared/**` lands with golden-parity coverage in the same PR (the `OutputSchema` mirror was born diverged, not rotted — so the lesson is coverage-at-landing, not cadence; whether the JVM rung also moves earlier is left open); (3) replace §10's velocity-taper assumption with a pinned detector — trailing-10-day commit count over the **port surface** (a derivation from §4, not a frozen list; LLM/ wholesale would count STAY backend churn, while Engine-only missed the LLM port surface — 1 commit in the calibration window, the whole 16→17 unfiltered delta), ≤5 schedules / >5 means wait or dual-land; baseline re-measured to 17 unfiltered / 16 filtered, superseding the Engine-only 16/15 — the two 16s mean different things — with the reading and either the re-estimate or the dual-landing decision recorded on #501 before the first Stage-3 PR, priced against **both** 8,044 production lines and ~1,658 lines of test siblings owed Kotlin counterparts under condition 4; the §4 amendment lands first or the reading is stale on arrival. Stage-3 precondition surfaced by it: `VoteTally` needs Models `RankingOrder` in the freeze-by-design `shared/models`, and condition 2 governs how a mirror lands, not whether a frozen module accepts one; (4) "module done" = a `commonTest` sibling shown to go red under perturbation of the ported code, not merely one that exists. §6 Stage 3 carries the gate; an abandonment trigger (handler bodies needing Swift-side restructuring to stay expressible) lets the stage stop — whether "handler body" should widen to any ported module body is tracked in #1191, not settled here. Accepted on faith and routed to later stages: macOS↔iOS K/N equivalence, K/N GC under device memory pressure (the largest uncovered risk; D1 + H7 backstop it), the Swift-decodes-Kotlin direction, H5/H7 distribution (Status: Accepted; #501)

## ADR-024 — Scenario semantic lint layer

Scenario semantic lint layer — `ScenarioSemanticLinter` (Engine) fires silent-no-op DSL traps at load time as findings (error blocks commit/run, warning never blocks; rule catalog R1–R20; linter-owned `PlaceholderAvailability` map absorbs #920's model; `pastura-harness lint` batch gate, shipped preset+gallery inventory zero-FP; warn-first promotion policy for post-v1 error rules) (Status: Accepted; #994)

## ADR-025 — Gallery scenario ordering

Gallery scenario ordering — replace the no-sort raw-JSON-array order (which sank newly-added scenarios to the bottom) with a client-side sort in `GalleryScenarioSearch.filter` (after category/language/query filtering): curator-pinned optional `featured` rank ascending (nil last) → `added_at` descending (raw String compare — date-only fixed-width `YYYY-MM-DD`, no `Date` parse) → `id` tie-break (total/deterministic); "New" (新着) badge for entries added <14 days, filling the Browse card's single badge slot only when install-state doesn't; popularity/DL-count ranking deferred indefinitely (needs a telemetry backend contradicting the offline/zero-cost/on-device-privacy positioning, and at ~44 items the signal ≈ list position via position bias — revisit trigger: catalog >150 via community submissions, opt-in only); random/shuffle rejected as list order (destroys spatial memory), serendipity belongs in a date-seeded / curator-driven Home surface (#89) (Status: Accepted; #1117)

## ADR-026 — LLM-dynamic Word Wolf topics (near-term no-go)

LLM-dynamic Word Wolf topic generation — near-term **No-Go**: keep the static `words:` pair; do not have the on-device model generate the majority/minority pair per playthrough. Harness-measured on Gemma 4 E2B (n≈100 × 5 categories × ja/en, 2026-07-16): a no-LLM-judge validator fails three ways — misses semantic part-of / script homographs (ja `カメ↔甲羅` 52%, `ネコ↔猫` 17%; caught 1 of ~70), false-positive-rejects good pairs (`Pen↔Pencil` via substring), and passes hallucinated non-words (`のび筆`); diversity collapses (every category dominated by 1-2 anchor pairs, ~3-5 usable distinct pairs each, so a curated ~30-pair static list wins on variety/cost/safety); and category quality is per-language (same "animals" catastrophic in ja, clean in en). General principle: LLM-generated game content must clear calibration AND diversity AND script-robustness, gated by harness measurement, else prefer static curation. Deferred (non-binding) design sketch retained for a stronger model: a non-diegetic `generate` LLM phase (structured pair → `state.variables`, not the conversation log; internal validator+retry+fallback) + `assign source_variable:`. Revisit on the LiteRT-LM migration / a successor model (ADR-002 §8.2; #496); tracked under #906 (Status: Accepted; #906)

## ADR-027 — Generic `pairwise_payoff` scoring logic

Generic `pairwise_payoff` scoring logic — move the two-player payoff matrix out of Swift (`PrisonersDilemmaLogic`'s `switch (act1, act2)` over English `cooperate`/`betray` literals) into scenario YAML (`payoff: [{when: [A, B], points: [x, y]}]`, positional match on `Pairing.action1/2`, no matching row → no points), on the `EventReactivePayoffLogic` (#931) YAML-authored-token precedent. Unblocks the last un-localized surface: `prisoners_dilemma.yaml` is `language: ja` with English options, because translating them makes every pair miss the switch and fall to `default:` → all agents scored as mutual defectors (a *latent* trap — under today's English options `default:` is reachable only as (betray,betray), where 1,1 is the correct game rule; PR2's legacy shim table must therefore keep all **four** rows). `ScoreCalcLogic.prisonersDilemma` is kept **permanently** and shrinks to a shim over the generic logic: Copy & Edit (`ScenarioDetailActionBar.swift:88-89`) clones preset YAML into `ScenarioRecord.yamlDefinition` (a text column) on TestFlight-shipped devices, and such local records never pass a gallery index, so only ADR-020's D5 parse-throw reaches them — deleting the case makes a user's own saved scenario unopenable, with no migration path. `?? "cooperate"` is removed as **dead code**, not as a bug fix (ADR-021 D2's pairing-drop guard at `ChooseHandler.swift:86` already closed it; the doc comments calling it fabrication are subjunctive rationale for that guard). Costs: an `EngineSchemaVersion` bump (expressed as "next unused integer at PR2 branch time", not pinned); ADR-022's forced switch sweep (3 sites); **2 compiler-silent `==` predicates** ADR-022's gate structurally cannot see (`ScenarioSemanticLinter+Ordering.swift:105` → R4 mis-fire; `SimulationResultCard+Model.swift:86` → result-card layout) — generalization: grep `== .<case>` when adding to any ADR-022-governed enum; both locale specs (the coverage gate fires on staging `ScoreCalcLogic.swift`, so they are engine-PR files); and new lint rules R19/R20 (ADR-024 § Amendment 2026-07-17). The `options[0]` fallback fix it depends on lives in ADR-021 § Amendment 2026-07-17, not here — it supersedes ADR-021/-002 text and belongs where a reader would look. KMP `shared/models` out of ADR-027's own scope (its `eventReactive` / `pairwise_payoff` enum mirror landed later in ADR-023 PR0-a2, #1196, with golden parity). Side benefit: chicken / stag hunt and other variants become authorable in YAML alone (Status: Accepted; #1151)

## ADR-028 — Dark-mode token pairing (trait-resolving `PasturaDynamicColor`)

Dark-mode token pairing — `PasturaDynamicColor` wraps a light/dark
`PasturaColorValue` pair in a `UIColor(dynamicProvider:)` closure branching on
`traitCollection.userInterfaceStyle`, and the paired `Color.*` aliases point at
it, so existing consumers adapt with **no callsite edit**. The **light** alias is
the dynamic side; `night*` stays static so an explicit dark request stays
expressible. `UIUserInterfaceStyle = Light` is removed (#1284) — the app follows
the device appearance. Pair values live in `DesignTokens+NightPalette.swift` and
design-system §2.9, not in the ADR; most of the file is amendments, so **enter at
§ "How to read this ADR"**, which routes by question rather than by date, and add
new content by the placement rule it states. **Standing invariants** —
§ Consequences → "Standing invariants the pairing created" states both with their
derivations: an occlusion layer, shadow or scrim, must be **darker than every
ground it covers** rather than merely fixed in both appearances; and a
fixed-appearance export must **inject** the appearance it wants
(`.environment(\.colorScheme, …)` plus an explicit parameter), gated in
pre-commit + CI by `scripts/check_imagerenderer_injection.py`, and read raw
`PasturaPalette` rather than `Color.*` aliases — unconditionally, not
belt-and-braces. Today's such palettes are pinned by reflection-based tests since
ADR-009 rules out snapshots, but nothing detects a *new* consumer's missing pin.
Operational forms of both: `swiftui-traps.md`. Asset-catalog colour
sets are rejected for blinding `check_design_tokens_css.py`'s hex→`tokens.css`
mirror and `DesignTokensTests`' sRGB assertions. Further rules bind anyone
adding a token: a dark value derives by **several independent arms** — measured
deltas, role inversion, target-contrast placement, family dimming — not one
formula, so pick the arm per family and inherit that arm's limits from its
derivation (§ Amendment 2026-07-29, § Amendment 2026-07-30); and a **token-pair
ratio is not a prediction about a presented surface**, because a sheet dims only
what sits behind it, so the comparand is the composite and the designed step can
arrive with its sign flipped (§ Amendment 2026-08-05, #1336). **What the gate
ladder structurally could not see**, kept because the shape recurs: a screen that
sets *no* background falls through to the system colour, and a raw-colour sweep
has no syntax to grep for an **absent** modifier — enumerate from the predicate
("a rendered state shows the system colour"), never from the previous fix list
(#1354). Gate predicates under-reach the same silent way: a `Views/` + `App/`
glob misses top-level `PasturaApp.swift` (use `Pastura/Pastura`), and
`Assets.xcassets` sat outside every one of them. Manual walkthrough:
`docs/qa/dark-mode-qa.md`.
**Isolation** — three deliberate constraints, each observed rather than
predicted and derived in § Consequences: the type-level `nonisolated` on the pair
type is a **runtime** guard that still builds without it, stopping the provider
closure being inferred `@MainActor` while UIKit may invoke it off-main
(`swift-isolation.md` Pattern 8), while `PasturaDynamicColor` is deliberately not
`Equatable` (Pattern 5) and `PasturaDynamicPalette` deliberately not
`nonisolated`. Still open, each where it is derived: the `ImageRenderer` alias
half stays armed at § Revisit trigger's stated thresholds; several fixes
post-date the device pass that closed gates 4 and 5 and so head
`docs/qa/dark-mode-qa.md`'s re-run list, one of them partially re-checked with
its gaps stated (§ Amendment 2026-07-31 → "What is NOT confirmed"). The `inkSecondary`
dark-side gap is **closed** by a paired role token (§ Amendment 2026-08-13
(#1408)). **A token's contrast exemption is scoped to the grounds it was measured
on** — design-system §8 exempts `muted` from the 4.5:1 bar on the strength of one
ground, so a label ambient there can be far below the bar on a tinted fill; the
family that owns the ground supplies the replacement, never a §2.4 preset rung
(§ Amendment 2026-08-13 (#1427), whose app-wide sweep is #1448). That scoping
extends to **composited** grounds — a translucent wash is a ground §8 never
measured either (§ Amendment 2026-08-15 (#1448), which also retires "unique on
this screen" as the must-read test and adds the per-file census that fires on
additions)
(Status: Accepted; #1274)

## ADR-029 — Shared-scenario highlights (static curated excerpts)

Shared-scenario highlights — curated static excerpts for the `/s/<id>` landing
pages and `GalleryScenarioDetailView`, one `docs/gallery/highlights/<id>.json`
sibling per gallery entry carrying a capped `excerpt` list, a `scenario_ref` and
a `content_filter_applied` attestation. Standing rules the schema and the gate
encode, each derived in the Decision it names: **spoiler eligibility is keyed to
event visibility, not phase position** (Decision 3) — only a persona's public
in-fiction utterance (`speak_all`/`speak_each`, `statement` field) is eligible,
while outcome disclosures, private in-fiction content, out-of-fiction `narrate`
and setup/control phases are ineligible everywhere; position adds a within-round
and a cross-round window on top, never instead. `yaml_sha256` is **raw-byte /
shasum-equivalent**, deliberately NOT
`jsonl_to_demo_replay.py`'s text-mode convention, whose consumer is the
demo-replay drift check. `gallery.json` stays the **single trust root**
(Decision 4): the paired `highlight_url` + `highlight_sha256` are both-or-neither,
the app fetch is unconditional / size-limited / hash-verified / uncached, and any
verification failure — unknown `schema_version` or a missing attestation included
— hides the section with an `.info` log, which is ADR-021's degrade-by-omission
stance. The web build reads the repo file directly and never resolves
`highlight_url`. **The enforcement point is the gallery gate, not the
extractor**: `check-gallery-entry.sh` re-derives the schema, the caps, the
spoiler rules, the blocklist re-audit and the sha three-way that makes the trust
root load-bearing (highlight pin == `gallery.json` == raw YAML bytes) — its own
header carries the authoritative list — while
`scripts/gallery_highlight_extract.py` keeps the same checks only as fail-fast
convenience, hard-failing on `secret:`-declaring scenarios and unknown phase
names (ADR-022 tripwire). Decision 6 states the Phase-3 boundary falsifiably —
static text, no replay-source construction, one verified fetch, a capped authored
enumeration, no community function — of which only the cap is mechanically
enforced; the rest are review-time obligations. Rollout is ja-first because
curation is the bottleneck and needs native-quality reading, and en is a
separately-generated batch: ja quality does not transfer at either the prompt or
the sampler layer. **§ Amendment 2026-08-07** adds the app-side hide trigger
`excerpt_phase_unrenderable` for an `excerpt[].phase` this build cannot render —
a **version-skew** guard rather than a verification failure, and a
**renderability** guard rather than a spoiler one, leaving eligibility enforced
once at the gate. It hides the whole section rather than the offending line,
because an excerpt is a quotation and dropping a line rewrites the passage while
still presenting it as the record. **§ Amendment 2026-08-08** adds
`yaml_hook.kind` and `excerpt[].persona_index` as required keys while leaving
`schema_version` at 1, licensed by a precondition that must be **re-checked per
use**: *no shipped build holds a v1 decoder* — a fact about the world, not a
version-number rule. `kind` lets the app render a persona fragment in its
scenario-editor vocabulary while the web keeps showing YAML (a deliberate
Decision-5 divergence — the web has no editor in which a setup's meaning could
show); `persona_index` retires the first-appearance stand-in for avatar colour
slots, and the gate cross-checks it against the sibling YAML. The same amendment
constrains **`source.model`** to
`ModelRegistry.catalog ∪ RETIRED_MODEL_IDS` — the app catalog, not the harness's
`ModelProfile.all`, which carries eval candidates nobody can install — since the
string publishes verbatim inside 「実際に端末で動かした結果」. Still open, per
§ Revisit trigger: the narrate and secret branches stay designed-untested until
an entry needs them; the en batch; the schema-bump precondition above; and a
model removed from `ModelRegistry.catalog` must have its id moved into
`RETIRED_MODEL_IDS` in the **same PR**, or the gate retroactively fails shipped
highlights that named it (Status: Accepted; #1381)

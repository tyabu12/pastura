# code-health-audit — finding ledger

The cross-run dedup memory. Every finding that survives a run's Vet is appended
here. Before surfacing a finding, a run reads this ledger and **must not
re-surface** any finding already recorded **regardless of status** — including
ones already `filed` as issues (e.g. #1056/#1057) or `rejected`. This is the
linchpin mechanism in [README](README.md); without it, a periodic sweep re-floods
the human with the same findings — and re-files what is already an open issue.

**Dedup is by concept, not `file:line`.** Code drifts, so a finding's line offset
moves between runs; a line-exact match would let an already-tracked finding
resurface at a new location. Match on the `concept` fingerprint below.

**Lifecycle:** the skill *appends* rows but never commits or pushes. A human
commits the append, bundled with promoting a digest finding to an issue (see
[README](README.md) § Promotion / § Ledger lifecycle).

## Format

One row per finding, append-only. Columns:

| Column | Meaning |
|--------|---------|
| `id` | `CH-NNN`, monotonically increasing (next id = highest existing + 1, zero-padded to 3). |
| `date` | `YYYY-MM-DD` of the run that surfaced it. |
| `category` | `test-coverage` · `correctness` · `concurrency` · … (the finder category). |
| `concept` | **Stable fingerprint for dedup** — a short, location-independent description of the *defect idea* (e.g. `vote-tie-break diverges eliminate vs vote_winner`), NOT a `file:line`. This is the dedup key; it must survive code drift. |
| `anchor` | The `file:line` lead at surface time — for human navigation only, **never** the dedup key (it drifts). |
| `status` | `proposed` (in a digest, awaiting triage) · `filed (#N)` · `rejected` · `done`. |
| `note` | Rationale for `proposed`, the rejection reason, or the resolving PR. Empty for `filed`. |

## Ledger

| id | date | category | concept | anchor | status | note |
|----|------|----------|---------|--------|--------|------|
<!-- Appended by code-health-audit runs. Seeded empty — the two pilot bugs are
     already tracked as GitHub issues #1056/#1057, so they are recorded here as
     `filed` to prevent the first real run from re-surfacing them. -->
| CH-001 | 2026-07-12 | correctness | vote-tie-break diverges: EliminateHandler (name asc) vs vote_winner (name desc) | Engine/Phases/EliminateHandler.swift:18 | filed (#1056) | pilot find |
| CH-002 | 2026-07-12 | correctness | WordwolfJudgeLogic vote-tie winner non-deterministic (no secondary sort key) | Engine/ScoringLogic/WordwolfJudgeLogic.swift:25 | filed (#1057) | pilot find |
| CH-003 | 2026-07-12 | correctness | speak_each subRounds=0/negative traps `1...subRounds` (uncatchable fatal) — no validator guard nor handler clamp, unlike WhisperHandler max(1,…) | Engine/Phases/SpeakEachHandler.swift:28 | filed (#1064) |  |
| CH-004 | 2026-07-12 | test-coverage | ScoreCalcHandler.execute logic-dispatch switch exercised for only 1/4 arms (only .eventReactive) + missing-logic throw untested | Engine/Phases/ScoreCalcHandler.swift:18 | proposed | MED; per-Logic structs tested directly, bypassing dispatch wiring; typo would mis-route silently |
| CH-005 | 2026-07-12 | test-coverage | exclude_self:false (self-voting) branch untested in both VoteHandler tally-filter and PromptBuilder candidate list | Engine/Phases/VoteHandler.swift:136 | proposed | MED; zero `excludeSelf: false` tests; supported YAML field, no preset uses it |
| CH-006 | 2026-07-12 | test-coverage | ScenarioLoader structural-shape guards untested: actionDeltasNotDict + branchNotArray (siblings tested) | Engine/ScenarioLoader.swift:384 | proposed | LOW; error-message-quality only; invalidTarget(:274) dropped — actually tested (+StrictTypes:146) |
| CH-007 | 2026-07-12 | test-coverage | JSONResponseParser closeUnclosedLastString refuses array-element truncation (only `:`-preceded value position repaired) | LLM/JSONResponseParser.swift:231 | rejected | demoted post-Vet: array-value output documented not-reachable (JSONResponseParser:239-242); filing would be coverage-theater until arrays reachable |
| CH-008 | 2026-07-12 | test-coverage | ChooseHandler.validateAction options.isEmpty passthrough untested | Engine/Phases/ChooseHandler.swift:208 | proposed | LOW; reachable (validator no-ops .choose) but degenerate config |
| CH-009 | 2026-07-12 | test-coverage | ScenarioLoader invalidTarget branch claimed untested | Engine/ScenarioLoader.swift:274 | rejected | mis-attributed: covered by ScenarioLoaderTests+StrictTypes.swift:146 (randomOne typo) + msg assert :490-491 |
| CH-010 | 2026-07-12 | concurrency | runGeneration/runStreamGeneration not @concurrent — safe only via off-main SimulationRunner Task; live Pattern-6 freeze if a View/VM ever calls llm.generate directly | LLM/LlamaCppService.swift:477 | rejected | watch-item, not a defect today (no MainActor caller path); recorded so concurrency category isn't re-swept blind |
| CH-011 | 2026-07-13 | correctness | R9 summarize-pairing-placeholders lint misses pairings-clearing prisoners_dilemma score_calc between round-robin choose and summarize (sibling R4 actionSignalUnreachable has the clearer check, R9 doesn't) → {agent1} summarize leaks with no warning | Engine/ScenarioSemanticLinter+Config.swift:98 | proposed | HIGH; canonical choose→score_calc(pd)→summarize order passes lint clean but per-pairing branch can't fire; S fix reuses R4 predicate |
| CH-012 | 2026-07-13 | test-coverage | ScenarioLoader convertToAnyCodableValue .dictionary success + extraDataDictNotString throw untested through load(yaml:) (every other branch has a loader-level test) | Engine/ScenarioLoader.swift:484 | proposed | HIGH; #130 bug class; .dictionary only built directly in serializer/validator tests, never YAML-round-tripped |
| CH-013 | 2026-07-13 | test-coverage | ConditionalHandler missing-handler runtime backstop throw (disallowed sub-phase type in a branch) untested — only the validator's load-time rejection is covered, not the handler's own depth-1 backstop | Engine/Phases/ConditionalHandler.swift:95 | proposed | HIGH; guards subHandlers/validateBranch drift for programmatically-built scenarios; S fix |
| CH-014 | 2026-07-13 | correctness | SummarizeHandler per-pairing branch unreachable in canonical choose→score_calc(pd)→summarize order (pairings cleared); doc-comment omits the summarize-before-score_calc precondition → {agent1} placeholders leak literally | Engine/Phases/SummarizeHandler.swift:25 | proposed | MED; branch IS reachable in valid summarize-before-score order so "dead" is too strong; latent (no shipped preset uses {agent1} summarize); coupled to CH-011 |
| CH-015 | 2026-07-13 | test-coverage | RelationshipUpdateHandler.applyActions early return (pairings present, action_deltas nil) returns signal-seen without mutating matrix, suppressing the no-signal .debug diagnostic — untested | Engine/Phases/RelationshipUpdateHandler.swift:96 | proposed | MED; may be intentional (vote-only updates while choose runs); test gap for sawActions=true/no-mutation stands |
| CH-016 | 2026-07-13 | test-coverage | AssignHandler.assignAll .string source branch untested for target:.all (doc lists .string as supported; only .array exercised) | Engine/Phases/AssignHandler.swift:83 | proposed | MED; refactor collapsing .string into default:"" would blank every assigned_<name> silently; no shipped preset uses scalar assign source |
| CH-017 | 2026-07-13 | test-coverage | ConditionalHandler sub-handler-throw catch/rethrow lifecycle pairing (.phaseCompleted emitted before rethrow) untested — existing throw test fires from evaluator, upstream of the catch | Engine/Phases/ConditionalHandler.swift:121 | proposed | MED; documented invariant, unbalanced phaseStarted/Completed if regressed; S fix via score_calc logic:nil in a branch |
| CH-018 | 2026-07-13 | test-coverage | ConditionalHandler Task.isCancelled early-return in runBranch untested (no mid-branch cancellation test) | Engine/Phases/ConditionalHandler.swift:81 | proposed | MED; lowest leverage; may be covered indirectly by SimulationRunnerTests cancellation; M effort |

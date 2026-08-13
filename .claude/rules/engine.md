---
paths:
  - "Pastura/Pastura/Engine/**"
  - "Pastura/Pastura/LLM/**"
---

# Engine Design Rules

## Scenario Engine Design

### YAML Decoding

Use `Yams.load(yaml:)` → `[String: Any]` with manual mapping to `Scenario` model.
Do NOT use `YAMLDecoder` + `Codable` for scenario definitions — the dynamic nature
of `phases` (each type has different fields) and `output` (user-defined field names)
makes Codable fragile against YAML format variations.

Strip code fences (```yaml ... ```) before parsing — LLM-generated YAML often
includes them.

### Phase Types

| Type         | Processing | Description                          |
|--------------|------------|--------------------------------------|
| speak_all    | LLM        | All agents speak simultaneously      |
| speak_each   | LLM        | Agents speak in turn (accumulating)  |
| vote         | LLM        | All agents vote for one agent        |
| choose       | LLM        | Choose from options                  |
| reflect      | LLM        | Each agent privately updates a short memo (`note`) |
| whisper      | LLM        | Pairs privately whisper — viewer-visible, hidden from other agents (#908) |
| score_calc   | Code       | Calculate scores                     |
| assign       | Code       | Distribute info to agents            |
| eliminate    | Code       | Remove most-voted agent              |
| summarize    | Code       | Format round summary                 |
| conditional  | Control    | Branch on state DSL; nests sub-phases |
| event_inject | Code       | Inject random extraData string into state.variables (#256) |
| relationship_update | Code | Deterministic affinity matrix → `{relationships}` prompt injection, zero inference (#910) |
| narrate      | LLM        | Commentator persona narrates the round highlight, one inference per round regardless of agent count; engine-fixed `{commentary}` output (#909) |

`event_inject` is allowed inside `conditional` branches (consistent with
assign / score_calc nesting) — `ConditionalHandler.subHandlers` includes
it, and `ScenarioValidator.validateBranch` runs the same shape-check it
applies at the top level.

`reflect` is an LLM phase: each non-eliminated agent makes one call
producing `{ note }` — a private memo stored under the reserved
`notes_<name>` key in `state.variables` and surfaced back to only that
agent (system-prompt section + `{my_notes}` template variable). Notes
never enter the conversation log or `lastOutputs`; the canonical `note`
output is itself the private reasoning, so reflect declares no secondary
thought field. `reflect` is NOT allowed inside `conditional` branches —
`ScenarioValidator.validateBranch` rejects it at load time and
`ConditionalHandler.subHandlers` omits it.

`whisper` is an LLM phase: active agents pair off (adjacent disjoint
pairs in persona order, rotated by round; an odd agent sits out) and each
pair runs `sub_rounds` back-and-forth exchanges producing `{ statement }`
(canonical, required at the run gate) with optional `inner_thought`.
Every utterance is emitted as a normal `.agentOutput` carrying a reserved
`whisper_to` field naming the partner — viewer-visible, but never written
to the conversation log or `lastOutputs`, so other agents' prompts can't
see it. Each participant's view of the exchange is stored under the
reserved `whispers_<name>` key (overwrite — latest exchange only; a
sat-out agent's stale key is cleared) and surfaced back to only that
agent (system-prompt section + `{my_whispers}` template variable).
`{whisper_partner}` / `{whisper_exchange}` are resolvable inside the
whisper phase's own prompt template; the handler also always appends a
partner-naming context block, so placeholder-free templates still work.
Like `reflect`, `whisper` is NOT allowed inside `conditional` branches
(same two enforcement points).

`relationship_update` is a zero-inference **code** phase (#910): it
deterministically maintains a per-agent affinity matrix and injects a
natural-language summary. Update rules are generic YAML config (no
per-scenario Swift) — `vote_against: Int` (delta on a target's view of
whoever voted for them, read from `state.lastOutputs[voter].vote`) and
`action_deltas: [String: Int]` (delta on each partner's view of the other's
`choose` action, read from `Pairing.action1/action2`). The raw matrix
accumulates across rounds in the reserved `relationships_raw_<name>`
`state.variables` key (JSON); `RelationshipVerbalizer` renders each row as
prose (|score| ≥ 2 threshold, ja/en) into `relationships_<name>`, surfaced
to only that agent (system-prompt section + `{relationships}` template
variable). Emits `.relationshipUpdate(relationships:)` carrying the raw
matrix (Phase-3 visualization source; App/UI does not consume it in v1).
`ScenarioValidator` requires ≥1 rule (`validateRelationshipUpdateShape`).
**Ordering constraints** (enforced at load time as lint warning R4
`relationship-update-placement`, ADR-024 — the runtime violation is still a
*silent no-op*): place this phase after the vote/choose phase that produces
its signals and **before `score_calc`** (`PrisonersDilemmaLogic` clears
`state.pairings` after scoring); a `lastOutputs`-writing LLM phase
(speak/vote/choose) between a vote and this phase loses the vote signal,
while `reflect`/`whisper` are safe to interleave. The handler logs a
`.debug` diagnostic when no vote/pairing signal is present. Like
`reflect`/`whisper`, it is NOT allowed inside `conditional` branches
(validator rejection + `ConditionalHandler.subHandlers` omission).

### `mood` output field — emotional inertia (opt-in, #913)

`mood` is NOT a phase type — it is an **opt-in output field**: a scenario
declares `mood: string` in any LLM phase's `output:` schema. The engine
convention is "if a turn's `mood` is non-empty, carry it into the same
agent's next prompt":

- **Capture**: `PromptBuilder.captureMood` writes the non-empty value to the
  reserved `mood_<name>` `state.variables` key (last-write-wins; non-empty
  guard so a failed inference doesn't erase the prior mood — mirrors
  `ReflectHandler`'s note save). Called from all six LLM handlers, including
  `choose` individual; a no-op where the schema doesn't declare `mood`.
- **Inject** (two paths, both self-only — an agent never sees another's mood):
  `injectMood` surfaces `{my_mood}` (miss → `""`), and `appendPrivateSections`
  emits a "Your Current Mood" section **placed last** (recency) and shown in
  **every** phase so the inertia survives intervening vote/choose. Inject/capture
  live in `PromptBuilder+Injection.swift`.
- **`moodRule`** (short-word + natural-change guidance) is appended by
  `buildAnswerRules` **only for phases that declare `mood`** — the primary lever
  against echo-fixation and unmotivated slashing.
- **Grammar stays structure-only**: `mood` is a plain `.string` field. Do NOT
  enumerate mood values into the grammar (the CJK sampler-crash trap — see
  § "Grammar must not enumerate values"). A UI-side loose keyword mapping is the
  intended path if mood ever drives avatar expressions (a separate, post-Go issue).
- `mood_<name>` is a doc-only reserved namespace (like `notes_`/`whispers_`);
  `{my_mood}` is registered in `PlaceholderAvailability` (over-approximated to all
  six LLM phases as producers). No bundled preset opts in yet — adoption + any UI
  surfacing are gated on the #913 Go/No-Go.

### Adding a new `PhaseType`

A new `PhaseType` case ripples to many sites in two classes: the Swift
compiler force-catches one (ADR-022's no-default-exhaustive contract — see
§ "SimulationEvent & the projection contract"), while the other only fails a
specific CI job or unit test, not the compiler. Touch **both** classes.

**Compiler-caught** — no-default exhaustive `switch` over `PhaseType`; omit one
and the build fails:

- `Models/PhaseType.swift` — the case + `requiresLLM`.
- `Models/ScenarioConventions.swift` — `primaryField` + `thoughtField`.
- `Engine/ScenarioLoader.swift` — `estimatePhase` (inference count).
- `Engine/ScenarioValidator.swift` — `validatePhases` arm (+ a
  `validateRelationshipUpdateShape`-style shape check if the phase needs one).
- `Views/Components/PhaseGlyph.swift`, `PhaseDisplayName.swift`;
  `Views/Editor/PhaseBlockRow.swift`, `PhaseEditorSheet.swift` (×2 switches) +
  `PhaseEditorSheet+CanonicalFieldHint.swift`.
- `Views/Community/SharedScenarios/GalleryCatalogRow.swift` —
  `ScenarioSignaturePhase.init?(phaseRawValue:)` (signature-glyph decision;
  parse-then-exhaustive since ADR-022 PR-B).
- `App/ScenarioGenerationPrompt.swift` — the `phaseDescription` no-default
  switch that generates the "Copy Gen Prompt" phase list (#1120). Canonical
  fields come from `ScenarioConventions`, so only the one-line description is new.
- Test switches: `PasturaTests/Engine/PhaseDispatcherTests.swift`,
  `PasturaTests/Views/PhaseTypeLabelTests.swift`, and the
  `PhaseType.allCases.count` pin in `PasturaTests/Models/PhaseTypeTests.swift`.

**NOT compiler-caught** — green iOS build (+ unit-suite compile + pre-commit),
red on a specific CI job or unit test, or (the conditional-branch policy) only
at run time. After ADR-022 (PR-A–PR-D) the CI-gate classes are census +
round-trip fixture; the conditional-branch policy below is a manual decision
neither compiler nor CI catches:

- **Census** — **`.claude/skills/scenario-factory/scripts/gallery_census.py`**:
  add the phase to `AXES` + `AXIS_PHASES` (a distinctive mechanic) OR
  `SCAFFOLDING_PHASES` (structural), else the Ubuntu **"Shell gate tests"** CI
  job fails (`census: unexpected drift`). Also update both connected fixtures
  under `.claude/skills/scenario-factory/tests/fixtures/`:
  `gallery_census_balanced.json` (keep the new axis at 2/4 so the
  fallback-rarest-3 test still fires) and `phase_types_current.swift` (mirror
  the new case count).
- **Round-trip fixture** — YAML config fields flow through
  `App/EditablePhase.swift` (`init(from:)` + `toPhase()`) and
  `Engine/ScenarioSerializer.swift`, neither a `switch`. A dropped field is now
  **test-caught** by the `PhaseType.allCases`-driven round-trip
  (`PasturaTests/App/EditablePhaseRoundTripTests.swift`, ADR-022 P11): a phase
  kind whose fixture is missing fails the test, so the fixture set cannot
  silently lag.
- **Conditional-branch policy** — `Engine/ScenarioValidator.swift`
  `validateBranch` (an `if type == …` chain) + `Engine/ConditionalHandler.swift`
  `subHandlers` (a dict). **Neither is `PhaseType`-exhaustive**, so a new phase
  is not compiler-caught: decide *allow* (register in `subHandlers`) or *reject*
  (add a `validateBranch` throw + a `ScenarioValidationMessage` case). Skip both
  and a branch-nested use passes every load gate then throws mid-run at dispatch
  (deferred failure). reflect / whisper / relationship_update / narrate all
  **reject** (#909); add a `ConditionalValidatorTests+<Phase>` test either way.
  ⚠️ **Mirror the same verdict into two Kotlin maps** — `PhaseDispatcher`'s
  `defaultHandlers()` and `ConditionalHandler.subHandlers` (`shared/engine`,
  ADR-023) — where it is likewise not compiler-caught, and where no validator
  exists to double-enforce it. Details: `.claude/rules/kmp-interop.md` Pattern 4.
- **Empty-primary skip reachability** (ADR-021 § Amendment 2026-08-06) — a new **LLM** phase
  must either route its `LLMCaller.call` through `turnGate.attempt`, or return `nil` from
  `ScenarioConventions.primaryField(for:)`. Otherwise the skip rule's `retriesExhausted` reaches
  a call site the gate does not own: it aborts the run if that site does not catch, and is
  silently swallowed if it does (today only `NarrateHandler`, which takes the `nil` exit). No
  compiler or CI check covers this — `primaryField` is exhaustive, but nothing ties a `nil`
  verdict to gate wiring.
- **Web format-spec coverage** — the public reference at
  `web/src/content/scenario-format.{en,ja}.md` must list the new phase as a
  backtick token, or `scripts/check-scenario-format-coverage.py` fails the
  **"Scenario Format Coverage"** CI job and the local pre-commit sub-gate
  (#1120). The same gate covers new `ScoreCalcLogic` cases. Add the phase to
  both locale specs; the in-app prompt itself is compiler-caught (above).

A new `SimulationEvent` the phase emits is a **separate**, compiler-caught cost
axis — not a `PhaseType` touch point; see § "SimulationEvent & the projection
contract".

Motivating incident: PR #959 (`relationship_update`, #910) — every iOS build /
unit / lint gate green, "Shell gate tests" red on the missing census axis.

### PhaseHandler Protocol

```swift
nonisolated public struct PhaseContext: Sendable {
    public let scenario: Scenario
    public let phase: Phase
    public let llm: LLMService
    public let suspendController: SuspendController
    public let emitter: @Sendable (SimulationEvent) -> Void
    public let pauseCheck: @Sendable (_ phasePath: [Int]) async -> Bool
    public let phasePath: [Int]
}

nonisolated public protocol PhaseHandler: Sendable {
    func execute(context: PhaseContext, state: inout SimulationState) async throws
}
```

`PhaseContext` bundles the read-only parameters; `state` remains `inout` as
the only mutable argument. Handlers are registered in PhaseDispatcher as a
[PhaseType: PhaseHandler] dictionary.

`phasePath` identifies the handler's position in the scenario. Top-level
handlers get `[K]`; handlers that dispatch sub-phases (conditional today)
append the sub-phase index so inner lifecycle
events can be attributed to their enclosing branch. `pauseCheck` is a narrow
bridge onto `SimulationRunner.checkPaused`; handlers running sub-phases
must call it between each one so the user's pause request is honored at
sub-phase granularity, and `.simulationPaused` remains single-emitter
(the runner, never a handler).

Since `SimulationViewModel.currentPhaseType` is set from `.phaseStarted`
events, a nested `.phaseStarted` temporarily shadows `currentPhaseType`
with the inner phase type. Consumers that need exact phase attribution for
a given event must read the event's own `phaseType`, not `currentPhaseType`.

### SimulationRunner Output

`SimulationRunner.run()` returns `AsyncStream<SimulationEvent>`.
Pause is implemented via an `isPaused` flag backed by `CheckedContinuation` —
the runner suspends with zero CPU during pause and resumes when the setter
clears the flag. Emits `simulationPaused` exactly once per pause cycle.
Cancellation uses standard Swift `Task` cancellation.

### Validation Limits

| Parameter        | Limit   | Behavior           |
|------------------|---------|---------------------|
| agents           | ≥ 2     | Error if below      |
| agents           | ≤ 10    | Error if exceeded   |
| rounds           | ≤ 30    | Error if exceeded   |
| log_window       | ≥ 1     | Error if below (when present) |
| est. inferences  | > 50    | Warning displayed   |
| est. inferences  | > 100   | Error, block run    |

Use `ScenarioLoader.estimateInferenceCount()` to calculate before execution.

#### Parse vs validate boundary

`ScenarioLoader.load(yaml:)` does **not** run these limit/semantic checks —
it only does structural mapping + construct-time invariants (accepted-language,
persona/agent-count, depth-1 conditional). The `ScenarioValidator` gate runs
separately, so any **new** YAML-ingest path must call it before use:

- Persist a newly-authored/ingested scenario → `validateForCommit(_:)`
  (adds the canonical-primary-field check on top of `validate`).
- Run a scenario → `validate(_:)` (already enforced at the run-gate).
- Re-parse already-persisted YAML (replay/export/display) → no validation;
  the gate ran upstream at create-time. This is why `load` stays un-validating.

See `ScenarioValidator` for the gate; #665 for the boundary rationale.
`ScenarioSemanticLinter` (ADR-024) runs at the same gates as `validate`:
lint errors block like validation errors; warnings surface non-blocking on
the run-start `.summary` channel. New semantic DSL rules belong in the
linter, not the validator — the validator's fail-fast contract stays frozen.

### Inference Count Estimation

```
speak_all:  agentCount per round
speak_each: agentCount × subRounds per round
vote:       agentCount per round
reflect:    agentCount per round
whisper:    (agentCount / 2) × subRounds × 2 per round
            (integer division — pair count × exchanges × 2 speakers)
choose:     agentCount × 2 for round_robin (N adjacent pairs, 2 calls each)
            agentCount for individual (no pairing)
score_calc/assign/eliminate/summarize/event_inject/relationship_update: 0 (code phases)
conditional: max(sum(thenPhases), sum(elsePhases))  — only one branch
             runs per invocation, so `max` matches execution semantics
             and doesn't artificially block asymmetric-branch designs

total = sum(phase estimates) × scenario.rounds
```

The same `max` reduction is used for BOTH the >50 warning and the >100
hard cap (see `ScenarioLoader.estimatePhase`). Using `sum(both)` anywhere
would over-count by construction — a rarely-taken expensive branch would
reject scenarios that in practice spend ≤ `max` inferences per round.

### Conversation-Log Window (`log_window`)

Scenario-level opt-in (`log_window: N`, N ≥ 1; absent = full log). Trims
the conversation log passed to LLM prompts to the last N entries
(`PromptBuilder.formatConversationLog(window:)`, threaded by all five LLM
handlers from `scenario.logWindow`). **Prompt-side only** — TurnRecord
persistence, replay, and export keep the full log. Interaction: the
window truncates the same log the #911 speak_each address rule reads, so
keep N ≥ agentCount for accumulating (speak_each) scenarios or same-round
earlier speakers vanish from the addressee pool (enforced as lint warning
R17, ADR-024).

### Pairing Data Flow (choose phase)

`ChooseHandler` populates `Pairing.action1` / `Pairing.action2` after LLM inference
for each agent in a round-robin pair. These fields are `nil` before execution.
`ScoreCalcHandler` and `SummarizeHandler` read the populated actions for scoring and display.

### Conditional Phase (depth-1 only)

YAML shape:

```yaml
- type: conditional
  if: "max_score >= 10 && active_count > 1"   # boolean DSL with && / || / parens, see ConditionEvaluator
  then:
    - type: summarize
      template: "Game over — someone hit the threshold"
  else:
    - type: speak_all
      prompt: "Keep going"
      output: { statement: string }
```

Rules enforced at both `ScenarioLoader` (YAML path) and `ScenarioValidator`
(programmatic construction path):

- `if:` must be non-empty after trimming whitespace
- `if:` must parse — `ScenarioValidator.validateConditionalPhase` calls
  `ConditionEvaluator.parse(_:)` so malformed expressions (mismatched
  parens, dangling `&&` / `||`, empty operand) fail at scenario-load
  time, not mid-simulation
- at least one of `then:` / `else:` must contain at least one sub-phase
- nested `conditional` inside a branch is rejected (**depth-1 only**).
  Multi-condition needs are met by `&&` / `||` within a single `if:`;
  full nesting is tracked separately if a need surfaces.

`ConditionalHandler` additionally enforces depth-1 structurally — it holds
a sub-handler dict that omits `.conditional`, so a nested conditional that
slipped past both validators would throw at dispatch time rather than
recurse. Data-layer `SimulationRecord.currentPhaseIndex: Int` remains the
top-level resume marker for now; distinguishing sub-phase turns in the
persistence layer is tracked as a follow-up issue.

### Consumer-scoped resolver naming

When a `Scenario` (or shared-state) value is resolved differently by multiple
consumers — Engine / Editor / Picker / UI shell each apply their own priority —
name the consumer-bound resolver after **its consumer**: `engineLanguage`, not a
generic `effectiveLanguage` / `resolved…`. A generic name invites a future
"consolidation" to route other consumers' reads through it, silently bypassing
their priority rules; the encoded name signals that other consumers keep their
own resolvers. Pair the property with a doc-comment listing every consumer row +
its resolver — a CI grep-guard defends *current* call sites, the name defends
*future* additions.

Reference: `Scenario.engineLanguage` (`Models/Scenario.swift`, with its consumer
table); rationale + the four-consumer table in ADR-010 §D5–D6.

## JSON Response Parser

Port directly from Python prototype `parse_json_response()`. Must handle:

1. Gemma 4 thinking tags: `<|channel>thought\n...<channel|>` → strip
2. Code block wrapping: ```json ... ``` → extract inner content
3. Leading garbage / trailing garbage around the object → extract the first
   **balanced** `{...}` via a string-aware brace scan (`StringStateMachine`),
   stopping at the `}` that returns brace balance to zero. This runs
   unconditionally (NOT gated on a `{`/`}` prefix/suffix check) so a stray
   trailing `}` (`{…}}`) or post-object prose is discarded. A greedy
   `\{.*\}` regex would keep them by matching to the last `}`. The scan
   returns the input unchanged when braces never balance, so the repair
   pipeline still fires on a genuinely-unclosed object. (#751 sub-class 1)
4. All values normalized to String in TurnOutput

**Schema-guarded multi-object salvage (#907).** When the happy-path parse
fails AND `expectedKeys` is non-empty, `parse(_:expectedKeys:)` re-extracts
the first balanced object with `allowObjectResidue: true` (overriding the
#751 refusal) and accepts it only if it carries ALL expected keys with
content — repairKind `multi_object_salvage`. The schema-less path
(`parse(_:)`) keeps the #751 refusal verbatim. Single-field grammars made
the multi-object shape dominant, so retrying that span never converges.

### Retry Policy

Max 2 retries. Retry on:
- JSON parse failure
- Empty fields ("..." or empty string)

**Empty-output → grammar-first resample (#751 sub-class 2, FIXED).**
Completely-empty model output was NOT a retry-budget problem: b8694's
`llama_sampler_dist_apply` silently selected a grammar-masked (`-inf`)
token when the grammar (as a chain member, applied after top_k) masked the
sorted top candidate — the pick is RNG-independent, so all retries
reproduced it identically and the budget could never recover. Fixed by
splitting the grammar out of the sampler chain and resampling grammar-first
on a miss (`LlamaCppService.grammarConstrainedSample`, mirroring llama.cpp's
`common_sampler_sample`) — see ADR-002 § "Grammar-all-rejected dist
fallthrough". The retry budget itself is unchanged; the failure is gone at
the sampler. Diagnostic `samplerGrammarResample` (position-0) measures the
residual rescue rate as a model-onboarding fragility signal.

**Grammar-accept crash after object completion → graceful stop (#907).** For
single-field grammars (e.g. `reflect`'s `{ note }`) Gemma 4 E2B frequently
completes the JSON object then keeps generating, tripping the caught
grammar-accept crash (`LLMError.samplerCrashCaught`). The generation loops
(`LlamaCppService.runGeneration` / `runStreamGeneration`) now catch it as
end-of-generation (like an EOG break) instead of failing — the completed
object is already in the accumulated text, so the parser's balanced-brace
scan recovers it. An incomplete object still fails parse and consumes the
retry budget as before. `LLMCaller`'s retry routing on this error stays as
defense in depth for any other surfacer (#885). The `samplerCrashCaught`
diagnostic still fires once per catch for occurrence-rate telemetry.

`GBNFGrammarBuilder`'s `trailing` production is a BOUNDED chain
(`trailingByteBudget` = 16 links) rather than an unbounded self-reference:
the unbounded form accepted unlimited printable ASCII after the close,
inviting the fabricated follow-on objects behind the salvage above (#907).
Overflow past the budget lands on this catch-as-EOS path — benign, the
object is already complete.

## Content Filter

Applied BETWEEN Engine output and UI display (not inside Engine).
Even in debug mode, displayed output is filtered (App Store compliance).
Raw (unfiltered) output is stored in `TurnRecord.rawOutput` and accessible
via a separate developer-only debug inspection UI (not the main simulation view).

## score_calc Built-in Logic

Built-in scoring logics (single source of truth: `Models/ScoreCalcLogic.swift`):
- `prisoners_dilemma`: cooperate/cooperate=3,3 | cooperate/betray=0,5 | betray/betray=1,1
- `vote_tally`: count votes per agent, add to scores
- `wordwolf_judge`: check if most-voted matches the minority agent
- `event_reactive`: reward agents whose last `choose` matched the injected event's favored action; needs a prior `event_inject` (#931)

Custom (author-supplied) logic is Phase 2 scope.

## Prompt literals are paired with the Kotlin port

Editing a `pickLanguage(_:ja:en:)` literal here changes only **half** the prompt.
ADR-023 keeps `shared/engine/src/commonMain/**` as a parallel Kotlin engine
carrying the same ja/en text, and a behaviour comparison between the two measures
nothing if they run different prompts. The en secret-section guidance diverged on
`main` and survived precisely because it was small (#1295).

**Apply**: change both sides in the same commit. `scripts/check-prompt-literal-parity.py`
enforces it (pre-commit sub-gate + the CI "Shell gate tests" job); pairing is by
basename with any `+Extension` suffix stripped, so `PromptBuilder+PrivateSections.swift`
pairs with `PromptBuilder.kt`. A deliberate one-sided literal — today none, and
the allowlist now holds **no** rows at all — needs a row in
`shared/prompt-literal-parity-allowlist.tsv`; the checker prints the exact row to
paste, keyed on a digest of the pair so a later reword forces re-approval.
Whole-file `unported` rows are capped (`MAX_UNPORTED_ROWS`) at the current count,
which reached its terminus of **0** when `NarrateHandler` ported (#1330) — the
last remaining Wave-B handler, `ConditionalHandler`, has no `pickLanguage`
literals. So adding an `unported` row now requires raising the cap in the same
change, with the reason recorded in the allowlist header.

**What the gate does NOT see** — it measures `pickLanguage` literal-pair parity,
not prompt parity, so separators (the `\n` vs `\n\n` join in `appendSecretSection`)
and prompt literals outside `pickLanguage` are invisible to it. The enumerated
blind spots live in the checker's own `What this cannot see` docstring section,
which is where a newly-found one gets added — read it there rather than trusting
this paragraph to have stayed current. Note also that a wording change is a
*behaviour* change: pair it with a harness A/B, and give that A/B a **deleted-text
control arm** — without one, "the two wordings tie" cannot be told from "this text
does nothing" (#1301 found a shipped guidance sentence inert in `en` exactly that way).

## SimulationEvent & the projection contract

`SimulationEvent` (and its `.error` payload `SimulationError`) is the contract
between Engine, App, and Views — all three layers depend on it. **Single source
of truth: `Pastura/Pastura/Models/SimulationEvent.swift`.** Do not re-enumerate
the cases here — per `context-budget.md`, grep-findable enumerations don't
belong in rules files, and this listing drifted twice before deletion.

**Projection contract (ADR-022).** Every production `switch` over
`SimulationEvent`, `PhaseType`, or `CodePhaseEventPayload` must be **no-default
exhaustive over the enum type**:

- **No `default:`.** A case a surface intentionally ignores goes in an
  explicitly-listed arm with a why-comment, so a new case lands in *no* arm and
  the compiler rejects the file (the `ReplayViewModel.apply` pattern).
- **Tiered switches are allowed iff the terminal tier is no-default
  exhaustive** (the `EventLineMapper` pattern: earlier tiers may `default:`-
  forward, the last one lists every remaining case).
- **No raw-string switching over phase/event kinds.** Parse
  `PhaseType(rawValue:)` first, then switch exhaustively over the enum (the
  `ScenarioSignaturePhase.init?(phaseRawValue:)` pattern).

Full contract + rationale: `docs/decisions/ADR-022.md` § D2.

The App-layer instance of the tiered rule: `SimulationViewModel.handleEvent`
keeps a lifecycle-tier `default:` that *forwards* to `handleOutputEvent`, whose
terminal tier is no-default exhaustive (ADR-022 PR-A) — so a new
`SimulationEvent` case compile-breaks in `handleOutputEvent`, not silently
no-ops.

**Not compiler-caught (CI-only):** a new case that also gets an `EventLineMapper`
line must be classified in `scripts/jsonl_to_demo_replay.py` (`HANDLED_EVENTS` /
`IGNORED_EVENTS`; live-only signals → `IGNORED_EVENTS`), or the
`demo-replay-event-coverage` Shell-gate job reddens (ADR-022 §D4).

## llama.cpp Backend Traps

llama.cpp is the active TestFlight backend; the LiteRT-LM migration
trigger has fired and evaluation is in progress (ADR-002 §8, #496) —
revisit this section if/when `LlamaCppService` is replaced.

Seven trap classes from prior incidents. The first four share a crash
signature (`Unexpected empty grammar stack` → SIGABRT) but have
**different root causes and different fixes** — diagnose before fixing.
The fifth is a distinct GGML-level compute abort. The last two never
crash at all: one loses diagnostics, one silently limits a knob's reach.

### Grammar sampler does not mask special tokens

`llama_sampler_init_grammar` does not exclude special tokens from its
mask. A thinking-mode model (Qwen 3, future R1-style ports) emitting a
leading `<think>` crashes `llama_grammar_accept_token`
(`std::runtime_error: Unexpected empty grammar stack`), uncaught at the
Swift boundary. Fix: prefill the assistant turn via
`ModelDescriptor.assistantPrefix` (e.g. `<think>\n\n</think>\n\n`) — the
simplified C-API `llama_chat_apply_template` does not auto-emit what the
Jinja template would under `enable_thinking=false` (PR #368).

**Wrong fixes** (tried and rejected): a GBNF `(think-block)?` rule
(wastes inference tokens on thinking output), `/no_think` system-prompt
hint (soft training hint only — Qwen 3 emitted `<think>` anyway),
sampler-chain token filtering (fights llama.cpp's design).

When adding a model to `ModelRegistry`, check whether its chat template
emits any special token before the response under default settings; if
yes, it needs a closed-form `assistantPrefix` or no grammar.
Defense-in-depth (post-sample `llama_vocab_is_special` check) is tracked
in #371 — consult it before adding any thinking-mode model.

### GGUF source *and variant* matter

unsloth's Gemma 3 GGUF exports flag `<start_of_turn>` / `<end_of_turn>`
as NORMAL instead of CONTROL (unslothai/unsloth#5070), so llama.cpp
BPE-splits the chat markers; the model receives a garbled prompt and
emits a garbage first token, which then trips the grammar. **Same crash
signature as the special-token trap above, different root cause,
different fix**: switch GGUF source — `assistantPrefix` does not help.
Prefer `ggml-org/*-GGUF` (or bartowski) for the Gemma 3 family; Gemma 4
unsloth exports are unaffected **by #5070** and the existing Gemma 4 E2B
descriptor stays on unsloth. (PR #480, closed — Gemma 3 1B no-go;
durable record in ADR-011.)

**This mis-flagging is the route that makes a turn marker reach decoded text
*systematically*** — the other is the model spelling the marker out as a
plaintext hallucination, which is per-response rather than per-export. Either way
it is what makes the per-model truncation in
`JSONResponseParser+Truncate.swift` live rather than dead code (#1422). Why a
correctly-exported model cannot produce one *except* by that hallucination
is stated in full on `Pastura/Pastura/Models/ChatTurnMarkers.swift`
§ "Contract for consumers" (its Kotlin mirror carries the same section). No shipped
model has been observed doing so — `docs/models/eval-log.md` § "Spelled-out
chat-template markers" — but read that negative as a statement about **the files
measured**, not the models. **Do not "simplify" the truncation away on the
strength of a corpus zero.**

**Variant, not just publisher.** Gemma 4 **QAT** exports — Google's and
unsloth's alike — ship a shared-KV tail layer the pinned llama.cpp cannot
load (`missing tensor 'blk.15.attn_k.weight'`), so a `-qat-` repo is never
a drop-in swap for its non-QAT sibling. Descriptor-side procedure:
`docs/models/onboarding.md`; measurements: the QAT-family entries in
`docs/models/eval-log.md`.

**Two failure modes, and only one is the pin's.** That shared-KV gap is a
**loader** gap and pin-relative — a bump to **b10327** (the only build
measured to load one) clears it. **Quant kernel coverage is not
pin-relative**: a build whose tensors use a type the Metal backend has no
kernel for **loads cleanly and then SIGSEGVs on the first inference**,
because the pipeline lookup returns NULL and
`ggml_metal_encoder_set_pipeline` dereferences it. Measured on the
QAT-Mobile `UD-Q2_K_XL` export — llama.cpp ships no `TQ`-family Metal
kernels, and still shipped none at b10375. So **do not read a pin bump as
unblocking a whole variant family**, and treat "it loaded" as no evidence
at all here.

**Apply**: before pulling any GGUF using a quant the catalog has not shipped
before, grep the release xcframework binary for that quant's kernel names —
**with a known-present kernel in the same grep as a positive control**, since
a pattern that matches nothing looks identical to a genuine absence.

When pinning a new descriptor, the HF resolve-URL headers
`X-Linked-Size` / `X-Linked-ETag` give authoritative `fileSize` /
`sha256` without an on-device PoC (`curl -sI <resolve-URL>`).

### Raw `llama_sampler_accept` with prompt tokens corrupts grammar state

`llama_sampler_accept` propagates to every chain component including the
grammar. Prompt tokens (`<bos>`, chat markers, plain text) do not match
the GBNF `root` rule, so every accept throws, the grammar stack empties,
and the next `llama_sampler_sample` hits `GGML_ASSERT(!stacks.empty())`
→ SIGABRT mid-generation. **A C++ exception catcher does NOT save you**
— the catches succeed during prefill but the assertion fires later in
`apply_impl`, and POSIX signals do not propagate through try/catch
(#253). If prompt-token-aware penalty samplers are ever needed, use lazy
grammar mode, split the chain into two samplers, or build a
`common_sampler_accept`-style per-component wrapper that excludes the
grammar. (PR #480 commit eb26153, reverted in 4ffaf6f; ADR-011.)

The **EOG-path** variant of this abort (#253 — EOG sampled mid-generation,
not prompt-token accept) is mitigated with exactly that
"control-the-accept-explicitly" technique. As of #751 the grammar is held
**outside** the sampler chain (`SamplerHandles`) and driven by
`LlamaCppService.grammarConstrainedSample`: `llama_sampler_apply` masks,
the chain selects, and the accept is taken on the grammar handle for
**non-EOG tokens only** (whose post-EOG grammar state is never read).
Non-EOG selection matches the bundled `common_sampler_sample`, so the
distribution is unchanged. SafeSampler still cannot *catch* a `SIGABRT`;
the EOG abort is *avoided*, not caught. The same split-out grammar also
fixes #751 sub-class 2 (grammar-first resample) — see ADR-002
§ "Grammar-all-rejected dist fallthrough" and § "Retry Policy" above.
(ADR-002 §12.9 Mitigation, #253.)

### Grammar must not enumerate values — structure only

`GBNFGrammarBuilder` constrains JSON **structure** (object shape, keys,
the shared `string` value production) but MUST NOT emit value
enumerations (option / candidate literals) into the grammar. CJK /
multi-byte / dynamic literal values crash llama.cpp's sampler at
accept-time (the `Unexpected empty grammar stack` class above; ADR-002
§12.9), and the trigger is the model's BPE tokenizer — so it is
**per-model**: a char-class guard that passes for Gemma 4 E2B is
unverified for any other runtime-selectable model or LiteRT-LM. There is
no model-agnostic "safe enumeration" predicate (one — `isSafeEnumerationOption`
— was tried and removed in #597).

Constrain closed-set values at **runtime** instead: `choose` (round-robin) →
`ChooseHandler.validateAction` **drops the pairing** (+ emits `.actionRejected`)
on a genuinely off-menu action, replacing the old fabricating `options[0]`
fallback (ADR-021 §Amendment 2026-07-17); `vote` → tally drop in
`VoteHandler`. `OutputSchema.Kind.choice` is a payload-free marker so
option strings never reach a grammar literal. Vote dropped grammar
enumeration in #597; choose in #599 (ADR-002 §Amendment 2026-06-14).
Residual: CJK field **names** still emit as JSON-key literals, same
mechanism (#607).

### iOS Simulator cannot run quantized inference

Simulator Metal reports `MTL0 ... 0 MiB free`; weight tensors fail to
buffer (`ggml_metal_buffer_get_id ... buffer is nil`) and the CPU
fallback hits `GGML_ASSERT` in `ggml_compute_forward_get_rows` → SIGABRT.
This is a GGML-level compute abort — **a distinct crash class from the
grammar paths above**; SafeSampler cannot catch it. Load-only
integration tests pass; anything calling `generate` / `generateStream`
dies. Verify inference on a real device, or accept unit-test-level
coverage for sampler code (PR #463 verification).

### Errors split between the log callback and raw stderr

A prebuilt C/C++ library (binary xcframework / pinned artifact) can split error
reporting across two paths: the **log-callback API** (`llama_log_set`,
`av_log_set_callback`) and **direct `fprintf(stderr, …)` writes** that bypass the
callback. iOS's `os_log` does NOT capture process stderr, so the second path is
silently lost. llama.cpp logs the generic `"failed to parse grammar"` via the
callback but writes the actionable parser detail (`"expecting ']'"`,
`"Undefined rule"`) only to stderr — in #194 this gap cost six rounds of
speculative grammar fixes before a `dup2`-based stderr capture revealed a
one-line cause (`is_word_char` rejecting `_` in rule names).

**Before the first commit** on a new C-API integration, grep the library source
for BOTH `*_LOG_*` macros AND `fprintf(stderr, …)` / `printf` on error paths. If
stderr writes exist on error paths, scaffold a narrow `dup2`-based capture around
the failing call. The capture details are load-bearing — the `Pipe()` drain order
matters and `defer` does NOT work (the read needs all writers closed before scope
exit) — so reuse `LlamaCppService+Sampler.swift` `initGrammarCapturingStderr` as
the reference implementation rather than re-deriving the fd plumbing.

### The chain's `penalties` cannot reach across a `generate()`

A sampler's history is **per-sampler-object**, and `createSampler` allocates a
fresh chain on every `generate()` — so the `penalties` member's ring buffer
starts empty each call. It is live and **load-bearing within** a generation (fed
every accepted token — via `acceptSampledToken` on the grammar path, internally
by `llama_sampler_sample` on the bundled no-grammar path — so do not remove it),
but it is structurally blind **across** generations: an agent echoing its own
prior statement, or cross-agent template collapse, is out of its reach no matter
how high `repeatPenalty` / `penalty_last_n` go. Silent — no crash, no
diagnostic; the knob simply moves nothing.

Cross-turn anti-repetition therefore needs a **separately seeded** handle, not a
chain-penalty tweak — that is what the #1105 DRY sampler is. But mind what the
shipped seeding does *not* reach: `SpeakEachHandler` is the only seeder in
Engine and it seeds the agent's **own** prior statement, so cross-agent template
collapse is uncovered, and so is every phase other than `speak_each`.

**Apply**: before proposing any repetition fix, name the scope it targets, and
check it against the three that exist:

1. **Within one generation** — the chain's `penalties`, and only its last
   `penalty_last_n`=64 tokens of up to `maxTokens`=1000. Not total even here.
2. **An agent's own prior turns, `speak_each` only** — the #1105 DRY seed.
3. **Anything else** (cross-agent collapse; any other phase) — currently
   unreached; needs a new seeder, not a knob.

Detail + the seeding contract live at `SamplerHandles.dry` and
`buildAndSeedDrySampler` (`LlamaCppService+DrySampler.swift`); keep the depth
there, not here.

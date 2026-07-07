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

**Deferred (#751 sub-class 2):** completely-empty model output (EOG-at-
position-0 suspected) exhausts the retry budget. It is inference-side, not
parser-recoverable — root-cause on-device per the issue before adding any
retry-budget change. Tracked under #751.

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

MVP includes exactly 3 scoring logics:
- `prisoners_dilemma`: cooperate/cooperate=3,3 | cooperate/betray=0,5 | betray/betray=1,1
- `vote_tally`: count votes per agent, add to scores
- `wordwolf_judge`: check if most-voted matches the minority agent

Custom logic is Phase 2 scope.

## SimulationEvent Definition

This enum is the contract between Engine, App, and Views. Define it early —
all three layers depend on it.

```swift
nonisolated public enum SimulationEvent: Sendable, Equatable {
    // Round lifecycle
    case roundStarted(round: Int, totalRounds: Int)
    case roundCompleted(round: Int, scores: [String: Int])

    // Phase lifecycle. `phasePath` is `[K]` for top-level phase K; nested
    // sub-phases carry `[K, N]` so future phase types with nested
    // sub-phases share one identifier shape.
    case phaseStarted(phaseType: PhaseType, phasePath: [Int])
    case phaseCompleted(phaseType: PhaseType, phasePath: [Int])

    // Agent outputs (LLM phases)
    case agentOutput(agent: String, output: TurnOutput, phaseType: PhaseType)

    // Code phase results
    case scoreUpdate(scores: [String: Int])
    case elimination(agent: String, voteCount: Int)
    case assignment(agent: String, value: String)
    case summary(text: String)

    // Vote results (after vote phase completes)
    case voteResults(votes: [String: String], tallies: [String: Int])

    // Pairing results (choose phase with round_robin)
    case pairingResult(agent1: String, action1: String, agent2: String, action2: String)

    // Simulation lifecycle
    case simulationCompleted
    // Emitted only by `SimulationRunner.checkPaused`; handlers must not
    // emit this case directly. Nested handlers invoke pause through
    // `PhaseContext.pauseCheck`, which routes back to the single runner-
    // owned emit point.
    case simulationPaused(round: Int, phasePath: [Int])
    case error(SimulationError)

    // Progress (for UI feedback during long inferences)
    case inferenceStarted(agent: String)
    case inferenceCompleted(agent: String, durationSeconds: Double)
}

nonisolated public enum SimulationError: Error, Sendable, Equatable {
    case scenarioValidationFailed(String)
    /// Stores description as String (not Error) for Sendable + Equatable conformance.
    case llmGenerationFailed(description: String)
    case jsonParseFailed(raw: String)
    case retriesExhausted
    case modelNotLoaded
    case cancelled
}
```

### Usage Pattern in Views

```swift
// In SimulationView
.task {
    for await event in runner.run(scenario: scenario, config: config) {
        switch event {
        case .agentOutput(let agent, let output, _):
            viewModel.appendOutput(agent: agent, output: output)
        case .roundCompleted(_, let scores):
            viewModel.updateScores(scores)
        case .inferenceStarted(let agent):
            viewModel.showThinking(agent: agent)
        case .error(let error):
            viewModel.showError(error)
        // ...
        }
    }
}
```

## llama.cpp Backend Traps

llama.cpp is the active TestFlight backend; the LiteRT-LM migration
trigger has fired and evaluation is in progress (ADR-002 §8, #496) —
revisit this section if/when `LlamaCppService` is replaced.

Five trap classes from prior incidents. The first four share a crash
signature (`Unexpected empty grammar stack` → SIGABRT) but have
**different root causes and different fixes** — diagnose before fixing.

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

### GGUF source matters — control-token type flags

unsloth's Gemma 3 GGUF exports flag `<start_of_turn>` / `<end_of_turn>`
as NORMAL instead of CONTROL (unslothai/unsloth#5070), so llama.cpp
BPE-splits the chat markers; the model receives a garbled prompt and
emits a garbage first token, which then trips the grammar. **Same crash
signature as the special-token trap above, different root cause,
different fix**: switch GGUF source — `assistantPrefix` does not help.
Prefer `ggml-org/*-GGUF` (or bartowski) for the Gemma 3 family; Gemma 4
unsloth exports are unaffected and the existing Gemma 4 E2B descriptor
stays on unsloth. (PR #480, closed — Gemma 3 1B no-go; durable record in
ADR-011.)

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
not prompt-token accept) is now mitigated with exactly that
"control-the-accept-explicitly" technique: `LlamaCppService.safeSample`
splits the grammar-active step into `llama_sampler_apply` + a guarded
`llama_sampler_accept`, skipping the accept for EOG tokens (whose post-EOG
grammar state is never read). Non-EOG selection is byte-identical to the
bundled `llama_sampler_sample`, so the distribution is unchanged. SafeSampler
still cannot *catch* a `SIGABRT`; the EOG abort is *avoided*, not caught.
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

Constrain closed-set values at **runtime** instead: `choose` → `options[0]`
fallback in `ChooseHandler.validateAction`; `vote` → tally drop in
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

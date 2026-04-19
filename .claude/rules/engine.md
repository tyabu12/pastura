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

| Type        | Processing | Description                          |
|-------------|------------|--------------------------------------|
| speak_all   | LLM        | All agents speak simultaneously      |
| speak_each  | LLM        | Agents speak in turn (accumulating)  |
| vote        | LLM        | All agents vote for one agent        |
| choose      | LLM        | Choose from options                  |
| score_calc  | Code       | Calculate scores                     |
| assign      | Code       | Distribute info to agents            |
| eliminate   | Code       | Remove most-voted agent              |
| summarize   | Code       | Format round summary                 |
| conditional | Control    | Branch on state DSL; nests sub-phases |

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
handlers get `[K]`; handlers that dispatch sub-phases (conditional today,
event_inject / reflect later) append the sub-phase index so inner lifecycle
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
| est. inferences  | > 50    | Warning displayed   |
| est. inferences  | > 100   | Error, block run    |

Use `ScenarioLoader.estimateInferenceCount()` to calculate before execution.

### Inference Count Estimation

```
speak_all:  agentCount per round
speak_each: agentCount × subRounds per round
vote:       agentCount per round
choose:     agentCount × 2 for round_robin (N adjacent pairs, 2 calls each)
            agentCount for individual (no pairing)
score_calc/assign/eliminate/summarize: 0 (code phases)
conditional: max(sum(thenPhases), sum(elsePhases))  — only one branch
             runs per invocation, so `max` matches execution semantics
             and doesn't artificially block asymmetric-branch designs

total = sum(phase estimates) × scenario.rounds
```

The same `max` reduction is used for BOTH the >50 warning and the >100
hard cap (see `ScenarioLoader.estimatePhase`). Using `sum(both)` anywhere
would over-count by construction — a rarely-taken expensive branch would
reject scenarios that in practice spend ≤ `max` inferences per round.

### Pairing Data Flow (choose phase)

`ChooseHandler` populates `Pairing.action1` / `Pairing.action2` after LLM inference
for each agent in a round-robin pair. These fields are `nil` before execution.
`ScoreCalcHandler` and `SummarizeHandler` read the populated actions for scoring and display.

### Conditional Phase (depth-1 only)

YAML shape:

```yaml
- type: conditional
  if: "max_score >= 10"       # single-comparison DSL, see ConditionEvaluator
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
- at least one of `then:` / `else:` must contain at least one sub-phase
- nested `conditional` inside a branch is rejected (**depth-1 only**). Follow-up
  issues relax this once `&&` / `||` combinators land in the DSL.

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
3. Leading garbage before `{` → find first `{...}` with regex
4. All values normalized to String in TurnOutput

### Retry Policy

Max 2 retries. Retry on:
- JSON parse failure
- Empty fields ("..." or empty string)

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
    // sub-phases carry `[K, N]` so future phase types with sub-phases
    // (conditional / event_inject / reflect) share one identifier shape.
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

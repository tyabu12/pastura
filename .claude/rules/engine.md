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

### PhaseHandler Protocol

```swift
public protocol PhaseHandler {
    func execute(
        scenario: Scenario,
        phase: Phase,
        state: inout SimulationState,
        llm: LLMService,
        emitter: (SimulationEvent) -> Void
    ) async throws
}
```

Handlers are registered in PhaseDispatcher as a [PhaseType: PhaseHandler] dictionary.

### SimulationRunner Output

`SimulationRunner.run()` returns `AsyncStream<SimulationEvent>`.
Pause is implemented via an `isPaused` flag with polling in the run loop.
Cancellation uses standard Swift `Task` cancellation.

### Validation Limits

| Parameter        | Limit   | Behavior           |
|------------------|---------|---------------------|
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
choose:     agentCount (or agentCount*(agentCount-1)/2 for round_robin) per round
score_calc/assign/eliminate/summarize: 0 (code phases)

total = sum(phase estimates) × scenario.rounds
```

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
public enum SimulationEvent {
    // Round lifecycle
    case roundStarted(round: Int, totalRounds: Int)
    case roundCompleted(round: Int, scores: [String: Int])

    // Phase lifecycle
    case phaseStarted(phaseType: PhaseType, phaseIndex: Int)
    case phaseCompleted(phaseType: PhaseType, phaseIndex: Int)

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
    case simulationPaused(round: Int, phaseIndex: Int)
    case error(SimulationError)

    // Progress (for UI feedback during long inferences)
    case inferenceStarted(agent: String)
    case inferenceCompleted(agent: String, durationSeconds: Double)
}

public enum SimulationError: Error {
    case scenarioValidationFailed(String)
    case llmGenerationFailed(underlying: Error)
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

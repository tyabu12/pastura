import Foundation
import Testing

@testable import Pastura

// MARK: - Configuration

/// Reads Ollama integration test settings from environment variables.
private enum OllamaConfig {
  /// Gate: must be exactly "1" to enable these tests.
  static var isEnabled: Bool {
    ProcessInfo.processInfo.environment["OLLAMA_INTEGRATION"] == "1"
  }

  static var baseURL: URL {
    let raw =
      ProcessInfo.processInfo.environment["OLLAMA_BASE_URL"]
      ?? "http://localhost:11434"
    guard let url = URL(string: raw) else {
      preconditionFailure("OLLAMA_BASE_URL '\(raw)' is not a valid URL")
    }
    return url
  }

  static var modelName: String {
    ProcessInfo.processInfo.environment["OLLAMA_MODEL"] ?? "gemma4:e2b"
  }
}

// MARK: - Tests

/// Integration tests that run against a live Ollama instance.
///
/// Gated by `OLLAMA_INTEGRATION=1` environment variable. These tests are skipped
/// in normal CI runs and require a local Ollama server with the target model pulled.
///
/// Run with:
/// ```
/// OLLAMA_INTEGRATION=1 xcodebuild test -scheme Pastura \
///   -project Pastura/Pastura.xcodeproj \
///   -destination 'platform=iOS Simulator,name=iPhone 16' \
///   -only-testing PasturaTests/OllamaIntegrationTests
/// ```
@Suite(.serialized, .enabled(if: OllamaConfig.isEnabled))
struct OllamaIntegrationTests {

  // MARK: - Helpers

  private func makeOllamaService() -> OllamaService {
    OllamaService(baseURL: OllamaConfig.baseURL, modelName: OllamaConfig.modelName)
  }

  /// Verifies the Ollama server is reachable and the target model is available.
  ///
  /// Checks the `/api/tags` endpoint and parses the response to confirm
  /// the configured model is pulled. Throws a descriptive error on failure.
  private func requireOllamaAvailable() async throws {
    let tagsURL = OllamaConfig.baseURL.appendingPathComponent("api/tags")
    let data: Data
    do {
      (data, _) = try await URLSession.shared.data(from: tagsURL)
    } catch {
      throw OllamaCheckError(
        message:
          "Ollama server not reachable at \(OllamaConfig.baseURL). "
          + "Start Ollama or set OLLAMA_BASE_URL."
      )
    }

    guard
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let models = json["models"] as? [[String: Any]]
    else {
      throw OllamaCheckError(message: "Unexpected response from /api/tags")
    }

    let modelNames = models.compactMap { $0["name"] as? String }
    let target = OllamaConfig.modelName
    // Ollama model names may include ":latest" suffix
    let found = modelNames.contains { name in
      name == target || name.hasPrefix("\(target):")
    }

    guard found else {
      throw OllamaCheckError(
        message:
          "Model '\(target)' not found on Ollama server. "
          + "Available: \(modelNames.joined(separator: ", ")). "
          + "Run: ollama pull \(target)"
      )
    }
  }

  /// Asserts that all `pairingResult` events contain valid cooperate/betray actions.
  private func assertPairingActionsValid(in events: [SimulationEvent]) {
    let validActions: Set<String> = ["cooperate", "betray"]
    for event in events {
      if case .pairingResult(let agent1, let action1, let agent2, let action2) = event {
        #expect(validActions.contains(action1), "\(agent1) chose invalid action '\(action1)'")
        #expect(validActions.contains(action2), "\(agent2) chose invalid action '\(action2)'")
      }
    }
  }

  // MARK: - Test 1: Minimal speakAll

  @Test(.timeLimit(.minutes(2)))
  func minimalSpeakAllProducesCompleteEventStream() async throws {
    try await requireOllamaAvailable()

    let ollama = makeOllamaService()
    try await ollama.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 1,
      phases: [
        Phase(
          type: .speakAll,
          prompt: "会話ログ: {conversation_log}",
          outputSchema: ["statement": "string"]
        )
      ]
    )

    let runner = SimulationRunner()
    let events = await collectAllEvents(
      runner.run(scenario: scenario, llm: ollama, suspendController: SuspendController()))

    try await ollama.unloadModel()

    // No errors in the event stream
    let errors = events.compactMap { event -> SimulationError? in
      if case .error(let err) = event { return err }
      return nil
    }
    #expect(errors.isEmpty, "Unexpected errors: \(errors)")

    // Full lifecycle events present
    #expect(events.contains { if case .roundStarted(1, 1) = $0 { true } else { false } })
    #expect(
      events.contains { if case .phaseStarted(.speakAll, [0]) = $0 { true } else { false } })
    #expect(
      events.contains { if case .phaseCompleted(.speakAll, [0]) = $0 { true } else { false } })
    #expect(events.contains { if case .roundCompleted(1, _) = $0 { true } else { false } })
    #expect(events.contains { if case .simulationCompleted = $0 { true } else { false } })

    // Both agents produced output with non-empty statement
    let agentOutputs = events.compactMap { event -> (String, TurnOutput)? in
      if case .agentOutput(let agent, let output, .speakAll) = event {
        return (agent, output)
      }
      return nil
    }
    #expect(agentOutputs.count == 2, "Expected 2 agent outputs, got \(agentOutputs.count)")

    for (agent, output) in agentOutputs {
      let statement = output.statement ?? ""
      #expect(!statement.isEmpty, "\(agent) produced empty statement")
      #expect(statement != "...", "\(agent) produced placeholder '...' statement")
    }
  }

  // MARK: - Test 2: Prisoners Dilemma

  @Test(.timeLimit(.minutes(3)))
  func prisonersDilemmaCompletesWithScores() async throws {
    try await requireOllamaAvailable()

    let ollama = makeOllamaService()
    try await ollama.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 1,
      phases: [
        Phase(
          type: .speakAll,
          prompt: "Declare your intention!",
          outputSchema: ["declaration": "string", "inner_thought": "string"]
        ),
        Phase(
          type: .choose,
          prompt: "Opponent: {opponent_name}",
          outputSchema: ["action": "string"],
          options: ["cooperate", "betray"],
          pairing: .roundRobin
        ),
        Phase(type: .scoreCalc, logic: .prisonersDilemma),
        Phase(type: .summarize, template: "Round {current_round} complete")
      ]
    )

    let runner = SimulationRunner()
    let events = await collectAllEvents(
      runner.run(scenario: scenario, llm: ollama, suspendController: SuspendController()))

    try await ollama.unloadModel()

    // No errors
    let errors = events.compactMap { event -> SimulationError? in
      if case .error(let err) = event { return err }
      return nil
    }
    #expect(errors.isEmpty, "Unexpected errors: \(errors)")

    // Simulation completed
    #expect(events.contains { if case .simulationCompleted = $0 { true } else { false } })

    // Score update emitted
    let scoreUpdates = events.compactMap { event -> [String: Int]? in
      if case .scoreUpdate(let scores) = event { return scores }
      return nil
    }
    #expect(!scoreUpdates.isEmpty, "No score updates emitted")

    // Pairing results have valid actions
    assertPairingActionsValid(in: events)
  }

  // MARK: - Test 3: JSONResponseParser with real E2B output

  @Test(.timeLimit(.minutes(1)))
  func jsonResponseParserHandlesRealE2BOutput() async throws {
    try await requireOllamaAvailable()

    let ollama = makeOllamaService()
    try await ollama.loadModel()

    // Build a realistic prompt using PromptBuilder
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 1,
      phases: [
        Phase(
          type: .speakAll,
          prompt: "Speak freely.",
          outputSchema: ["statement": "string"]
        )
      ]
    )

    let persona = scenario.personas[0]
    let phase = scenario.phases[0]
    let state = SimulationState.initial(for: scenario)
    let builder = PromptBuilder()

    let systemPrompt = builder.buildSystemPrompt(
      scenario: scenario, persona: persona, phase: phase, state: state)
    let userPrompt = "会話ログ: （まだなし）"

    let rawResponse = try await ollama.generate(system: systemPrompt, user: userPrompt)

    try await ollama.unloadModel()

    // JSONResponseParser should handle the raw E2B output
    let parser = JSONResponseParser()
    let turnOutput = try parser.parse(rawResponse)

    let statement = turnOutput.statement ?? ""
    #expect(!statement.isEmpty, "Parsed statement is empty. Raw: \(rawResponse)")
    #expect(statement != "...", "Parsed statement is placeholder. Raw: \(rawResponse)")
  }
}

// MARK: - Error Type

/// Error used for Ollama pre-flight checks. Provides a clear diagnostic message.
private struct OllamaCheckError: Error, CustomStringConvertible {
  let message: String
  var description: String { message }
}

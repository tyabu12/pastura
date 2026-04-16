import Foundation
import Testing

@testable import Pastura

@Suite @MainActor struct ResultMarkdownExporterTests {  // swiftlint:disable:this type_body_length

  // MARK: - Fixtures

  private let createdAt = Date(timeIntervalSince1970: 1_712_000_000)  // 2024-04-01T19:33:20Z
  private let updatedAt = Date(timeIntervalSince1970: 1_712_000_342)  // +5m 42s
  private let exportAt = Date(timeIntervalSince1970: 1_713_000_000)  // 2024-04-13T08:53:20Z

  private func makeScenario(
    id: String = "s1",
    name: String = "Prisoners Dilemma",
    yaml: String = "name: Prisoners Dilemma\nrounds: 2\n"
  ) -> ScenarioRecord {
    ScenarioRecord(
      id: id, name: name, yamlDefinition: yaml,
      isPreset: true, createdAt: Date(), updatedAt: Date())
  }

  private func makeSimulation(
    id: String = "sim1",
    scenarioId: String = "s1",
    status: SimulationStatus = .completed,
    modelIdentifier: String? = "Gemma 4 E2B (Q4_K_M)",
    llmBackend: String? = "llama.cpp"
  ) -> SimulationRecord {
    SimulationRecord(
      id: id, scenarioId: scenarioId,
      status: status.rawValue,
      currentRound: 2, currentPhaseIndex: 0,
      stateJSON: "{}", configJSON: nil,
      createdAt: createdAt, updatedAt: updatedAt,
      modelIdentifier: modelIdentifier, llmBackend: llmBackend)
  }

  private func makeTurn(
    round: Int,
    seq: Int,
    phase: String,
    agent: String?,
    fields: [String: String]
  ) -> TurnRecord {
    let json =
      (try? JSONEncoder().encode(TurnOutput(fields: fields))).flatMap {
        String(data: $0, encoding: .utf8)
      } ?? "{}"
    return TurnRecord(
      id: UUID().uuidString,
      simulationId: "sim1",
      roundNumber: round,
      phaseType: phase,
      agentName: agent,
      rawOutput: json,
      parsedOutputJSON: json,
      sequenceNumber: seq,
      createdAt: Date())
  }

  private func makeState(
    scores: [String: Int] = ["Alice": 5, "Bob": 3],
    eliminated: [String: Bool] = [:]
  ) -> SimulationState {
    SimulationState(
      scores: scores,
      eliminated: eliminated,
      conversationLog: [],
      lastOutputs: [:],
      voteResults: [:],
      pairings: [],
      variables: [:],
      currentRound: 2)
  }

  private func makeExporter(
    filter: ContentFilter = ContentFilter(blockedPatterns: [])
  ) -> ResultMarkdownExporter {
    ResultMarkdownExporter(
      contentFilter: filter,
      environment: .init(deviceModel: "iPhone", osVersion: "Version 17.5"),
      now: exportAt)
  }

  // MARK: - Tests

  @Test func includesVersionMarkerAndMetadataHeader() throws {
    let exporter = makeExporter()
    let input = ResultMarkdownExporter.Input(
      simulation: makeSimulation(),
      scenario: makeScenario(),
      turns: [],
      state: makeState())

    let result = try exporter.export(input)

    #expect(result.text.hasPrefix("<!-- pastura-export v1 -->"))
    #expect(result.text.contains("# Simulation Export: Prisoners Dilemma"))
    #expect(result.text.contains("## Metadata"))
    #expect(result.text.contains("**Status**: completed"))
    #expect(result.text.contains("**Started**: 2024-04-01T19:33:20Z"))
    #expect(result.text.contains("**Ended**: 2024-04-01T19:39:02Z"))
    #expect(result.text.contains("**Duration**: 5m 42s"))
    #expect(result.text.contains("**Model**: Gemma 4 E2B (Q4_K_M)"))
    #expect(result.text.contains("**Backend**: llama.cpp"))
    #expect(result.text.contains("**Device**: iPhone / Version 17.5"))
  }

  @Test func includesScenarioYAMLFence() throws {
    let exporter = makeExporter()
    let input = ResultMarkdownExporter.Input(
      simulation: makeSimulation(),
      scenario: makeScenario(yaml: "name: Test\nrounds: 1\n"),
      turns: [],
      state: makeState())

    let result = try exporter.export(input)

    #expect(result.text.contains("## Scenario Definition"))
    #expect(result.text.contains("```yaml\nname: Test\nrounds: 1\n\n```"))
  }

  @Test func rendersSpeakAllTurn() throws {
    let exporter = makeExporter()
    let turn = makeTurn(
      round: 1, seq: 1, phase: "speak_all",
      agent: "Alice", fields: ["statement": "Hello from Alice"])
    let input = ResultMarkdownExporter.Input(
      simulation: makeSimulation(),
      scenario: makeScenario(),
      turns: [turn],
      state: makeState())

    let result = try exporter.export(input)

    #expect(result.text.contains("### Round 1"))
    #expect(result.text.contains("#### Phase: speak_all"))
    #expect(result.text.contains("- **Alice**: Hello from Alice"))
    #expect(result.text.contains("**Inference count**: 1"))
  }

  @Test func rendersInnerThoughtAsNestedBullet() throws {
    let exporter = makeExporter()
    let turn = makeTurn(
      round: 1, seq: 1, phase: "speak_each",
      agent: "Alice",
      fields: [
        "statement": "I pick A.",
        "inner_thought": "Actually I believe B but am going along"
      ])
    let input = ResultMarkdownExporter.Input(
      simulation: makeSimulation(),
      scenario: makeScenario(),
      turns: [turn],
      state: makeState())

    let result = try exporter.export(input)

    #expect(result.text.contains("- **Alice**: I pick A."))
    #expect(result.text.contains("  - 💭 _Actually I believe B but am going along_"))
  }

  @Test func rendersVoteTurn() throws {
    let exporter = makeExporter()
    let turn = makeTurn(
      round: 1, seq: 1, phase: "vote",
      agent: "Alice", fields: ["vote": "Bob"])
    let input = ResultMarkdownExporter.Input(
      simulation: makeSimulation(),
      scenario: makeScenario(),
      turns: [turn],
      state: makeState())

    let result = try exporter.export(input)

    #expect(result.text.contains("#### Phase: vote"))
    #expect(result.text.contains("- **Alice**: → Bob"))
  }

  @Test func appliesContentFilterToRenderedMarkdown() throws {
    // Applies to everything — including persona names in YAML and turn output.
    let filter = ContentFilter(blockedPatterns: ["死ね"], replacement: "***")
    let exporter = makeExporter(filter: filter)
    let yaml = "personas:\n  - name: 死ね太郎\n"
    let turn = makeTurn(
      round: 1, seq: 1, phase: "speak_all",
      agent: "死ね太郎", fields: ["statement": "死ね and hi"])
    let input = ResultMarkdownExporter.Input(
      simulation: makeSimulation(),
      scenario: makeScenario(yaml: yaml),
      turns: [turn],
      state: makeState(scores: ["死ね太郎": 1]))

    let result = try exporter.export(input)

    #expect(!result.text.contains("死ね"))
    #expect(result.text.contains("***"))
  }

  @Test func includesFinalScoresSection() throws {
    let exporter = makeExporter()
    let scoreEvent = makeCodePhaseEventForFinalScoresFixture(
      seq: 1, payload: .scoreUpdate(scores: ["Alice": 10, "Bob": 3]))
    let elimEvent = makeCodePhaseEventForFinalScoresFixture(
      seq: 2, payload: .elimination(agent: "Bob", voteCount: 2))
    let input = ResultMarkdownExporter.Input(
      simulation: makeSimulation(),
      scenario: makeScenario(),
      turns: [],
      codePhaseEvents: [scoreEvent, elimEvent],
      personas: ["Alice", "Bob"],
      state: makeState())

    let result = try exporter.export(input)

    #expect(result.text.contains("## Final Scores"))
    #expect(result.text.contains("| Alice | 10 | active |"))
    #expect(result.text.contains("| Bob | 3 | eliminated |"))
  }

  private func makeCodePhaseEventForFinalScoresFixture(
    seq: Int, payload: CodePhaseEventPayload
  ) -> CodePhaseEventRecord {
    let json =
      (try? JSONEncoder().encode(payload)).flatMap {
        String(data: $0, encoding: .utf8)
      } ?? "{}"
    return CodePhaseEventRecord(
      id: UUID().uuidString, simulationId: "sim1",
      roundNumber: 2,
      phaseType: "score_calc",
      sequenceNumber: seq, payloadJSON: json,
      createdAt: Date())
  }

  @Test func unknownModelAndBackendFallBackToPlaceholder() throws {
    let exporter = makeExporter()
    let input = ResultMarkdownExporter.Input(
      simulation: makeSimulation(modelIdentifier: nil, llmBackend: nil),
      scenario: makeScenario(),
      turns: [],
      state: makeState())

    let result = try exporter.export(input)

    #expect(result.text.contains("**Model**: (unknown)"))
    #expect(result.text.contains("**Backend**: (unknown)"))
  }

  @Test func zeroTurnRunRendersMinimally() throws {
    // Simulates a run that errored at LLM load before any inference fired.
    let exporter = makeExporter()
    let input = ResultMarkdownExporter.Input(
      simulation: makeSimulation(status: .failed),
      scenario: makeScenario(),
      turns: [],
      state: makeState(scores: [:]))

    let result = try exporter.export(input)

    #expect(result.text.contains("**Status**: failed"))
    #expect(result.text.contains("**Inference count**: 0"))
    #expect(result.text.contains("_No turns recorded._"))
    #expect(!result.text.contains("## Final Scores"))
  }

  @Test func suppressesFinalScoresForObservationOnlyScenario() throws {
    // Pure speak_each / observation scenarios have no score_calc phase, so
    // all-zero scores mean "no scoring happened" rather than "everyone scored 0".
    // Rendering a Final Scores table of all 0s would be misleading noise.
    let exporter = makeExporter()
    let input = ResultMarkdownExporter.Input(
      simulation: makeSimulation(),
      scenario: makeScenario(),
      turns: [
        makeTurn(
          round: 1, seq: 1, phase: "speak_each",
          agent: "Alice", fields: ["statement": "hello"])
      ],
      state: makeState(
        scores: ["Alice": 0, "Bob": 0],
        eliminated: ["Alice": false, "Bob": false]))

    let result = try exporter.export(input)

    #expect(!result.text.contains("## Final Scores"))
  }

  @Test func codePhaseTurnRendersWithoutAgentHeader() throws {
    let exporter = makeExporter()
    let turn = makeTurn(
      round: 1, seq: 1, phase: "score_calc",
      agent: nil, fields: [:])
    let input = ResultMarkdownExporter.Input(
      simulation: makeSimulation(),
      scenario: makeScenario(),
      turns: [turn],
      state: makeState())

    let result = try exporter.export(input)

    #expect(result.text.contains("#### Phase: score_calc"))
    #expect(result.text.contains("_(code phase — no agent output)_"))
    // Code-phase turn should NOT count toward inference count.
    #expect(result.text.contains("**Inference count**: 0"))
  }

  @Test func sanitizesFilenameForNonAsciiScenarioName() {
    let name = "囚人のジレンマ / テスト"
    let sanitized = ResultMarkdownExporter.sanitizeFilename(name)
    #expect(sanitized == "囚人のジレンマ___テスト")
  }

  @Test func sanitizeFilenameTruncatesLongNames() {
    let name = String(repeating: "a", count: 120)
    let sanitized = ResultMarkdownExporter.sanitizeFilename(name)
    #expect(sanitized.count == 50)
  }

  @Test func sanitizeFilenameHandlesEmptyInput() {
    #expect(ResultMarkdownExporter.sanitizeFilename("") == "export")
  }

  @Test func normalizeOSVersionRewritesAppleFormat() {
    let normalized = ResultMarkdownExporter.ExportEnvironment.normalizeOSVersion(
      "Version 26.4 (Build 23E246)")
    #expect(normalized == "iOS 26.4 (build 23E246)")
  }

  @Test func normalizeOSVersionLeavesUnfamiliarStringsUnchanged() {
    let raw = "custom-os-26.4"
    #expect(ResultMarkdownExporter.ExportEnvironment.normalizeOSVersion(raw) == raw)
  }

  @Test func writesMarkdownFileToTempDirectory() throws {
    let exporter = makeExporter()
    let input = ResultMarkdownExporter.Input(
      simulation: makeSimulation(),
      scenario: makeScenario(name: "test-scenario"),
      turns: [],
      state: makeState())

    let result = try exporter.export(input)
    defer { try? FileManager.default.removeItem(at: result.fileURL) }

    let contents = try String(contentsOf: result.fileURL, encoding: .utf8)
    #expect(contents == result.text)
    #expect(result.fileURL.lastPathComponent.hasSuffix(".md"))
    #expect(result.fileURL.lastPathComponent.contains("test-scenario"))
  }
}

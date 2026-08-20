// swiftlint:disable file_length
import CryptoKit
import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct YAMLReplayExporterTests {  // swiftlint:disable:this type_body_length

  // MARK: - Fixtures

  private let exportAt = Date(timeIntervalSince1970: 1_713_000_000)  // 2024-04-13T09:20:00Z

  /// Minimal valid scenario YAML covering every phase_type used by the
  /// tests below. Defined once so the scenario SHA is stable across
  /// cases that don't care about scenario content.
  private static let baseScenarioYAML = """
    id: test_scn
    language: ja
    name: Test Scenario
    description: test
    agents: 2
    rounds: 2
    context: ctx
    personas:
      - name: Alice
        description: ''
      - name: Bob
        description: ''
    phases:
      - type: speak_all
        prompt: say
        output:
          statement: string
      - type: vote
        prompt: vote
        candidates: agents
      - type: score_calc
        logic: vote_tally
    """

  private func makeScenario(
    yaml: String = YAMLReplayExporterTests.baseScenarioYAML
  ) -> ScenarioRecord {
    ScenarioRecord(
      id: "test_scn", name: "Test Scenario",
      yamlDefinition: yaml, isPreset: true,
      createdAt: Date(), updatedAt: Date())
  }

  private func makeSimulation(
    modelIdentifier: String? = "Gemma 4 E2B (Q4_K_M)"
  ) -> SimulationRecord {
    SimulationRecord(
      id: "sim1", scenarioId: "test_scn",
      status: SimulationStatus.completed.rawValue,
      currentRound: 2, currentPhaseIndex: 0,
      stateJSON: "{}", configJSON: nil,
      createdAt: exportAt, updatedAt: exportAt,
      modelIdentifier: modelIdentifier, llmBackend: "llama.cpp")
  }

  private func makeTurn(
    round: Int, seq: Int, phase: String,
    agent: String?, fields: [String: String],
    phasePathJSON: String? = nil
  ) -> TurnRecord {
    let json =
      (try? JSONEncoder().encode(TurnOutput(fields: fields))).flatMap {
        String(data: $0, encoding: .utf8)
      } ?? "{}"
    return TurnRecord(
      id: UUID().uuidString, simulationId: "sim1",
      roundNumber: round, phaseType: phase,
      agentName: agent, rawOutput: json,
      parsedOutputJSON: json, sequenceNumber: seq,
      phasePathJSON: phasePathJSON,
      createdAt: Date())
  }

  private func makeCodePhaseEvent(
    round: Int, seq: Int, phase: String,
    payload: CodePhaseEventPayload,
    phasePathJSON: String? = nil
  ) -> CodePhaseEventRecord {
    let json =
      (try? JSONEncoder().encode(payload)).flatMap {
        String(data: $0, encoding: .utf8)
      } ?? "{}"
    return CodePhaseEventRecord(
      id: UUID().uuidString, simulationId: "sim1",
      roundNumber: round, phaseType: phase,
      sequenceNumber: seq, payloadJSON: json,
      phasePathJSON: phasePathJSON,
      createdAt: Date())
  }

  private func makeExporter(
    filter: ContentFilter = ContentFilter(blockedPatterns: [])
  ) -> YAMLReplayExporter {
    YAMLReplayExporter(contentFilter: filter, now: exportAt)
  }

  // MARK: - Shape

  @Test func emitsSchemaVersionAndTopLevelSections() throws {
    let exporter = makeExporter()
    let result = try exporter.export(
      .init(
        simulation: makeSimulation(), scenario: makeScenario(),
        turns: [], codePhaseEvents: []))

    #expect(result.text.contains("schema_version: 2"))
    #expect(result.text.contains("preset_ref:"))
    #expect(result.text.contains("metadata:"))
    #expect(result.text.contains("turns:"))
    // No code_phase_events section when empty
    #expect(!result.text.contains("code_phase_events:"))
  }

  @Test func writesFileToTempDirectory() throws {
    let exporter = makeExporter()
    let result = try exporter.export(
      .init(
        simulation: makeSimulation(), scenario: makeScenario(),
        turns: [], codePhaseEvents: []))

    #expect(FileManager.default.fileExists(atPath: result.fileURL.path))
    #expect(result.fileURL.pathExtension == "yaml")
    let onDisk = try String(contentsOf: result.fileURL, encoding: .utf8)
    #expect(onDisk == result.text)
  }

  // MARK: - SHA-256

  @Test func yamlSHA256IsLowercaseHexOfYAMLDefinition() throws {
    let exporter = makeExporter()
    let scenario = makeScenario()
    let expected = SHA256.hash(data: Data(scenario.yamlDefinition.utf8))
      .map { String(format: "%02x", $0) }.joined()

    let result = try exporter.export(
      .init(
        simulation: makeSimulation(), scenario: scenario,
        turns: [], codePhaseEvents: []))

    #expect(result.text.contains("yaml_sha256: '\(expected)'"))
  }

  // MARK: - ContentFilter at record time

  @Test func contentFilterRewritesTurnFieldValues() throws {
    let exporter = makeExporter(
      filter: ContentFilter(blockedPatterns: ["死ね"], replacement: "***"))
    let turn = makeTurn(
      round: 1, seq: 1, phase: "speak_all",
      agent: "Alice", fields: ["statement": "お前は死ね。"])

    let result = try exporter.export(
      .init(
        simulation: makeSimulation(), scenario: makeScenario(),
        turns: [turn], codePhaseEvents: []))

    #expect(result.text.contains("お前は***。"))
    #expect(!result.text.contains("お前は死ね。"))
  }

  @Test func contentFilterRewritesCodePhaseSummary() throws {
    let exporter = makeExporter(
      filter: ContentFilter(blockedPatterns: ["fuck"], replacement: "***"))
    let event = makeCodePhaseEvent(
      round: 2, seq: 5, phase: "summarize",
      payload: .summary(text: "fuck this"))

    let result = try exporter.export(
      .init(
        simulation: makeSimulation(), scenario: makeScenario(),
        turns: [], codePhaseEvents: [event]))

    #expect(result.text.contains("summary: '*** this'"))
    #expect(!result.text.contains("fuck this"))
  }

  @Test func contentFilterAppliedFlagAlwaysFalse() throws {
    // Spec §3.4: curator flips to `true` only after manual audit.
    let exporter = makeExporter()
    let result = try exporter.export(
      .init(
        simulation: makeSimulation(), scenario: makeScenario(),
        turns: [], codePhaseEvents: []))

    #expect(result.text.contains("content_filter_applied: false"))
  }

  // MARK: - Metadata

  @Test func metadataIncludesModelAndRecordedAt() throws {
    let exporter = makeExporter()
    let result = try exporter.export(
      .init(
        simulation: makeSimulation(modelIdentifier: "gemma4_e2b_q4km"),
        scenario: makeScenario(), turns: [], codePhaseEvents: []))

    #expect(result.text.contains("recorded_with_model: 'gemma4_e2b_q4km'"))
    #expect(result.text.contains("recorded_at: 2024-04-13T09:20:00Z"))
    #expect(result.text.contains("language: ja"))
  }

  @Test func metadataReflectsScenarioLanguageForEnglishScenario() throws {
    // Regression guard for the bundled L180 fix (#340 slice-5):
    // metadata previously hardcoded `language: ja` regardless of
    // scenario.language. After the fix, the metadata field follows
    // scenario.language so EN-scenario exports no longer emit
    // contradictory `language: ja` alongside locale-dependent
    // summary text.
    let enScenarioYAML = Self.baseScenarioYAML.replacingOccurrences(
      of: "language: ja", with: "language: en")
    let exporter = makeExporter()
    let result = try exporter.export(
      .init(
        simulation: makeSimulation(), scenario: makeScenario(yaml: enScenarioYAML),
        turns: [], codePhaseEvents: []))

    #expect(result.text.contains("language: en"))
    #expect(!result.text.contains("language: ja"))
  }

  @Test func metadataTotalTurnsCountsOnlyAgentRows() throws {
    let exporter = makeExporter()
    let turns = [
      makeTurn(round: 1, seq: 1, phase: "speak_all", agent: "Alice", fields: ["statement": "hi"]),
      makeTurn(round: 1, seq: 2, phase: "speak_all", agent: "Bob", fields: ["statement": "hi"]),
      // Legacy code-phase TurnRecord with nil agent — must not be counted.
      makeTurn(round: 1, seq: 3, phase: "score_calc", agent: nil, fields: [:])
    ]

    let result = try exporter.export(
      .init(
        simulation: makeSimulation(), scenario: makeScenario(),
        turns: turns, codePhaseEvents: []))

    #expect(result.text.contains("total_turns: 2"))
  }

  // MARK: - Structured payload preservation

  @Test func scoreUpdatePayloadEmitsStructuredStanza() throws {
    let exporter = makeExporter()
    let event = makeCodePhaseEvent(
      round: 2, seq: 5, phase: "score_calc",
      payload: .scoreUpdate(scores: ["Alice": 2, "Bob": 1]))

    let result = try exporter.export(
      .init(
        simulation: makeSimulation(), scenario: makeScenario(),
        turns: [], codePhaseEvents: [event]))

    #expect(result.text.contains("kind: scoreUpdate"))
    #expect(result.text.contains("Alice: 2"))
    #expect(result.text.contains("Bob: 1"))
  }

  @Test func voteResultsPayloadEmitsVotesAndTallies() throws {
    let exporter = makeExporter()
    let event = makeCodePhaseEvent(
      round: 1, seq: 3, phase: "vote",
      payload: .voteResults(
        votes: ["Alice": "Bob", "Bob": "Alice"],
        tallies: ["Alice": 1, "Bob": 1]))

    let result = try exporter.export(
      .init(
        simulation: makeSimulation(), scenario: makeScenario(),
        turns: [], codePhaseEvents: [event]))

    #expect(result.text.contains("kind: voteResults"))
    #expect(result.text.contains("votes:"))
    #expect(result.text.contains("tallies:"))
  }

  // MARK: - phase_index resolution

  @Test func phaseIndexAdvancesWhenPhaseTypeChanges() throws {
    let exporter = makeExporter()
    let turns = [
      makeTurn(round: 1, seq: 1, phase: "speak_all", agent: "Alice", fields: ["statement": "s"]),
      makeTurn(round: 1, seq: 2, phase: "speak_all", agent: "Bob", fields: ["statement": "s"]),
      makeTurn(round: 1, seq: 3, phase: "vote", agent: "Alice", fields: ["vote": "Bob"]),
      makeTurn(round: 1, seq: 4, phase: "vote", agent: "Bob", fields: ["vote": "Alice"])
    ]

    let result = try exporter.export(
      .init(
        simulation: makeSimulation(), scenario: makeScenario(),
        turns: turns, codePhaseEvents: []))

    // Scenario phases: [0=speak_all, 1=vote, 2=score_calc]
    let speakAllIndexLines = result.text
      .components(separatedBy: "\n")
      .filter { $0.contains("phase_index: 0") }.count
    let voteIndexLines = result.text
      .components(separatedBy: "\n")
      .filter { $0.contains("phase_index: 1") }.count
    #expect(speakAllIndexLines == 2)
    #expect(voteIndexLines == 2)
  }

  // MARK: - phase_index derivation (persisted path vs cursor fallback)

  /// Two ADJACENT phases of the same type — the shape the cursor cannot
  /// tell apart, since it only advances when the observed `phaseType`
  /// changes. Used as a control pair by the two tests below.
  private static let adjacentSameTypeScenarioYAML = """
    id: test_scn
    language: ja
    name: Test Scenario
    description: test
    agents: 2
    rounds: 2
    context: ctx
    personas:
      - name: Alice
        description: ''
      - name: Bob
        description: ''
    phases:
      - type: speak_all
        prompt: first
        output:
          statement: string
      - type: speak_all
        prompt: second
        output:
          statement: string
      - type: vote
        prompt: vote
        candidates: agents
    """

  private func phaseIndexLines(_ text: String) -> [String] {
    text.components(separatedBy: "\n")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { $0.hasPrefix("phase_index:") }
  }

  @Test func persistedPhasePathOverridesCursorDerivation() throws {
    // Both turns are `speak_all`, so the cursor holds at 0 for both. The
    // persisted paths say 0 and 1 — a value the cursor could not have
    // produced, which is what makes this discriminating rather than
    // agreeing-by-luck.
    let exporter = makeExporter()
    let turns = [
      makeTurn(
        round: 1, seq: 1, phase: "speak_all", agent: "Alice",
        fields: ["statement": "s"], phasePathJSON: "[0]"),
      makeTurn(
        round: 1, seq: 2, phase: "speak_all", agent: "Bob",
        fields: ["statement": "s"], phasePathJSON: "[1]")
    ]

    let result = try exporter.export(
      .init(
        simulation: makeSimulation(),
        scenario: makeScenario(yaml: Self.adjacentSameTypeScenarioYAML),
        turns: turns, codePhaseEvents: []))

    #expect(phaseIndexLines(result.text) == ["phase_index: 0", "phase_index: 1"])
  }

  @Test func preV6RowsStillCollapseViaCursorDerivation() throws {
    // The control for the test above: identical fixture, `phasePathJSON`
    // nil. Migration v6 added that column with no backfill, so these rows
    // must export exactly as they did before schema v2 — collapsed to the
    // first matching index, limitation and all. A failure here means the
    // fallback changed, not that the cursor is wrong.
    let exporter = makeExporter()
    let turns = [
      makeTurn(round: 1, seq: 1, phase: "speak_all", agent: "Alice", fields: ["statement": "s"]),
      makeTurn(round: 1, seq: 2, phase: "speak_all", agent: "Bob", fields: ["statement": "s"])
    ]

    let result = try exporter.export(
      .init(
        simulation: makeSimulation(),
        scenario: makeScenario(yaml: Self.adjacentSameTypeScenarioYAML),
        turns: turns, codePhaseEvents: []))

    #expect(phaseIndexLines(result.text) == ["phase_index: 0", "phase_index: 0"])
  }

  @Test func branchSubPhaseEventResolvesToItsPathNotTheConditional() throws {
    // `resolveEventPhaseIndices` has its own fallback, so it needs its own
    // pair. `summarize` is not a top-level phase of the base scenario, so
    // the pre-v6 lookup would land on `conditionalFallbackIndex` — which,
    // with no conditional present, is 0.
    let exporter = makeExporter()
    let withPath = makeCodePhaseEvent(
      round: 1, seq: 1, phase: "summarize",
      payload: .summary(text: "s"), phasePathJSON: "[1, 0]")
    let withoutPath = makeCodePhaseEvent(
      round: 1, seq: 1, phase: "summarize", payload: .summary(text: "s"))

    let resolved = try exporter.export(
      .init(
        simulation: makeSimulation(), scenario: makeScenario(),
        turns: [], codePhaseEvents: [withPath]))
    let fallback = try exporter.export(
      .init(
        simulation: makeSimulation(), scenario: makeScenario(),
        turns: [], codePhaseEvents: [withoutPath]))

    #expect(phaseIndexLines(resolved.text) == ["phase_index: 1"])
    #expect(phaseIndexLines(fallback.text) == ["phase_index: 0"])
  }

  // MARK: - phase_path emission (schema v2)

  @Test func turnWithPhasePathJSONEmitsPhasePathLine() throws {
    let exporter = makeExporter()
    let turns = [
      makeTurn(
        round: 1, seq: 1, phase: "speak_all", agent: "Alice",
        fields: ["statement": "s"], phasePathJSON: "[1, 0]")
    ]

    let result = try exporter.export(
      .init(
        simulation: makeSimulation(), scenario: makeScenario(),
        turns: turns, codePhaseEvents: []))

    #expect(result.text.contains("phase_path: [1, 0]"))
  }

  @Test func turnWithoutPhasePathJSONOmitsPhasePathLine() throws {
    // Pre-v6 rows have `phasePathJSON == nil` — the load-bearing case, since
    // the reader falls back to `[phase_index]` only when the line is absent.
    let exporter = makeExporter()
    let turns = [
      makeTurn(
        round: 1, seq: 1, phase: "speak_all", agent: "Alice",
        fields: ["statement": "s"])
    ]

    let result = try exporter.export(
      .init(
        simulation: makeSimulation(), scenario: makeScenario(),
        turns: turns, codePhaseEvents: []))

    // Paired with a positive assertion on `phase_index:`, which every
    // rendered entry emits unquoted: a bare `!contains` also passes when the
    // entry was never rendered, so absence alone is not evidence. (String
    // fields are single-quoted by `yamlValue`, so `agent: Alice` would not
    // have matched — measured, not assumed.)
    #expect(result.text.contains("phase_index:"))
    #expect(!result.text.contains("phase_path"))
  }

  @Test func codePhaseEventWithPhasePathJSONEmitsPhasePathLine() throws {
    let exporter = makeExporter()
    let events = [
      makeCodePhaseEvent(
        round: 1, seq: 1, phase: "score_calc",
        payload: .scoreUpdate(scores: ["Alice": 3]), phasePathJSON: "[2]")
    ]

    let result = try exporter.export(
      .init(
        simulation: makeSimulation(), scenario: makeScenario(),
        turns: [], codePhaseEvents: events))

    #expect(result.text.contains("phase_path: [2]"))
  }

  @Test func codePhaseEventWithoutPhasePathJSONOmitsPhasePathLine() throws {
    let exporter = makeExporter()
    let events = [
      makeCodePhaseEvent(
        round: 1, seq: 1, phase: "score_calc",
        payload: .scoreUpdate(scores: ["Alice": 3]))
    ]

    let result = try exporter.export(
      .init(
        simulation: makeSimulation(), scenario: makeScenario(),
        turns: [], codePhaseEvents: events))

    #expect(result.text.contains("phase_index:"))
    #expect(!result.text.contains("phase_path"))
  }

  @Test func emptyPersistedPathEmitsNoPhasePathLine() throws {
    // `phasePathJSON: "[]"` decodes to a non-nil EMPTY array — `phasePath`
    // nils out only on a nil / empty *string*. So `phasePath?.first` is nil and
    // `phase_index` comes from the cursor; emitting `phase_path: []` alongside
    // it would write the two fields from different sources and produce a
    // document violating spec §3.2's `phase_index == phase_path[0]`.
    let exporter = makeExporter()
    let turns = [
      makeTurn(
        round: 1, seq: 1, phase: "speak_all", agent: "Alice",
        fields: ["statement": "s"], phasePathJSON: "[]")
    ]

    let result = try exporter.export(
      .init(
        simulation: makeSimulation(), scenario: makeScenario(),
        turns: turns, codePhaseEvents: []))

    #expect(result.text.contains("phase_index:"))
    #expect(!result.text.contains("phase_path"))
  }

  @Test func emptyPersistedPathOnCodeEventEmitsNoPhasePathLine() throws {
    // The same fix landed at two emit sites; without this arm, deleting
    // `!path.isEmpty` from `renderCodePhaseEvents` alone leaves the suite
    // green — an unarmed half of the guard this branch added.
    let exporter = makeExporter()
    let events = [
      makeCodePhaseEvent(
        round: 1, seq: 1, phase: "score_calc",
        payload: .scoreUpdate(scores: ["Alice": 3]), phasePathJSON: "[]")
    ]

    let result = try exporter.export(
      .init(
        simulation: makeSimulation(), scenario: makeScenario(),
        turns: [], codePhaseEvents: events))

    #expect(result.text.contains("phase_index:"))
    #expect(!result.text.contains("phase_path"))
  }

  // MARK: - YAML emitter edge cases (Japanese / multi-line / control chars)

  @Test func japaneseStatementUsesSingleQuoted() throws {
    let exporter = makeExporter()
    let turn = makeTurn(
      round: 1, seq: 1, phase: "speak_all",
      agent: "Alice",
      fields: ["statement": "私は猫が好きだ。「にゃー」と言うから。"])

    let result = try exporter.export(
      .init(
        simulation: makeSimulation(), scenario: makeScenario(),
        turns: [turn], codePhaseEvents: []))

    #expect(
      result.text.contains(
        "statement: '私は猫が好きだ。「にゃー」と言うから。'"))
  }

  @Test func singleQuoteInsideStatementIsDoubled() throws {
    let exporter = makeExporter()
    let turn = makeTurn(
      round: 1, seq: 1, phase: "speak_all",
      agent: "Alice", fields: ["statement": "it's fine"])

    let result = try exporter.export(
      .init(
        simulation: makeSimulation(), scenario: makeScenario(),
        turns: [turn], codePhaseEvents: []))

    #expect(result.text.contains("statement: 'it''s fine'"))
  }

  @Test func multilineStatementUsesBlockLiteral() throws {
    let exporter = makeExporter()
    let turn = makeTurn(
      round: 1, seq: 1, phase: "speak_all",
      agent: "Alice", fields: ["statement": "line 1\nline 2"])

    let result = try exporter.export(
      .init(
        simulation: makeSimulation(), scenario: makeScenario(),
        turns: [turn], codePhaseEvents: []))

    // Block literal with strip (no trailing newline in source).
    #expect(result.text.contains("statement: |-"))
    #expect(result.text.contains("line 1"))
    #expect(result.text.contains("line 2"))
  }

  @Test func tabAndCRUseDoubleQuotedEscapes() throws {
    let exporter = makeExporter()
    let turn = makeTurn(
      round: 1, seq: 1, phase: "speak_all",
      agent: "Alice", fields: ["statement": "a\tb\rc"])

    let result = try exporter.export(
      .init(
        simulation: makeSimulation(), scenario: makeScenario(),
        turns: [turn], codePhaseEvents: []))

    #expect(result.text.contains("\"a\\tb\\rc\""))
  }

  // MARK: - Error surface

  @Test func invalidScenarioYAMLThrows() {
    let exporter = makeExporter()
    let bad = ScenarioRecord(
      id: "x", name: "x",
      yamlDefinition: "this is: not: valid: yaml: at: all",
      isPreset: true, createdAt: Date(), updatedAt: Date())

    #expect(throws: YAMLReplayExporterError.self) {
      _ = try exporter.export(
        .init(
          simulation: makeSimulation(), scenario: bad,
          turns: [], codePhaseEvents: []))
    }
  }

  // MARK: - Conditional sub-phase fallback

  @Test func subPhaseEventResolvesToConditionalIndex() throws {
    // Mirror the word_wolf preset shape: the tail `summarize` phases
    // live inside a `conditional` at index 5. The exporter must
    // resolve `summarize` code events to 5, not 0, so consumers can
    // still locate the enclosing phase context when rendering.
    let yaml = """
      id: cond_scn
      language: ja
      name: Conditional
      description: ''
      agents: 2
      rounds: 1
      context: ''
      personas:
        - name: Alice
          description: ''
        - name: Bob
          description: ''
      phases:
        - type: assign
        - type: speak_each
          prompt: s
          rounds: 1
          output: { statement: string }
        - type: vote
          prompt: v
          candidates: agents
        - type: eliminate
        - type: score_calc
          logic: vote_tally
        - type: conditional
          if: max_score >= 1
          then:
            - type: summarize
              template: '{{winner}} wins'
          else:
            - type: summarize
              template: 'no winner'
      """
    let scenario = ScenarioRecord(
      id: "cond_scn", name: "Conditional",
      yamlDefinition: yaml, isPreset: true,
      createdAt: Date(), updatedAt: Date())
    let event = makeCodePhaseEvent(
      round: 1, seq: 10, phase: "summarize",
      payload: .summary(text: "Alice wins"))

    let result = try makeExporter().export(
      .init(
        simulation: makeSimulation(), scenario: scenario,
        turns: [], codePhaseEvents: [event]))

    // conditional lives at index 5 in the phases array above.
    #expect(result.text.contains("phase_index: 5"))
    #expect(!result.text.contains("phase_index: 0\n    phase_type: 'summarize'"))
  }

  @Test func emptyTurnsEmitsEmptyList() throws {
    let exporter = makeExporter()
    let result = try exporter.export(
      .init(
        simulation: makeSimulation(), scenario: makeScenario(),
        turns: [], codePhaseEvents: []))

    #expect(result.text.contains("turns: []"))
  }
}

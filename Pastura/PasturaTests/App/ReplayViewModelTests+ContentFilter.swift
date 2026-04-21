import Foundation
import Testing

@testable import Pastura

// ContentFilter scope tests for `ReplayViewModel` — split from
// `ReplayViewModelTests.swift` to stay under the 250-line
// `type_body_length` cap. Extension (not new `@Suite`) per
// `.claude/rules/testing.md`: a second suite would race against the
// first on shared test-process state.
extension ReplayViewModelTests {

  // MARK: - ContentFilter narrow scope

  @Test func filtersAgentOutputFieldValues() async throws {
    let yaml = """
      schema_version: 1
      turns:
        - round: 1
          phase_index: 0
          phase_type: speak_all
          agent: Alice
          fields: { statement: 'oh shit that hurt' }
      """
    let source = try YAMLReplaySource(
      yaml: yaml, scenario: Self.makeScenario(), config: Self.fastConfig)
    let viewModel = ReplayViewModel(
      sources: [source], config: Self.fastConfig, contentFilter: ContentFilter())
    viewModel.start()
    await Self.waitForState(viewModel) { _ in viewModel.agentOutputs.count >= 1 }
    #expect(viewModel.agentOutputs.count == 1)
    // Default ContentFilter has "shit" in its blocklist — confirm it
    // was filtered in the rendered output.
    let statement = viewModel.agentOutputs[0].output.statement ?? ""
    #expect(!statement.lowercased().contains("shit"))
    #expect(statement.contains("***"))
  }

  @Test func doesNotFilterAgentNameThroughElimination() async throws {
    // Round-trip asserting the VM's filter scope: even when a persona
    // name is a blocklist literal, the `.elimination.agent` field must
    // pass through untouched. We can't observe `.elimination` on the
    // VM's `agentOutputs` directly (that event goes through `apply()`
    // into a no-op branch in PR1) — instead we verify that the
    // scenario's personas stay referable by name in `agentOutputs`
    // after filtering. Concretely: a persona named "Shit" publishing
    // a `.agentOutput` should have `entry.agent == "Shit"` — only
    // `entry.output.fields.values` is filtered.
    let scenarioWithColliderYAML = """
      id: ts
      name: Test
      description: ''
      agents: 2
      rounds: 1
      context: ''
      personas:
        - name: Shit
          description: ''
        - name: Alice
          description: ''
      phases:
        - type: speak_all
          prompt: say
          output:
            statement: string
      """
    let scenario = try ScenarioLoader().load(yaml: scenarioWithColliderYAML)
    let yaml = """
      schema_version: 1
      turns:
        - round: 1
          phase_index: 0
          phase_type: speak_all
          agent: Shit
          fields: { statement: 'clean content' }
      """
    let source = try YAMLReplaySource(
      yaml: yaml, scenario: scenario, config: Self.fastConfig)
    let filter = ContentFilter(blockedPatterns: ["shit"], replacement: "XXX")
    let viewModel = ReplayViewModel(
      sources: [source], config: Self.fastConfig, contentFilter: filter)
    viewModel.start()
    await Self.waitForState(viewModel) { _ in viewModel.agentOutputs.count >= 1 }
    // Persona name survives; only `fields.*` values route through the
    // filter. "clean content" has no blocked substring so it stays
    // verbatim.
    #expect(viewModel.agentOutputs[0].agent == "Shit")
    #expect(viewModel.agentOutputs[0].output.statement == "clean content")
  }

  // MARK: - Persistence absence (spec §4.2)

  @Test func constructorAcceptsNoPersistenceParameters() throws {
    // This test's mere existence is the contract: the public init
    // signature is `(sources:config:contentFilter:)` — no repository,
    // no DB writer, no EventStore-style sink. If a future change tries
    // to add one, this file will fail to compile in an obvious place,
    // prompting a spec §4.2 revisit.
    let source = try Self.makeSource()
    _ = ReplayViewModel(
      sources: [source], config: Self.fastConfig,
      contentFilter: ContentFilter())
  }
}

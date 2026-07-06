import Foundation
import Testing

@testable import Pastura

// MARK: - relationship_update affinity injection (#910)
//
// Sibling-file extension per the testing.md split convention — NOT a new
// @Suite (a second suite would run in parallel against the same shared state
// class; see PR #157). Helpers (`builder`, `makeScenario`) stay at internal
// access in PromptBuilderTests.swift so this file can see them.
extension PromptBuilderTests {

  private func speakPhase() -> Phase {
    Phase(type: .speakAll, prompt: "Go!", outputSchema: ["statement": "string"])
  }

  // MARK: - injectRelationships

  @Test func injectRelationshipsSetsRelationshipsFromNamespacedKey() {
    var variables = ["relationships_Alice": "You are wary of Bob."]
    builder.injectRelationships(into: &variables, personaName: "Alice")
    #expect(variables["relationships"] == "You are wary of Bob.")
  }

  @Test func injectRelationshipsSetsEmptyStringOnMiss() {
    var variables: [String: String] = [:]
    builder.injectRelationships(into: &variables, personaName: "Alice")
    #expect(variables["relationships"] == "")
  }

  // MARK: - System-prompt private-relationships section

  @Test func systemPromptContainsRelationshipsSectionWhenSet() {
    let scenario = makeScenario()
    var state = SimulationState.initial(for: scenario)
    state.variables["relationships_Alice"] = "SENTINEL_REL_WARY"

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0],
      phase: speakPhase(), state: state
    )
    #expect(prompt.contains("あなたの人間関係"))
    #expect(prompt.contains("SENTINEL_REL_WARY"))
  }

  @Test func systemPromptOmitsRelationshipsSectionWhenUnset() {
    let scenario = makeScenario()
    let state = SimulationState.initial(for: scenario)

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0],
      phase: speakPhase(), state: state
    )
    #expect(!prompt.contains("あなたの人間関係"))
  }

  @Test func systemPromptOmitsRelationshipsSectionWhenEmpty() {
    // An empty summary (no relationship crossed the verbalizer threshold)
    // must not render an empty header, mirroring the reflect / whisper guards.
    let scenario = makeScenario()
    var state = SimulationState.initial(for: scenario)
    state.variables["relationships_Alice"] = ""

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0],
      phase: speakPhase(), state: state
    )
    #expect(!prompt.contains("あなたの人間関係"))
  }
}

import Testing

@testable import Pastura

/// Parse coverage for the per-phase `max_sentences:` key (#881) — guards the
/// literal YAML key name, which a serializer↔loader round-trip alone cannot
/// (a symmetric mis-key would still round-trip).
extension ScenarioLoaderTests {
  @Test func parsesMaxSentencesOnPhase() throws {
    let yaml = """
      id: t
      language: ja
      name: T
      description: d
      agents: 2
      rounds: 1
      context: c
      personas:
        - name: Alice
          description: a
        - name: Bob
          description: b
      phases:
        - type: speak_each
          prompt: "Speak."
          max_sentences: 5
          output:
            statement: string
        - type: speak_all
          prompt: "Speak."
          output:
            statement: string
      """
    let scenario = try loader.load(yaml: yaml)
    #expect(scenario.phases[0].maxSentences == 5)
    // Absent key → nil (no backward-compat fill).
    #expect(scenario.phases[1].maxSentences == nil)
  }
}

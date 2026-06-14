import Foundation
import Testing

@testable import Pastura

/// Cross-resolver consistency for the per-phase private-thought field (#609).
///
/// Two resolvers name the THINKING-section source: the committed-display path
/// uses `ScenarioConventions.thoughtField(for: phaseType)` (phase-driven) and
/// the live-streaming path uses `OutputSchema.thoughtFieldName` (schema-driven,
/// the secondary key the phase's `output:` actually declares). They agree as
/// long as each phase authors at most one secondary key. This suite pins that
/// invariant across every bundled preset, so a future preset that authors both
/// `inner_thought` and `reason` on one phase (the sole divergence case) fails
/// here at commit time rather than as a silent live-vs-replay UI discrepancy.
@Suite(.timeLimit(.minutes(1)))
struct ThoughtFieldResolverConsistencyTests {
  @Test func bundledPresetsAgreeOnThoughtFieldAcrossResolvers() throws {
    let bundle = Bundle(for: ThoughtFieldResolverConsistencyAnchor.self)
    let loader = ScenarioLoader()

    for fileName in PresetLoader.presetFileNames {
      let url = try #require(
        bundle.url(forResource: fileName, withExtension: "yaml")
          ?? Bundle.main.url(forResource: fileName, withExtension: "yaml"),
        "preset \(fileName).yaml not found in test or app bundle")
      let scenario = try loader.load(yaml: try String(contentsOf: url, encoding: .utf8))

      for phase in scenario.phases {
        // Only LLM phases that declare a secondary key are constrained —
        // when the schema declares none, `thoughtFieldName` is nil and the
        // streaming path falls back to the default key (no inconsistency).
        guard let schemaThought = OutputSchema.from(phase: phase)?.thoughtFieldName
        else { continue }
        #expect(
          schemaThought == ScenarioConventions.thoughtField(for: phase.type),
          """
          \(fileName): phase \(phase.type.rawValue) — schema-derived thought \
          field '\(schemaThought)' disagrees with phase-driven \
          '\(ScenarioConventions.thoughtField(for: phase.type) ?? "nil")'
          """)
      }
    }
  }
}

/// Class anchor for `Bundle(for:)` lookup against the test target — preset
/// YAMLs live in the app bundle, not the simulator UI runner's `Bundle.main`.
private final class ThoughtFieldResolverConsistencyAnchor {}

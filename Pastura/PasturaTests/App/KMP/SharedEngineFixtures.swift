import Foundation
import PasturaSharedEngine

@testable import Pastura

/// Shared inputs for the tests that drive a **real bundled preset** through the
/// Kotlin engine (ADR-023 §5, S5-2 PR-B, #1647).
///
/// Factored out of ``SharedEngineEndToEndTests`` because the same scenario and
/// the same scripted answers are reused by the suspension-relay test that
/// parks the mock mid-run — two suites, one fixture, so a preset swap moves one
/// file rather than two.
///
/// Kotlin twins are spelled `PasturaSharedEngine.X`
/// (`.claude/rules/kmp-interop.md` Pattern 1b).
enum SharedEngineFixtures {

  /// The bundled preset these fixtures drive.
  ///
  /// `target_score_race` is the smallest shipped preset that still has ≥ 2
  /// agents — the Kotlin `SimulationEngine` short-circuits a 1-agent run
  /// (`activeCount < 2`) and would complete with **zero** LLM calls, which
  /// would make every backend assertion vacuous. Its four phases are
  /// `speak_all` / `vote` / `score_calc` / `conditional(summarize)`, so exactly
  /// two of them cost inferences and the script below is derivable rather than
  /// transcribed.
  static let presetFileName = "target_score_race"

  /// Parses the bundled preset through the **Kotlin** loader.
  ///
  /// The point of the whole fixture: `PasturaSharedEngine.ScenarioLoader` gets
  /// its first non-synthetic caller here, so a YAML shape the Swift loader
  /// accepts and the Kotlin one does not fails loudly instead of waiting for
  /// S5-4 to flip the run path.
  ///
  /// `Bundle(for: DatabaseManager.self)` rather than `.main`: under
  /// `xcodebuild test` the main bundle is the test runner, which carries no
  /// presets (the same lookup `PresetLoaderTests` uses).
  static func loadedPreset() throws -> PasturaSharedEngine.Scenario {
    let bundle = Bundle(for: DatabaseManager.self)
    guard let url = bundle.url(forResource: presetFileName, withExtension: "yaml") else {
      throw FixtureError.presetNotBundled(presetFileName)
    }
    let yaml = try String(contentsOf: url, encoding: .utf8)
    return try PasturaSharedEngine.ScenarioLoader().load(yaml: yaml)
  }

  /// How many LLM calls a complete run of `scenario` costs.
  ///
  /// Derived, not transcribed: Kotlin's own `InferenceEstimator` is an
  /// `internal object` and reaches no header, so the count is recomputed here
  /// from the shape this preset actually has — every round runs one `speak_all`
  /// and one `vote`, each one inference per agent, and the remaining phases are
  /// code phases costing zero. A preset swap that changes that shape must
  /// change this function too; ``SharedEngineEndToEndTests`` asserts the run
  /// consumed exactly this many, so a stale count reddens rather than silently
  /// over-scripting.
  static func expectedInferenceCount(for scenario: PasturaSharedEngine.Scenario) -> Int {
    Int(scenario.rounds) * scenario.personas.count * 2
  }

  /// Schema-valid JSON answers for a whole run, in call order.
  ///
  /// `MockLLMService.responses` is positional, so the order matters: per round
  /// the engine issues the `speak_all` turns for every agent and then the
  /// `vote` turns for every agent, in persona order.
  ///
  /// Two properties are load-bearing beyond "it parses":
  ///
  /// - **Every vote names a real other agent.** The phase sets
  ///   `exclude_self: true`, and a self-vote or an unknown name is rejected and
  ///   retried, which shifts every later index of a positional script.
  /// - **Each answer's natural-language fields are ≥ 12 unicode scalars of
  ///   Japanese.** Below that `LLMCaller` skips the ADR-010 Step E adherence
  ///   check outright (`MIN_DETECTION_LENGTH`), so the injected detector seam
  ///   would never be consulted and the test that asserts it is live would be
  ///   asserting nothing.
  static func scriptedResponses(for scenario: PasturaSharedEngine.Scenario) -> [String] {
    let names = scenario.personas.map(\.name)
    var responses: [String] = []
    for round in 1...Int(scenario.rounds) {
      responses.append(contentsOf: names.map { speakAllAnswer(agent: $0, round: round) })
      responses.append(
        contentsOf: names.indices.map { voteAnswer(target: names[($0 + 1) % names.count]) })
    }
    return responses
  }

  private static func speakAllAnswer(agent: String, round: Int) -> String {
    """
    {"statement": "\(agent)です。ラウンド\(round)は着実に得点を積み上げていきます。", \
    "inner_thought": "焦らずに周りの動きを観察してから動くのが得策だろう。"}
    """
  }

  private static func voteAnswer(target: String) -> String {
    """
    {"vote": "\(target)", \
    "reason": "\(target)さんの発言が今回のラウンドで最も筋が通っていたからです。"}
    """
  }

  enum FixtureError: Error {
    case presetNotBundled(String)
  }
}

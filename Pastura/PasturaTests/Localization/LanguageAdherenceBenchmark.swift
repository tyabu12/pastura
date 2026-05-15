import Foundation
import Testing

@testable import Pastura

// MARK: - Configuration

/// Reads `LanguageAdherenceBenchmark` settings from environment variables.
///
/// Mirrors `LlamaCppIntegrationTests`' env-gate shape so the harness can
/// be enabled in the same Xcode scheme block (see `Pastura.xcscheme`
/// item 7). The benchmark is **off by default** — both flags must be
/// set explicitly:
///
/// ```
/// LANGUAGE_ADHERENCE_BENCHMARK=1 \
///   LLAMACPP_QWEN_MODEL_PATH=/path/to/Qwen3-4B-Q4_K_M.gguf \
///   xcodebuild test -scheme Pastura -project Pastura/Pastura.xcodeproj \
///   -destination "$DEST" \
///   -only-testing PasturaTests/LanguageAdherenceBenchmark
/// ```
///
/// `LANGUAGE_ADHERENCE_BENCHMARK` is independent from
/// `LLAMACPP_INTEGRATION` because this harness pre-builds the runner
/// with `NLLanguageDetector()` injected — the LlamaCpp integration
/// suite is orthogonal and may be enabled / disabled independently.
private enum BenchmarkConfig {
  static var isEnabled: Bool {
    guard ProcessInfo.processInfo.environment["LANGUAGE_ADHERENCE_BENCHMARK"] == "1" else {
      return false
    }
    guard let path = ProcessInfo.processInfo.environment["LLAMACPP_QWEN_MODEL_PATH"],
      !path.isEmpty
    else {
      return false
    }
    return true
  }

  static var modelPath: String {
    ProcessInfo.processInfo.environment["LLAMACPP_QWEN_MODEL_PATH"] ?? ""
  }
}

// MARK: - Benchmark Harness

/// ADR-010 Step E PR2 item 6 — measures `(JSON parse success %, adherence %)`
/// per (preset × agent) under `LlamaCppService` Qwen 3 4B Q4_K_M.
///
/// The harness is local-developer-run only: CI does NOT enable
/// `LANGUAGE_ADHERENCE_BENCHMARK` (memory `feedback_ci_time_budget`).
/// Each `@Test` carries its own `.timeLimit(.minutes(5))` to bound
/// real-LLM inference per preset; the suite has no `.timeLimit` trait
/// (testing.md integration-suite exception — the tighter suite-level
/// bound would mis-fire on the per-test cap).
///
/// Run output (CSV-like, one line per `.agentOutput` event observed):
/// ```
/// LANG_BENCH preset=word_wolf_en agent=Alice expected=en detected=en parsedOK=1
/// LANG_BENCH preset=word_wolf_en agent=Bob expected=en detected=ja parsedOK=1
/// ...
/// LANG_BENCH_SUMMARY preset=word_wolf_en agents=4 parseOK=4 adherent=3 \
///   parseRate=1.00 adherenceRate=0.75
/// ```
///
/// Aggregation is intentionally minimal — the summary line is parseable
/// by a follow-up `scripts/analyze-streaming-diag.sh`-style script if
/// item 9's ADR pin needs cross-run aggregation. For PR2 we capture
/// the per-run baseline into ADR-010 §D5 / Out-of-Scope (item 9 fork).
@Suite(.serialized)
struct LanguageAdherenceBenchmark {

  // MARK: - Per-preset @Tests

  @Test(
    "EN preset: word_wolf_en",
    .enabled(if: BenchmarkConfig.isEnabled),
    .timeLimit(.minutes(5))
  )
  func wordWolfEn() async throws {
    try await runBenchmark(presetFilename: "word_wolf_en", expectedLanguage: "en")
  }

  @Test(
    "EN preset: bokete_en",
    .enabled(if: BenchmarkConfig.isEnabled),
    .timeLimit(.minutes(5))
  )
  func boketeEn() async throws {
    try await runBenchmark(presetFilename: "bokete_en", expectedLanguage: "en")
  }

  @Test(
    "EN preset: prisoners_dilemma_en",
    .enabled(if: BenchmarkConfig.isEnabled),
    .timeLimit(.minutes(5))
  )
  func prisonersDilemmaEn() async throws {
    try await runBenchmark(presetFilename: "prisoners_dilemma_en", expectedLanguage: "en")
  }

  @Test(
    "EN preset: target_score_race_en",
    .enabled(if: BenchmarkConfig.isEnabled),
    .timeLimit(.minutes(5))
  )
  func targetScoreRaceEn() async throws {
    try await runBenchmark(presetFilename: "target_score_race_en", expectedLanguage: "en")
  }

  @Test(
    "Cross-language: word_wolf (ja) + simulation_language=en",
    .enabled(if: BenchmarkConfig.isEnabled),
    .timeLimit(.minutes(5))
  )
  func crossLanguageWordWolf() async throws {
    // Load the JA preset, then layer simulation_language=en on top so
    // Engine emits English prompts for a JA scenario (ADR-010 D5
    // resolver). This exercises the cross-language path the EN
    // bundled presets cannot reach by themselves.
    let scenario = try loadPreset(filename: "word_wolf", overrideSimulationLanguage: "en")
    try await runBenchmark(scenario: scenario, expectedLanguage: "en", label: "word_wolf+sim_en")
  }

  // MARK: - Helpers

  private func runBenchmark(presetFilename: String, expectedLanguage: String) async throws {
    let scenario = try loadPreset(filename: presetFilename, overrideSimulationLanguage: nil)
    try await runBenchmark(
      scenario: scenario, expectedLanguage: expectedLanguage, label: presetFilename)
  }

  private func runBenchmark(scenario: Scenario, expectedLanguage: String, label: String)
    async throws {
    let service = makeQwenService()
    try await service.loadModel()
    defer { Task { try? await service.unloadModel() } }

    let detector = NLLanguageDetector()
    let runner = SimulationRunner(detector: detector)

    var parseOK = 0
    var adherent = 0
    var totalAgentOutputs = 0
    let suspendController = SuspendController()
    let events = await collectAllEvents(
      runner.run(scenario: scenario, llm: service, suspendController: suspendController))

    for event in events {
      guard case .agentOutput(let agent, let output, _) = event else { continue }
      totalAgentOutputs += 1
      // Parse OK is implied: only fully-parsed outputs reach `.agentOutput`.
      parseOK += 1
      let joined = output.fields.values.joined(separator: "\n")
      let detected = detector.detect(text: joined)
      let parsedOKInt = 1
      let isAdherent = (detected == expectedLanguage)
      if isAdherent { adherent += 1 }
      print(
        "LANG_BENCH preset=\(label) agent=\(agent) expected=\(expectedLanguage) "
          + "detected=\(detected ?? "nil") parsedOK=\(parsedOKInt) adherent=\(isAdherent ? 1 : 0)"
      )
    }

    // Mismatch events fired by LLMCaller after the adherence retry exhausted.
    // Counted separately from per-output rate above to give the run-level
    // signal independent of count-of-outputs.
    let mismatchEventCount = events.reduce(0) { count, event in
      if case .languageMismatch = event { return count + 1 }
      return count
    }

    // Avoid divide-by-zero on empty runs (e.g., validation-rejected scenarios).
    let parseRate =
      totalAgentOutputs > 0 ? Double(parseOK) / Double(totalAgentOutputs) : 0
    let adherenceRate =
      totalAgentOutputs > 0 ? Double(adherent) / Double(totalAgentOutputs) : 0
    print(
      "LANG_BENCH_SUMMARY preset=\(label) agents=\(totalAgentOutputs) parseOK=\(parseOK) "
        + "adherent=\(adherent) mismatchEvents=\(mismatchEventCount) "
        + "parseRate=\(String(format: "%.2f", parseRate)) "
        + "adherenceRate=\(String(format: "%.2f", adherenceRate))"
    )
    // No #expect assertions on the rates themselves — item 9 pins the
    // measured baseline into ADR-010. This @Test passes as long as the
    // run completes without throwing.
  }

  private func makeQwenService() -> LlamaCppService {
    // Mirror `ModelRegistry.qwen34B` to stay in lockstep with production.
    LlamaCppService(
      modelPath: BenchmarkConfig.modelPath,
      stopSequence: "<|im_end|>",
      modelIdentifier: "Qwen 3 4B (Q4_K_M)",
      systemPromptSuffix: "/no_think",
      assistantPrefix: "<think>\n\n</think>\n\n"
    )
  }

  /// Loads a bundled preset YAML and optionally overrides
  /// `simulationLanguage`. The override path constructs a new
  /// `Scenario` so we don't mutate the bundled file on disk.
  private func loadPreset(filename: String, overrideSimulationLanguage: String?) throws -> Scenario {
    let bundle = Bundle(for: LanguageAdherenceBenchmarkAnchor.self)
    guard
      let url = bundle.url(forResource: filename, withExtension: "yaml")
        ?? Bundle.main.url(forResource: filename, withExtension: "yaml")
    else {
      throw BenchmarkError.presetNotFound(filename)
    }
    let yaml = try String(contentsOf: url, encoding: .utf8)
    let base = try ScenarioLoader().load(yaml: yaml)
    guard let override = overrideSimulationLanguage else { return base }
    return Scenario(
      id: base.id,
      name: base.name,
      description: base.description,
      language: base.language,
      simulationLanguage: override,
      agentCount: base.agentCount,
      rounds: base.rounds,
      context: base.context,
      personas: base.personas,
      phases: base.phases,
      extraData: base.extraData
    )
  }

  enum BenchmarkError: Error, CustomStringConvertible {
    case presetNotFound(String)
    var description: String {
      switch self {
      case .presetNotFound(let name):
        return "Preset YAML '\(name).yaml' not found in test bundle or app bundle"
      }
    }
  }
}

/// Class anchor for `Bundle(for:)` lookup against the test target.
/// `Bundle.main` is the simulator UI runner during tests, not the app
/// bundle — anchor on a class declared in the test module so resource
/// lookup falls through to the test target's bundle first.
private final class LanguageAdherenceBenchmarkAnchor {}

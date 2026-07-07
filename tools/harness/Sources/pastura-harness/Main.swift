import Foundation
import PasturaCore
import PasturaHarnessKit

/// Headless simulation harness CLI (ADR-013). Runs one scenario YAML
/// through the Engine with real llama.cpp inference and writes a JSONL
/// run log. Exit codes: 0 = run ok, 1 = run failed (recorded in the log),
/// 2 = configuration error.
@main
enum Main {
  static func main() async {
    let args = Array(CommandLine.arguments.dropFirst())
    // `lint` is an inference-free subcommand (ADR-022 D6) — it never touches
    // HarnessConfig / --model, so branch before the run-mode arg parse to keep
    // the existing run CLI contract untouched.
    if args.first == "lint" {
      runLint(paths: Array(args.dropFirst()))
    }

    let config: HarnessConfig
    do {
      config = try HarnessConfig.parse(args)
    } catch let error as HarnessConfigError {
      FileHandle.standardError.write(Data((error.message + "\n").utf8))
      exit(2)
    } catch {
      FileHandle.standardError.write(Data("\(error)\n".utf8))
      exit(2)
    }

    do {
      let summary = try await run(config: config)
      exit(summary.status == .ok ? 0 : 1)
    } catch let error as HarnessConfigError {
      FileHandle.standardError.write(Data((error.message + "\n").utf8))
      exit(2)
    } catch {
      FileHandle.standardError.write(Data("\(error)\n".utf8))
      exit(2)
    }
  }

  /// Runs the inference-free `lint` subcommand and exits (ADR-022 D6).
  /// Exit codes: 0 = clean, 1 = errors / failures found, 2 = usage error.
  private static func runLint(paths: [String]) -> Never {
    guard !paths.isEmpty else {
      FileHandle.standardError.write(Data((LintBatchRunner.usage + "\n").utf8))
      exit(2)
    }
    let report = LintBatchRunner.run(paths: paths)
    print(report.humanReadable())
    exit(report.hasFailure ? 1 : 0)
  }

  private static func run(config: HarnessConfig) async throws -> RunSummary {
    guard FileManager.default.fileExists(atPath: config.modelPath) else {
      throw HarnessConfigError("model file not found: \(config.modelPath)")
    }
    if let warning = config.profile.mismatchWarning(forModelPath: config.modelPath) {
      FileHandle.standardError.write(Data("\(warning)\n".utf8))
    }
    let yaml = try String(contentsOfFile: config.scenarioPath, encoding: .utf8)
    let scenario = try ScenarioLoader().load(yaml: yaml)

    let now = Date()
    let runID = Self.runID(at: now)
    let outPath = config.outPath ?? defaultOutPath(runID: runID, at: now)
    let writer = try FileRunLogWriter(path: outPath)

    let profile = config.profile
    let llmFactory = makeLLMFactory(profile: profile, modelPath: config.modelPath)
    let quiet = config.quiet
    // if/else instead of `quiet ? nil : { ... }` — the ternary trips a
    // "failed to produce diagnostic" compiler bug (Swift 6.3.2) when
    // inferring an optional @Sendable closure.
    var progress: (@Sendable (String) -> Void)?
    if !quiet {
      progress = { print("[pastura-harness] \($0)") }
    }
    let runner = HarnessRunner(
      llmFactory: llmFactory,
      writer: writer,
      timeoutSeconds: config.timeoutSeconds,
      progress: progress)

    if !quiet {
      print("[pastura-harness] scenario: \(scenario.name) (\(scenario.id))")
      print("[pastura-harness] log: \(outPath)")
    }
    let summary = await runner.execute(
      scenario: scenario, runID: runID,
      startDate: ISO8601DateFormatter().string(from: now),
      modelName: profile.name)
    print(
      "[pastura-harness] \(summary.status.rawValue) after \(summary.attempts) attempt(s) "
        + "in \(String(format: "%.1f", summary.durationSec))s"
        + (summary.error.map { " — \($0)" } ?? ""))
    return summary
  }

  private static func makeLLMFactory(
    profile: ModelProfile, modelPath: String
  ) -> HarnessRunner.LLMFactory {
    return { () -> any LLMService in
      LlamaCppService(
        modelPath: modelPath,
        stopSequence: profile.stopSequence,
        modelIdentifier: profile.name,
        systemPromptSuffix: profile.systemPromptSuffix,
        assistantPrefix: profile.assistantPrefix)
    }
  }

  /// `yyyyMMdd-HHmmss-xxxx` — sortable and unique enough for one machine.
  private static func runID(at date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    let suffix = String(format: "%04x", UInt16.random(in: .min ... .max))
    return "\(formatter.string(from: date))-\(suffix)"
  }

  private static func defaultOutPath(runID: String, at date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return "data/factory/runs/\(formatter.string(from: date))/\(runID).jsonl"
  }
}

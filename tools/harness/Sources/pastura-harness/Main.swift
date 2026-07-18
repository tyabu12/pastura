import Foundation
import PasturaCore
import PasturaHarnessKit

#if canImport(FoundationModels)
  import FoundationModels
#endif

/// Headless simulation harness CLI (ADR-013). Runs one scenario YAML
/// through the Engine with real llama.cpp inference and writes a JSONL
/// run log. Exit codes: 0 = run ok, 1 = run failed (recorded in the log),
/// 2 = configuration error.
@main
enum Main {
  static func main() async {
    let args = Array(CommandLine.arguments.dropFirst())
    // `lint` is an inference-free subcommand (ADR-024 D6) — it never touches
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

  /// Runs the inference-free `lint` subcommand and exits (ADR-024 D6).
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
    // Resolve the backend factory + run-log model name FIRST. The
    // `LLMFactory` closure can neither throw nor return nil, so every
    // backend-availability rejection (missing GGUF, Foundation Models
    // unavailable or not built into this binary) must surface here, upstream
    // of the factory.
    let (llmFactory, modelName) = try resolveBackend(config)

    let yaml = try String(contentsOfFile: config.scenarioPath, encoding: .utf8)
    let scenario = try ScenarioLoader().load(yaml: yaml)

    let now = Date()
    let runID = Self.runID(at: now)
    let outPath = config.outPath ?? defaultOutPath(runID: runID, at: now)
    let writer = try FileRunLogWriter(path: outPath)

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
      modelName: modelName)
    print(
      "[pastura-harness] \(summary.status.rawValue) after \(summary.attempts) attempt(s) "
        + "in \(String(format: "%.1f", summary.durationSec))s"
        + (summary.error.map { " — \($0)" } ?? ""))
    return summary
  }

  /// Resolves the configured backend into an `LLMFactory` + a run-log model
  /// name, performing ALL availability rejection here because the factory
  /// (`@Sendable () -> any LLMService`) can neither throw nor return nil.
  private static func resolveBackend(
    _ config: HarnessConfig
  ) throws -> (factory: HarnessRunner.LLMFactory, modelName: String) {
    switch config.backend {
    case .llamaCpp:
      guard FileManager.default.fileExists(atPath: config.modelPath) else {
        throw HarnessConfigError("model file not found: \(config.modelPath)")
      }
      if let warning = config.profile.mismatchWarning(forModelPath: config.modelPath) {
        FileHandle.standardError.write(Data("\(warning)\n".utf8))
      }
      let profile = config.profile
      let modelPath = config.modelPath
      let factory: HarnessRunner.LLMFactory = {
        LlamaCppService(
          modelPath: modelPath,
          stopSequence: profile.stopSequence,
          modelIdentifier: profile.name,
          systemPromptSuffix: profile.systemPromptSuffix,
          assistantPrefix: profile.assistantPrefix)
      }
      return (factory, profile.name)

    case .foundationModels:
      #if canImport(FoundationModels)
        if #available(macOS 26, *) {
          // `HarnessConfig.Guardrails` is a plain enum with no FoundationModels
          // import — the `SystemLanguageModel` construction stays confined to
          // this `#if canImport` block so the config type keeps compiling on
          // toolchains without the macOS 26 SDK.
          //
          // Both arms construct through `init(guardrails:)`, and the model and
          // the run-log label derive from the same `config.guardrails` value.
          // Two reasons, both learned from #1156's invalid battery:
          //
          // 1. The label used to be a hand-written literal in this tuple,
          //    independent of what the factory built — which is exactly how six
          //    cells logged "(permissive)" while every session ran default
          //    guardrails. Deriving both from one value means neither can drift
          //    from the *request* on its own. It is not a guarantee the label
          //    matches the model: `SystemLanguageModel` exposes no `guardrails`
          //    accessor, so a model-derived label is unreachable, and the
          //    `switch` below stays an unverified mapping — miswire it and the
          //    label lies again, one hop upstream. The battery remains its only
          //    control.
          // 2. The default arm used to call `FoundationModelsService()`, i.e.
          //    the STATIC `SystemLanguageModel.default`, while the permissive
          //    arm called `init(guardrails:)`. That left the A/B differing in
          //    construction path as well as guardrails. Whether the static and
          //    the initializer are equivalent is not knowable from the SDK
          //    interface, so the arms are made symmetric instead of assumed so.
          //
          // The instance is now built once and shared across `llmFactory()`
          // calls (i.e. across `HarnessRunner`'s retry attempts) rather than
          // per-call. That matches the old default arm, whose static `.default`
          // was always process-shared — so this is more symmetric, not less.
          let guardrails: SystemLanguageModel.Guardrails
          switch config.guardrails {
          case .default: guardrails = .default
          case .permissive: guardrails = .permissiveContentTransformations
          }
          let model = SystemLanguageModel(guardrails: guardrails)
          let maxResponseTokens = config.maxResponseTokens
          let guidedGeneration = config.guidedGeneration
          let factory: HarnessRunner.LLMFactory = {
            FoundationModelsService(
              model: model, maximumResponseTokens: maxResponseTokens,
              guidedGeneration: guidedGeneration)
          }
          // Label derives from the same `config` values passed into the
          // factory above (`foundationModelsRunLabel`) — see the #1156 note
          // just above for why hand-writing a parallel literal here would
          // reopen the drift it describes, now across two more dimensions.
          return (factory, config.foundationModelsRunLabel)
        } else {
          throw HarnessConfigError(
            "--backend \(HarnessConfig.Backend.foundationModels.rawValue) requires macOS 26 or later"
          )
        }
      #else
        throw HarnessConfigError(
          "this pastura-harness was built without FoundationModels support "
            + "(needs the macOS 26 SDK)")
      #endif
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

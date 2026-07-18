import Foundation

/// Error thrown by ``HarnessConfig/parse(_:)`` with a user-facing message.
package struct HarnessConfigError: Error, Equatable {
  /// Human-readable description of what is wrong with the arguments.
  package let message: String

  package init(_ message: String) {
    self.message = message
  }
}

/// Parsed command-line configuration for one harness invocation.
package struct HarnessConfig: Sendable, Equatable {
  /// Inference backend the run drives.
  package enum Backend: String, Sendable, Equatable, CaseIterable {
    /// On-device llama.cpp over a GGUF file (the default; needs `--model`).
    case llamaCpp = "llama-cpp"
    /// Apple Foundation Model (iOS 26 / macOS 26 system model, #1072). Has no
    /// GGUF file, so `--model` is optional and any `--profile` is ignored.
    case foundationModels = "foundation-models"
  }

  /// Path to the scenario YAML (preset schema).
  package var scenarioPath: String
  /// Absolute path to the GGUF model file. Empty for the
  /// ``Backend/foundationModels`` backend, which has no model file.
  package var modelPath: String
  /// Output JSONL path; `nil` lets the caller derive the default
  /// `data/factory/runs/<date>/<run_id>.jsonl`.
  package var outPath: String?
  /// Per-scenario wall-clock budget. Default is generous because
  /// on-device-class inference is slow (45 inferences ≈ tens of minutes).
  package var timeoutSeconds: Int = 1800
  /// Suppress per-event progress on stdout.
  package var quiet = false
  /// Prompt-format profile applied to the `--model` GGUF. Defaults to
  /// Gemma so existing callers (`run_scenario.sh`, scenario-refine) stay
  /// unchanged. Ignored for the ``Backend/foundationModels`` backend.
  package var profile: ModelProfile = .gemma4E2B
  /// Inference backend. Defaults to ``Backend/llamaCpp`` so existing callers
  /// stay unchanged.
  package var backend: Backend = .llamaCpp

  /// Apple Foundation Models guardrail mode (spike #1072 correction: Apple
  /// exposes an adjustment API — `SystemLanguageModel.Guardrails
  /// .permissiveContentTransformations` — the original spike wrongly assumed
  /// there was none). This is a PLAIN enum with no `FoundationModels` import:
  /// that framework only exists in the macOS 26 SDK, and this file must stay
  /// buildable on toolchains without it (the CI "Harness package build" job).
  /// FM type references live only in `Main.swift`'s `#if canImport(FoundationModels)` block.
  package enum Guardrails: String, Sendable, Equatable, CaseIterable {
    /// Apple's default content guardrails (unchanged behaviour).
    case `default`
    /// `SystemLanguageModel.Guardrails.permissiveContentTransformations`.
    case permissive
  }

  /// Foundation Models guardrail mode. Ignored for the
  /// ``Backend/llamaCpp`` backend, which has no guardrail concept.
  package var guardrails: Guardrails = .default

  /// Foundation Models `maximumResponseTokens` cap. `nil` keeps the SDK
  /// default. Ignored for the ``Backend/llamaCpp`` backend.
  package var maxResponseTokens: Int?
  /// Foundation Models guided-generation mode. Ignored for the
  /// ``Backend/llamaCpp`` backend.
  package var guidedGeneration = false

  package static let usage = """
    usage: pastura-harness --scenario <path.yaml> [--model <path.gguf>] \
    [--backend <id>] [--out <path.jsonl>] [--timeout <seconds>] [--quiet] [--profile <id>] \
    [--guardrails <id>] [--max-response-tokens <n>] [--guided-generation]
    --backend selects the inference backend (default: \(Backend.llamaCpp.rawValue); \
    also: \(Backend.foundationModels.rawValue)). --model is required for \
    \(Backend.llamaCpp.rawValue) and ignored for \(Backend.foundationModels.rawValue).
    --profile selects prompt-format hints and must match the --model file's \
    model family (default: \(ModelProfile.gemma4E2B.id))
    --guardrails selects the Foundation Models guardrail mode (default: \
    \(Guardrails.default.rawValue); also: \(Guardrails.permissive.rawValue)). \
    Ignored for the \(Backend.llamaCpp.rawValue) backend.
    --max-response-tokens caps the Foundation Models response length \
    (default: unset, uses the SDK default). Ignored for the \(Backend.llamaCpp.rawValue) backend.
    --guided-generation enables Foundation Models guided generation. Ignored for the \
    \(Backend.llamaCpp.rawValue) backend.
    """

  /// Mutable accumulator for ``parse(_:)``'s argument loop.
  ///
  /// The arms are split across two `apply*` methods — paths vs run options —
  /// rather than living in one switch inside `parse`. A single switch put
  /// `parse` over the cyclomatic-complexity limit the moment `--guardrails`
  /// was added, and folding every arm into one helper would sit exactly AT
  /// the limit, so the next flag would break it again.
  private struct Accumulator {
    var scenario: String?
    var model: String?
    var out: String?
    var timeout = 1800
    var quiet = false
    var profile = ModelProfile.gemma4E2B
    var backend = Backend.llamaCpp
    var guardrails = Guardrails.default
    var maxResponseTokens: Int?
    var guidedGeneration = false

    mutating func apply(
      _ arg: String, from iterator: inout IndexingIterator<[String]>
    ) throws {
      if try applyPathFlag(arg, from: &iterator) { return }
      if try applyOptionFlag(arg, from: &iterator) { return }
      if try applyFoundationModelsFlag(arg, from: &iterator) { return }
      throw HarnessConfigError("unknown argument '\(arg)'\n\(usage)")
    }

    /// - Returns: `true` when `arg` was a path flag this consumed.
    private mutating func applyPathFlag(
      _ arg: String, from iterator: inout IndexingIterator<[String]>
    ) throws -> Bool {
      switch arg {
      case "--scenario": scenario = try HarnessConfig.value(for: arg, from: &iterator)
      case "--model": model = try HarnessConfig.value(for: arg, from: &iterator)
      case "--out": out = try HarnessConfig.value(for: arg, from: &iterator)
      default: return false
      }
      return true
    }

    /// - Returns: `true` when `arg` was a run-option flag this consumed.
    private mutating func applyOptionFlag(
      _ arg: String, from iterator: inout IndexingIterator<[String]>
    ) throws -> Bool {
      switch arg {
      case "--timeout":
        timeout = try HarnessConfig.parseTimeout(HarnessConfig.value(for: arg, from: &iterator))
      case "--quiet": quiet = true
      case "--profile":
        profile = try HarnessConfig.parseProfile(HarnessConfig.value(for: arg, from: &iterator))
      case "--backend":
        backend = try HarnessConfig.parseBackend(HarnessConfig.value(for: arg, from: &iterator))
      case "--guardrails":
        guardrails = try HarnessConfig.parseGuardrails(
          HarnessConfig.value(for: arg, from: &iterator))
      default: return false
      }
      return true
    }

    /// - Returns: `true` when `arg` was a Foundation Models tuning flag this
    ///   consumed. Split out from `applyOptionFlag` to stay under the
    ///   cyclomatic-complexity limit (see the note above `apply`).
    private mutating func applyFoundationModelsFlag(
      _ arg: String, from iterator: inout IndexingIterator<[String]>
    ) throws -> Bool {
      switch arg {
      case "--max-response-tokens":
        maxResponseTokens = try HarnessConfig.parseMaxResponseTokens(
          HarnessConfig.value(for: arg, from: &iterator))
      case "--guided-generation": guidedGeneration = true
      default: return false
      }
      return true
    }
  }

  /// Parses CLI arguments (excluding argv[0]).
  package static func parse(_ args: [String]) throws -> HarnessConfig {
    var accumulator = Accumulator()
    var iterator = args.makeIterator()
    while let arg = iterator.next() {
      try accumulator.apply(arg, from: &iterator)
    }

    guard let scenario = accumulator.scenario else {
      throw HarnessConfigError("--scenario is required\n\(usage)")
    }
    let modelPath = try resolveModelPath(accumulator.model, backend: accumulator.backend)
    return HarnessConfig(
      scenarioPath: scenario, modelPath: modelPath, outPath: accumulator.out,
      timeoutSeconds: accumulator.timeout, quiet: accumulator.quiet,
      profile: accumulator.profile, backend: accumulator.backend,
      guardrails: accumulator.guardrails, maxResponseTokens: accumulator.maxResponseTokens,
      guidedGeneration: accumulator.guidedGeneration)
  }

  /// Run-log label for the Foundation Models backend, derived from the same
  /// guardrails/guided-generation/max-tokens values used to construct the
  /// `FoundationModelsService` — so a run's log line and its actual request
  /// shape cannot independently drift (#1156 taught that a hand-written label
  /// can silently stop matching the request it describes).
  package var foundationModelsRunLabel: String {
    var label = "Apple Foundation Model (\(guardrails.rawValue)"
    if guidedGeneration {
      label += ", guided"
    }
    if let maxResponseTokens {
      label += ", maxtok=\(maxResponseTokens)"
    }
    label += ")"
    return label
  }

  /// The effective model path: `--model` is required for the GGUF-backed
  /// llama.cpp backend, and empty for Foundation Models (no model file).
  private static func resolveModelPath(_ model: String?, backend: Backend) throws -> String {
    switch backend {
    case .llamaCpp:
      guard let model else {
        throw HarnessConfigError(
          "--model is required for backend '\(Backend.llamaCpp.rawValue)'\n\(usage)")
      }
      return model
    case .foundationModels:
      return model ?? ""
    }
  }

  private static func value(
    for flag: String, from iterator: inout IndexingIterator<[String]>
  ) throws -> String {
    guard let value = iterator.next() else {
      throw HarnessConfigError("missing value for \(flag)\n\(usage)")
    }
    return value
  }

  private static func parseTimeout(_ raw: String) throws -> Int {
    guard let parsed = Int(raw), parsed > 0 else {
      throw HarnessConfigError("--timeout must be a positive integer, got '\(raw)'")
    }
    return parsed
  }

  private static func parseProfile(_ raw: String) throws -> ModelProfile {
    guard let resolved = ModelProfile.named(raw) else {
      let knownIDs = ModelProfile.all.map(\.id).joined(separator: ", ")
      throw HarnessConfigError(
        "unknown --profile '\(raw)' — known profiles: \(knownIDs)\n\(usage)")
    }
    return resolved
  }

  private static func parseBackend(_ raw: String) throws -> Backend {
    guard let resolved = Backend(rawValue: raw) else {
      let knownIDs = Backend.allCases.map(\.rawValue).joined(separator: ", ")
      throw HarnessConfigError(
        "unknown --backend '\(raw)' — known backends: \(knownIDs)\n\(usage)")
    }
    return resolved
  }

  private static func parseGuardrails(_ raw: String) throws -> Guardrails {
    guard let resolved = Guardrails(rawValue: raw) else {
      let knownIDs = Guardrails.allCases.map(\.rawValue).joined(separator: ", ")
      throw HarnessConfigError(
        "unknown --guardrails '\(raw)' — known guardrails: \(knownIDs)\n\(usage)")
    }
    return resolved
  }

  private static func parseMaxResponseTokens(_ raw: String) throws -> Int {
    guard let parsed = Int(raw), parsed > 0 else {
      throw HarnessConfigError(
        "--max-response-tokens must be a positive integer, got '\(raw)'\n\(usage)")
    }
    return parsed
  }
}

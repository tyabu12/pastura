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

  package static let usage = """
    usage: pastura-harness --scenario <path.yaml> [--model <path.gguf>] \
    [--backend <id>] [--out <path.jsonl>] [--timeout <seconds>] [--quiet] [--profile <id>]
    --backend selects the inference backend (default: \(Backend.llamaCpp.rawValue); \
    also: \(Backend.foundationModels.rawValue)). --model is required for \
    \(Backend.llamaCpp.rawValue) and ignored for \(Backend.foundationModels.rawValue).
    --profile selects prompt-format hints and must match the --model file's \
    model family (default: \(ModelProfile.gemma4E2B.id))
    """

  /// Parses CLI arguments (excluding argv[0]).
  package static func parse(_ args: [String]) throws -> HarnessConfig {
    var scenario: String?
    var model: String?
    var out: String?
    var timeout = 1800
    var quiet = false
    var profile = ModelProfile.gemma4E2B
    var backend = Backend.llamaCpp

    var iterator = args.makeIterator()
    while let arg = iterator.next() {
      switch arg {
      case "--scenario": scenario = try value(for: arg, from: &iterator)
      case "--model": model = try value(for: arg, from: &iterator)
      case "--out": out = try value(for: arg, from: &iterator)
      case "--timeout": timeout = try parseTimeout(value(for: arg, from: &iterator))
      case "--quiet": quiet = true
      case "--profile": profile = try parseProfile(value(for: arg, from: &iterator))
      case "--backend": backend = try parseBackend(value(for: arg, from: &iterator))
      default: throw HarnessConfigError("unknown argument '\(arg)'\n\(usage)")
      }
    }

    guard let scenario else { throw HarnessConfigError("--scenario is required\n\(usage)") }
    let modelPath = try resolveModelPath(model, backend: backend)
    return HarnessConfig(
      scenarioPath: scenario, modelPath: modelPath, outPath: out,
      timeoutSeconds: timeout, quiet: quiet, profile: profile, backend: backend)
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
}

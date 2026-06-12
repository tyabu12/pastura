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
  /// Path to the scenario YAML (preset schema).
  package var scenarioPath: String
  /// Absolute path to the GGUF model file.
  package var modelPath: String
  /// Output JSONL path; `nil` lets the caller derive the default
  /// `data/factory/runs/<date>/<run_id>.jsonl`.
  package var outPath: String?
  /// Per-scenario wall-clock budget. Default is generous because
  /// on-device-class inference is slow (45 inferences ≈ tens of minutes).
  package var timeoutSeconds: Int = 1800
  /// Suppress per-event progress on stdout.
  package var quiet = false

  package static let usage = """
    usage: pastura-harness --scenario <path.yaml> --model <path.gguf> \
    [--out <path.jsonl>] [--timeout <seconds>] [--quiet]
    """

  /// Parses CLI arguments (excluding argv[0]).
  package static func parse(_ args: [String]) throws -> HarnessConfig {
    var scenario: String?
    var model: String?
    var out: String?
    var timeout = 1800
    var quiet = false

    var iterator = args.makeIterator()
    while let arg = iterator.next() {
      switch arg {
      case "--scenario": scenario = try value(for: arg, from: &iterator)
      case "--model": model = try value(for: arg, from: &iterator)
      case "--out": out = try value(for: arg, from: &iterator)
      case "--timeout":
        let raw = try value(for: arg, from: &iterator)
        guard let parsed = Int(raw), parsed > 0 else {
          throw HarnessConfigError("--timeout must be a positive integer, got '\(raw)'")
        }
        timeout = parsed
      case "--quiet": quiet = true
      default: throw HarnessConfigError("unknown argument '\(arg)'\n\(usage)")
      }
    }

    guard let scenario else { throw HarnessConfigError("--scenario is required\n\(usage)") }
    guard let model else { throw HarnessConfigError("--model is required\n\(usage)") }
    return HarnessConfig(
      scenarioPath: scenario, modelPath: model, outPath: out,
      timeoutSeconds: timeout, quiet: quiet)
  }

  private static func value(
    for flag: String, from iterator: inout IndexingIterator<[String]>
  ) throws -> String {
    guard let value = iterator.next() else {
      throw HarnessConfigError("missing value for \(flag)\n\(usage)")
    }
    return value
  }
}

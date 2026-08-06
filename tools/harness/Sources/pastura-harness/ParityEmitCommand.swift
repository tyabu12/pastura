import Foundation
import PasturaHarnessKit

/// The `parity-emit` subcommand (ADR-023 Stage 4).
///
/// Lives outside `Main` so that enum stays under the `type_body_length` cap —
/// the CLI has accumulated three inference-free subcommands and `Main` was
/// already near the limit.
///
/// Paths resolve against the current directory, so every mode must run from the
/// repository root — the same contract `emit-golden` already uses.
enum ParityEmitCommand {

  private static let usage = """
    usage: pastura-harness parity-emit [--write | --check]

      (no flag)  print the generated Kotlin source to stdout
      --write    write it to \(ParityFixtureEmitter.generatedPath)
      --check    fail if the committed file differs from a fresh generation
    """

  /// Runs the subcommand and exits.
  ///
  /// Exit codes: 0 = printed / written / no drift, 1 = drift found or a fixture
  /// could not be produced, 2 = usage error.
  static func run(args: [String]) async -> Never {
    // Reject an unknown flag BEFORE running the fixtures: each drives a full
    // Engine run, and a usage error that costs one reads as a hang.
    switch args.first {
    case nil, "--write", "--check":
      break
    default:
      FileHandle.standardError.write(Data((usage + "\n").utf8))
      exit(2)
    }

    let generated: String
    do {
      var fixtures: [ParityFixtureEmitter.Fixture] = []
      for spec in ParityFixtureEmitter.specs {
        fixtures.append(try await ParityFixtureEmitter.run(spec))
      }
      generated = try ParityFixtureEmitter.kotlinSource(from: fixtures)
    } catch {
      FileHandle.standardError.write(Data("\(error)\n".utf8))
      exit(1)
    }

    let path = ParityFixtureEmitter.generatedPath
    switch args.first {
    case "--write":
      write(generated, to: path)
    case "--check":
      checkDrift(expected: generated, at: path)
    default:
      print(generated)
      exit(0)
    }
  }

  private static func write(_ generated: String, to path: String) -> Never {
    do {
      try generated.write(toFile: path, atomically: true, encoding: .utf8)
      print("wrote \(path)")
      exit(0)
    } catch {
      FileHandle.standardError.write(Data("could not write \(path): \(error)\n".utf8))
      exit(1)
    }
  }

  /// Compares the committed golden against a fresh generation and exits.
  ///
  /// Exit codes: 0 = up to date, 1 = missing or stale. A read failure is drift,
  /// not a crash: an absent generated file is one of the two states this gate
  /// exists to catch.
  private static func checkDrift(expected: String, at path: String) -> Never {
    let committed = try? String(contentsOfFile: path, encoding: .utf8)
    if committed == expected {
      print("\(path) is up to date")
      exit(0)
    }
    let diagnosis =
      committed == nil
      ? "\(path) is missing — it has never been generated in this checkout."
      : """
      \(path) is stale.
      The Swift Engine's behaviour changed without the parity goldens being regenerated.
      """
    FileHandle.standardError.write(
      Data(
        """
        \(diagnosis)
        Regenerate from the repository root: \(ParityFixtureEmitter.regenerateCommand)

        """.utf8))
    exit(1)
  }
}

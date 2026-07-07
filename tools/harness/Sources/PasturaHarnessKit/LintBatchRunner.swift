import Foundation
import PasturaCore

/// The outcome of linting a single scenario YAML file (ADR-022 D6).
///
/// A file passes through three gates in order — parse, validate, lint — and
/// the outcome records the first blocking gate it hit, or the lint findings
/// (possibly empty) when it reached the linter.
package enum LintFileOutcome: Sendable, Equatable {
  /// `ScenarioLoader.load` threw — structural / type-mapping failure.
  case parseFailure(String)
  /// `ScenarioValidator.validate` threw — hard-limit / phase-shape failure.
  case validatorFailure(String)
  /// The file reached the semantic linter; carries every finding (empty = clean).
  case findings([LintFinding])
}

/// One file's lint report: its path plus the gate outcome.
package struct LintFileReport: Sendable {
  /// The file-system path that produced this report.
  package let path: String
  /// What happened when the file was run through the lint pipeline.
  package let outcome: LintFileOutcome

  package init(path: String, outcome: LintFileOutcome) {
    self.path = path
    self.outcome = outcome
  }

  /// Error-severity findings only (empty for parse/validator failures, which
  /// are counted separately by ``LintBatchReport``).
  private var errorFindings: [LintFinding] {
    guard case .findings(let findings) = outcome else { return [] }
    return findings.filter { $0.severity == .error }
  }

  /// Warning-severity findings on this file.
  private var warningFindings: [LintFinding] {
    guard case .findings(let findings) = outcome else { return [] }
    return findings.filter { $0.severity == .warning }
  }

  /// Whether this file is exit-worthy: a parse failure, a validator failure,
  /// or at least one error-severity lint finding. Warnings/info never fail.
  package var isFailure: Bool {
    switch outcome {
    case .parseFailure, .validatorFailure: return true
    case .findings(let findings): return findings.contains { $0.severity == .error }
    }
  }

  /// Whether this file is fully clean (reached the linter with no findings).
  package var isClean: Bool {
    if case .findings(let findings) = outcome { return findings.isEmpty }
    return false
  }

  /// Number of error-level problems on this file (parse/validator failure = 1;
  /// otherwise the count of error-severity findings).
  package var errorCount: Int {
    switch outcome {
    case .parseFailure, .validatorFailure: return 1
    case .findings: return errorFindings.count
    }
  }

  /// Number of warning-severity findings on this file.
  package var warningCount: Int { warningFindings.count }

  /// Human-readable block for this file: a status line plus indented reasons.
  package func humanReadable() -> String {
    if isClean { return "✔ \(path)" }

    let marker = isFailure ? "✘" : "⚠"
    var lines = ["\(marker) \(path)"]
    switch outcome {
    case .parseFailure(let message):
      lines.append("    parse error: \(message)")
    case .validatorFailure(let message):
      lines.append("    validation error: \(message)")
    case .findings(let findings):
      for finding in findings {
        let sev: String
        switch finding.severity {
        case .error: sev = "error"
        case .warning: sev = "warning"
        case .info: sev = "info"
        }
        // finding.message already leads with the ruleID — don't print it twice.
        lines.append("    [\(sev)] \(finding.message)")
      }
    }
    return lines.joined(separator: "\n")
  }
}

/// Aggregate report over a batch of linted files (ADR-022 D6).
package struct LintBatchReport: Sendable {
  /// Per-file reports, in the order the files were linted.
  package let files: [LintFileReport]

  package init(files: [LintFileReport]) {
    self.files = files
  }

  /// Total error-level problems across all files (parse + validator failures +
  /// error-severity findings).
  package var errorCount: Int { files.reduce(0) { $0 + $1.errorCount } }

  /// Total warning-severity findings across all files.
  package var warningCount: Int { files.reduce(0) { $0 + $1.warningCount } }

  /// Whether the batch is exit-worthy — any file failed. Warnings alone do not.
  package var hasFailure: Bool { files.contains { $0.isFailure } }

  /// The full human-readable report: one block per file, then a summary line.
  package func humanReadable() -> String {
    var blocks = files.map { $0.humanReadable() }
    blocks.append("\(files.count) files, \(errorCount) errors, \(warningCount) warnings")
    return blocks.joined(separator: "\n")
  }
}

/// Inference-free batch linter for scenario YAML files (ADR-022 D6).
///
/// Runs each file through `ScenarioLoader` → `ScenarioValidator` →
/// `ScenarioSemanticLinter`, mirroring the load-time gate order the app uses,
/// with no LLM in the loop. Powers the `pastura-harness lint` subcommand and
/// the CI zero-false-positive gate.
package enum LintBatchRunner {
  /// One-line usage string for the `lint` subcommand.
  package static let usage = """
    usage: pastura-harness lint <path>...
      Lint scenario YAML files with no inference. Each <path> is a file or a
      directory (expanded to its *.yaml files, non-recursive, sorted).
      Exit 0 = clean, 1 = errors / failures found, 2 = usage error.
    """

  /// Lints a batch of file-or-directory paths.
  ///
  /// Directories expand to their direct `*.yaml` children (non-recursive,
  /// sorted); file paths are linted as-is. Paths are processed in argument
  /// order, with each directory's expansion inserted in place.
  ///
  /// - Parameters:
  ///   - paths: File or directory paths to lint.
  ///   - fileManager: Injected for testability; defaults to `.default`.
  /// - Returns: The aggregate batch report.
  package static func run(
    paths: [String], fileManager: FileManager = .default
  ) -> LintBatchReport {
    let expanded = expand(paths: paths, fileManager: fileManager)
    let reports = expanded.map { path -> LintFileReport in
      let outcome: LintFileOutcome
      do {
        let yaml = try String(contentsOfFile: path, encoding: .utf8)
        outcome = lint(yaml: yaml)
      } catch {
        outcome = .parseFailure("cannot read file: \(message(for: error))")
      }
      return LintFileReport(path: path, outcome: outcome)
    }
    return LintBatchReport(files: reports)
  }

  /// Lints a single YAML string through the full load → validate → lint path.
  ///
  /// Testable disk-free entry point; also the per-file body used by ``run(paths:fileManager:)``.
  ///
  /// - Parameter yaml: The scenario YAML source.
  /// - Returns: The gate outcome for this YAML.
  package static func lint(yaml: String) -> LintFileOutcome {
    let scenario: Scenario
    do {
      scenario = try ScenarioLoader().load(yaml: yaml)
    } catch {
      return .parseFailure(message(for: error))
    }
    do {
      _ = try ScenarioValidator().validate(scenario)
    } catch {
      return .validatorFailure(message(for: error))
    }
    return .findings(ScenarioSemanticLinter().lint(scenario))
  }

  /// Expands directory paths to their sorted `*.yaml` children; passes files
  /// through unchanged. Unreadable directories yield the original path so the
  /// per-file read surfaces the failure as a parse error.
  private static func expand(
    paths: [String], fileManager: FileManager
  ) -> [String] {
    var result: [String] = []
    for path in paths {
      var isDirectory: ObjCBool = false
      let exists = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
      if exists && isDirectory.boolValue {
        let children = (try? fileManager.contentsOfDirectory(atPath: path)) ?? []
        let yamls =
          children
          .filter { $0.hasSuffix(".yaml") }
          .sorted()
          .map { (path as NSString).appendingPathComponent($0) }
        result.append(contentsOf: yamls)
      } else {
        result.append(path)
      }
    }
    return result
  }

  /// Prefers a `LocalizedError`'s description, else stringifies the error.
  private static func message(for error: Error) -> String {
    if let localized = (error as? LocalizedError)?.errorDescription {
      return localized
    }
    return String(describing: error)
  }
}

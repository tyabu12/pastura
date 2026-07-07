import Foundation
import Testing

@testable import PasturaHarnessKit

@Suite(.timeLimit(.minutes(1)))
struct LintBatchRunnerTests {

  // MARK: - Fixtures

  /// `event_reactive` correctly paired with a dict-shaped `event_inject`
  /// keeping the default `as:` — R5's passing case (ADR-022 D6 caveat: no
  /// shipped YAML exercises `event_reactive`, so R5 needs synthetic fixtures).
  private static let r5CleanYAML = """
    id: r5_clean
    language: en
    name: R5 Clean
    description: Event-reactive scoring correctly paired with a dict event_inject.
    agents: 2
    rounds: 1
    context: A minimal test scenario.
    events:
      - text: "A storm rewards caution."
        favors: cooperate
    personas:
      - name: Alice
        description: A careful agent.
      - name: Bob
        description: A bold agent.
    phases:
      - type: event_inject
        source: events
      - type: score_calc
        logic: event_reactive
    """

  /// `event_reactive` with a NON-qualifying `event_inject` (custom `as:`, so
  /// the favored variable is never written under the name the scorer reads) —
  /// R5's tripping case.
  private static let r5ViolatingYAML = """
    id: r5_violating
    language: en
    name: R5 Violating
    description: Event-reactive scoring with a custom-`as` event_inject.
    agents: 2
    rounds: 1
    context: A minimal test scenario.
    events:
      - text: "A storm rewards caution."
        favors: cooperate
    personas:
      - name: Alice
        description: A careful agent.
      - name: Bob
        description: A bold agent.
    phases:
      - type: event_inject
        source: events
        as: my_event
      - type: score_calc
        logic: event_reactive
    """

  /// Structurally broken YAML — `ScenarioLoader.load` throws (missing `phases`
  /// and other required fields).
  private static let parseFailureYAML = """
    id: broken
    this is not: [a, valid, scenario
    """

  /// `choose` without `options` → R7 warning only (non-fatal), no errors.
  private static let warningsOnlyYAML = """
    id: warn_only
    language: en
    name: Warnings Only
    description: A choose phase without options.
    agents: 2
    rounds: 1
    context: A minimal test scenario.
    personas:
      - name: Alice
        description: A careful agent.
      - name: Bob
        description: A bold agent.
    phases:
      - type: choose
        prompt: "Pick an action."
        output:
          action: string
    """

  private static let r5RuleID = "event-reactive-needs-event-inject"

  // MARK: - Single-YAML entry point

  @Test func r5CleanYAMLLintsClean() {
    let outcome = LintBatchRunner.lint(yaml: Self.r5CleanYAML)
    guard case .findings(let findings) = outcome else {
      Issue.record("expected .findings, got \(outcome)")
      return
    }
    #expect(findings.isEmpty)
  }

  @Test func r5ViolatingYAMLProducesR5Error() {
    let outcome = LintBatchRunner.lint(yaml: Self.r5ViolatingYAML)
    guard case .findings(let findings) = outcome else {
      Issue.record("expected .findings, got \(outcome)")
      return
    }
    let r5Finding = findings.first { $0.ruleID == Self.r5RuleID }
    #expect(r5Finding != nil)
    #expect(r5Finding?.severity == .error)
  }

  @Test func parseFailureYAMLIsParseFailure() {
    let outcome = LintBatchRunner.lint(yaml: Self.parseFailureYAML)
    guard case .parseFailure = outcome else {
      Issue.record("expected .parseFailure, got \(outcome)")
      return
    }
  }

  @Test func warningsOnlyYAMLIsNonFatal() {
    let outcome = LintBatchRunner.lint(yaml: Self.warningsOnlyYAML)
    guard case .findings(let findings) = outcome else {
      Issue.record("expected .findings, got \(outcome)")
      return
    }
    #expect(findings.allSatisfy { $0.severity != .error })
    #expect(findings.contains { $0.severity == .warning })
  }

  // MARK: - Directory expansion + aggregation

  @Test func directoryBatchAggregatesAcrossFiles() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("lint-batch-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let files: [(String, String)] = [
      ("a_clean.yaml", Self.r5CleanYAML),
      ("b_violating.yaml", Self.r5ViolatingYAML),
      ("c_parsefail.yaml", Self.parseFailureYAML),
      ("d_warn.yaml", Self.warningsOnlyYAML),
      // Non-YAML sibling must be ignored by the non-recursive *.yaml expansion.
      ("notes.txt", "ignore me")
    ]
    for (name, content) in files {
      try content.write(
        to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    let report = LintBatchRunner.run(paths: [dir.path])

    // Four YAMLs expanded (the .txt is excluded), sorted by name.
    #expect(report.files.count == 4)
    #expect(
      report.files.map { ($0.path as NSString).lastPathComponent }
        == ["a_clean.yaml", "b_violating.yaml", "c_parsefail.yaml", "d_warn.yaml"])

    // Aggregate: R5 error + parse failure = 2 errors; R7 = 1 warning.
    #expect(report.hasFailure)
    #expect(report.errorCount == 2)
    #expect(report.warningCount == 1)

    #expect(report.files[0].isClean)
    #expect(report.files[1].isFailure)
    #expect(report.files[2].isFailure)
    #expect(report.files[3].isFailure == false)
    #expect(report.files[3].warningCount == 1)

    let text = report.humanReadable()
    #expect(text.contains("✔ "))
    #expect(text.contains("✘ "))
    #expect(text.contains("⚠ "))
    #expect(text.contains("4 files, 2 errors, 1 warnings"))
  }

  @Test func filePathPassesThroughUnexpanded() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("lint-file-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let file = dir.appendingPathComponent("clean.yaml")
    try Self.r5CleanYAML.write(to: file, atomically: true, encoding: .utf8)

    let report = LintBatchRunner.run(paths: [file.path])
    #expect(report.files.count == 1)
    #expect(report.hasFailure == false)
    #expect(report.files[0].isClean)
  }
}

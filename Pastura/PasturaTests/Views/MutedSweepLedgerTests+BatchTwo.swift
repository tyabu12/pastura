import Foundation
import Testing

// Batch 2's applied-site pin, split out of `MutedSweepLedgerTests.swift` at
// SwiftLint's 400-line ceiling (`testing.md` § "Splitting a Suite Across
// Files") — an extension of that suite, never a second `@Suite`.

extension MutedSweepLedgerTests {

  /// One batch-2 (#1448) repointed site, anchored by a literal that is unique
  /// among its file's **non-comment** lines. The repointed `.foregroundStyle`
  /// sits within `window` non-comment lines after that anchor.
  ///
  /// Comment lines are dropped before the window is measured, so inserting or
  /// growing a why-comment cannot slide a site out of its own window — which
  /// batch 2 did to all eight files. A line-anchored table could not have
  /// survived its own commit.
  private struct BatchTwoSite {
    let path: String
    let anchor: String
    let window: Int

    init(_ path: String, _ anchor: String, window: Int) {
      self.path = path
      self.anchor = anchor
      self.window = window
    }
  }

  /// The nineteen sites the ledger § 5 marks `B2`, in § 5's order.
  ///
  /// Anchors are the nearest preceding unique line, so each window is one to
  /// four lines and holds exactly one `Color.` styling line: the site itself.
  /// That is what makes a failure name the site rather than a file. Keep it
  /// that way when re-anchoring — a window wide enough to catch a *neighbouring*
  /// `inkSecondary` passes with the site reverted.
  private static let batchTwoSites: [BatchTwoSite] = [
    .init(
      "Views/Components/AgentOutputRow.swift",
      ".textStyle(Typography.thinkingBody)", window: 1),
    .init(
      "Views/Simulation/SimulationView+LogEntries.swift",
      #"Text(String(format: String(localized: "%@ assigned: %@"), agent, value))"#, window: 2),
    .init(
      "Views/Simulation/SimulationView+LogEntries.swift",
      #"Text(String(format: String(localized: "  %@: %lld votes"), name, count))"#, window: 4),
    .init(
      "Views/Simulation/SimulationView+LogEntries.swift",
      #"Text(String(localized: "No event this round"))"#, window: 2),
    .init(
      "Views/Simulation/SimulationView+LogEntries.swift",
      #"format: String(localized: "%@'s turn was skipped (%@)"),"#, window: 4),
    .init(
      "Views/Simulation/SimulationView+LogEntries.swift",
      #"format: String(localized: "%@'s choice \"%@\" wasn't an option"),"#, window: 4),
    .init(
      "Views/Simulation/SimulationView+LogEntries.swift",
      "func scoresSummary(_ scores: [String: Int]) -> some View {", window: 8),
    .init(
      "Views/Results/ResultDetailView.swift",
      #"Text(String(format: String(localized: "Turns skipped ×%lld"), skipped))"#, window: 1),
    .init(
      "Views/Results/ResultDetailView+CodePhaseRows.swift",
      ".monospacedDigit()", window: 1),
    .init(
      "Views/Results/ResultDetailView+CodePhaseRows.swift",
      #"Text(String(format: String(localized: "  %@ → %@"), filtered(voter), filtered(target)))"#,
      window: 4),
    .init(
      "Views/Results/ResultDetailView+CodePhaseRows.swift",
      #"Text(String(format: String(localized: "%@ assigned: %@"), filtered(agent), filtered(value)))"#,
      window: 2),
    .init(
      "Views/Results/ResultDetailView+CodePhaseRows.swift",
      #"Text(String(localized: "No event this round"))"#, window: 2),
    .init(
      "Views/Results/ResultsView.swift",
      #"Text(String(format: String(localized: "Turns skipped ×%lld"), skipped))"#, window: 2),
    .init(
      "Views/ScenarioDetail/ScenarioDetailView+Sections.swift",
      "Text(scenario.description)", window: 2),
    .init(
      "Views/ModelDownload/ModelDownloadHostView+CodePhaseRows.swift",
      #"Text(String(format: String(localized: "%@ assigned: %@"), agent, value))"#, window: 2),
    .init(
      "Views/ModelDownload/ModelDownloadHostView+CodePhaseRows.swift",
      #"Text(String(format: String(localized: "  %@: %lld votes"), name, count))"#, window: 4),
    .init(
      "Views/ModelDownload/ModelDownloadHostView+CodePhaseRows.swift",
      "private func scoresContent(_ scores: [String: Int]) -> some View {", window: 8),
    .init(
      "Views/ModelDownload/ModelDownloadHostView+CodePhaseRows.swift",
      #"Text(String(localized: "No event this round"))"#, window: 2),
    .init(
      "Views/Community/SharedScenarios/GalleryScenarioDetailView.swift",
      "Text(value)", window: 1)
  ]

  /// Batch 2's counterpart, anchored per site rather than per file — see
  /// ``expectedAppliedInkSecondary`` for why the shapes differ.
  ///
  /// Three assertions per site, and the **first is the control**: the anchor
  /// must match exactly one non-comment line. A rename, a deletion, or a second
  /// copy of the anchored line all land there and name the site, so the two
  /// content checks below can never pass by scanning nothing. The window then
  /// has to contain `Color.inkSecondary` and must not contain `Color.muted`;
  /// the second is what catches a revert, and the first what catches a slide to
  /// `Color.ink` or a raw hex that the census would wave through.
  @Test func batchTwoSitesStillReadInkSecondary() throws {
    #expect(Self.batchTwoSites.count == 19, "the ledger § 5 marks nineteen rows `B2`")

    var failures: [String] = []
    for site in Self.batchTwoSites {
      let url = SourceTreeProbe.appSourceRoot.appending(path: site.path)
      let code = try String(contentsOf: url, encoding: .utf8)
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("//") }

      let hits = code.indices.filter { code[$0].contains(site.anchor) }
      guard hits.count == 1, let start = hits.first else {
        failures.append(
          "  \(site.path): anchor matched \(hits.count) lines, expected 1 — \(site.anchor)")
        continue
      }
      let window = code[start...min(start + site.window, code.count - 1)]
      if !window.contains(where: { $0.contains("Color.inkSecondary") }) {
        failures.append(
          "  \(site.path): no `Color.inkSecondary` within \(site.window) lines of "
            + "\(site.anchor)")
      }
      if window.contains(where: { $0.contains("Color.muted") }) {
        failures.append("  \(site.path): `Color.muted` came back at \(site.anchor)")
      }
    }

    #expect(
      failures.isEmpty,
      """
      Batch 2's repointed sites no longer read `Color.inkSecondary`. An anchor \
      that stopped resolving is a rename — re-anchor it and keep the window \
      holding one `Color.` line. A token that changed is a design decision: \
      re-adjudicate the site against `muted-application-audit.md` § 2 first.
      \(failures.joined(separator: "\n"))
      """)
  }
}

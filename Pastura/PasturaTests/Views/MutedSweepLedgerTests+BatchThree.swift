// Batch 3's applied-site pin — the eliminated-player rows in
// `SimulationResultCard` / `ScoreboardSheet` and the prediction countdown
// (#1448). An extension of `MutedSweepLedgerTests`, never a second
// `@Suite`; the site type and the checker live in `+BatchTwo`.

import Foundation
import Testing

extension MutedSweepLedgerTests {

  /// The six sites the ledger § 5 marks `B3`, in § 5's order.
  ///
  /// Anchors are the nearest preceding line unique among the file's
  /// non-comment lines, and every window holds exactly one `Color.` styling
  /// line — the site. Two windows are worth a word: the `survivalRow` window
  /// is five lines, wider than any in batch 2, because the row's `Text`
  /// carries three modifiers before its `.foregroundStyle` and no nearer line
  /// is unique (`Text(entry.name)` and `.strikethrough(entry.isEliminated)`
  /// both also appear in `rankedRow`); it still holds a single `Color.` line.
  /// The `nameColor` window is **one** line on purpose — the next line is
  /// `return isWinner ? Color.mossInk : Color.ink`, and a window reaching it
  /// would pass with the site reverted.
  ///
  /// `.strikethrough(entry.isEliminated)` is unique in `ScoreboardSheet` even
  /// though it appears twice in `SimulationResultCard`; uniqueness is per
  /// file, which is what the control checks.
  ///
  /// The `%lld s left` window reaches its site at two lines, and the eyebrow's
  /// surviving quietude-tier line sits *before* the anchor, so the
  /// no-`Color.muted`-in-window check cannot be tripped by a site that is
  /// meant to stay.
  private static let batchThreeSites: [AppliedSite] = [
    .init(
      "Views/Components/SimulationResultCard.swift",
      "private func survivalRow(_ entry: Entry) -> some View {", window: 5),
    .init(
      "Views/Components/SimulationResultCard.swift",
      "Text(formattedValue(value, kind: entry.valueKind))", window: 3),
    .init(
      "Views/Components/SimulationResultCard.swift",
      "private func nameColor(_ entry: Entry, isWinner: Bool) -> Color {", window: 1),
    .init(
      "Views/Simulation/ScoreboardSheet.swift",
      ".strikethrough(entry.isEliminated)", window: 1),
    .init(
      "Views/Simulation/ScoreboardSheet.swift",
      #"Text(String(format: String(localized: "%lld pts"), entry.score))"#, window: 3),
    .init(
      "Views/Simulation/ViewerPredictionSheet.swift",
      #"Text(String(format: String(localized: "%lld s left"), remaining))"#, window: 2)
  ]

  /// Batch 3's pin, same three assertions per site as
  /// ``batchTwoSitesStillReadInkSecondary`` via the shared checker; the count
  /// is the control that the table was not trimmed.
  @Test func batchThreeSitesStillReadInkSecondary() throws {
    #expect(Self.batchThreeSites.count == 6, "the ledger § 5 marks six rows `B3`")

    let failures = try Self.appliedSiteFailures(Self.batchThreeSites)

    #expect(
      failures.isEmpty,
      """
      Batch 3's repointed sites no longer read `Color.inkSecondary`. An anchor \
      that stopped resolving is a rename — re-anchor it and keep the window \
      holding one `Color.` line. A token that changed is a design decision: \
      re-adjudicate the site against `muted-application-audit.md` § 2 first.
      \(failures.joined(separator: "\n"))
      """)
  }
}

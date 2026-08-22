// Batch 4's applied-site pin — the header pill's terminal-state labels, the
// model row's meta line, and the blocked clear-all label (#1448). An extension
// of `MutedSweepLedgerTests`, never a second `@Suite`; the site type and the
// checker live in `+BatchTwo`.

import Testing

extension MutedSweepLedgerTests {

  /// The three sites the ledger § 5 marks `B4`, in § 5's order.
  ///
  /// **The first batch whose rows do not share a token.** B1 through B3 all
  /// landed on `Color.inkSecondary` — §8's neutral-ground answer — so the
  /// checker could hardcode it. B4 routes by the ground's *family* instead, and
  /// gets three different answers: the header pill's wash is ink-family and
  /// translucent, so it takes the role token; the model row's ground is the
  /// card under a §2.7 state overlay, so it takes the neutral one; and the
  /// clear-all label is a disabled control, which is a routing question §8 does
  /// not govern at all. That is why ``AppliedSite`` carries a token.
  ///
  /// Two windows are worth a word:
  ///
  /// - The `foreground` window is **nine** lines and holds **three** `Color.`
  ///   lines rather than the usual one, because the anchor is the property and
  ///   the site is one arm of its `switch`. A nearer anchor does exist —
  ///   `return Color.mossInk` is unique in the file and sits two lines above —
  ///   and is deliberately not used: anchoring on a **sibling arm's** token
  ///   couples this pin to `.completed`'s routing, so a later re-adjudication
  ///   of that arm would surface here as a resolution failure and be read as a
  ///   rename. Anchoring on the property costs a wider window and keeps the
  ///   two arms independent. (`case .paused, .cancelled, .error:` is not
  ///   available either way — it appears again in `washToken`.)
  ///
  ///   The window stops two lines past the site and never reaches
  ///   `washToken`'s surviving `Color.muted`, so the no-`Color.muted` check
  ///   still means what it means elsewhere: it catches this arm reverting, not
  ///   the wash. Two residuals come with the width, and neither is covered:
  ///   a **coordinated** edit that reverts this arm *and* puts
  ///   `Color.inkOnWash` on another arm keeps the window green; and a future
  ///   re-route of `.completed` or the active arms to `Color.muted` reddens
  ///   *this* pin with a message naming the `foreground` anchor, attributing
  ///   the change to the terminal arm. Read the arm, not just the message.
  /// - The clear-all window's single `Color.` line carries **two** tokens
  ///   (`Color.disabledText` and `Color.danger`, the blocked and unblocked
  ///   arms of one ternary). `+BatchTwo`'s doc describes windows holding one
  ///   `Color.` line; this one does too, but that line is not a single-token
  ///   line. The token check is a `contains`, so it reads the blocked arm
  ///   correctly — and a revert of *that* arm to `Color.muted` reddens both
  ///   checks at once.
  private static let batchFourSites: [AppliedSite] = [
    .init(
      "Views/Components/GameHeaderStatus.swift",
      "public var foreground: Color {", window: 9, token: "Color.inkOnWash"),
    .init(
      "Views/ModelSelection/ModelRow.swift",
      ".font(.system(size: 11.5, design: .monospaced))", window: 1,
      token: "Color.inkSecondary"),
    .init(
      "Views/Settings/SettingsView+PastResults.swift",
      #"Text(String(localized: "Clear all results"))"#, window: 3,
      token: "Color.disabledText")
  ]

  /// Batch 4's pin, same three assertions per site as
  /// ``batchTwoSitesStillReadInkSecondary`` via the shared checker; the count
  /// is the control that the table was not trimmed.
  @Test func batchFourSitesStillReadTheirTokens() throws {
    #expect(Self.batchFourSites.count == 3, "the ledger § 5 marks three rows `B4`")

    let failures = try Self.appliedSiteFailures(Self.batchFourSites)

    #expect(
      failures.isEmpty,
      """
      Batch 4's repointed sites no longer read the token their ground's family \
      supplies. An anchor that stopped resolving is a rename — re-anchor it and \
      keep the window clear of the surviving `Color.muted` wash. A token that \
      changed is a design decision: re-adjudicate the site against \
      `muted-application-audit.md` § 2 and design-system § 8's routing bullets \
      first.
      \(failures.joined(separator: "\n"))
      """)
  }
}

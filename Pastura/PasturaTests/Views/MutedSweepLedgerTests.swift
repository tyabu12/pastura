import Foundation
import Testing

/// Mechanical mirror of `docs/design/muted-application-audit.md` § 5 — the
/// per-file census of `Color.muted`, design-system §8's deliberately sub-AA
/// "quietude" tier (#1448).
///
/// **A failure is not a bug.** It means the population moved. The sweep runs in
/// batches and most of §5 still ships as written, so a count change is a
/// question, not a regression: re-adjudicate the site against § 2's five
/// misapplication classes, update the ledger row, then update the expectation
/// here. **Three causes produce the same observation of a vanished file, and
/// they take opposite remedies**: a rename or a deletion means re-anchor the
/// row by symbol rather than dropping it; an **applied batch** means the row
/// stays put with its `B` marker bolded and the entry here is dropped, which is
/// what batches 1, 5, 2 and 3 did. Read the file's § 5 rows before choosing.
///
/// **It fires on an addition too**, which is the half prose cannot do. The
/// expectation is a whole-map comparison, so a new file reaching for
/// `Color.muted` fails as loudly as an unreviewed repoint away from it — the
/// ledger's adjudications are only worth anything while the population they
/// were taken over is the current one.
///
/// Scope note: this counts *occurrences of a spelling*, not rendered sites. It
/// cannot tell a `#Preview` from shipped code, or text from a glyph fill — §5
/// carries those verdicts and this file deliberately does not restate them.
/// What it guarantees is that nobody changes the population without meeting §5.
@Suite(.timeLimit(.minutes(1)))
struct MutedSweepLedgerTests {

  /// Non-comment `Color.muted` occurrences per file, keyed relative to
  /// `Pastura/Pastura`. Reproduce with the ledger § 8 command; every entry is
  /// a row (or group of rows) in § 5 — with **one exception, created by batch
  /// 2**: `ResultDetailView`'s degraded banner was a single `Label` tint at the
  /// baseline census, and splitting it left a glyph occurrence that no
  /// `9a40565a` row could have anticipated. The ledger records it as an added
  /// row; § 5's tally deliberately does not move.
  ///
  /// Batch 1 (#1486) removed eight occurrences and emptied three files, batch 5
  /// (#1510) removed three more and emptied three more, and batch 2 repointed
  /// nineteen sites for a net **eighteen** occurrences — the nineteenth kept
  /// the spelling on the glyph above — and emptied none. Batch 3 repointed six
  /// sites in three files — the eliminated rows in `SimulationResultCard` /
  /// `ScoreboardSheet` and the prediction countdown — and emptied none either.
  /// So this table is the post-batch-3 population, not § 1's `9a40565a`
  /// baseline.
  private static let expectedMutedOccurrences: [String: Int] = [
    "Views/Community/SharedScenarios/GalleryCatalogRow.swift": 1,
    "Views/Community/SharedScenarios/GalleryScenarioDetailView+Highlight.swift": 2,
    "Views/Community/SharedScenarios/GalleryScenarioDetailView.swift": 3,
    "Views/Community/SharedScenarios/SharedScenariosListView.swift": 1,
    "Views/Components/ActiveModelChip.swift": 2,
    "Views/Components/AgentOutputRow.swift": 2,
    "Views/Components/DogMark.swift": 2,
    "Views/Components/GameHeaderStatus.swift": 1,
    "Views/Components/IdleFriendlyProgressView.swift": 1,
    "Views/Components/PasturaCard.swift": 1,
    "Views/Components/PasturaRowLabel.swift": 1,
    "Views/Components/PersonaDetailSheet.swift": 1,
    "Views/Components/SheepAvatar.swift": 4,
    "Views/Components/SimulationResultCard.swift": 2,
    "Views/Editor/PhaseBlockRow.swift": 1,
    "Views/Editor/PhaseEditorSheet+ConditionalSection.swift": 1,
    "Views/Editor/ScenarioEditorView.swift": 2,
    "Views/Home/HomeCompactScenarioRow.swift": 2,
    "Views/ModelDownload/ModelDownloadHostView+CodePhaseRows.swift": 1,
    "Views/ModelSelection/ModelPickerView.swift": 2,
    "Views/Report/ReportSheet.swift": 1,
    "Views/Results/ResultDetailView+CodePhaseRows.swift": 1,
    "Views/Results/ResultDetailView+RowLayout.swift": 1,
    "Views/Results/ResultDetailView.swift": 1,
    "Views/Results/ResultsView+Timeline.swift": 1,
    "Views/Results/ResultsView.swift": 5,
    "Views/ScenarioDetail/ScenarioDetailView+Sections.swift": 1,
    "Views/Settings/ModelSettingsRow.swift": 1,
    "Views/Settings/SettingsView.swift": 2,
    "Views/Simulation/HighlightCandidatesSection.swift": 2,
    "Views/Simulation/ScoreboardSheet.swift": 1,
    "Views/Simulation/SimulationView+Background.swift": 1,
    "Views/Simulation/SimulationView+LogEntries.swift": 3,
    "Views/Simulation/SimulationView.swift": 2,
    "Views/Simulation/ViewerPredictionSheet.swift": 1
  ]

  /// Reads of the raw `muted` / `nightMuted` palette values that do **not** go
  /// through the `Color.muted` alias — the spelling § 1 defines the population
  /// by, and therefore the spelling the ledger's grep is blind to.
  ///
  /// One rendering consumer exists: `HighlightShareCard`'s model-name line, a
  /// fixed-appearance `ImageRenderer` export that must read the raw palette
  /// rather than a trait-resolving alias (`swiftui-traps.md` § "`ImageRenderer`
  /// does not inherit the ambient environment"). Its two other occurrences are
  /// the `light` / `dark` palette constructions feeding it. Adjudicated in the
  /// ledger § 1; on `screenBackground` / `nightBackground`, §8's own
  /// calibration grounds.
  ///
  /// `DesignTokens*` files are excluded: they *define* the token, so a read
  /// there is plumbing rather than an application of the tier.
  private static let expectedRawPaletteReads: [String: Int] = [
    "Views/Components/HighlightShareCard.swift": 3
  ]

  /// The `Color.inkSecondary` count of the three files batch 5 (#1485) emptied
  /// of `Color.muted`, and the reason this arm exists at all.
  ///
  /// **An applied batch leaves the census permanently.** The map above pins the
  /// *absence* of `Color.muted`, so once a site is repointed the only drift it
  /// still catches is a re-add of the old token. A later slide to `Color.ink`,
  /// `.secondary` or a raw hex would leave every gate green while
  /// design-system § 2.2's claim — that the hand-rolled headers now follow the
  /// table — went quietly false. The two arms are complementary and neither
  /// subsumes the other: revert-to-`muted` reddens the map above, drift-to-
  /// anything-else reddens this one.
  ///
  /// Counts, not presence: `SettingsView+Models` already read `inkSecondary`
  /// for its switch-blocked reason before batch 5 (class A1, batch 1), so a
  /// `> 0` check there would pass with the header reverted. Scoped to these
  /// three files on purpose — this is a pin on B5's applied rows, not a second
  /// app-wide census.
  ///
  /// **A per-file count is the right shape here and the wrong one for batch 2**,
  /// which is why the two applied batches are pinned differently. It works
  /// because these three files hold 1 / 1 / 2 `Color.inkSecondary` in total: a
  /// reverted header shows up as an off-by-one. Batch 2's files hold 1 to 13,
  /// and in the three densest (13 / 11 / 10) roughly half predate the batch
  /// (7 / 7 / 6), so a revert there hides inside the total unless an unrelated
  /// edit happens to move it the other way — the same dilution this comment's
  /// `> 0` argument warns about, one step further along.
  /// ``batchTwoSitesStillReadInkSecondary`` anchors by symbol for that reason.
  private static let expectedAppliedInkSecondary: [String: Int] = [
    "Views/Components/PasturaSection.swift": 1,
    "Views/Home/HomeView.swift": 1,
    "Views/Settings/SettingsView+Models.swift": 2
  ]

  private static let rawPaletteNeedles = [
    "PasturaPalette.muted", "PasturaPalette.nightMuted",
    "PasturaDynamicPalette.muted", "palette.muted"
  ]

  // MARK: - The ledger mirror

  @Test func perFileMutedCensusMatchesTheLedger() throws {
    let observed = Self.census(of: ["Color.muted"], excludingDesignTokens: false)
    #expect(
      observed == Self.expectedMutedOccurrences,
      "\(Self.diff(observed: observed, expected: Self.expectedMutedOccurrences, what: "Color.muted"))"
    )
  }

  @Test func rawPaletteReadsStayWithinTheRecordedSet() throws {
    let observed = Self.census(of: Self.rawPaletteNeedles, excludingDesignTokens: true)
    #expect(
      observed == Self.expectedRawPaletteReads,
      """
      \(Self.diff(
        observed: observed, expected: Self.expectedRawPaletteReads, what: "raw palette muted read"))
      """)
  }

  @Test func batchFiveSitesStillReadInkSecondary() throws {
    let observed = Self.census(of: ["Color.inkSecondary"], excludingDesignTokens: true)
      .filter { Self.expectedAppliedInkSecondary.keys.contains($0.key) }
    #expect(
      observed == Self.expectedAppliedInkSecondary,
      """
      \(Self.diff(
        observed: observed, expected: Self.expectedAppliedInkSecondary,
        what: "batch 5 `Color.inkSecondary`"))
      """)
  }

  // MARK: - Controls

  /// Both arms above are set comparisons, so a probe that scans nothing — or a
  /// comment filter that eats everything — produces an empty map and only
  /// fails by accident of the expectation being non-empty. These assert the
  /// instrument directly, in both directions.
  ///
  /// **The negative arm is the one carrying discriminating power.** The
  /// positive arm cannot fail alone — `expectedMutedOccurrences` already pins
  /// that file at 3, so an always-zero predicate reddens the census first. It
  /// is kept because it fails *locally*, naming the predicate rather than
  /// printing a forty-row diff; the census map is the real positive control.
  @Test func theProbeIsStillMeasuringSomething() throws {
    let swiftFiles = SourceTreeProbe.swiftFiles(under: SourceTreeProbe.appSourceRoot)
    #expect(!swiftFiles.isEmpty, "scanned no app sources — the source root did not resolve")

    // Positive: a file the sweep does not empty still matches, so the
    // counting predicate has not been narrowed into always-zero. Batch 2
    // took this file 9 -> 3; the three survivors are the § 5 rows that carry
    // no batch marker (`vs`, and the turn-skipped / action-rejected icons),
    // so no later batch empties it either. Pick a replacement on that
    // property, not on "not swept yet", if it ever does.
    let partiallySwept = "Views/Simulation/SimulationView+LogEntries.swift"
    let observed = Self.census(of: ["Color.muted"], excludingDesignTokens: false)
    #expect(
      (observed[partiallySwept] ?? 0) > 0,
      "\(partiallySwept) stopped matching — the predicate, not the file, is the likely cause")

    // Negative: a file whose only occurrence is a doc comment must count zero
    // while still containing the raw needle. A comment filter that did nothing
    // would count it; one that ate every line would fail the positive above.
    let commentOnly = "Views/Components/ActiveModelChipPresenter.swift"
    let source = try String(
      contentsOf: SourceTreeProbe.appSourceRoot.appending(path: commentOnly), encoding: .utf8)
    #expect(source.contains("Color.muted"), "\(commentOnly) no longer mentions the token at all")
    #expect(observed[commentOnly] == nil, "\(commentOnly) counted a comment-only occurrence")
  }

  /// The ledger § 8 regeneration command counts matching *lines*; this file
  /// counts *occurrences*. They agree only while no line carries two, and a
  /// reader comparing the two figures would never learn that they had stopped
  /// agreeing. Pin the equality so the divergence is what fails.
  @Test func occurrenceCountAndLineCountAgree() throws {
    let occurrences = Self.census(of: ["Color.muted"], excludingDesignTokens: false)
      .values.reduce(0, +)
    let lines = Self.matchingLines(of: ["Color.muted"], excludingDesignTokens: false).count
    #expect(
      occurrences == lines,
      """
      \(occurrences) occurrences across \(lines) lines — a line now carries two. \
      The ledger § 8 command undercounts; switch it to `grep -o` before trusting it.
      """)
  }

  // MARK: - Census

  /// Per-file count of `needles` across the app target, skipping lines whose
  /// first non-whitespace characters are `//`. Files with no match are absent
  /// rather than zero, so the comparison catches an emptied file.
  private static func census(of needles: [String], excludingDesignTokens: Bool) -> [String: Int] {
    var counts: [String: Int] = [:]
    for (path, line) in matchingLines(of: needles, excludingDesignTokens: excludingDesignTokens) {
      counts[path, default: 0] += needles.reduce(0) {
        $0 + line.components(separatedBy: $1).count - 1
      }
    }
    return counts
  }

  /// Every (app-relative path, line) whose line contains one of `needles` and
  /// is not a comment. Comment skipping lives in ``SourceTreeProbe`` so this
  /// guard and `StructuralBoundaryTests` share one predicate.
  private static func matchingLines(
    of needles: [String], excludingDesignTokens: Bool
  ) -> [(path: String, line: String)] {
    SourceTreeProbe.matchingLines(of: needles, under: SourceTreeProbe.appSourceRoot)
      .filter {
        // Match the basename, not the path: `contains("/DesignTokens")` only
        // works while every `DesignTokens*.swift` sits in a subdirectory, and
        // one at the app source root would silently stop being excluded.
        !excludingDesignTokens
          || !($0.path as NSString).lastPathComponent.hasPrefix("DesignTokens")
      }
  }

  private static func diff(
    observed: [String: Int], expected: [String: Int], what: String
  ) -> String {
    let changes = Set(observed.keys).union(expected.keys).sorted().compactMap { key -> String? in
      let (was, now) = (expected[key], observed[key])
      guard was != now else { return nil }
      return
        "  \(key): expected \(was.map(String.init) ?? "absent") → found \(now.map(String.init) ?? "absent")"
    }
    return """
      The \(what) population moved. Decide which happened first — an applied \
      batch (§ 5 row stays, bold its `B`, drop the entry here) or an unreviewed \
      change (re-adjudicate against § 2, update the § 5 row, then this \
      expectation). Do not reach for the second remedy without checking § 7:
      \(changes.joined(separator: "\n"))
      """
  }
}

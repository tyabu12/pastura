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
/// here. A row whose file no longer appears was renamed or deleted — re-anchor
/// it by symbol rather than dropping it.
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
  /// a row (or group of rows) in § 5.
  ///
  /// Batch 1 (#1448) removed eight occurrences and emptied three files, so
  /// this table is the post-batch-1 population, not § 1's `9a40565a` baseline.
  private static let expectedMutedOccurrences: [String: Int] = [
    "Views/Community/SharedScenarios/GalleryCatalogRow.swift": 1,
    "Views/Community/SharedScenarios/GalleryScenarioDetailView+Highlight.swift": 2,
    "Views/Community/SharedScenarios/GalleryScenarioDetailView.swift": 4,
    "Views/Community/SharedScenarios/SharedScenariosListView.swift": 1,
    "Views/Components/ActiveModelChip.swift": 2,
    "Views/Components/AgentOutputRow.swift": 3,
    "Views/Components/DogMark.swift": 2,
    "Views/Components/GameHeaderStatus.swift": 2,
    "Views/Components/IdleFriendlyProgressView.swift": 1,
    "Views/Components/PasturaCard.swift": 1,
    "Views/Components/PasturaRowLabel.swift": 1,
    "Views/Components/PasturaSection.swift": 1,
    "Views/Components/PersonaDetailSheet.swift": 1,
    "Views/Components/SheepAvatar.swift": 4,
    "Views/Components/SimulationResultCard.swift": 5,
    "Views/Editor/PhaseBlockRow.swift": 1,
    "Views/Editor/PhaseEditorSheet+ConditionalSection.swift": 1,
    "Views/Editor/ScenarioEditorView.swift": 2,
    "Views/Home/HomeCompactScenarioRow.swift": 2,
    "Views/Home/HomeView.swift": 1,
    "Views/ModelDownload/ModelDownloadHostView+CodePhaseRows.swift": 5,
    "Views/ModelSelection/ModelPickerView.swift": 2,
    "Views/ModelSelection/ModelRow.swift": 1,
    "Views/Report/ReportSheet.swift": 1,
    "Views/Results/ResultDetailView+CodePhaseRows.swift": 5,
    "Views/Results/ResultDetailView+RowLayout.swift": 1,
    "Views/Results/ResultDetailView.swift": 1,
    "Views/Results/ResultsView+Timeline.swift": 1,
    "Views/Results/ResultsView.swift": 6,
    "Views/ScenarioDetail/ScenarioDetailView+Sections.swift": 2,
    "Views/Settings/ModelSettingsRow.swift": 1,
    "Views/Settings/SettingsView+Models.swift": 1,
    "Views/Settings/SettingsView+PastResults.swift": 1,
    "Views/Settings/SettingsView.swift": 2,
    "Views/Simulation/HighlightCandidatesSection.swift": 2,
    "Views/Simulation/ScoreboardSheet.swift": 3,
    "Views/Simulation/SimulationView+Background.swift": 1,
    "Views/Simulation/SimulationView+LogEntries.swift": 9,
    "Views/Simulation/SimulationView.swift": 2,
    "Views/Simulation/ViewerPredictionSheet.swift": 2
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

  // MARK: - Controls

  /// Both arms above are set comparisons, so a probe that scans nothing — or a
  /// comment filter that eats everything — produces an empty map and only
  /// fails by accident of the expectation being non-empty. These assert the
  /// instrument directly, in both directions.
  @Test func theProbeIsStillMeasuringSomething() throws {
    let swiftFiles = SourceTreeProbe.swiftFiles(under: SourceTreeProbe.appSourceRoot)
    #expect(!swiftFiles.isEmpty, "scanned no app sources — the source root did not resolve")

    // Positive: a file this sweep has NOT touched (batch 2) still matches, so
    // the counting predicate has not been narrowed into always-zero.
    let unswept = "Views/Simulation/SimulationView+LogEntries.swift"
    let observed = Self.census(of: ["Color.muted"], excludingDesignTokens: false)
    #expect(
      (observed[unswept] ?? 0) > 0,
      "\(unswept) stopped matching — the predicate, not the file, is the likely cause")

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
      .filter { !excludingDesignTokens || !$0.path.contains("/DesignTokens") }
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
      The \(what) population moved. Re-adjudicate each site against \
      docs/design/muted-application-audit.md § 2, update its § 5 row, then update \
      this expectation:
      \(changes.joined(separator: "\n"))
      """
  }
}

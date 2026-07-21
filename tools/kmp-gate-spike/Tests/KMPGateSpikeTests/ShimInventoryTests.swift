import Foundation
import Testing

@testable import KMPGateSpike

/// Guards the measurement (i)/(iii) scanner.
///
/// A counting measurement fails silently in one direction — it under-reports —
/// and an under-reported shim budget is evidence pointing the wrong way at a
/// GO/NO-GO gate. Both of the scanner's first-draft defects were exactly that
/// shape in reverse (it counted its own predicate strings, and summed
/// overlapping categories into a ~2x total), so the invariants live here rather
/// than in a comment.
///
/// Roots are derived from `#filePath` rather than from the working directory.
/// `kmp-gate-bench` resolves its own roots against the cwd because it is a CLI
/// with a documented "run from the repo root" contract; a test has no such
/// contract, and cwd-relative paths here would make the suite pass or fail on
/// where it happened to be launched from.
@Suite("shim inventory", .timeLimit(.minutes(1)))
struct ShimInventoryTests {

  /// This file lives at `<package>/Tests/KMPGateSpikeTests/`.
  private static let packageRoot: String = {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<3 { url.deleteLastPathComponent() }
    return url.path
  }()

  private static let roots = [
    packageRoot + "/Sources/KMPGateSpike",
    packageRoot + "/Tests/KMPGateSpikeTests"
  ]

  @Test("the scan finds the adapters rather than reporting an empty budget")
  func scanIsNotVacuous() throws {
    let inventory = try ShimInventory.scan(roots: Self.roots)

    #expect(inventory.total > 0)
    // The two retroactive vouches are the boundary's signature cost and are
    // named in the ADR record; if they vanish, either the adapters changed
    // shape or the scanner stopped seeing them.
    let retroactive = try #require(
      inventory.categories.first { $0.name == "retroactive Sendable vouch" })
    #expect(retroactive.count == 2)
    #expect(retroactive.hits.allSatisfy { $0.file == "SharedEngineRunner.swift" })
  }

  /// Fixture lines for the two tests below, assembled from fragments.
  ///
  /// They must not appear verbatim in this file's *code*. `roots` includes the
  /// Tests directory, so a literal `@retroactive @unchecked Sendable` written
  /// as a string here is counted by `scan` as a real shim — indistinguishable
  /// from the ones in `SharedEngineRunner.swift`, inflating the measured
  /// budget. That is the scanner's original defect (counting its own predicate
  /// strings) in a new costume. Doc comments are exempt — `scan` skips lines
  /// whose trimmed form starts with `//` — so this prose may name the patterns
  /// freely.
  ///
  /// `fixturesAreNotCountedAsShims` is what actually holds the invariant.
  /// `scanIsNotVacuous`'s `count == 2` catches only a regressed
  /// `retroactiveLine`; the other two feed buckets no test pins a count on, so
  /// they would inflate the budget silently.
  private static let retroactiveLine =
    "extension SimulationEvent: @" + "retroactive @" + "unchecked Sendable {}"
  private static let uncheckedLine =
    "nonisolated" + " final class RunHandleBox: @" + "unchecked Sendable {"
  private static let nonisolatedLine =
    "nonisolated" + " public enum ShimInventoryError: Error {"

  /// No line of this file's own code may classify as a shim.
  ///
  /// Asserted with the scanner's own predicate rather than by looking for the
  /// fixture strings: a substring check only catches a fixture re-joined into
  /// ONE literal, while a *partial* rejoin — `"… @retroactive @" + "unchecked
  /// Sendable {}"` — leaves the joined string absent from source and still
  /// matches rule 1, so the fixture would be counted as a real vouch with the
  /// test green. `classify` is the thing that decides, so `classify` is what
  /// this asks.
  ///
  /// Preferred over pinning per-bucket hit counts: an exact count would be a
  /// tripwire on every unrelated `@unchecked Sendable` added to this package,
  /// while the hazard is specifically "this file started counting itself".
  @Test("no line of this test file is counted as a shim")
  func fixturesAreNotCountedAsShims() throws {
    let source = try String(contentsOfFile: #filePath, encoding: .utf8)

    for (index, line) in source.split(separator: "\n", omittingEmptySubsequences: false)
      .enumerated() {
      // Same predicate `scan` applies before classifying — comment lines are
      // exempt, which is why the prose here may name the patterns freely.
      guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }
      let bucket = ShimInventory.classify(String(line))
      #expect(
        bucket == nil,
        "line \(index + 1) of this file classifies as '\(bucket ?? "")': \(line)")
    }
  }

  /// Pins `classify`'s "most specific first" precedence on the lines that
  /// actually overlap.
  ///
  /// This replaces a mutual-exclusivity assertion that held by construction:
  /// `classify` returns `String?` — at most one bucket — and hits are keyed
  /// `file:line`, so no arrangement of the rules could have made it fail. It
  /// read as coverage it did not provide.
  ///
  /// Precedence, by contrast, is load-bearing and only half-covered. Both
  /// overlaps occur on real production lines in `SharedEngineRunner.swift`:
  /// `@retroactive @unchecked Sendable` matches rules 1 and 2, and
  /// `nonisolated final class … : @unchecked Sendable` matches rules 2 and 3.
  /// A 1↔2 swap already fails `scanIsNotVacuous` via `retroactive.count == 2`,
  /// but **a 2↔3 swap fails nothing today** — it silently moves every
  /// `nonisolated … : @unchecked Sendable` declaration in the scanned roots
  /// (ten lines, four of them in `SharedEngineRunner.swift`) out of
  /// "hand-asserted Sendable conformance", while `total`, the retroactive
  /// count, and the old exclusivity assertion all stay green.
  @Test("classification precedence is most-specific-first")
  func classifyPrefersTheMoreSpecificRule() {
    let cases: [(line: String, expected: String?)] = [
      // Rules 1 and 2 both match — 1 must win.
      (Self.retroactiveLine, "retroactive Sendable vouch"),
      // Rules 2 and 3 both match — 2 must win. The uncovered pair.
      (Self.uncheckedLine, "hand-asserted Sendable conformance"),
      // Rule 3 alone.
      (Self.nonisolatedLine, "type-level nonisolated only"),
      // No rule. A plain line must not be counted into the shim budget.
      ("let relayCount = 1", nil)
    ]

    for (line, expected) in cases {
      #expect(ShimInventory.classify(line) == expected, "misclassified: \(line)")
    }
  }

  /// Ties `classify`'s hardcoded bucket strings to the reported category names.
  ///
  /// `rationales` documents its order as "also the classification priority",
  /// but nothing enforces that — the two are independent literals, so a rename
  /// on one side would produce a category that can never receive a hit and a
  /// bucket that is never reported. Either way the budget under-reports, which
  /// is the failure direction this suite exists to catch.
  @Test("every bucket classify can return is a reported category")
  func classifyBucketsAreReportedCategories() throws {
    let reported = Set(try ShimInventory.scan(roots: Self.roots).categories.map(\.name))
    let produced = [Self.retroactiveLine, Self.uncheckedLine, Self.nonisolatedLine]
      .compactMap(ShimInventory.classify)

    // Locality guard only — `classifyPrefersTheMoreSpecificRule` is what pins
    // each fixture to its bucket. This just keeps the loop below from passing
    // vacuously on an empty `produced`.
    #expect(produced.count == 3)
    for bucket in produced {
      #expect(reported.contains(bucket), "classify returns an unreported bucket: \(bucket)")
    }
  }

  @Test("the scanner does not count its own source")
  func measurementMachineryIsExcluded() throws {
    let inventory = try ShimInventory.scan(roots: Self.roots)
    let files = Set(inventory.categories.flatMap { $0.hits.map(\.file) })

    for excluded in ShimInventory.excluded.keys {
      #expect(!files.contains(excluded), "\(excluded) should not be counted")
    }
  }

  @Test("a bad root is an error, never a zero")
  func missingSourcesThrow() {
    #expect(throws: ShimInventoryError.self) {
      _ = try ShimInventory.scan(roots: ["./definitely-not-a-source-dir"])
    }
  }

  @Test("one moved root is an error even when the others still resolve")
  func partiallyMissingRootsThrow() {
    // The negative control the all-roots-empty test above cannot provide. The
    // scanner previously asked "did *any* root yield files?", which a surviving
    // root answers yes to — so a renamed root dropped its hits and the budget
    // still printed a plausible total. Only a mixed root set catches that.
    // Pinned to `.emptyRoot` specifically: `ShimInventoryError.self` would also
    // be satisfied by a `staleExclusion` thrown for an unrelated reason, which
    // would make this pass without exercising the per-root check at all.
    #expect(throws: ShimInventoryError.emptyRoot("./definitely-not-a-source-dir")) {
      _ = try ShimInventory.scan(roots: Self.roots + ["./definitely-not-a-source-dir"])
    }
  }

  @Test("an exclusion naming a file that no longer exists is an error")
  func staleExclusionThrows() {
    // The exclusion list is matched by file name, so a rename would silently
    // re-enable counting the excluded file. Only a root that contains none of
    // the excluded names can exercise this, so the Tests directory is used
    // alone — it holds no excluded file.
    #expect(throws: ShimInventoryError.self) {
      _ = try ShimInventory.scan(roots: [Self.packageRoot + "/Tests/KMPGateSpikeTests"])
    }
  }

  /// One pinned sibling-test shim hit, anchored on `(file, bucket, type)`.
  ///
  /// Not on `Hit`'s raw line number: an unrelated edit *above* a hit shifts its
  /// line and would churn the expectation for no real change. The declared type
  /// name is the stable identity — a hit only moves buckets or files, or gains a
  /// sibling, when something the budget cares about actually changed. Residual
  /// blind spot: two hits sharing a file, bucket, and type name would collapse
  /// into one member (none do today — all seven types are distinct); accepted
  /// over the line-number churn the anchor exists to avoid.
  private struct SiblingHit: Hashable, CustomStringConvertible {
    let file: String
    let bucket: String
    let type: String
    var description: String { "\(file):[\(bucket)] \(type)" }
  }

  /// The complete set of shim hits `scan` finds in the sibling **test** files.
  ///
  /// `fixturesAreNotCountedAsShims` holds `ShimInventoryTests.swift` itself to
  /// zero, but `scan`'s roots cover the whole `Tests/KMPGateSpikeTests`
  /// directory — so a fixture-shaped line written into any *sibling* test file
  /// is counted by `scan` as a real boundary shim and silently inflates the
  /// measured budget, which is ADR-023 §6 measurement (i)/(iii) evidence. That
  /// is the "under-report in reverse" this suite exists to catch, one file over.
  ///
  /// This set cannot be a blanket "every line under `Tests/` classifies as nil":
  /// the seven hits below are **legitimate**. Each is a `@unchecked Sendable`
  /// conformer or a type-level `nonisolated` declaration that a boundary test
  /// genuinely needs — recording backends, callbacks, and probes built to
  /// exercise the K/N boundary from the Swift side. Do **not** "fix" a failure
  /// here by deleting a conformance; that would break the test that declares it.
  ///
  /// Compared as a **set**, not a count, so the guard fails on an *added* hit
  /// (a superset) AND on an add+remove swap that leaves the total unchanged (a
  /// changed member) — the swap is exactly the drift a count would cancel out.
  /// A new legitimate hit must be acknowledged by adding it here, on purpose.
  private static let expectedSiblingTestShimHits: Set<SiblingHit> = [
    SiblingHit(
      file: "BoundaryContractTests.swift", bucket: "type-level nonisolated only",
      type: "RecordingRunHandle"),
    SiblingHit(
      file: "BoundaryContractTests.swift", bucket: "hand-asserted Sendable conformance",
      type: "RecordingCallbacks"),
    SiblingHit(
      file: "BoundaryContractTests.swift", bucket: "hand-asserted Sendable conformance",
      type: "TerminalBox"),
    SiblingHit(
      file: "PatternSixProbeTests.swift", bucket: "type-level nonisolated only",
      type: "BlockingProbe"),
    SiblingHit(
      file: "PatternSixProbeTests.swift", bucket: "type-level nonisolated only",
      type: "ThreadObservations"),
    SiblingHit(
      file: "PatternSixProbeTests.swift", bucket: "hand-asserted Sendable conformance",
      type: "ThreadObservingBackend"),
    SiblingHit(
      file: "PatternSixProbeTests.swift", bucket: "hand-asserted Sendable conformance",
      type: "ThreadObservingCallbacks")
  ]

  /// The declared type name from a classified declaration line — the identifier
  /// after the `class` / `struct` / `enum` / `actor` / `extension` keyword.
  private static func declaredTypeName(in text: String) -> String {
    let keywords: Set<String> = ["class", "struct", "enum", "actor", "protocol", "extension"]
    let tokens = text.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
    guard let keywordIndex = tokens.firstIndex(where: { keywords.contains($0) }),
      keywordIndex + 1 < tokens.count
    else { return "" }
    let raw = tokens[keywordIndex + 1]
    return String(raw.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" }))
  }

  @Test("the sibling-test shim-hit set is pinned so a new hit can't join silently")
  func siblingTestShimHitsMatchThePinnedSet() throws {
    let inventory = try ShimInventory.scan(roots: Self.roots)

    // Restrict to the actual test-directory files by basename. `Hit.file` is a
    // basename, so this holds only while Sources/ and Tests/ share no filename —
    // true today (distinct dir conventions); a future collision would need this
    // widened to a path match.
    let testDir = Self.packageRoot + "/Tests/KMPGateSpikeTests"
    let testFileNames = Set(
      try FileManager.default.contentsOfDirectory(atPath: testDir)
        .filter { $0.hasSuffix(".swift") })

    var actual: Set<SiblingHit> = []
    for category in inventory.categories {
      for hit in category.hits where testFileNames.contains(hit.file) {
        actual.insert(
          SiblingHit(
            file: hit.file, bucket: category.name,
            type: Self.declaredTypeName(in: hit.text)))
      }
    }

    let added = actual.subtracting(Self.expectedSiblingTestShimHits)
    let removed = Self.expectedSiblingTestShimHits.subtracting(actual)
    #expect(
      actual == Self.expectedSiblingTestShimHits,
      """
      sibling-test shim-hit set drifted. \
      unexpected (add to expectedSiblingTestShimHits only if legitimate): \
      \(added.sorted { $0.description < $1.description }); \
      missing (a pinned hit vanished or moved): \
      \(removed.sorted { $0.description < $1.description })
      """)
  }
}

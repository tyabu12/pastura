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
      #expect(
        ShimInventory.classify(String(line)) == nil,
        "line \(index + 1) of this file classifies as a shim: \(line)")
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
  /// but **a 2↔3 swap fails nothing today** — it silently moves four types out
  /// of "hand-asserted Sendable conformance" while `total`, the retroactive
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
}

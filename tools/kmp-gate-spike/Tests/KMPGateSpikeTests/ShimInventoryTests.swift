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

  @Test("categories never double-count a declaration")
  func categoriesAreMutuallyExclusive() throws {
    let inventory = try ShimInventory.scan(roots: Self.roots)
    let locations = inventory.categories.flatMap { category in
      category.hits.map { "\($0.file):\($0.line)" }
    }

    #expect(locations.count == Set(locations).count)
    #expect(locations.count == inventory.total)
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
    #expect(throws: ShimInventoryError.self) {
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

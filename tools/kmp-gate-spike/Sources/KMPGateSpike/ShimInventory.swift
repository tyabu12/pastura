import Foundation

/// ADR-023 §6 measurements (i) and (iii) — the *ergonomic* cost of the two
/// boundary adapters, counted from the sources rather than asserted by hand.
///
/// **Why counted and not written down.** A shim budget quoted in prose is a
/// number that rots: the next adapter change adds a box, the ADR still says
/// three, and the gate's own evidence quietly becomes wrong. Scanning the
/// files makes the figure a measurement, and makes it re-derivable by anyone
/// re-running the bench.
///
/// **What this is not.** These are counts of *workarounds the K/N boundary
/// forced*, not a code-quality score. Each category exists because Kotlin/Native
/// omits something Swift's concurrency checking wants; the count is a proxy for
/// how much hand-written trust the boundary needs.
public struct ShimInventory: Sendable {

  /// One occurrence, kept with its location so a reader can audit the count
  /// instead of trusting it.
  public struct Hit: Sendable, Equatable {
    public let file: String
    public let line: Int
    public let text: String
  }

  /// A named class of workaround.
  public struct Category: Sendable {
    public let name: String
    /// What the K/N boundary withholds that makes this necessary.
    public let rationale: String
    public let hits: [Hit]

    public var count: Int { hits.count }
  }

  public let categories: [Category]

  /// Total across every category — the headline shim-budget figure.
  public var total: Int { categories.reduce(0) { $0 + $1.count } }

  /// Files under the roots that are deliberately NOT counted, each with the
  /// reason. Excluding by name is auditable in a way "skip string literals"
  /// heuristics are not — and the first draft of this scanner counted its own
  /// predicate strings, which is exactly the failure the list prevents.
  public static let excluded: [String: String] = [
    "ShimInventory.swift": "the scanner itself — its predicates name the patterns it counts",
    "RelayBenchmark.swift": "measurement machinery, not a boundary adapter",
    "SuspendController.swift":
      "a verbatim copy of the app's file; its Sendable assertion predates the K/N boundary"
  ]

  /// Scans `roots` and classifies every declaration that needed a workaround.
  ///
  /// Classification is **mutually exclusive**, by descending specificity, so
  /// the total is a count of declarations rather than of matches. A single
  /// `nonisolated final class Box: @unchecked Sendable` is one workaround the
  /// boundary forced, not two — summing overlapping categories was the first
  /// draft's other defect, and it inflated the headline figure by ~2x.
  ///
  /// - Throws: ``ShimInventoryError/emptyRoot(_:)`` when **any** root yields no
  ///   Swift files, and ``ShimInventoryError/staleExclusion(_:)`` when an
  ///   entry in ``excluded`` matches no file. Per-root, not "every root came
  ///   up empty": a partial under-report is the most misleading way this
  ///   measurement could fail, because it still prints a plausible number.
  ///   A rename that quietly disables an exclusion is the same hazard.
  public static func scan(roots: [String]) throws -> ShimInventory {
    var files: [(path: String, lines: [String])] = []
    var seenNames: Set<String> = []
    for root in roots {
      for path in try swiftFiles(under: root) {
        let name = (path as NSString).lastPathComponent
        seenNames.insert(name)
        guard excluded[name] == nil else { continue }
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        files.append((path, contents.components(separatedBy: "\n")))
      }
    }
    if let stale = excluded.keys.sorted().first(where: { !seenNames.contains($0) }) {
      throw ShimInventoryError.staleExclusion(stale)
    }

    var buckets: [String: [Hit]] = [:]
    for file in files {
      for (index, line) in file.lines.enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // A rationale that *names* a workaround is not an instance of one.
        guard !trimmed.hasPrefix("//") else { continue }
        guard let bucket = classify(line) else { continue }
        buckets[bucket, default: []].append(
          Hit(file: (file.path as NSString).lastPathComponent, line: index + 1, text: trimmed))
      }
    }

    return ShimInventory(
      categories: rationales.map { name, rationale in
        Category(name: name, rationale: rationale, hits: buckets[name] ?? [])
      })
  }

  /// Category names paired with what the K/N boundary withholds, in report
  /// order. The order is also the classification priority.
  private static let rationales: [(String, String)] = [
    (
      "retroactive Sendable vouch",
      """
      K/N emits no Swift `Sendable` conformances, so a Kotlin type that \
      demonstrably crosses threads must be vouched for from the Swift side.
      """
    ),
    (
      "hand-asserted Sendable conformance",
      """
      A Kotlin protocol carries no `Sendable`, and an existential of one \
      cannot be given a retroactive conformance at all — so every type that \
      implements or carries one asserts thread-safety by hand, whether it is \
      an adapter or a wrapper that exists only to cross a `Mutex` \
      (`withLock` takes `inout sending`).
      """
    ),
    (
      "type-level nonisolated only",
      """
      The package compiles under default-`MainActor` isolation to mirror the \
      app, so every type that must keep Engine/LLM semantics says so \
      explicitly — including sibling-file extensions.
      """
    )
  ]

  /// Assigns a line to at most one category, most specific first.
  ///
  /// `internal` rather than `private` so `ShimInventoryTests` can pin the
  /// precedence directly. Going through `scan(roots:)` cannot reach it without
  /// fabricating one file per ``excluded`` entry: `scan` throws
  /// ``ShimInventoryError/staleExclusion(_:)`` unless every name in that list
  /// appears in the scanned roots, so a fixture directory holding only the
  /// overlapping lines throws before classifying anything.
  static func classify(_ line: String) -> String? {
    if line.contains("@retroactive") && line.contains("Sendable") {
      return "retroactive Sendable vouch"
    }
    if line.contains("@unchecked Sendable") {
      return "hand-asserted Sendable conformance"
    }
    let declarators = ["final class", "struct", "enum", "extension"]
    if line.contains("nonisolated ") && declarators.contains(where: { line.contains($0) }) {
      return "type-level nonisolated only"
    }
    return nil
  }

  /// - Throws: ``ShimInventoryError/emptyRoot(_:)`` when this root contributes
  ///   nothing. Returning `[]` — as this did — makes a moved or renamed root
  ///   indistinguishable from one that legitimately holds no Swift files, and
  ///   the caller's "did *any* root yield files?" check then passes on the
  ///   surviving roots while the budget silently loses the moved one's hits.
  ///   Under-reporting is the one failure this measurement must not have.
  private static func swiftFiles(under root: String) throws -> [String] {
    let manager = FileManager.default
    guard let enumerator = manager.enumerator(atPath: root) else {
      throw ShimInventoryError.emptyRoot(root)
    }
    let files =
      enumerator
      .compactMap { $0 as? String }
      .filter { $0.hasSuffix(".swift") }
      .map { (root as NSString).appendingPathComponent($0) }
      .sorted()
    guard !files.isEmpty else { throw ShimInventoryError.emptyRoot(root) }
    return files
  }
}

/// Why the shim inventory could not be produced.
/// `Equatable` so tests can pin the specific case rather than settling for
/// `ShimInventoryError.self`, which any of these would satisfy.
nonisolated public enum ShimInventoryError: Error, Equatable, CustomStringConvertible {
  /// A scan root contributed no Swift files — a wrong working directory, or a
  /// root that moved. Raised per root, not once for the whole set.
  case emptyRoot(String)
  /// An entry in ``ShimInventory/excluded`` matched no file — a rename would
  /// otherwise silently re-enable counting the scanner's own source.
  case staleExclusion(String)

  public var description: String {
    switch self {
    case .emptyRoot(let root):
      return """
        no Swift sources under '\(root)' — run kmp-gate-bench from the \
        repository root, or update the root if it moved
        """
    case .staleExclusion(let name):
      return "ShimInventory.excluded names '\(name)', which no longer exists — update the list"
    }
  }
}

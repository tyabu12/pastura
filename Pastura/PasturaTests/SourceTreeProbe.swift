import Foundation

/// Read-only walker over the app target's Swift sources, shared by the guards
/// that assert something about the *source tree* rather than about runtime
/// behaviour — `StructuralBoundaryTests` (ADR-010 D8) and
/// `MutedSweepLedgerTests` (#1448).
///
/// **The repo root comes from `#filePath`, and that is load-bearing.** The
/// bundle-walk resolver this replaced — walk up from `Bundle.main.bundlePath`
/// looking for a `Pastura/Pastura` marker, else fall back to the process
/// working directory — cannot resolve on a simulator test runner: the app is
/// installed into the simulator's own container, so no ancestor of the bundle
/// carries the marker, and the fallback lands on `/`. Every directory the
/// caller then scanned was absent, ``swiftFilesContaining(_:under:)`` returned
/// `[]` through its `fileExists` guard, and the guard passed with nothing
/// scanned. Measured on the iPhone 17 Pro simulator: `bundleWalkFound=NIL`,
/// `cwd=/`. `#filePath` expands at compile time to this file's absolute source
/// path and is what the rest of the suite already uses (`AppStoreLinksTests`,
/// `RecordsCountPluralTests`, `SimulationViewModalInventoryTests`).
///
/// That failure mode is why every caller must **assert it scanned something**.
/// A source-tree guard that finds no files reports success, so a broken root or
/// a renamed directory reads exactly like a clean tree.
enum SourceTreeProbe {

  /// Repository root, resolved from this file's compile-time path.
  static let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // Pastura/PasturaTests
    .deletingLastPathComponent()  // Pastura
    .deletingLastPathComponent()  // repo root

  /// `Pastura/Pastura` — the app target's source root.
  static let appSourceRoot = repoRoot.appending(path: "Pastura/Pastura")

  /// Every `.swift` file under `directory`, recursively.
  ///
  /// Empty when `directory` does not exist — callers must not read that as
  /// "no matches", see the type's note above.
  static func swiftFiles(under directory: URL) -> [URL] {
    let manager = FileManager.default
    guard manager.fileExists(atPath: directory.path) else { return [] }
    guard
      let enumerator = manager.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles])
    else { return [] }

    var files: [URL] = []
    for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
      files.append(fileURL)
    }
    return files
  }

  /// Every `(app-relative path, line)` under `directory` whose line contains
  /// one of `needles` and is **not** a comment.
  ///
  /// A line counts as a comment when its first non-whitespace characters are
  /// `//`, which covers `//` and `///` alike. Deliberately not a parser, and it
  /// errs in both directions: a trailing comment on a code line, or a `/* … */`
  /// block, still counts — and a line **inside a `"""` literal** that happens to
  /// start with `//` is skipped, which is the direction that *hides* an
  /// occurrence and so the one a census cares about. Both were enumerated and
  /// returned nothing when this was written (#1448) — re-run rather than
  /// inherit the claim:
  ///
  ///     grep -rn "Color\.muted" Pastura/Pastura --include="*.swift" \
  ///       | grep -E '[^ ].*//.*Color\.muted' | grep -vE ':[0-9]+: *//'
  ///
  /// for the trailing-comment direction, and a scan for a `//`-leading line
  /// between an odd pair of `"""` delimiters for the hiding one. Both
  /// callers want the same thing from it — a source-tree guard that fires on a
  /// *reference* must not fire on prose naming the thing it guards, which is
  /// what `Models/Scenario.swift` does for `LocaleResolver`.
  static func matchingLines(
    of needles: [String], under directory: URL
  ) -> [(path: String, line: String)] {
    var result: [(path: String, line: String)] = []
    for fileURL in swiftFiles(under: directory) {
      guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
      let path = appRelativePath(fileURL.path)
      for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        guard !trimmed.hasPrefix("//") else { continue }
        if needles.contains(where: line.contains) { result.append((path, String(line))) }
      }
    }
    return result
  }

  /// App-relative paths of `.swift` files under `directory` carrying a
  /// non-comment occurrence of `needle`. Plain substring matching, not a
  /// parser.
  static func swiftFilesContaining(_ needle: String, under directory: URL) -> [String] {
    Set(matchingLines(of: [needle], under: directory).map(\.path)).sorted()
  }

  /// `path`, expressed relative to ``appSourceRoot`` (e.g.
  /// `Views/Results/ResultsView.swift`). Returned unchanged when it lies
  /// outside that root.
  static func appRelativePath(_ path: String) -> String {
    let prefix = appSourceRoot.path + "/"
    guard path.hasPrefix(prefix) else { return path }
    return String(path.dropFirst(prefix.count))
  }
}

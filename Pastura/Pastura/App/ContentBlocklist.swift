import Foundation

/// Shared blocklist resource used by both ``ScenarioContentValidator`` (input
/// validation) and ``ContentFilter`` (output filtering).
///
/// Per ADR-005 §4.4, the bundled file at
/// `Pastura/Pastura/Resources/ContentBlocklist.txt` is the single source of
/// truth for content-safety patterns. Production callers use
/// ``defaultPatterns``; tests inject an alternate bundle via ``load(from:)``,
/// mirroring the ``PresetLoader`` pattern so the `.main` default path is
/// never evaluated under the XCTest host without the host-app bundle present.
///
/// Declared `nonisolated` so ``ContentFilter`` (itself `nonisolated + Sendable`)
/// can access ``defaultPatterns`` without crossing a MainActor boundary under
/// the project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
nonisolated enum ContentBlocklist {
  /// Patterns loaded from the app bundle at first access.
  ///
  /// Evaluated lazily by Swift's `static let` semantics. A missing or
  /// unreadable resource triggers ``preconditionFailure`` — a
  /// build-configuration bug should fail fast at launch rather than
  /// silently degrade the filter to an empty list.
  static let defaultPatterns: [String] = load(from: .main)

  /// Loads the blocklist from the given bundle.
  ///
  /// - Parameter bundle: Bundle to load from. Production uses `.main`;
  ///   tests pass `Bundle(for: DatabaseManager.self)` (matching
  ///   ``PresetLoader``'s test pattern) to point at the host-app bundle.
  /// - Returns: Parsed pattern list.
  static func load(from bundle: Bundle) -> [String] {
    guard
      let url = bundle.url(forResource: "ContentBlocklist", withExtension: "txt"),
      let text = try? String(contentsOf: url, encoding: .utf8)
    else {
      preconditionFailure(
        "ContentBlocklist.txt missing or unreadable in bundle \(bundle.bundleIdentifier ?? "<unknown>")"
      )
    }
    return parse(text)
  }

  /// Parses the raw blocklist text into a pattern array.
  ///
  /// Extracted from ``load(from:)`` so the parser can be unit-tested with
  /// inline fixtures without a bundle round-trip.
  ///
  /// - Blank lines are skipped.
  /// - Lines beginning with `#` are treated as comments and skipped.
  /// - Leading and trailing whitespace on each line is trimmed before
  ///   the comment / blank check.
  static func parse(_ text: String) -> [String] {
    text.split(separator: "\n", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty && !$0.hasPrefix("#") }
  }
}

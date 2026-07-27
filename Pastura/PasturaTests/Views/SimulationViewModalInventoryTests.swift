import Foundation
import Testing

@testable import Pastura

/// Drift gate for `SimulationView.isAnyModalPresented` (#1279).
///
/// That predicate is a hand-maintained enumeration of the view's modal
/// bindings, consumed to suppress the App Store review prompt while the screen
/// is obstructed. Adding a `.sheet` / `.alert` / `.fullScreenCover` without
/// extending it silently re-opens the failure it guards — the prompt fires
/// under a modal, and because the version stamp is written *before* the
/// request, that build's single attempt is burned with nothing shown.
///
/// A doc comment reaches readers; this reaches editors. Source-reading via
/// `#filePath` follows the same technique as `AppStoreLinksTests` and
/// `RecordsCountPluralTests`.
///
/// **A failure is not a bug.** It means the modal inventory changed: add the
/// new binding's state to `isAnyModalPresented` (or convince yourself it
/// cannot obstruct the result card), then update the expected count here.
@Suite(.timeLimit(.minutes(1)))
struct SimulationViewModalInventoryTests {

  /// Every modal-presenting modifier across `SimulationView`'s own files.
  /// Counted, not parsed: the point is to notice the *arrival* of a new one.
  ///
  /// Current inventory — 7 presenters mapping to 8 terms in
  /// `isAnyModalPresented` (`highlightShareSurfaces` mounts two bindings, so
  /// the two counts legitimately differ): prediction sheet, export share
  /// sheet, export-failure alert, `highlightShareSurfaces`, leave sheet,
  /// scoreboard sheet, persona sheet.
  private static let expectedPresenterCount = 7

  @Test func modalPresenterCountMatchesTheGuardedInventory() throws {
    let sources = try Self.simulationViewSources()

    let presenters = sources.reduce(into: 0) { total, source in
      for marker in [".sheet(", ".alert(", ".fullScreenCover(", ".highlightShareSurfaces("] {
        total += source.components(separatedBy: marker).count - 1
      }
    }

    #expect(
      presenters == Self.expectedPresenterCount,
      """
      SimulationView's modal-presenter count changed (\(presenters) vs \
      \(Self.expectedPresenterCount)). Extend `isAnyModalPresented` to cover the \
      new binding, then update `expectedPresenterCount`.
      """)
  }

  // MARK: - Sources

  /// `SimulationView` is split across siblings; a new presenter could land in
  /// any of them, so the gate reads all three rather than the main file alone.
  private static func simulationViewSources() throws -> [String] {
    let viewsDir = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // Views
      .deletingLastPathComponent()  // PasturaTests
      .deletingLastPathComponent()  // Pastura
      .appending(path: "Pastura/Views/Simulation")

    return try [
      "SimulationView.swift",
      "SimulationView+LogEntries.swift",
      "SimulationView+Background.swift"
    ].map { try String(contentsOf: viewsDir.appending(path: $0), encoding: .utf8) }
  }
}

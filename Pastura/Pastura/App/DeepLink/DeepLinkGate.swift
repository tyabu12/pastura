import Foundation
import SwiftUI

/// Per-scene observable coordinating Deep Link queueing.
///
/// `sheetPresentationCount` is incremented by the `.deepLinkGated()` view
/// modifier whenever a gated sheet's content appears, and decremented on
/// disappear. The `RootView` consults `isSheetActive` (and its own other
/// signals — app state, router path) to decide whether to drain a
/// `pendingURL` or keep it queued and show a blocking-reason toast.
///
/// The gate intentionally does **not** track app state or router
/// navigation depth — those signals live at `RootView` where they're
/// naturally observable. Keeping this type small makes it cheap to
/// inject and keeps the "one responsibility per observable" rule.
@Observable @MainActor
public final class DeepLinkGate {
  /// How many gated sheets are currently on-screen. Counter semantics so
  /// nested/stacked sheets (e.g. a report sheet over a phase editor)
  /// don't prematurely release the gate when the inner one dismisses.
  public var sheetPresentationCount: Int = 0

  /// The most recently received Deep Link URL that is waiting for a
  /// navigable state. "Most-recent-wins" — if a new URL arrives while
  /// one is pending, it replaces the old one.
  public var pendingURL: URL?

  public init() {}

  /// True while any `.deepLinkGated()`-marked sheet is on-screen.
  public var isSheetActive: Bool { sheetPresentationCount > 0 }
}

/// Attach to a sheet's content view so its presentation lifetime is
/// counted by the scene-level `DeepLinkGate`.
///
/// Usage:
/// ```swift
/// .sheet(isPresented: $showing) {
///   PhaseEditorSheet(...)
///     .deepLinkGated()
/// }
/// ```
///
/// The modifier reads `DeepLinkGate` from the environment; the parent
/// scene MUST inject it via `.environment(gate)` at or above the sheet
/// presenter. Forgetting to inject is a programmer error — the
/// environment lookup falls back to a dummy gate and the counter never
/// propagates to the real one. Sheet content should always be wrapped.
extension View {
  public func deepLinkGated() -> some View {
    modifier(DeepLinkGatedModifier())
  }
}

private struct DeepLinkGatedModifier: ViewModifier {
  @Environment(DeepLinkGate.self) private var gate

  func body(content: Content) -> some View {
    content
      .onAppear { gate.sheetPresentationCount += 1 }
      .onDisappear { gate.sheetPresentationCount -= 1 }
  }
}

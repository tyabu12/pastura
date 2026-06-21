import SwiftUI

/// A drop-in replacement for an indeterminate `ProgressView` that renders a
/// **static** placeholder under the XCUITest harness (`\.isUITestMode`).
///
/// An indeterminate `ProgressView` is a continuous `CAAnimation` that never
/// settles, so XCUITest's automatic synchronization never sees the app reach
/// "idle" and stalls every element query for the full idle-wait. On the
/// GPU-less CI simulator this is the dominant cost in the heavy `SimulationView`
/// UI tests (#728). Swapping to a non-animating stand-in while testing lets the
/// idle-wait resolve immediately; production (where `isUITestMode` is `false`)
/// renders the real spinner unchanged.
struct IdleFriendlyProgressView: View {
  @Environment(\.isUITestMode) private var isUITestMode

  /// Optional title, mirroring `ProgressView(_:)`'s `StringProtocol` overload.
  /// Kept as `String` (not `LocalizedStringKey`) so callers pass the existing
  /// `String(localized:)` value verbatim — no change to catalog extraction.
  private let title: String?

  init() {
    self.title = nil
  }

  /// - Parameter title: Must be an already-localized string (e.g.
  ///   `String(localized: "…")`) — it is displayed verbatim. The SwiftLint
  ///   i18n tripwire does not inspect this initializer, so a bare literal here
  ///   would silently escape catalog extraction.
  init(_ title: String) {
    self.title = title
  }

  var body: some View {
    if isUITestMode {
      // Static stand-in: preserves a visible placeholder (and the title, if any)
      // without an animating indicator that would stall XCUITest's idle-wait.
      if let title {
        Text(title)
      } else {
        Image(systemName: "ellipsis")
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }
    } else if let title {
      ProgressView(title)
    } else {
      ProgressView()
    }
  }
}

import OSLog
import SwiftUI

/// ADR-020 D5 "Open App Store" deep link, split out of
/// `GalleryScenarioDetailView` to satisfy SwiftLint's `type_body_length` cap
/// (mirrors `GalleryScenarioDetailView+RecommendedModel.swift`).
extension GalleryScenarioDetailView {
  /// Builds the `.alert(item:)` content for an ``OutcomeAlert``.
  ///
  /// Only the ADR-020 D5 `.updateRequired` outcome carries `appStoreURL`;
  /// every other outcome keeps the plain single-dismiss form. Not `private`:
  /// called from `GalleryScenarioDetailView.body` in the sibling file.
  func outcomeAlertView(for alert: OutcomeAlert) -> Alert {
    guard let appStoreURL = alert.appStoreURL else {
      return Alert(title: Text(alert.title), message: Text(alert.message))
    }
    return Alert(
      title: Text(alert.title),
      message: Text(alert.message),
      primaryButton: .default(Text(String(localized: "Open App Store"))) {
        openAppStore(appStoreURL)
      },
      secondaryButton: .cancel())
  }

  /// Opens the `.updateRequired` alert's "Open App Store" button target.
  ///
  /// Uses the `openURL(_:completion:)` overload rather than the fire-and-forget
  /// form, mirroring `SettingsView+Feedback.swift`'s `externalLinkRow`:
  /// `openURL` reports nothing on a URL the system cannot route, so a broken
  /// link would be indistinguishable from a tester not noticing. The log line
  /// is the only signal such a regression would leave.
  ///
  /// Not `private`: called from `GalleryScenarioDetailView.body` in the sibling
  /// file — `private` blocks cross-file extension access.
  func openAppStore(_ url: URL) {
    openURL(url) { accepted in
      guard !accepted else { return }
      Self.linkLogger.error(
        "openURL declined for \(url.absoluteString, privacy: .public)")
    }
  }

  private static let linkLogger = Logger(
    subsystem: "app.pastura.Pastura", category: "GalleryScenarioDetailLinks")
}

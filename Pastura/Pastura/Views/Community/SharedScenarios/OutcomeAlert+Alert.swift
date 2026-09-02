import OSLog
import SwiftUI

/// SwiftUI rendering of an ``OutcomeAlert``, shared by the two surfaces that
/// present one: the gallery detail's install outcomes (ADR-020 D5) and the
/// Browse catalog's greyed, engine-incompatible card (ADR-020 D4), which
/// presents the same `.updateRequired` alert so the "why" reaches the user
/// before the App Store does.
extension OutcomeAlert {
  /// The `.alert(item:)` content for this outcome.
  ///
  /// Only an alert carrying ``appStoreURL`` renders the two-button form with
  /// **Open App Store**; every other outcome keeps the plain single-dismiss
  /// form. `openURL` is the presenting view's `\.openURL` environment action.
  func makeAlert(openURL: OpenURLAction) -> Alert {
    guard let appStoreURL else {
      return Alert(title: Text(title), message: Text(message))
    }
    return Alert(
      title: Text(title),
      message: Text(message),
      primaryButton: .default(Text(String(localized: "Open App Store"))) {
        Self.openAppStore(appStoreURL, with: openURL)
      },
      secondaryButton: .cancel())
  }

  /// Uses the `openURL(_:completion:)` overload rather than the fire-and-forget
  /// form, mirroring `SettingsView+Feedback.swift`'s `externalLinkRow`:
  /// `openURL` reports nothing on a URL the system cannot route, so a broken
  /// link would be indistinguishable from a tester not noticing. The log line
  /// is the only signal such a regression would leave.
  private static func openAppStore(_ url: URL, with openURL: OpenURLAction) {
    openURL(url) { accepted in
      guard !accepted else { return }
      linkLogger.error(
        "openURL declined for \(url.absoluteString, privacy: .public)")
    }
  }

  private static let linkLogger = Logger(
    subsystem: "app.pastura.Pastura", category: "OutcomeAlertLinks")
}

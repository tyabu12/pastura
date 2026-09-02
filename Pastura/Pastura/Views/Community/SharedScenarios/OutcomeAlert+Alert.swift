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
  /// form (``hasStoreAction`` is the unit-testable name for that branch).
  /// `openURL` is the presenting view's `\.openURL` environment action.
  func makeAlert(openURL: OpenURLAction) -> Alert {
    guard let appStoreURL else {
      return Alert(title: Text(title), message: Text(message))
    }
    return Alert(
      title: Text(title),
      message: Text(message),
      primaryButton: .default(Text(String(localized: "Open App Store"))) {
        openURL.callLogged(appStoreURL, logger: Self.linkLogger)
      },
      secondaryButton: .cancel())
  }

  private static let linkLogger = Logger(
    subsystem: "app.pastura.Pastura", category: "OutcomeAlertLinks")
}

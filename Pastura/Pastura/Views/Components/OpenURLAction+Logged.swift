import OSLog
import SwiftUI

extension OpenURLAction {
  /// Opens `url` and logs when the system declines it.
  ///
  /// Uses the `callAsFunction(_:completion:)` overload rather than the
  /// fire-and-forget form: `openURL` reports nothing on a URL the system
  /// cannot route, so a broken link would be indistinguishable from a tester
  /// not noticing. The log line is the only signal such a regression would
  /// leave. Shared by every external-link surface (Settings rate-app row, the
  /// ADR-020 "Open App Store" alert button) so the message and its
  /// `privacy: .public` annotation cannot drift between them.
  func callLogged(_ url: URL, logger: Logger) {
    self(url) { accepted in
      guard !accepted else { return }
      logger.error("openURL declined for \(url.absoluteString, privacy: .public)")
    }
  }
}

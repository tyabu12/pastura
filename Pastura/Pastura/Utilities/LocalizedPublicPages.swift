import Foundation

/// Locale-routed URLs for Pastura's public pages (pastura.app).
///
/// Per ADR-010 D6, UI-shell consumers read `Bundle.main.preferredLocalizations`
/// directly (Apple's standard `String(localized:)` resolution). `LocaleResolver`
/// is deliberately NOT used here: its D2 scope is new-data creation seeds and
/// multi-variant selection of stored content, not external URL routing for the
/// shell itself.
///
/// Japanese (`"ja"`) routes to the `/ja/` mirror (`pages/ja/**`); every other
/// locale falls through to the English pages.
nonisolated enum LocalizedPublicPages {

  /// Privacy Policy page (`pages/legal/privacy-policy/`). Linked from
  /// Settings → Legal per App Store Guideline 5.1.1.
  ///
  /// - Parameter preferredLocalizations: Injectable for unit tests.
  ///   Production callers pass `Bundle.main.preferredLocalizations`
  ///   (the default).
  static func privacyPolicy(
    preferredLocalizations: [String] = Bundle.main.preferredLocalizations
  ) -> URL? {
    url(path: "legal/privacy-policy/", preferredLocalizations: preferredLocalizations)
  }

  /// Support landing page (`pages/support/`) — the App Store Connect
  /// Support URL and ADR-005 §6 report-channel host. Also documents
  /// supported devices, which is why the unsupported-device fallback
  /// links here instead of hardcoding model names that drift (#499).
  ///
  /// - Parameter preferredLocalizations: Injectable for unit tests.
  ///   Production callers pass `Bundle.main.preferredLocalizations`
  ///   (the default).
  static func support(
    preferredLocalizations: [String] = Bundle.main.preferredLocalizations
  ) -> URL? {
    url(path: "support/", preferredLocalizations: preferredLocalizations)
  }

  private static func url(
    path: String, preferredLocalizations: [String]
  ) -> URL? {
    let prefix = preferredLocalizations.first == "ja" ? "ja/" : ""
    return URL(string: "https://pastura.app/\(prefix)\(path)")
  }
}

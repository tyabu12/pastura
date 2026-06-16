import Foundation

/// Locale-routed URLs for Pastura's public pages (pastura.app).
///
/// Per ADR-010 D6, UI-shell consumers read `Bundle.main.preferredLocalizations`
/// directly (Apple's standard `String(localized:)` resolution). `LocaleResolver`
/// is deliberately NOT used here: its D2 scope is new-data creation seeds and
/// multi-variant selection of stored content, not external URL routing for the
/// shell itself.
///
/// Japanese (`"ja"`) routes to the `/ja/` mirror (`web/src/pages/ja/**`);
/// every other locale falls through to the English pages.
nonisolated enum LocalizedPublicPages {

  /// Privacy Policy page (`web/src/pages/legal/privacy-policy.astro`). Linked from
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

  /// Support landing page (`web/src/pages/support.astro`) — the App Store Connect
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

  /// Deep link to the "Supported devices" section of the support page.
  /// The fragment matches the `id="supported-devices"` anchor in
  /// `web/src/pages/support.astro` and its `ja` mirror
  /// (`web/src/pages/ja/support.astro`) — update both if the anchor is
  /// ever renamed.
  static func supportedDevices(
    preferredLocalizations: [String] = Bundle.main.preferredLocalizations
  ) -> URL? {
    url(
      path: "support/#supported-devices",
      preferredLocalizations: preferredLocalizations)
  }

  /// Scenario guide page (`web/src/pages/docs/scenario.astro`) — the public
  /// walkthrough of how Pastura scenarios work. Linked from the
  /// in-app scenario editor's help affordance (#638), completing the
  /// Swift-side half of the guide shipped on pastura.app in #628.
  ///
  /// - Parameter preferredLocalizations: Injectable for unit tests.
  ///   Production callers pass `Bundle.main.preferredLocalizations`
  ///   (the default).
  static func scenarioGuide(
    preferredLocalizations: [String] = Bundle.main.preferredLocalizations
  ) -> URL? {
    url(path: "docs/scenario/", preferredLocalizations: preferredLocalizations)
  }

  private static func url(
    path: String, preferredLocalizations: [String]
  ) -> URL? {
    let prefix = preferredLocalizations.first == "ja" ? "ja/" : ""
    return URL(string: "https://pastura.app/\(prefix)\(path)")
  }
}

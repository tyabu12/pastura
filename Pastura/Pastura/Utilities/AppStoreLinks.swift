import Foundation

/// App Store deep links for Pastura's own product page.
///
/// Sibling of ``LocalizedPublicPages`` (which routes pastura.app pages); kept
/// separate because the App Store product page has no per-locale variant — the
/// store localizes it from the requesting device.
nonisolated enum AppStoreLinks {

  /// Pastura's App Store item id, as published on pastura.app.
  ///
  /// Mirrored in `web/src/pages/index.astro` (and its `ja` mirror),
  /// `web/src/pages/404.astro`, and `web/src/components/ScenarioLanding.astro`.
  /// Those are the store-badge links; this is the in-app one.
  static let appStoreItemID = "6788409688"

  /// Opens the product page with the write-a-review sheet pre-presented — the
  /// passive, always-available counterpart to the rate-limited system prompt
  /// in `App/`. (Named in prose, not DocC-linked: `Utilities/` depends on
  /// nothing, and a symbol link is the shape that invites a real import.)
  /// User-initiated, so StoreKit's 3-per-365-days
  /// cap does not apply, and it stays the path for users who disabled
  /// in-app rating requests entirely.
  ///
  /// `https` rather than the `itms-apps://` variant: iOS routes the
  /// `apps.apple.com` universal link to the App Store app either way, whereas
  /// an unregistered custom scheme makes `openURL` fail **silently** — which
  /// device QA cannot distinguish from a tester simply not noticing.
  static let writeReview = URL(
    string: "https://apps.apple.com/app/id\(appStoreItemID)?action=write-review")

  /// The plain product page — no `action=` query. Deep-link target for the
  /// ADR-020 D4/D5 "update the app" affordance: the `.updateRequired` install
  /// outcome's alert opens this so the user can update from the App Store
  /// rather than being told and left to find it themselves.
  ///
  /// `https` rather than `itms-apps://` for the same reason as ``writeReview``.
  static let productPage = URL(string: "https://apps.apple.com/app/id\(appStoreItemID)")
}

import OSLog
import SwiftUI

// Feedback section (rate the app + content report) and the shared
// external-link row for `SettingsView` (#1279). Split into this sibling to
// keep `SettingsView` under the file_length cap. `SettingsView` is a
// default-MainActor View, so this extension needs no `nonisolated`
// annotation.

extension SettingsView {
  /// The two ways a user can tell us something (#1279): rate the app on the
  /// App Store, or report content.
  ///
  /// "Rate Pastura" is the passive, always-available counterpart to the
  /// rate-limited system prompt fired from `SimulationView` — user-initiated,
  /// so StoreKit's 3-per-365-days cap does not apply, and it remains reachable
  /// for users who turned in-app rating requests off.
  ///
  /// The content-report row lives here rather than under Legal: reporting is
  /// feedback, and a discoverability-driven rate row buried in a legal section
  /// would defeat its own purpose. ADR-005 §6.6's substantive commitment is
  /// about the Settings *surface* exposing report-mechanism copy (carried by
  /// `ReportSheet`'s introCopy), not about which section header sits above it.
  ///
  /// Not `private`: `private` is file-scoped, and `SettingsView.body` lives in
  /// the sibling file.
  var feedbackSection: some View {
    PasturaSection(String(localized: "Feedback"), style: .grouped) {
      VStack(spacing: 0) {
        externalLinkRow(
          title: String(localized: "Rate Pastura"),
          url: AppStoreLinks.writeReview,
          accessibilityIdentifier: "settings.rateAppLink")

        PasturaRowDivider(leadingInset: PasturaCardMetrics.horizontalMargin)
        Button {
          isReportSheetPresented = true
        } label: {
          PasturaRowLabel(title: String(localized: "Send a content report"))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.sendContentReportButton")
      }
    }
  }

  /// A row that leaves the app: green `Color.link` text plus the external-link
  /// glyph, no chevron (Theme D — see the `body` comment).
  ///
  /// Opens through ``OpenURLAction/callLogged(_:logger:)`` so a URL the
  /// system declines leaves a log line (see that helper for why).
  ///
  /// ⚠️ **`title` MUST be a `String(localized:)` value.** It renders through
  /// `Text(_:)` as a plain `String`, invisible to both the SwiftLint tripwire
  /// and `check_i18n_potential_keys.py` — a future caller passing a raw literal
  /// leaks untranslated copy with no gate firing. Typing the parameter
  /// `LocalizedStringKey` is a real alternative — but it needs
  /// `extractionState: "manual"` on every key, which trades this leak for a
  /// silent orphan on the next copy rename. Both measured; the trade-off table
  /// is `.claude/rules/i18n-ui.md` § "A custom func's `LocalizedStringKey`
  /// parameter is not extracted". Revisit if this helper gains more callers.
  func externalLinkRow(
    title: String,
    url: URL?,
    accessibilityIdentifier: String
  ) -> some View {
    Button {
      guard let url else { return }
      openURL.callLogged(url, logger: Self.linkLogger)
    } label: {
      HStack {
        Text(title)
          .foregroundStyle(Color.link)
        Spacer()
        Image(systemName: "arrow.up.right.square")
          .foregroundStyle(Color.link)
      }
      .padding(.horizontal, 17)
      .padding(.vertical, 15)
      .contentShape(Rectangle())
    }
    .accessibilityIdentifier(accessibilityIdentifier)
  }

  private static let linkLogger = Logger(
    subsystem: "app.pastura.Pastura", category: "SettingsLinks")
}

import SwiftUI

/// Dual-use presentation surface for content reports.
///
/// - **Scenario-scoped** (`scenario != nil`): pushed from a Shared
///   Scenarios detail's More menu. Shows scenario metadata, pre-fills
///   the form / GitHub URLs with scenarioId.
/// - **General** (`scenario == nil`): pushed from Settings → Legal →
///   "Send a content report". Hides scenarioMetadata; routes the
///   form and GitHub URLs to the no-scenarioId variants in
///   `ReportURLBuilder`. The Google Forms scenario id field and the
///   GitHub issue template's `scenario_id` are both configured as
///   optional with "leave blank for general feedback" hints — same
///   shape as the App Store Connect §1.5 Support URL co-tenancy
///   precedent in ADR-005 §6.7.
///
/// Progressive disclosure: the primary action opens a Google Forms
/// report in Safari (no account required); the secondary opens a
/// GitHub issue for reporters who prefer public discussion. Text
/// entry happens on the external page — this sheet is a metadata
/// display and launching pad only.
///
/// Dismissal: there is no Cancel toolbar item. The sheet relies on
/// the swipe-down gesture (interactive dismiss is enabled by default
/// for `.presentationDetents([.medium, .large])`).
///
/// See ADR-005 §6 (and §6.7 for the dual-use precedent) for the
/// policy rationale, and `docs/gallery/shared-scenario-reports.md`
/// for operational details.
///
/// The type/file name still encodes scenario-specificity. Renaming
/// to `ReportSheet` is deferred to a follow-up to keep this PR
/// focused on the UX additions.
struct ReportScenarioSheet: View {
  let scenario: GalleryScenario?

  @Environment(\.openURL) private var openURL
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          if let scenario {
            scenarioMetadata(for: scenario)
          }
          introCopy
          primarySection
          Divider()
          secondarySection
        }
        .padding()
      }
      .navigationTitle(navigationTitleText)
      .navigationBarTitleDisplayMode(.inline)
    }
    .presentationDetents([.medium, .large])
  }

  private var navigationTitleText: String {
    scenario == nil
      ? String(localized: "Send report")
      : String(localized: "Report scenario")
  }

  // MARK: - Sections

  private func scenarioMetadata(for scenario: GalleryScenario) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(scenario.title)
        .font(.headline)
      Text(String(format: String(localized: "ID: %@"), scenario.id))
        .font(.caption)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
  }

  private var introCopy: some View {
    Text(
      String(
        localized:
          "Reports are reviewed by the Pastura maintainer. You'll receive a confirmation email when your report is received."
      )
    )
    .font(.body)
    .foregroundStyle(.secondary)
  }

  private var primarySection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Button(action: openReportForm) {
        HStack {
          Image(systemName: "paperplane.fill")
          Text(String(localized: "Open Report Form"))
        }
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .accessibilityIdentifier("reportSheet.openFormButton")

      Text(String(localized: "No account required."))
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(
        String(
          localized:
            "Opens Google Forms in Safari. Your report is processed by Google under their privacy policy."
        )
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
  }

  private var secondarySection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(String(localized: "Prefer public discussion?"))
        .font(.footnote)

      Button(action: openGitHubIssue) {
        HStack {
          Image(systemName: "arrow.up.right.square")
          Text(String(localized: "Open on GitHub"))
        }
      }
      .buttonStyle(.bordered)
      .accessibilityIdentifier("reportSheet.openGitHubButton")

      Text(String(localized: "Requires a GitHub account. The resulting issue is public."))
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  // MARK: - Actions

  private func openReportForm() {
    let urlOrNil: URL? = {
      if let scenario {
        return ReportURLBuilder.buildGoogleFormURL(
          scenarioId: scenario.id, appVersion: appVersion)
      }
      return ReportURLBuilder.buildGoogleFormURL(appVersion: appVersion)
    }()
    guard let url = urlOrNil else { return }
    openURL(url)
    dismiss()
  }

  /// Dispatches by nil-ness, mirroring `openReportForm`. The general
  /// path (`scenario == nil`) produces a bare `[Shared Scenario
  /// Report]` title; the reporter fills in details on GitHub. The
  /// issue template's `scenario_id` field is optional, so general
  /// reports can submit without a value.
  private func openGitHubIssue() {
    let urlOrNil: URL? = {
      if let scenario {
        return ReportURLBuilder.buildGitHubIssueURL(scenarioId: scenario.id)
      }
      return ReportURLBuilder.buildGitHubIssueURL()
    }()
    guard let url = urlOrNil else { return }
    openURL(url)
    dismiss()
  }

  private var appVersion: String {
    (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
  }
}

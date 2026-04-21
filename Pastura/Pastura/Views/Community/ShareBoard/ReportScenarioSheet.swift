import SwiftUI

/// Presentation surface for "Report this scenario" from Share Board.
///
/// Uses progressive disclosure: the primary action opens a pre-filled
/// Google Forms report in Safari (no account required); a secondary
/// link opens a GitHub issue for reporters who prefer public
/// discussion. Text entry happens on the external page — this sheet
/// is a metadata display and launching pad only.
///
/// See ADR-005 §6 for the policy rationale, and
/// `docs/gallery/share-board-reports.md` for operational details.
struct ReportScenarioSheet: View {
  let scenario: GalleryScenario

  @Environment(\.openURL) private var openURL
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          scenarioMetadata
          introCopy
          primarySection
          Divider()
          secondarySection
        }
        .padding()
      }
      .navigationTitle("Report scenario")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  // MARK: - Sections

  private var scenarioMetadata: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(scenario.title)
        .font(.headline)
      Text("id: \(scenario.id)")
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
      "Reports are reviewed by the Pastura maintainer. "
        + "You'll receive a confirmation email when your report is received."
    )
    .font(.body)
    .foregroundStyle(.secondary)
  }

  private var primarySection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Button(action: openReportForm) {
        HStack {
          Image(systemName: "paperplane.fill")
          Text("Open Report Form")
        }
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .accessibilityIdentifier("reportSheet.openFormButton")

      Text("No account required.")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(
        "Opens Google Forms in Safari. Your report is processed by Google "
          + "under their privacy policy."
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
  }

  private var secondarySection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Prefer public discussion?")
        .font(.footnote)

      Button(action: openGitHubIssue) {
        HStack {
          Image(systemName: "arrow.up.right.square")
          Text("Open on GitHub")
        }
      }
      .buttonStyle(.bordered)
      .accessibilityIdentifier("reportSheet.openGitHubButton")

      Text("Requires a GitHub account. The resulting issue is public.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  // MARK: - Actions

  private func openReportForm() {
    guard
      let url = ReportURLBuilder.buildGoogleFormURL(
        scenarioId: scenario.id, appVersion: appVersion)
    else { return }
    openURL(url)
    dismiss()
  }

  private func openGitHubIssue() {
    guard let url = ReportURLBuilder.buildGitHubIssueURL(scenarioId: scenario.id)
    else { return }
    openURL(url)
    dismiss()
  }

  private var appVersion: String {
    (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
  }
}

import SwiftUI

/// Settings screen hosting static informational copy for the Pastura app.
///
/// Phase-2 scope is deliberately minimal: only the Content reporting
/// section (ADR-005 §6.4 reviewer identity + brief mechanism
/// description). About / version / Cloud-API consent controls are
/// future work; this file will gain sections as those features land.
///
/// Pushed onto the root `NavigationStack` via `Route.settings`. Per
/// `.claude/rules/navigation.md`, this view must NOT add
/// `navigationDestination(item:|isPresented:)` modifiers.
struct SettingsView: View {
  var body: some View {
    List {
      Section {
        contentReportingBody
      } header: {
        Text("Content reporting")
      }
    }
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var contentReportingBody: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(
        "Reports about scenarios on the Share Board are reviewed by "
          + "the Pastura maintainer (github.com/tyabu12)."
      )
      .font(.body)

      Text(
        "To report a scenario: open it from the Share Board, tap "
          + "the More menu, and choose Report this scenario."
      )
      .font(.body)
      .foregroundStyle(.secondary)

      Text("You'll receive a confirmation email when your report is received.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, 4)
  }
}

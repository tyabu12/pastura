import SwiftUI

/// The reporting context the sheet was opened with.
///
/// An explicit three-way replacing the prior `scenario: GalleryScenario?`
/// two-state, so the illegal "scenario AND migration error" combination
/// is unrepresentable by construction.
///
/// - ``scenario(_:)``: pushed from a Shared Scenarios detail's More menu.
/// - ``migrationFailure(error:)``: presented from the DB recovery screen
///   (`PasturaApp` `.databaseRecovery`, #580) with the SQLite migration
///   error auto-attached.
/// - ``general``: pushed from Settings → Feedback → "Send a content report".
enum ReportContext {
  case scenario(GalleryScenario)
  case migrationFailure(error: String)
  case general
}

/// Multi-use presentation surface for reports.
///
/// Routes each ``ReportContext`` to the matching `ReportURLBuilder`
/// variant:
///
/// - **Scenario-scoped**: shows scenario metadata, pre-fills the
///   form / GitHub URLs with scenarioId.
/// - **Migration failure**: shows the attached error, pre-fills the
///   Google Form Reason field and a dedicated GitHub issue template
///   (`db-migration-failure.yml`) with the SQLite error. Framed as a
///   technical bug report (GitHub `bug` label / §1.5 general-contact
///   co-tenancy on the form), NOT a §1.2 UGC content report.
/// - **General**: hides scenario metadata; routes to the no-scenarioId
///   variants. The Google Forms scenario id field and the GitHub issue
///   template's `scenario_id` are both configured as optional with
///   "leave blank for general feedback" hints — same shape as the App
///   Store Connect §1.5 Support URL co-tenancy precedent in ADR-005 §6.7.
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
struct ReportSheet: View {
  let context: ReportContext

  @Environment(\.openURL) private var openURL
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          switch context {
          case .scenario(let scenario):
            scenarioMetadata(for: scenario)
          case .migrationFailure(let error):
            migrationErrorDetail(error)
          case .general:
            EmptyView()
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
    switch context {
    case .scenario:
      return String(localized: "Report scenario")
    case .migrationFailure:
      return String(localized: "Report a problem")
    case .general:
      return String(localized: "Send report")
    }
  }

  // MARK: - Sections

  private func scenarioMetadata(for scenario: GalleryScenario) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(scenario.title)
        .font(.headline)
      Text(String(format: String(localized: "ID: %@"), scenario.id))
        .font(.caption)
        .foregroundStyle(Color.muted)
        .textSelection(.enabled)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.rule.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
  }

  private func migrationErrorDetail(_ error: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(String(localized: "This error detail is attached to your report:"))
        .font(.caption)
        .foregroundStyle(Color.inkSecondary)
      Text(error)
        .font(.caption.monospaced())
        .textSelection(.enabled)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.rule.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
  }

  private var introCopy: some View {
    Text(
      String(
        localized:
          "Reports are reviewed by the Pastura maintainer. You'll receive a confirmation email when your report is received."
      )
    )
    .font(.body)
    .foregroundStyle(Color.inkSecondary)
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
        .foregroundStyle(Color.inkSecondary)
      Text(
        String(
          localized:
            "Opens Google Forms in Safari. Your report is processed by Google under their privacy policy."
        )
      )
      .font(.caption2)
      .foregroundStyle(Color.inkSecondary)
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
        .foregroundStyle(Color.inkSecondary)
    }
  }

  // MARK: - Actions

  private func openReportForm() {
    let urlOrNil: URL? = {
      switch context {
      case .scenario(let scenario):
        return ReportURLBuilder.buildGoogleFormURL(
          scenarioId: scenario.id, appVersion: appVersion)
      case .migrationFailure(let error):
        return ReportURLBuilder.buildGoogleFormURL(appVersion: appVersion, dbError: error)
      case .general:
        return ReportURLBuilder.buildGoogleFormURL(appVersion: appVersion)
      }
    }()
    guard let url = urlOrNil else { return }
    openURL(url)
    dismiss()
  }

  /// Mirrors `openReportForm`'s dispatch. The general path produces a
  /// bare `[Shared Scenario Report]` title (the template's `scenario_id`
  /// is optional, so general reports submit without a value); the
  /// migration path selects the dedicated `db-migration-failure.yml`
  /// template with the SQLite error pre-filled.
  private func openGitHubIssue() {
    let urlOrNil: URL? = {
      switch context {
      case .scenario(let scenario):
        return ReportURLBuilder.buildGitHubIssueURL(scenarioId: scenario.id)
      case .migrationFailure(let error):
        return ReportURLBuilder.buildGitHubIssueURL(migrationError: error)
      case .general:
        return ReportURLBuilder.buildGitHubIssueURL()
      }
    }()
    guard let url = urlOrNil else { return }
    openURL(url)
    dismiss()
  }

  private var appVersion: String {
    (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
  }
}

extension View {
  /// Presents a ``ReportSheet`` for the given ``ReportContext``, bound to
  /// `isPresented`.
  ///
  /// Folds the three identical report-sheet call sites
  /// (`GalleryScenarioDetailView`, `SettingsView`, `PasturaApp`'s DB-recovery
  /// screen) into one presentation surface.
  ///
  /// `.deepLinkGated()` is applied **internally** — callers must NOT wrap
  /// again. Gating is load-bearing here: a `pastura://` URL arriving while
  /// the user is mid-report queues until the sheet dismisses, rather than
  /// pushing a destination under it (see `navigation.md` QA scenario 9).
  func reportSheet(isPresented: Binding<Bool>, context: ReportContext) -> some View {
    sheet(isPresented: isPresented) {
      ReportSheet(context: context)
        .deepLinkGated()
    }
  }
}

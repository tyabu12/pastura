import Foundation

/// Builds pre-filled URLs for Shared Scenario reports.
///
/// Backs `ReportScenarioSheet`'s primary (Google Forms) and secondary
/// (GitHub issue) surfaces. See `docs/gallery/shared-scenario-reports.md`
/// for the form configuration and ADR-005 §6.6 for the record of the
/// chosen mechanism.
///
/// The Google form ID and each entry-field ID are compile-time
/// constants. If the form is ever re-created or migrated, update the
/// constants in the same PR that changes the form.
nonisolated enum ReportURLBuilder {
  // Google Forms identifiers — mirror the form configuration
  // documented in docs/gallery/shared-scenario-reports.md §1.1.
  private static let googleFormID =
    "1FAIpQLSfsZkY9-R3QxqVfdXSzsUnx3SXR-g9O7DxjdN-1-VtMjMXSAw"
  private static let scenarioIdFieldID = "entry.149667905"
  private static let appVersionFieldID = "entry.1904779030"
  // The existing "Reason" paragraph field (form field #3, docs/gallery/
  // shared-scenario-reports.md §1.1). The DB-migration report path
  // pre-fills it with the SQLite error so no new form field is needed.
  private static let reasonFieldID = "entry.532267701"

  // GitHub issue identifiers.
  private static let githubRepoPath = "tyabu12/pastura"
  private static let githubTemplateSlug = "shared-scenario-report.yml"
  private static let githubLabel = "shared-scenario-report"

  // GitHub issue identifiers for the DB-migration-failure report path.
  // `dbMigrationErrorFieldID` MUST equal the `id:` of the `db_error`
  // field in `.github/ISSUE_TEMPLATE/db-migration-failure.yml` — GitHub
  // prefills issue-form fields by exact id match, so the underscore form
  // is load-bearing (a hyphen would silently no-op the auto-attach).
  private static let dbMigrationTemplateSlug = "db-migration-failure.yml"
  private static let dbMigrationErrorFieldID = "db_error"
  private static let dbMigrationLabel = "bug"

  /// Build the pre-filled Google Forms URL for a Shared Scenario report.
  ///
  /// Opens the form in Safari with the Scenario ID and App Version
  /// fields populated; the Reason and Email fields are left blank for
  /// the reporter to fill on the form itself. The Email field is not
  /// pre-fillable by Google Forms design — the form must be configured
  /// with `Collect email addresses: Responder input` so the email
  /// field is rendered as a user-typed field that triggers the
  /// response-receipt auto-acknowledgement (see ADR-005 §6.3).
  ///
  /// The same underlying form co-tenants as the §1.5 general-contact
  /// surface reached from the App Store Connect Support URL landing
  /// page (`pages/support/index.html`, #182). That path links the bare
  /// form URL with no pre-fill, and the Scenario ID field is
  /// configured as optional so general-feedback submissions can leave
  /// it blank. This builder always pre-fills both fields — the
  /// in-app path is unaffected by the optional configuration.
  ///
  /// - Parameters:
  ///   - scenarioId: Gallery scenario identifier.
  ///   - appVersion: Running app version (e.g. "1.0.0"). Empty
  ///     strings are permitted and leave the App Version field blank.
  /// - Returns: The pre-filled form URL, or `nil` if URL construction
  ///   fails.
  static func buildGoogleFormURL(scenarioId: String, appVersion: String) -> URL? {
    guard
      var components = URLComponents(
        string: "https://docs.google.com/forms/d/e/\(googleFormID)/viewform")
    else {
      return nil
    }
    components.queryItems = [
      URLQueryItem(name: "usp", value: "pp_url"),
      URLQueryItem(name: scenarioIdFieldID, value: scenarioId),
      URLQueryItem(name: appVersionFieldID, value: appVersion)
    ]
    return components.url
  }

  /// Build the bare Google Forms URL for a general report submitted from
  /// Settings (no specific scenario context).
  ///
  /// Omits the Scenario ID query parameter — the form's Scenario ID
  /// field is configured as optional per ADR-005 §6.7, identical to the
  /// App Store Connect §1.5 Support URL co-tenancy path. Reporters fill
  /// in the rest on the form itself. App version is still pre-filled so
  /// triage has it for free.
  ///
  /// - Parameter appVersion: Running app version (e.g. "1.0.0"). Empty
  ///   strings are permitted and leave the App Version field blank.
  /// - Returns: The pre-filled (app-version-only) form URL, or `nil` if
  ///   URL construction fails.
  static func buildGoogleFormURL(appVersion: String) -> URL? {
    guard
      var components = URLComponents(
        string: "https://docs.google.com/forms/d/e/\(googleFormID)/viewform")
    else {
      return nil
    }
    components.queryItems = [
      URLQueryItem(name: "usp", value: "pp_url"),
      URLQueryItem(name: appVersionFieldID, value: appVersion)
    ]
    return components.url
  }

  /// Build the pre-filled Google Forms URL for a database
  /// migration-failure report (private path of the recovery screen).
  ///
  /// Pre-fills the existing **Reason** paragraph field with the exact
  /// migration error so the reporter doesn't have to hand-type a SQLite
  /// string; App Version is pre-filled as usual. No new form field is
  /// added — the migration error rides the same Reason field general
  /// feedback uses, framed as an extension of the §1.5 general-contact
  /// co-tenancy (ADR-005 §6.7), not a §1.2 UGC report. The Scenario ID
  /// field is omitted (there is no scenario context on a boot failure).
  ///
  /// - Parameters:
  ///   - appVersion: Running app version (e.g. "1.0.0"). Empty strings
  ///     are permitted and leave the App Version field blank.
  ///   - dbError: The migration error detail (e.g.
  ///     `SQLite error 1: no such column …`).
  /// - Returns: The pre-filled form URL, or `nil` if URL construction
  ///   fails.
  static func buildGoogleFormURL(appVersion: String, dbError: String) -> URL? {
    guard
      var components = URLComponents(
        string: "https://docs.google.com/forms/d/e/\(googleFormID)/viewform")
    else {
      return nil
    }
    components.queryItems = [
      URLQueryItem(name: "usp", value: "pp_url"),
      URLQueryItem(name: appVersionFieldID, value: appVersion),
      URLQueryItem(name: reasonFieldID, value: dbError)
    ]
    return components.url
  }

  /// Build the pre-seeded GitHub issue URL for a Shared Scenario report.
  ///
  /// Opens github.com's new-issue page with the Shared Scenario template
  /// selected, the title pre-filled (`[Shared Scenario Report] <id>`), and
  /// the `shared-scenario-report` label attached. The reporter must be
  /// signed into GitHub to submit — this is why this surface is the
  /// secondary "public discussion" path, not the primary report path.
  ///
  /// - Parameter scenarioId: Gallery scenario identifier. Rendered
  ///   into the pre-filled title.
  /// - Returns: The pre-seeded issue-creation URL, or `nil` if URL
  ///   construction fails.
  static func buildGitHubIssueURL(scenarioId: String) -> URL? {
    guard
      var components = URLComponents(
        string: "https://github.com/\(githubRepoPath)/issues/new")
    else {
      return nil
    }
    components.queryItems = [
      URLQueryItem(name: "template", value: githubTemplateSlug),
      URLQueryItem(name: "title", value: "[Shared Scenario Report] \(scenarioId)"),
      URLQueryItem(name: "labels", value: githubLabel)
    ]
    return components.url
  }

  /// Build the pre-seeded GitHub issue URL for a general report
  /// submitted from Settings (no specific scenario context).
  ///
  /// Title is the bare `[Shared Scenario Report]` prefix (no scenario
  /// id suffix). The issue template's `scenario_id` field is
  /// configured as optional with a "Leave blank for general feedback"
  /// hint so reporters arriving from this path can submit without
  /// inventing a value.
  ///
  /// - Returns: The pre-seeded issue-creation URL, or `nil` if URL
  ///   construction fails.
  static func buildGitHubIssueURL() -> URL? {
    guard
      var components = URLComponents(
        string: "https://github.com/\(githubRepoPath)/issues/new")
    else {
      return nil
    }
    components.queryItems = [
      URLQueryItem(name: "template", value: githubTemplateSlug),
      URLQueryItem(name: "title", value: "[Shared Scenario Report]"),
      URLQueryItem(name: "labels", value: githubLabel)
    ]
    return components.url
  }

  /// Build the pre-seeded GitHub issue URL for a database
  /// migration-failure report (public path of the recovery screen).
  ///
  /// Selects the dedicated `db-migration-failure.yml` issue-form
  /// template and pre-fills its `db_error` field with the migration
  /// error. The query-parameter name MUST match the template field's
  /// `id` exactly (`db_error`, underscore) — GitHub prefills issue-form
  /// fields by exact id match, so a hyphen would silently no-op. This
  /// is the public-tracker (account-required) path; the SQLite error
  /// may, in rare data-migrating failures, embed scenario fragments, so
  /// the template carries a review-before-submit caveat (ADR-005 §6 PII
  /// hygiene). Framed as technical bug intake (`bug` label), outside the
  /// §6 Shared Scenario UGC report tracker.
  ///
  /// - Parameter migrationError: The migration error detail rendered
  ///   into the pre-filled `db_error` field.
  /// - Returns: The pre-seeded issue-creation URL, or `nil` if URL
  ///   construction fails.
  static func buildGitHubIssueURL(migrationError: String) -> URL? {
    guard
      var components = URLComponents(
        string: "https://github.com/\(githubRepoPath)/issues/new")
    else {
      return nil
    }
    components.queryItems = [
      URLQueryItem(name: "template", value: dbMigrationTemplateSlug),
      URLQueryItem(name: "title", value: "[DB migration failure]"),
      URLQueryItem(name: "labels", value: dbMigrationLabel),
      URLQueryItem(name: dbMigrationErrorFieldID, value: migrationError)
    ]
    return components.url
  }
}

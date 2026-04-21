import Foundation

/// Builds pre-filled URLs for Share Board scenario reports.
///
/// Backs `ReportScenarioSheet`'s primary (Google Forms) and secondary
/// (GitHub issue) surfaces. See `docs/gallery/share-board-reports.md`
/// for the form configuration and ADR-005 §6.6 for the record of the
/// chosen mechanism.
///
/// The Google form ID and each entry-field ID are compile-time
/// constants. If the form is ever re-created or migrated, update the
/// constants in the same PR that changes the form.
nonisolated enum ReportURLBuilder {
  // Google Forms identifiers — mirror the form configuration
  // documented in docs/gallery/share-board-reports.md §1.1.
  private static let googleFormID =
    "1FAIpQLSfsZkY9-R3QxqVfdXSzsUnx3SXR-g9O7DxjdN-1-VtMjMXSAw"
  private static let scenarioIdFieldID = "entry.149667905"
  private static let appVersionFieldID = "entry.1904779030"

  // GitHub issue identifiers.
  private static let githubRepoPath = "tyabu12/pastura"
  private static let githubTemplateSlug = "share-board-report.yml"
  private static let githubLabel = "share-board-report"

  /// Build the pre-filled Google Forms URL for a Share Board report.
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
  /// page (`docs/support/index.html`, #182). That path links the bare
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

  /// Build the pre-seeded GitHub issue URL for a Share Board report.
  ///
  /// Opens github.com's new-issue page with the Share Board template
  /// selected, the title pre-filled (`[Share Board Report] <id>`), and
  /// the `share-board-report` label attached. The reporter must be
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
      URLQueryItem(name: "title", value: "[Share Board Report] \(scenarioId)"),
      URLQueryItem(name: "labels", value: githubLabel)
    ]
    return components.url
  }
}

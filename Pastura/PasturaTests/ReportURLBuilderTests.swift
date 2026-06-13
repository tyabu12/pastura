import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct ReportURLBuilderTests {
  // MARK: - Google Forms URL

  @Test
  func googleFormURLBuildsWithExpectedHostAndPath() throws {
    let url = try #require(
      ReportURLBuilder.buildGoogleFormURL(scenarioId: "prisoners_dilemma", appVersion: "1.0.0"))
    #expect(url.scheme == "https")
    #expect(url.host == "docs.google.com")
    #expect(url.path.hasPrefix("/forms/d/e/"))
    #expect(url.path.hasSuffix("/viewform"))
  }

  @Test
  func googleFormURLIncludesPreFillMarker() throws {
    let url = try #require(
      ReportURLBuilder.buildGoogleFormURL(scenarioId: "any", appVersion: ""))
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let items = components.queryItems ?? []
    #expect(items.contains { $0.name == "usp" && $0.value == "pp_url" })
  }

  @Test
  func googleFormURLEmbedsScenarioIdAndAppVersionValues() throws {
    let url = try #require(
      ReportURLBuilder.buildGoogleFormURL(scenarioId: "test_scenario", appVersion: "1.2.3"))
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let values = Set((components.queryItems ?? []).compactMap { $0.value })
    #expect(values.contains("test_scenario"))
    #expect(values.contains("1.2.3"))
  }

  @Test
  func googleFormURLRoundTripsSpecialCharacters() throws {
    // Spaces, slash, and ampersand all require percent-encoding in
    // query values. Confirm the builder produces a URL whose parsed
    // queryItems decode back to the exact input.
    let tricky = "id with spaces/slash&amp"
    let url = try #require(
      ReportURLBuilder.buildGoogleFormURL(scenarioId: tricky, appVersion: ""))
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let match = components.queryItems?.first { $0.value == tricky }
    #expect(match != nil)
  }

  @Test
  func googleFormURLRoundTripsMultiByteCharacters() throws {
    let japanese = "日本語_シナリオ"
    let url = try #require(
      ReportURLBuilder.buildGoogleFormURL(scenarioId: japanese, appVersion: ""))
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let match = components.queryItems?.first { $0.value == japanese }
    #expect(match != nil)
  }

  @Test
  func googleFormURLAcceptsEmptyAppVersion() throws {
    let url = try #require(
      ReportURLBuilder.buildGoogleFormURL(scenarioId: "x", appVersion: ""))
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    // App version field is still present but with empty value — form
    // renders an empty field rather than a pre-filled one.
    let entryNames = (components.queryItems ?? []).map { $0.name }.filter {
      $0.hasPrefix("entry.")
    }
    #expect(entryNames.count == 2)
  }

  // MARK: - GitHub issue URL

  @Test
  func gitHubIssueURLBuildsWithExpectedHostAndPath() throws {
    let url = try #require(ReportURLBuilder.buildGitHubIssueURL(scenarioId: "x"))
    #expect(url.scheme == "https")
    #expect(url.host == "github.com")
    #expect(url.path == "/tyabu12/pastura/issues/new")
  }

  @Test
  func gitHubIssueURLCarriesTemplateTitleAndLabel() throws {
    let url = try #require(
      ReportURLBuilder.buildGitHubIssueURL(scenarioId: "prisoners_dilemma_v2"))
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let items = components.queryItems ?? []
    #expect(items.contains { $0.name == "template" && $0.value == "shared-scenario-report.yml" })
    #expect(items.contains { $0.name == "labels" && $0.value == "shared-scenario-report" })
    #expect(
      items.contains {
        $0.name == "title" && $0.value == "[Shared Scenario Report] prisoners_dilemma_v2"
      })
  }

  @Test
  func gitHubIssueURLRoundTripsMultiByteScenarioId() throws {
    let japanese = "日本語_シナリオ"
    let url = try #require(ReportURLBuilder.buildGitHubIssueURL(scenarioId: japanese))
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let match = components.queryItems?.first {
      $0.name == "title" && $0.value == "[Shared Scenario Report] \(japanese)"
    }
    #expect(match != nil)
  }

  // MARK: - Google Forms URL (no scenarioId)

  @Test
  func googleFormURLNoScenarioBuildsWithExpectedHostAndPath() throws {
    let url = try #require(ReportURLBuilder.buildGoogleFormURL(appVersion: "1.0.0"))
    #expect(url.scheme == "https")
    #expect(url.host == "docs.google.com")
    #expect(url.path.hasPrefix("/forms/d/e/"))
    #expect(url.path.hasSuffix("/viewform"))
  }

  @Test
  func googleFormURLNoScenarioIncludesPreFillMarker() throws {
    let url = try #require(ReportURLBuilder.buildGoogleFormURL(appVersion: ""))
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let items = components.queryItems ?? []
    #expect(items.contains { $0.name == "usp" && $0.value == "pp_url" })
  }

  @Test
  func googleFormURLNoScenarioOmitsScenarioIdField() throws {
    let url = try #require(ReportURLBuilder.buildGoogleFormURL(appVersion: "1.0.0"))
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    // The scenario-scoped variant has 2 entry.* items; this variant should have exactly 1
    // (appVersion only — no scenarioId entry).
    let entryItems = (components.queryItems ?? []).filter { $0.name.hasPrefix("entry.") }
    #expect(entryItems.count == 1)
    // Additionally, no query item name should equal the scenarioId field name
    // — the scenario-scoped variant uses "entry.149667905" (2nd entry.*).
    // Since we can't reference the private constant directly, we verify by count
    // and by confirming no item value contains a scenario-id-like value.
    let allNames = (components.queryItems ?? []).map { $0.name }
    #expect(!allNames.contains("entry.149667905"))
  }

  @Test
  func googleFormURLNoScenarioEmbedsAppVersion() throws {
    let url = try #require(ReportURLBuilder.buildGoogleFormURL(appVersion: "1.2.3"))
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let values = (components.queryItems ?? []).compactMap { $0.value }
    #expect(values.contains("1.2.3"))
  }

  // MARK: - GitHub issue URL (no scenarioId)

  @Test
  func gitHubIssueURLNoScenarioBuildsWithExpectedHostAndPath() throws {
    let url = try #require(ReportURLBuilder.buildGitHubIssueURL())
    #expect(url.scheme == "https")
    #expect(url.host == "github.com")
    #expect(url.path == "/tyabu12/pastura/issues/new")
  }

  @Test
  func gitHubIssueURLNoScenarioCarriesTemplateLabelAndBareTitle() throws {
    let url = try #require(ReportURLBuilder.buildGitHubIssueURL())
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let items = components.queryItems ?? []
    #expect(items.contains { $0.name == "template" && $0.value == "shared-scenario-report.yml" })
    #expect(items.contains { $0.name == "labels" && $0.value == "shared-scenario-report" })
    // Title is exactly the bare prefix — no trailing space, no scenario id.
    #expect(items.contains { $0.name == "title" && $0.value == "[Shared Scenario Report]" })
  }

  // MARK: - GitHub issue URL (DB migration failure)

  @Test
  func gitHubIssueURLMigrationBuildsWithExpectedHostAndPath() throws {
    let url = try #require(ReportURLBuilder.buildGitHubIssueURL(migrationError: "boom"))
    #expect(url.scheme == "https")
    #expect(url.host == "github.com")
    #expect(url.path == "/tyabu12/pastura/issues/new")
  }

  @Test
  func gitHubIssueURLMigrationCarriesTemplateLabelTitleAndDbError() throws {
    let error = "SQLite error 1: no such column: foo"
    let url = try #require(ReportURLBuilder.buildGitHubIssueURL(migrationError: error))
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let items = components.queryItems ?? []
    #expect(items.contains { $0.name == "template" && $0.value == "db-migration-failure.yml" })
    #expect(items.contains { $0.name == "labels" && $0.value == "bug" })
    #expect(items.contains { $0.name == "title" && $0.value == "[DB migration failure]" })
    // C1 regression guard: the prefill query param key MUST be the underscore
    // form `db_error` (matching the yml field id), not the hyphen form
    // `db-error` — GitHub prefills issue-form fields by exact id match, so a
    // hyphen would silently no-op the auto-attach.
    #expect(items.contains { $0.name == "db_error" && $0.value == error })
    #expect(!items.contains { $0.name == "db-error" })
  }

  @Test
  func gitHubIssueURLMigrationRoundTripsErrorDetail() throws {
    // Real SQLite errors carry colons, spaces, and (rarely) multi-byte
    // scenario fragments. Confirm the value survives percent-encoding intact.
    let error = "table シナリオ has 3 columns but 4 values supplied: a/b&c"
    let url = try #require(ReportURLBuilder.buildGitHubIssueURL(migrationError: error))
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let match = components.queryItems?.first { $0.name == "db_error" && $0.value == error }
    #expect(match != nil)
  }

  // MARK: - Google Forms URL (DB migration failure)

  @Test
  func googleFormURLMigrationBuildsWithExpectedHostAndPath() throws {
    let url = try #require(
      ReportURLBuilder.buildGoogleFormURL(appVersion: "1.0.0", dbError: "boom"))
    #expect(url.scheme == "https")
    #expect(url.host == "docs.google.com")
    #expect(url.path.hasPrefix("/forms/d/e/"))
    #expect(url.path.hasSuffix("/viewform"))
  }

  @Test
  func googleFormURLMigrationEmbedsAppVersionAndReasonError() throws {
    let error = "SQLite error 1: no such column: foo"
    let url = try #require(
      ReportURLBuilder.buildGoogleFormURL(appVersion: "1.2.3", dbError: error))
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let items = components.queryItems ?? []
    #expect(items.contains { $0.name == "usp" && $0.value == "pp_url" })
    // The migration error pre-fills the existing Reason paragraph field
    // (entry.532267701) — no new form field was added.
    #expect(items.contains { $0.name == "entry.532267701" && $0.value == error })
    let values = items.compactMap { $0.value }
    #expect(values.contains("1.2.3"))
    // No scenario-id field on this path (matches the no-scenario variant).
    #expect(!items.contains { $0.name == "entry.149667905" })
  }

  @Test
  func googleFormURLMigrationRoundTripsErrorDetail() throws {
    let error = "table シナリオ has 3 columns but 4 values supplied: a/b&c"
    let url = try #require(
      ReportURLBuilder.buildGoogleFormURL(appVersion: "", dbError: error))
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let match = components.queryItems?.first {
      $0.name == "entry.532267701" && $0.value == error
    }
    #expect(match != nil)
  }
}

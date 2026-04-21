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
    #expect(items.contains { $0.name == "template" && $0.value == "share-board-report.yml" })
    #expect(items.contains { $0.name == "labels" && $0.value == "share-board-report" })
    #expect(
      items.contains {
        $0.name == "title" && $0.value == "[Share Board Report] prisoners_dilemma_v2"
      })
  }

  @Test
  func gitHubIssueURLRoundTripsMultiByteScenarioId() throws {
    let japanese = "日本語_シナリオ"
    let url = try #require(ReportURLBuilder.buildGitHubIssueURL(scenarioId: japanese))
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let match = components.queryItems?.first {
      $0.name == "title" && $0.value == "[Share Board Report] \(japanese)"
    }
    #expect(match != nil)
  }
}

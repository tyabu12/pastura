import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1))) struct DeepLinkURLTests {

  // MARK: - Accept cases

  @Test func acceptCases() {
    let cases: [(String, DeepLinkURL)] = [
      ("pastura://scenario/asch_conformity_v1", .scenario(id: "asch_conformity_v1")),
      ("pastura://scenario/foo", .scenario(id: "foo")),
      ("pastura://scenario/abc123", .scenario(id: "abc123")),
      ("pastura://scenario/a", .scenario(id: "a")),
      ("pastura://scenario/a_b_c", .scenario(id: "a_b_c")),
      ("pastura://scenario/123", .scenario(id: "123")),
      ("PASTURA://scenario/foo", .scenario(id: "foo")),  // scheme case-insensitive
      ("Pastura://scenario/foo", .scenario(id: "foo"))  // scheme case-insensitive
    ]
    for (urlString, expected) in cases {
      // swiftlint:disable:next force_unwrapping
      let url = URL(string: urlString)!
      let result = DeepLinkURL.parse(url)
      #expect(result == expected, "Expected \(expected) for \(urlString)")
    }
  }

  @Test func accept128CharId() {
    let id = String(repeating: "a", count: 128)
    // swiftlint:disable:next force_unwrapping
    let url = URL(string: "pastura://scenario/\(id)")!
    let result = DeepLinkURL.parse(url)
    #expect(result == .scenario(id: id))
  }

  // MARK: - Reject cases

  @Test func rejectCases() {
    let urlStrings: [String] = [
      // Wrong scheme
      "http://scenario/foo",
      "pastur://scenario/foo",
      // Wrong/missing host
      "pastura:///foo",
      "pastura://Scenario/foo",
      "pastura://other/foo",
      // Empty id
      "pastura://scenario/",
      "pastura://scenario",
      // Id charset violations
      "pastura://scenario/Asch",
      "pastura://scenario/asch-v1",
      "pastura://scenario/asch.v1",
      "pastura://scenario/asch%20v1",
      // Extra path segments
      "pastura://scenario/foo/bar",
      // Query or fragment
      "pastura://scenario/foo?x=1",
      "pastura://scenario/foo#bar"
    ]
    for urlString in urlStrings {
      // URL(string:) may fail for some malformed strings; treat nil URL as nil parse
      let url = URL(string: urlString)
      let result = url.flatMap { DeepLinkURL.parse($0) }
      #expect(result == nil, "Expected nil for \(urlString)")
    }
  }

  @Test func rejectSpaceInId() {
    // "asch v1" — space makes URL(string:) fail or percent-encode the space
    // Test both the raw form and percent-encoded form
    if let url = URL(string: "pastura://scenario/asch%20v1") {
      #expect(DeepLinkURL.parse(url) == nil)
    }
  }

  @Test func rejectDoubleDots() {
    // swiftlint:disable:next force_unwrapping
    let url = URL(string: "pastura://scenario/..")!
    #expect(DeepLinkURL.parse(url) == nil)
  }

  @Test func reject129CharId() {
    let id = String(repeating: "a", count: 129)
    // swiftlint:disable:next force_unwrapping
    let url = URL(string: "pastura://scenario/\(id)")!
    #expect(DeepLinkURL.parse(url) == nil)
  }

  // MARK: - Universal Link (https) accept cases

  @Test func acceptUniversalLinkCases() {
    let cases: [(String, DeepLinkURL)] = [
      ("https://pastura.app/s/foo", .scenario(id: "foo")),
      // Trailing slash — Astro serves the canonical URL as /s/<id>/
      // (trailingSlash: 'always'), so this is the primary real-world shape.
      ("https://pastura.app/s/foo/", .scenario(id: "foo")),
      ("https://pastura.app/s/asch_conformity_v1/", .scenario(id: "asch_conformity_v1")),
      // Japanese mirror — the /ja prefix is stripped to the same id.
      ("https://pastura.app/ja/s/foo", .scenario(id: "foo")),
      ("https://pastura.app/ja/s/foo/", .scenario(id: "foo")),
      // Social platforms append tracking params — ignore query/fragment
      // for the https shape (unlike the strict pastura:// arm).
      ("https://pastura.app/s/foo?utm_source=x", .scenario(id: "foo")),
      ("https://pastura.app/s/foo/?fbclid=abc", .scenario(id: "foo")),
      ("https://pastura.app/s/foo#section", .scenario(id: "foo")),
      // Scheme + host are both case-insensitive.
      ("HTTPS://pastura.app/s/foo", .scenario(id: "foo")),
      ("https://PASTURA.APP/s/foo", .scenario(id: "foo"))
    ]
    for (urlString, expected) in cases {
      // swiftlint:disable:next force_unwrapping
      let url = URL(string: urlString)!
      let result = DeepLinkURL.parse(url)
      #expect(result == expected, "Expected \(expected) for \(urlString)")
    }
  }

  // MARK: - Universal Link (https) reject cases

  @Test func rejectUniversalLinkCases() {
    let urlStrings: [String] = [
      // Wrong host — the trust boundary: only pastura.app.
      "https://evil.com/s/foo",
      "https://pastura.app.evil.com/s/foo",
      // http (not https)
      "http://pastura.app/s/foo",
      // Wrong path prefix
      "https://pastura.app/x/foo",
      "https://pastura.app/foo",
      "https://pastura.app/ja/foo",
      // Empty / missing id
      "https://pastura.app/s/",
      "https://pastura.app/s",
      "https://pastura.app/",
      "https://pastura.app/ja/s/",
      // Extra path segments
      "https://pastura.app/s/foo/bar",
      "https://pastura.app/ja/s/foo/bar",
      // Id charset violations
      "https://pastura.app/s/Asch",
      "https://pastura.app/s/asch-v1"
    ]
    for urlString in urlStrings {
      let url = URL(string: urlString)
      let result = url.flatMap { DeepLinkURL.parse($0) }
      #expect(result == nil, "Expected nil for \(urlString)")
    }
  }
}

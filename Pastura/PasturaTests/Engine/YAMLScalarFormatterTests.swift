import Foundation
import Testing
import Yams

@testable import Pastura

/// Unit tests for the shared inline-scalar quoting helper extracted from
/// ``ScenarioSerializer`` (ADR-018 D6). The patcher and serializer both
/// consume this, so its rules are pinned here.
@Suite(.timeLimit(.minutes(1)))
struct YAMLScalarFormatterTests {

  @Test func plainValuePassesThrough() {
    #expect(YAMLScalarFormatter.quote("Alice") == "Alice")
    #expect(YAMLScalarFormatter.quote("cooperate") == "cooperate")
  }

  @Test func emptyValueIsQuoted() {
    #expect(YAMLScalarFormatter.quote("") == "\"\"")
  }

  @Test func numberAndBoolLookAlikesAreQuoted() {
    #expect(YAMLScalarFormatter.quote("42") == "\"42\"")
    #expect(YAMLScalarFormatter.quote("3.14") == "\"3.14\"")
    #expect(YAMLScalarFormatter.quote("true") == "\"true\"")
    #expect(YAMLScalarFormatter.quote("false") == "\"false\"")
    #expect(YAMLScalarFormatter.quote("null") == "\"null\"")
    #expect(YAMLScalarFormatter.quote("~") == "\"~\"")
  }

  @Test func colonAndCommentMarkersForceQuoting() {
    #expect(YAMLScalarFormatter.quote("key: value") == "\"key: value\"")
    #expect(YAMLScalarFormatter.quote("trailing # here") == "\"trailing # here\"")
  }

  @Test func leadingIndicatorsForceQuoting() {
    #expect(YAMLScalarFormatter.quote("- dash") == "\"- dash\"")
    #expect(YAMLScalarFormatter.quote("? question") == "\"? question\"")
    #expect(YAMLScalarFormatter.quote("*anchor") == "\"*anchor\"")
    #expect(YAMLScalarFormatter.quote("&ref") == "\"&ref\"")
  }

  @Test func interiorQuotesWithoutTriggerPassThrough() {
    // Preserved serializer behavior: an interior `"` / `\` alone does NOT
    // force quoting (no leading indicator, no `: ` / ` #`, not a number).
    #expect(YAMLScalarFormatter.quote("say \"hi\"") == "say \"hi\"")
    #expect(YAMLScalarFormatter.quote("a\\b") == "a\\b")
  }

  @Test func quotedValueEscapesInteriorQuotesAndBackslashes() {
    // When a trigger (here `: `) forces quoting, interior `"` and `\` are escaped.
    #expect(YAMLScalarFormatter.quote("a: \"q\"") == "\"a: \\\"q\\\"\"")
    #expect(YAMLScalarFormatter.quote("a: b\\c") == "\"a: b\\\\c\"")
  }

  @Test func newlineEscapesAsBackslashN() {
    // A newline forces quoting and is emitted as the escaped `\n` sequence,
    // NOT a literal LF byte: a literal LF inside a double-quoted scalar is
    // FOLDED to a space by YAML on reparse (round-trip corruption). The
    // escaped form parses back to a real LF. See `roundTripProperty` for the
    // behavioral guarantee — this test documents the emitted shape.
    #expect(YAMLScalarFormatter.quote("line1\nline2") == "\"line1\\nline2\"")
  }

  @Test func ordinaryJapaneseTextPassesThrough() {
    // CJK text without special indicators stays unquoted (matches serializer).
    #expect(YAMLScalarFormatter.quote("アリス") == "アリス")
  }

  // MARK: - Round-trip Property (primary regression guard, #749)

  /// Parses `quote(value)` in the exact `key: <scalar>` context the serializer
  /// emits (`name:`/`description:`/`if:`/…), then extracts the scalar back.
  /// Returns `nil` if the document doesn't parse as `[key: String]` — which
  /// surfaces the pre-fix corruption shapes (unquoted leading-indicator →
  /// ScannerError → throw; number/null look-alikes → non-String node).
  private func roundTrip(_ value: String) throws -> String? {
    let yaml = "k: \(YAMLScalarFormatter.quote(value))"
    let parsed = try Yams.load(yaml: yaml) as? [String: Any]
    return parsed?["k"] as? String
  }

  /// Adversarial corpus: each entry is a value whose naive (unquoted /
  /// literal-LF) emission corrupts or fails on reparse. Every entry MUST
  /// satisfy `parse(quote(v)) == v`. If the fix is reverted, the newline,
  /// leading-reserved-indicator, and trailing/leading-whitespace cases must
  /// fail — that is the regression these assertions guard.
  @Test func roundTripProperty() throws {
    let corpus: [String] = [
      // finding #1 — line breaks fold/normalize inside double quotes
      "line1\nline2",
      "carriage\rreturn",
      "crlf\r\nline",
      // finding #2 — leading YAML reserved / indicator characters
      "@reserved",
      "`backtick",
      "|pipe",
      ">folded",
      ",comma",
      "=equals",
      ":colon",
      ":",
      // finding #3 — leading / trailing / all whitespace
      "trailing space ",
      " leading space",
      "   ",
      "\ttab-leading",
      "tab-trailing\t",
      "a\tinterior\tb",
      // combined shapes
      "@reserved trailing ",
      // already-handled shapes — confirm no regression
      "Alice",
      "アリス",
      "42",
      "3.14",
      "true",
      "null",
      "~",
      "key: value",
      "trailing # here",
      "- dash",
      "say \"hi\"",
      "a\\b",
      ""
    ]

    for value in corpus {
      do {
        let parsed = try roundTrip(value)
        #expect(
          parsed == value,
          "round-trip mismatch for \(value.debugDescription): got \(String(describing: parsed).debugDescription)"
        )
      } catch {
        Issue.record("round-trip threw for \(value.debugDescription): \(error)")
      }
    }
  }
}

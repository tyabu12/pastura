import Foundation
import Testing

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

  @Test func newlineForcesQuotingWithLiteralBreak() {
    // A newline forces quoting; the byte stays a literal LF inside the quotes
    // (the serializer routes true multi-line strings through block scalars).
    #expect(YAMLScalarFormatter.quote("line1\nline2") == "\"line1\nline2\"")
  }

  @Test func ordinaryJapaneseTextPassesThrough() {
    // CJK text without special indicators stays unquoted (matches serializer).
    #expect(YAMLScalarFormatter.quote("アリス") == "アリス")
  }
}

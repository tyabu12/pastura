import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct ContentBlocklistTests {

  // MARK: - Bundle integration (production path)

  @Test func entriesFromBundleReturnsAllNinePatterns() {
    let entries = ContentBlocklist.entries(from: Bundle(for: DatabaseManager.self))
    #expect(entries.count == 9)
  }

  @Test func bundleResourceIsJSONNotLegacyText() {
    // Per ADR-005 §10.1 amendment: the legacy plain-text bundle was retired
    // when the JSON format shipped. The folder-reference Resources/ pattern
    // means a forgotten `git rm` would silently leave the .txt in the bundle
    // alongside the JSON, so we assert its absence directly.
    let bundle = Bundle(for: DatabaseManager.self)
    #expect(bundle.url(forResource: "ContentBlocklist", withExtension: "json") != nil)
    #expect(bundle.url(forResource: "ContentBlocklist", withExtension: "txt") == nil)
  }

  // MARK: - Partition (inputPatterns / outputPatterns)

  @Test func outputPatternsContainsAllNinePatterns() {
    #expect(ContentBlocklist.outputPatterns.count == 9)
  }

  @Test func inputPatternsExcludesViolence() {
    // Current source.json: 3 violence (殺す / 殺害 / 殺人) → 9 - 3 = 6 input.
    // Cardinality is brittle as the blocklist grows — kept here as a
    // canary alongside the invariant test below.
    #expect(ContentBlocklist.inputPatterns.count == 6)
  }

  @Test func outputPatternsIsSupersetOfInputPatterns() {
    // The behavioral invariant per ADR-005 §10.1 — output catches every
    // input pattern plus the excluded categories. Robust to blocklist
    // growth in a way absolute cardinality is not.
    let inputSet = Set(ContentBlocklist.inputPatterns)
    let outputSet = Set(ContentBlocklist.outputPatterns)
    #expect(outputSet.isSuperset(of: inputSet))
  }

  @Test func violenceTermsPresentOnlyInOutputPartition() {
    let violence = ["殺す", "殺害", "殺人"]
    for term in violence {
      #expect(ContentBlocklist.outputPatterns.contains(term))
      #expect(!ContentBlocklist.inputPatterns.contains(term))
    }
  }

  @Test func nonViolenceTermsPresentInBothPartitions() {
    let nonViolence = ["死ね", "ガイジ", "キチガイ", "fuck", "shit", "asshole"]
    for term in nonViolence {
      #expect(ContentBlocklist.inputPatterns.contains(term))
      #expect(ContentBlocklist.outputPatterns.contains(term))
    }
  }

  // MARK: - decode(_:) failure modes

  @Test func decodeAcceptsValidJSON() throws {
    let valid = Data(
      #"""
      {
        "version": 1,
        "patterns": [
          {"term": "test1", "contentCategory": "harassment"},
          {"term": "test2", "contentCategory": "violence"}
        ]
      }
      """#.utf8
    )
    let entries = try ContentBlocklist.decode(valid)
    #expect(entries.count == 2)
    #expect(entries[0].term == "test1")
    #expect(entries[0].contentCategory == .harassment)
    #expect(entries[1].contentCategory == .violence)
  }

  @Test func decodeRejectsMalformedJSON() {
    let malformed = Data("{not valid json".utf8)
    #expect(throws: (any Error).self) {
      try ContentBlocklist.decode(malformed)
    }
  }

  @Test func decodeRejectsUnknownContentCategory() {
    let unknown = Data(
      #"""
      {"version": 1, "patterns": [{"term": "x", "contentCategory": "spam"}]}
      """#.utf8
    )
    #expect(throws: (any Error).self) {
      try ContentBlocklist.decode(unknown)
    }
  }

  @Test func decodeRejectsWrongSchemaVersion() {
    let wrongVersion = Data(
      #"""
      {"version": 2, "patterns": [{"term": "x", "contentCategory": "harassment"}]}
      """#.utf8
    )
    #expect(throws: ContentBlocklist.DecodeError.self) {
      try ContentBlocklist.decode(wrongVersion)
    }
  }

  @Test func decodeRejectsEmptyPatterns() {
    let empty = Data(
      #"""
      {"version": 1, "patterns": []}
      """#.utf8
    )
    #expect(throws: ContentBlocklist.DecodeError.self) {
      try ContentBlocklist.decode(empty)
    }
  }
}

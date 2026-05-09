import Foundation
import Testing

@testable import Pastura

/// Exercises the state-machine partial-JSON extractor against the
/// synthetic byte-stream fixtures from item 1 and additional edge cases.
/// Every test feeds the buffer incrementally (byte-by-byte where it
/// matters) and asserts the extracted snapshot at each prefix is
/// consistent with what the canonical `JSONResponseParser` would return
/// on the final buffer.
@Suite(.timeLimit(.minutes(1)))
struct PartialOutputExtractorTests {

  let extractor = PartialOutputExtractor()

  // MARK: - Empty / pre-JSON

  @Test func emptyBufferYieldsEmptySnapshot() {
    #expect(extractor.extract(from: "") == .empty)
  }

  @Test func bufferWithoutOpenBraceYieldsEmpty() {
    #expect(extractor.extract(from: "Sure! Here is the JSON:") == .empty)
  }

  @Test func bufferStoppedBeforeOpeningQuoteYieldsEmpty() {
    // Colon not yet arrived — extractor must wait.
    #expect(extractor.extract(from: #"{"statement""#).primary == nil)
    // Colon arrived but no opening quote — still wait.
    #expect(extractor.extract(from: #"{"statement":"#).primary == nil)
  }

  // MARK: - Primary key reveals

  @Test func primaryRevealsAfterOpeningQuote() {
    // Opening quote present but no content — primary is empty string, not nil.
    let snap = extractor.extract(from: #"{"statement":""#)
    #expect(snap.primary == "")
  }

  @Test func primaryRevealsIncrementalText() {
    let snap = extractor.extract(from: #"{"statement":"Let's coope"#)
    #expect(snap.primary == "Let's coope")
    #expect(snap.thought == nil)
  }

  @Test func primaryRevealsCompleteValue() {
    let snap = extractor.extract(
      from: #"{"statement":"Let's cooperate."}"#)
    #expect(snap.primary == "Let's cooperate.")
  }

  @Test func allKnownPrimaryKeysResolve() {
    for key in PartialOutputExtractor.primaryKeys {
      let snap = extractor.extract(from: #"{"\#(key)":"val"}"#)
      #expect(snap.primary == "val", "primary key \(key) failed to resolve")
    }
  }

  // MARK: - Thought

  @Test func thoughtResolvesAfterPrimary() {
    let snap = extractor.extract(
      from: #"{"statement":"hi","inner_thought":"secret"}"#)
    #expect(snap.primary == "hi")
    #expect(snap.thought == "secret")
  }

  @Test func thoughtIsNilIfNotYetOpened() {
    let snap = extractor.extract(from: #"{"statement":"hi""#)
    #expect(snap.primary == "hi")
    #expect(snap.thought == nil)
  }

  // MARK: - Escape handling

  @Test func escapedQuoteInPrimary() {
    let snap = extractor.extract(
      from: #"{"statement":"She said \"hi\""}"#)
    #expect(snap.primary == #"She said "hi""#)
  }

  @Test func escapedBackslashInPrimary() {
    let snap = extractor.extract(
      from: #"{"statement":"a\\b"}"#)
    #expect(snap.primary == #"a\b"#)
  }

  @Test func escapedNewlineInPrimary() {
    let snap = extractor.extract(
      from: #"{"statement":"line1\nline2"}"#)
    #expect(snap.primary == "line1\nline2")
  }

  @Test func incompleteEscapeAtEndHoldsBack() {
    // Buffer ends with a lone backslash — the next char might be `"` (end
    // of string) or `\\` (literal backslash). Must not emit the `\` yet.
    let snap = extractor.extract(from: #"{"statement":"x\"#)
    #expect(snap.primary == "x")
  }

  @Test func incompleteUnicodeEscapeHoldsBack() {
    // \uXXXX needs 4 hex digits — fewer is incomplete.
    let snap = extractor.extract(from: #"{"statement":"a\u00"#)
    #expect(snap.primary == "a")
  }

  @Test func completeUnicodeEscapeDecodes() {
    // \u00E9 is é.
    let snap = extractor.extract(
      from: #"{"statement":"caf\u00e9"}"#)
    #expect(snap.primary == "café")
  }

  // MARK: - Thinking-tag handling

  @Test func unclosedChannelThinkingTagHidesEverything() {
    // While we're inside a thinking tag, no extraction should fire even
    // if `{` appears later in the tag's content.
    let snap = extractor.extract(
      from: #"<|channel>thought\nI'll say {"statement":"hi"}"#)
    #expect(snap == .empty)
  }

  @Test func closedChannelThinkingTagIsStripped() {
    let buffer = """
      <|channel>thought
      reasoning here
      <channel|>{"statement":"visible"}
      """
    #expect(extractor.extract(from: buffer).primary == "visible")
  }

  @Test func unclosedThinkTagHidesEverything() {
    let snap = extractor.extract(
      from: #"<think>reasoning {"statement":"hi"#)
    #expect(snap == .empty)
  }

  // MARK: - Leading garbage

  @Test func leadingGarbageSkippedUntilBrace() {
    let snap = extractor.extract(
      from: "Sure! Here's my response:\n\n{\"statement\":\"OK\"}")
    #expect(snap.primary == "OK")
  }

  // MARK: - Byte-stream replay (item 1 fixtures)
  //
  // Feeding every prefix of the reconstructed bytes must never produce a
  // snapshot that contradicts what the final (complete) parse would
  // reveal. "Contradict" means: primary text at prefix N is not a
  // prefix of primary at prefix N+1, or the final primary.

  @Test func cjkBoundaryFixtureReplaysWithoutContradiction() throws {
    let fixture = try LlamaCppTraceFixtures.named("cjk_utf8_boundary")
    try replayAndCheckMonotonicity(fixture: fixture)
  }

  @Test func escapedQuoteFixtureReplaysWithoutContradiction() throws {
    let fixture = try LlamaCppTraceFixtures.named("escaped_quote")
    try replayAndCheckMonotonicity(fixture: fixture)
  }

  @Test func normalFixtureReplaysWithoutContradiction() throws {
    let fixture = try LlamaCppTraceFixtures.named("normal_statement")
    try replayAndCheckMonotonicity(fixture: fixture)
  }

  // MARK: - Replay helper

  /// Feeds `fixture` byte-by-byte through the extractor and verifies:
  /// 1. Primary text never shrinks between successive prefixes.
  /// 2. Primary text at every prefix is a prefix of the canonical final
  ///    parse result (when the final parse succeeds).
  /// 3. No replacement characters (`U+FFFD`) appear in the primary at any
  ///    intermediate state — feeding a partial UTF-8 sequence must not
  ///    surface mojibake.
  private func replayAndCheckMonotonicity(
    fixture: LlamaCppTraceFixture
  ) throws {
    var bytes = Data()
    var lastPrimary = ""

    // Canonical parse for the complete text — the extractor must stay
    // consistent with this.
    let parser = JSONResponseParser()
    let finalParsed = try? parser.parse(fixture.finalText)
    let canonicalPrimary =
      finalParsed?.statement
      ?? finalParsed?.action
      ?? finalParsed?.vote

    for piece in fixture.pieces {
      for byte in piece.bytes {
        bytes.append(byte)
        // Mirror `LlamaCppService.longestValidUtf8Prefix`: feed the
        // extractor the longest valid UTF-8 prefix, not the raw bytes
        // converted with fallback-to-empty. Otherwise hitting a
        // continuation byte would briefly zero the buffer and the
        // monotonicity check would fire spuriously.
        let text = Self.longestValidUtf8Prefix(bytes)
        let snap = extractor.extract(from: text)
        let current = snap.primary ?? ""

        #expect(
          !current.contains("\u{FFFD}"),
          "Replacement character leaked into extracted primary at byte offset \(bytes.count)"
        )
        #expect(
          current.hasPrefix(lastPrimary) || lastPrimary.isEmpty,
          "Primary shrank: was \(lastPrimary.debugDescription), now \(current.debugDescription)"
        )
        if let canonicalPrimary {
          #expect(
            canonicalPrimary.hasPrefix(current),
            "Intermediate primary \(current.debugDescription) is not a prefix of canonical \(canonicalPrimary.debugDescription)"
          )
        }
        lastPrimary = current
      }
    }
  }

  /// Longest UTF-8-decodable prefix of `bytes`. Duplicates (intentionally
  /// — this test helper stays test-local) the production helper in
  /// `LlamaCppService`.
  private static func longestValidUtf8Prefix(_ bytes: Data) -> String {
    for trim in 0...min(3, bytes.count) {
      let slice = bytes.prefix(bytes.count - trim)
      if let text = String(data: slice, encoding: .utf8) {
        return text
      }
    }
    return ""
  }
}

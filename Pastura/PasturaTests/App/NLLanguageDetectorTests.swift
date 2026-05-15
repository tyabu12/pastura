import Testing

@testable import Pastura

/// Apple `NLLanguageRecognizer`-backed implementation of
/// ``LanguageDetector``. Lives in App/ because ``NaturalLanguage`` is
/// forbidden in Engine / LLM / Models / Data per ADR-010 D8.
///
/// The tests below cover (i) the happy path on a clearly-classifiable
/// Japanese / English sample, (ii) the low-confidence path on a short
/// or ambiguous input (returns `nil` so ``LLMCaller`` skips the
/// adherence check rather than misclassifying short outputs as a
/// mismatch — critic Axis 5 pin).
@Suite(.timeLimit(.minutes(1)))
struct NLLanguageDetectorTests {
  @Test func detectJapaneseSampleReturnsJa() {
    let detector = NLLanguageDetector()
    let result = detector.detect(text: "今日は良い天気ですね。明日も晴れるといいなと思います。")
    #expect(result == "ja")
  }

  @Test func detectEnglishSampleReturnsEn() {
    let detector = NLLanguageDetector()
    let result = detector.detect(
      text: "It's a beautiful day today. I hope it stays sunny tomorrow as well.")
    #expect(result == "en")
  }

  @Test func detectEmptyInputReturnsNil() {
    let detector = NLLanguageDetector()
    #expect(detector.detect(text: "") == nil)
  }

  @Test func detectAmbiguousShortInputReturnsNilOrLow() {
    // Proper nouns / single tokens fall below `NLLanguageRecognizer`'s
    // confidence floor; the detector returns nil so callers skip the
    // adherence check rather than spuriously retrying on short outputs.
    // We accept either `nil` (preferred) or a non-`ja` / non-`en` ISO
    // code in case the recognizer locks onto a low-confidence guess —
    // the load-bearing assertion is that ambiguous one-token input
    // does NOT lock onto either of our two target languages with high
    // confidence.
    let detector = NLLanguageDetector()
    let result = detector.detect(text: "a")
    #expect(result == nil)
  }

  @Test func detectorIsReusableAcrossCalls() {
    // Each call constructs a fresh `NLLanguageRecognizer` internally,
    // so prior `processString` state doesn't leak into subsequent
    // calls (would yield wrong-language results on cross-language
    // benchmark loops in Step E PR2 item 6).
    let detector = NLLanguageDetector()
    let ja = detector.detect(text: "今日は良い天気ですね。明日も晴れるといいなと思います。")
    let en = detector.detect(
      text: "It's a beautiful day today. I hope it stays sunny tomorrow as well.")
    let jaAgain = detector.detect(text: "おはようございます。今朝はとても清々しいですね。")
    #expect(ja == "ja")
    #expect(en == "en")
    #expect(jaAgain == "ja")
  }
}

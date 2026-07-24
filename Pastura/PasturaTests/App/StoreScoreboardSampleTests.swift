#if DEBUG

  import Foundation
  import Testing

  @testable import Pastura

  /// Unit tests for ``StoreScoreboardSample`` — the fixed scoreboard fixture the
  /// App Store capture photographs (`--ui-test-open-scoreboard`, shot 04).
  ///
  /// Like `StubScenarioSeederTests`, every language assertion pins `language:`
  /// and compares against a literal: the production default is
  /// `LocaleResolver.deviceDefault()`, so a locale-resolved expectation would
  /// pass on any runner without proving the selection works.
  @Suite(.timeLimit(.minutes(1)))
  @MainActor
  struct StoreScoreboardSampleTests {

    @Test func testSelectorReturnsRequestedLanguage() {
      #expect(StoreScoreboardSample.current(language: "en").scores["Alice"] == 5)
      #expect(StoreScoreboardSample.current(language: "ja").scores["ハルカ"] == 5)
      // The other language's cast must be absent, not merely outscored — a
      // selector that merged both dictionaries would still satisfy the lookups
      // above.
      #expect(StoreScoreboardSample.current(language: "ja").scores["Alice"] == nil)
      #expect(StoreScoreboardSample.current(language: "en").scores["ハルカ"] == nil)
    }

    /// Unknown / unsupported codes fall back to English, the App Store base
    /// locale — the same arm `LocaleResolver.deviceDefault()` takes, kept in
    /// sync through the shared `pickCaptureLanguage`.
    @Test func testUnknownLanguageFallsBackToEnglish() {
      #expect(StoreScoreboardSample.current(language: "fr").scores["Alice"] == 5)
      #expect(StoreScoreboardSample.current(language: "").scores["Alice"] == 5)
    }

    /// The eliminated agent must exist in `scores`. `ScoreboardSheet` renders
    /// the struck-through row by looking the name up in `scores`, so a typo in
    /// either dictionary silently produces a scoreboard with nothing eliminated
    /// — invisible in a green build, visible only in the shipped screenshot.
    @Test func testEliminatedAgentIsPresentInScores() {
      for language in ["en", "ja"] {
        let sample = StoreScoreboardSample.current(language: language)
        let eliminatedNames = sample.eliminated.filter(\.value).map(\.key)
        // Without this the loop below passes vacuously on an empty `eliminated`
        // — and an empty one is itself the regression (shot 04 is supposed to
        // show a struck-through row).
        #expect(!eliminatedNames.isEmpty, "\(language): no agent marked eliminated")
        for name in eliminatedNames {
          #expect(
            sample.scores[name] != nil,
            "\(language): eliminated agent '\(name)' is absent from scores")
          // The type doc-comment promises the "0 点" row is part of the shot.
          // `testLanguagesShareTheSameScoreShape` compares the two languages
          // against each other, so an edit applied to BOTH would drop the
          // zero-score row while every other assertion still passed.
          #expect(
            sample.scores[name] == 0,
            "\(language): eliminated agent '\(name)' should score 0 for the struck-through row")
        }
      }
    }

    /// Both languages must be the **same shot** — same roster size, same score
    /// multiset, same number eliminated — so shot 04 differs between the two
    /// store listings only by the names rendered.
    @Test func testLanguagesShareTheSameScoreShape() {
      let english = StoreScoreboardSample.current(language: "en")
      let japanese = StoreScoreboardSample.current(language: "ja")
      #expect(english.scores.count == japanese.scores.count)
      #expect(english.scores.values.sorted() == japanese.scores.values.sorted())
      #expect(
        english.eliminated.filter(\.value).count == japanese.eliminated.filter(\.value).count)
    }
  }

#endif

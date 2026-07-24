#if DEBUG

  import Foundation

  /// Fixed scoreboard data for the App Store capture, presented when
  /// `--ui-test-open-scoreboard` is passed (see `RootView`'s
  /// `isStoreScoreboardPresented`). The scoreboard is otherwise reachable only
  /// from a completed live run, which `--ui-test` cannot produce
  /// (`MockLLMService(responses: [])` throws on any generate).
  ///
  /// **Localized for the same reason the seeded Home rows are**
  /// (`StubScenarioSeeder+Localized.swift`): shot 04 is photographed for the ja
  /// App Store listing, and English agent names beside the Japanese transcript
  /// in shot 01 read as a half-translated screen.
  ///
  /// Scores and the elimination flag are **identical across languages** — only
  /// the names differ — so the podium order, the struck-through last row, and
  /// the "0 点" zero-score rendering are the same shot in both locales.
  ///
  /// `#if DEBUG`-gated like the sibling stubs so Release-iphoneos binaries carry
  /// no UI-test plumbing (ADR-005 §8.5 dev-only exclusion).
  nonisolated public enum StoreScoreboardSample {
    /// One language's scoreboard fixture. The two fields travel together so a
    /// callsite cannot pair one language's `scores` with another's
    /// `eliminated` — the eliminated key must exist in `scores` or the row
    /// simply never renders struck through.
    public struct Sample: Sendable {
      public let scores: [String: Int]
      public let eliminated: [String: Bool]
    }

    /// The fixture for `language`.
    ///
    /// - Parameter language: see ``pickCaptureLanguage(_:ja:en:)``. Production
    ///   callers take the default; pin it explicitly in tests.
    public static func current(language: String = LocaleResolver.deviceDefault()) -> Sample {
      pickCaptureLanguage(language, ja: japanese, en: english)
    }

    /// Generic English sample names, matching the `Alice` / `Bob` / `Carol` /
    /// `Dave` cast the other en fixtures use.
    static let english = Sample(
      scores: ["Alice": 5, "Bob": 3, "Carol": 2, "Dave": 0],
      eliminated: ["Dave": true])

    /// Japanese cast. Deliberately **not** the ワードウルフ transcript's names
    /// (レン / サクラ / ユウキ / アオイ / タクミ, shot 01): the two screens are
    /// independent samples, not one continuous run, and reusing the cast would
    /// imply a scoreboard for a run whose seeded timeline shows no scores.
    static let japanese = Sample(
      scores: ["ハルカ": 5, "ケンタ": 3, "ミサキ": 2, "リュウジ": 0],
      eliminated: ["リュウジ": true])
  }

#endif

#if DEBUG

  import Foundation

  /// Per-language display copy for the seeded Home rows, plus the selector that
  /// picks between them.
  ///
  /// **Why the rows are localized at all:** `StoreScreenshotTests` photographs
  /// the seeded Home list (shot 02) and Past-Results list (shot 05) for the App
  /// Store. Before this split, a ja-locale capture rendered Japanese UI chrome
  /// around English scenario names.
  ///
  /// **Why there is no new locale switch:** the language comes from
  /// ``LocaleResolver/deviceDefault(preferredLocalizations:)`` — the ADR-010 D2
  /// canonical seam, already fed by the `-AppleLanguages` launch arguments the
  /// UI test passes. A separate `--ui-test-seed-home-ja`-style argument would be
  /// a second switch that has to agree with those args, and silently produces
  /// mismatched captures when it doesn't.
  ///
  /// Ids, `agents`, `rounds`, and phase shape are **identical across
  /// languages** — only human-readable text differs — so accessibility anchors
  /// and the ``StubScenarioSeeder/richWordWolfRounds`` invariant hold in both.
  ///
  /// `nonisolated` on the extension: the enclosing enum is `nonisolated`, but a
  /// plain sibling-file `extension` would inherit the App layer's default
  /// MainActor isolation and break the `nonisolated` callers in
  /// `StubScenarioSeeder.swift` (`.claude/rules/swift-isolation.md` Pattern 3 —
  /// the diagnostic fires at the call site, not here).
  nonisolated extension StubScenarioSeeder {

    /// Display name + YAML for one seeded Home row, in one language.
    ///
    /// Bundled rather than returned as separate accessors so the two can't be
    /// selected with different languages at a callsite — the record's `name`
    /// drives the Home row label while the YAML's own `name` drives re-parsed
    /// metadata, and a mismatch shows one name on Home and another after a
    /// reload.
    struct SeedFixture: Sendable {
      let name: String
      let yaml: String
    }

    // MARK: - Selection

    /// Picks the language variant.
    ///
    /// **Not `pickLanguage(_:ja:en:)`**: that helper's `default:` arm returns
    /// **ja** (correct for Engine scenario-language dispatch, where the value is
    /// validator-gated to `{ja, en}` and ja is the authoring baseline). Here the
    /// input is a *device* locale and the base locale is **en** — the App Store
    /// launch target — so an unrecognized code must fall back to English, the
    /// same arm `LocaleResolver.deviceDefault()` takes.
    fileprivate static func localized(_ language: String, ja: String, en: String) -> String {
      language == "ja" ? ja : en
    }

    /// The Home-list base row (always seeded under `--ui-test`).
    static func homeSeed(language: String = LocaleResolver.deviceDefault()) -> SeedFixture {
      SeedFixture(
        name: localized(language, ja: "はじめての牧場", en: "Hello, Pasture"),
        yaml: localized(language, ja: homeSeedYAMLJa, en: homeSeedYAMLEn))
    }

    /// Rich-seed preset row 1.
    static func richDilemma(language: String = LocaleResolver.deviceDefault()) -> SeedFixture {
      SeedFixture(
        name: localized(language, ja: "囚人のジレンマ", en: "Prisoner's Dilemma"),
        yaml: localized(language, ja: richDilemmaYAMLJa, en: richDilemmaYAMLEn))
    }

    /// Rich-seed preset row 2.
    static func richDesert(language: String = LocaleResolver.deviceDefault()) -> SeedFixture {
      SeedFixture(
        name: localized(language, ja: "砂漠のサバイバル", en: "Desert Survival"),
        yaml: localized(language, ja: richDesertYAMLJa, en: richDesertYAMLEn))
    }

    /// Rich-seed gallery-sourced ("shared") row. ``StubPausedRunSeeder`` reads
    /// its `name` for the resume card's snapshot fallback.
    static func richWordWolf(language: String = LocaleResolver.deviceDefault()) -> SeedFixture {
      SeedFixture(
        name: localized(language, ja: "ワードウルフ", en: "Word Wolf"),
        yaml: localized(language, ja: richWordWolfYAMLJa, en: richWordWolfYAMLEn))
    }

    /// Every seeded Home row for `language`, in Home-list order.
    ///
    /// Exposed so `StubScenarioSeederTests` can run the parse / validate /
    /// content-validate gate over **both** languages unconditionally. Without a
    /// list the test would have to reach the variants through the locale-
    /// dependent default, and whichever language the runner wasn't configured
    /// for would never be validated.
    static func allHomeFixtures(language: String) -> [SeedFixture] {
      [
        homeSeed(language: language),
        richDilemma(language: language),
        richDesert(language: language),
        richWordWolf(language: language)
      ]
    }

    // MARK: - Japanese copy

    // NOTE: YAML is indentation-sensitive; do not reflow these multi-line
    // literals (the closing `"""` column is the baseline). See the same note in
    // `StubScenarioSeeder.swift`.

    /// Japanese copy for the Home-list seed row. 2 personas / 1 phase, matching
    /// ``StubScenarioSeeder/homeSeedYAMLEn``.
    static let homeSeedYAMLJa: String = """
      id: ui_test_home_seed
      language: ja
      name: はじめての牧場
      description: エージェント2体の小さな観測。ここから自分のシナリオを作りはじめる。
      agents: 2
      rounds: 1
      context: 牧場に集まった2体が、はじめての挨拶を交わす。
      personas:
        - name: ミドリ
          description: 誰にでも自分から先に声をかける。
        - name: ソラ
          description: 相手の様子をうかがってから話す。
      phases:
        - type: speak_all
          prompt: 挨拶をしてください。
          output:
            statement: string
      """

    /// Japanese preset fixture: 2 agents, 10 rounds — same shape as
    /// ``StubScenarioSeeder/richDilemmaYAMLEn``.
    static let richDilemmaYAMLJa: String = """
      id: ui_test_preset_dilemma
      language: ja
      name: 囚人のジレンマ
      description: 協力か、裏切りか。ラウンドを重ねる中で信頼が育つか壊れるかを観る。
      agents: 2
      rounds: 10
      context: 2体のエージェントが、協力するか裏切るかを繰り返し選ぶ。
      personas:
        - name: アリス
          description: 信頼が積み上がっているうちは協力を選びやすい。
        - name: ボブ
          description: 目先の利益と評判を天秤にかける。
      phases:
        - type: speak_all
          prompt: 自分の選択とその理由を述べてください。
          output:
            statement: string
      """

    /// Japanese preset fixture: 3 agents, 8 rounds — same shape as
    /// ``StubScenarioSeeder/richDesertYAMLEn``.
    static let richDesertYAMLJa: String = """
      id: ui_test_preset_desert
      language: ja
      name: 砂漠のサバイバル
      description: 遭難した3人が装備の優先順位を話し合い、脱出のための合意にたどり着く。
      agents: 3
      rounds: 8
      context: 3人の生存者が、限られた物資の優先順位を決めなければならない。
      personas:
        - name: キャロル
          description: 現実的で、危険を避けたがる。
        - name: デイブ
          description: 楽観的で、すぐに動きたがる。
        - name: エリン
          description: 几帳面で、全員が共有できる計画を求める。
      phases:
        - type: speak_all
          prompt: 自分が優先したい物資とその理由を主張してください。
          output:
            statement: string
      """

    /// Japanese gallery-sourced user fixture: 4 agents, 5 rounds — same shape as
    /// ``StubScenarioSeeder/richWordWolfYAMLEn``, so `rounds` stays ≥ 2 for the
    /// paused-run resume card.
    static let richWordWolfYAMLJa: String = """
      id: ui_test_home_wordwolf
      language: ja
      name: ワードウルフ
      description: ひとりだけ違うお題を渡された少数派を探す、正体隠匿のトークゲーム。
      agents: 4
      rounds: 5
      context: プレイヤーは自分のお題について語り、違うお題を持つ1人をあぶり出す。
      personas:
        - name: レン
          description: 早い段階から探りを入れる質問をする。
        - name: サクラ
          description: 疑われないよう目立たずに振る舞う。
        - name: ユウキ
          description: 他人の手がかりに乗せて話を広げる。
        - name: アオイ
          description: 追い詰められると自信たっぷりにはったりをかける。
      phases:
        - type: speak_all
          prompt: お題を直接言わずに説明してください。
          output:
            statement: string
      """
  }

#endif

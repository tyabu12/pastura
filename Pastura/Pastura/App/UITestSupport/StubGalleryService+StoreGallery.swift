#if DEBUG

  import Foundation

  // MARK: - Store-marketing gallery fixture (#1612)

  extension StubGalleryService {
    /// A ten-entry gallery fixture used to capture App Store screenshots.
    ///
    /// This is a **hand copy** of the ten entries below from `docs/gallery/gallery.json`, taken as
    /// of 2026-09-08. There is no automatic sync — when the shots are re-taken against a newer
    /// curated feed, refresh these literals by hand (`jq` against `gallery.json` and
    /// `docs/gallery/highlights/*.json` is the fastest way to pull fresh values, as done for this
    /// fixture).
    ///
    /// `yamlSHA256` / `highlightSHA256` here are decorative: the stub never verifies a hash
    /// (`fetchScenarioYAML` / `fetchHighlightData` serve straight from the in-memory
    /// dictionaries), so a value going stale relative to the real feed has no effect on this
    /// fixture.
    ///
    /// Every entry's `phases` must keep passing
    /// `EngineSchemaVersion.isCompatible(phases:minEngineVersion:)` on the build that ships the
    /// screenshots. An incompatible entry gets an `.incompatible` suffix appended to its
    /// Browse-tab cell identifier (`SharedScenariosViewModel+InstallState.swift`), which the
    /// screenshot UI test's tap-by-identifier lookup does not expect — the tap would silently miss.
    public static func uiTestStoreGallery() -> StubGalleryService {
      let index = GalleryIndex(
        version: 1, updatedAt: "2026-09-01", scenarios: storeGalleryScenarios)
      return StubGalleryService(
        index: index,
        highlightsByURL: [
          iiwakeJaHighlightURL: iiwakeJaHighlightJSON,
          iiwakeEnHighlightURL: iiwakeEnHighlightJSON
        ])
    }

    /// The ten curated entries, ordered as `docs/gallery/gallery.json` lists them (ja block, then
    /// en block) — not the order the Browse tab will render them in, which is `addedAt`-descending
    /// (see the `addedAt` note below).
    private static var storeGalleryScenarios: [GalleryScenario] {
      [
        shazaiJa, kinokoTakenokoJa, iiwakeBattleJa, chinJimakuJa, hissatsuNamingJa,
        shazaiEn, chinJimakuEn, iiwakeBattleEn, hissatsuNamingEn, aschConformityEn
      ]
    }

    private static func stubURL(_ string: String) -> URL {
      // Hardcoded literal — failure is structurally impossible, but the
      // project bans `!` so the guard makes the invariant explicit.
      guard let url = URL(string: string) else {
        fatalError("Store gallery stub URL literal failed to parse: \(string)")
      }
      return url
    }

    // MARK: ja entries

    private static let shazaiJaYAMLURL = stubURL("stub://gallery/shazai_master_v1.yaml")

    private static let shazaiJa = GalleryScenario(
      id: "shazai_master_v1",
      title: "謝罪マスター選手権",
      category: .roleplay,
      description:
        "5人の謝罪芸人が、毎ラウンド変わる不祥事のお題に全力の謝罪会見コメントで応戦する勝ち抜き戦。号泣・逆ギレ・論点そらし・責任転嫁・過剰卑屈——最も誠意のない謝罪が毎ラウンド脱落する。",
      author: "tyabu12",
      recommendedModel: ModelRegistry.gemma4E2B.id,
      estimatedInferences: 40,
      yamlURL: shazaiJaYAMLURL,
      yamlSHA256: "241b8b807be66aa4c37e01971cb7b6187e9e2b1d8ce4b3d7928d8d2c5b865058",
      addedAt: "2026-08-25",
      agentCount: 5,
      rounds: 4,
      phases: ["assign", "speak_all", "vote", "score_calc", "eliminate", "summarize"],
      language: "ja"
    )

    private static let kinokoTakenokoJa = GalleryScenario(
      id: "kinoko_takenoko_v1",
      title: "きのこの山 vs たけのこの里",
      category: .creative,
      description:
        "4人の芸人が持ちキャラの芸風（陰謀論・叙事詩・演歌・捏造データ）で「きのこ派 vs たけのこ派」の至高を主張し合う大喜利バトル。最も笑わせた主張に投票する。",
      author: "tyabu12",
      recommendedModel: ModelRegistry.gemma4E2B.id,
      estimatedInferences: 16,
      yamlURL: stubURL("stub://gallery/kinoko_takenoko_v1.yaml"),
      yamlSHA256: "84eceaff5af19c40f09a298b39854310b8e90883d79fd26b347cda1e58a311be",
      addedAt: "2026-08-29",
      agentCount: 4,
      rounds: 2,
      phases: ["assign", "speak_all", "vote", "score_calc", "summarize"],
      language: "ja"
    )

    private static let iiwakeJaHighlightURL = stubURL(
      "stub://gallery/iiwake_battle_v1-highlight.json")

    /// `addedAt` is the newest date in this fixture (both `iiwake_battle_*` entries share it) —
    /// the Browse list sorts `addedAt` descending then `id` (`GalleryScenarioSearch`), and the
    /// screenshot UI test taps `iiwake_battle_v1` / `iiwake_battle_v1_en` without scrolling, so
    /// this entry must sort to the top of its language.
    private static let iiwakeBattleJa = GalleryScenario(
      id: "iiwake_battle_v1",
      title: "言い訳エスカレーション",
      category: .creative,
      description:
        "やらかしたシチュエーションに対して順番に言い訳をしていくバトル。 前の人の言い訳より大胆でスケールの大きい言い訳を重ねないと埋もれる、 後攻有利と自爆リスクが同居した順番制の大喜利。",
      author: "tyabu12",
      recommendedModel: ModelRegistry.gemma4E2B.id,
      estimatedInferences: 16,
      yamlURL: stubURL("stub://gallery/iiwake_battle_v1.yaml"),
      yamlSHA256: "6b35dbf5ac872170d480ca73f5c088dd34f5c727f21015a7d39eb7032d22ec9d",
      addedAt: "2026-09-01",
      agentCount: 4,
      rounds: 2,
      phases: ["assign", "speak_each", "vote", "score_calc", "summarize"],
      language: "ja",
      highlightURL: iiwakeJaHighlightURL,
      highlightSHA256: "621a38610ec73d0d981c4f9bdf34cbfd5cc1e300e630541d1efa5773ef7b20cd"
    )

    private static let chinJimakuJa = GalleryScenario(
      id: "chin_jimaku_v1",
      title: "映画の珍字幕",
      category: .creative,
      description:
        "洋画の名シーンと原語のセリフが与えられ、4人のダメ字幕翻訳者が それぞれの芸風で「珍妙な日本語字幕」をつける大喜利。最も笑える字幕に投票する。",
      author: "tyabu12",
      recommendedModel: ModelRegistry.gemma4E2B.id,
      estimatedInferences: 16,
      yamlURL: stubURL("stub://gallery/chin_jimaku_v1.yaml"),
      yamlSHA256: "c234c6dea41a7266a842e9a8728a9c1962e19882efb38f4380fa9f7392b37118",
      addedAt: "2026-08-27",
      agentCount: 4,
      rounds: 2,
      phases: ["assign", "speak_all", "vote", "score_calc", "summarize"],
      language: "ja"
    )

    private static let hissatsuNamingJa = GalleryScenario(
      id: "hissatsu_naming_v1",
      title: "必殺技ネーミング 決勝サドンデス",
      category: .creative,
      description:
        "地味な日常動作に、字面が強すぎる中二病的な必殺技名を一文で命名する 大喜利。最終ラウンドは「サドンデス」に突入し、二つの地味な動作を 合体させた究極奥義へとお題が過激化する。",
      author: "tyabu12",
      recommendedModel: ModelRegistry.gemma4E2B.id,
      estimatedInferences: 16,
      yamlURL: stubURL("stub://gallery/hissatsu_naming_v1.yaml"),
      yamlSHA256: "85ab46895c23dbade22e0850f9775df82cc72295f78989be866eac686110b99a",
      addedAt: "2026-08-26",
      agentCount: 4,
      rounds: 2,
      phases: [
        "conditional", "speak_all", "vote", "score_calc", "summarize",
        "speak_all", "vote", "score_calc", "summarize"
      ],
      language: "ja"
    )

    // MARK: en entries

    private static let shazaiEnYAMLURL = stubURL("stub://gallery/shazai_master_v1_en.yaml")

    private static let shazaiEn = GalleryScenario(
      id: "shazai_master_v1_en",
      title: "Apology Master Championship",
      category: .roleplay,
      description:
        """
        A last-one-standing showdown where five apology performers meet a rotating scandal \
        prompt with an all-out crisis-apology press conference. Sobbing, backlash, \
        topic-dodging, blame-shifting, and groveling — the least sincere apology is voted out \
        each round.
        """,
      author: "tyabu12",
      recommendedModel: ModelRegistry.gemma4E2B.id,
      estimatedInferences: 40,
      yamlURL: shazaiEnYAMLURL,
      yamlSHA256: "b50e9539ef0c5b71332af1fc308fb6a5aff5ad35a62b48427e94d7203f9b91fc",
      addedAt: "2026-08-25",
      agentCount: 5,
      rounds: 4,
      phases: ["assign", "speak_all", "vote", "score_calc", "eliminate", "summarize"],
      language: "en"
    )

    private static let chinJimakuEn = GalleryScenario(
      id: "chin_jimaku_v1_en",
      title: "Terrible Movie Subtitles",
      category: .creative,
      description:
        """
        Four hopeless subtitle translators slap absurd English subtitles onto a famous movie \
        line, each in their own terrible style; everyone votes for the funniest.
        """,
      author: "tyabu12",
      recommendedModel: ModelRegistry.gemma4E2B.id,
      estimatedInferences: 16,
      yamlURL: stubURL("stub://gallery/chin_jimaku_v1_en.yaml"),
      yamlSHA256: "05c55f6a8dd5a50a8ae737eff55204882a117dc1fb6f0692acc6a498b25aec0a",
      addedAt: "2026-08-29",
      agentCount: 4,
      rounds: 2,
      phases: ["assign", "speak_all", "vote", "score_calc", "summarize"],
      language: "en"
    )

    private static let iiwakeEnHighlightURL = stubURL(
      "stub://gallery/iiwake_battle_v1_en-highlight.json")

    /// See the ja twin's note: shares the newest `addedAt` so it sorts first
    /// within the en language filter too.
    private static let iiwakeBattleEn = GalleryScenario(
      id: "iiwake_battle_v1_en",
      title: "Excuse Escalation",
      category: .creative,
      description:
        """
        A turn-based battle of excuses for the same screw-up: top the previous player's excuse \
        or get buried, but overreach and it backfires.
        """,
      author: "tyabu12",
      recommendedModel: ModelRegistry.gemma4E2B.id,
      estimatedInferences: 16,
      yamlURL: stubURL("stub://gallery/iiwake_battle_v1_en.yaml"),
      yamlSHA256: "b47f37647dcc7890cba6eca655f9a3cbe66d9e0710fa4f76456ba01a466284f3",
      addedAt: "2026-09-01",
      agentCount: 4,
      rounds: 2,
      phases: ["assign", "speak_each", "vote", "score_calc", "summarize"],
      language: "en",
      highlightURL: iiwakeEnHighlightURL,
      highlightSHA256: "ac1b38ca3a945efdc768f318edf1833baede865fba30d279abdaae4677fc8165"
    )

    private static let hissatsuNamingEn = GalleryScenario(
      id: "hissatsu_naming_v1_en",
      title: "Finishing-Move Naming — Sudden-Death Final",
      category: .creative,
      description:
        """
        Brand a dull everyday action with an absurdly epic anime finishing-move name — the \
        sudden-death final fuses two mundane actions into one ultimate technique.
        """,
      author: "tyabu12",
      recommendedModel: ModelRegistry.gemma4E2B.id,
      estimatedInferences: 16,
      yamlURL: stubURL("stub://gallery/hissatsu_naming_v1_en.yaml"),
      yamlSHA256: "2cab9d9498fcfe433af1b880ad80c0beb5b8cad4632ab010ea3dc33c2749dc76",
      addedAt: "2026-08-27",
      agentCount: 4,
      rounds: 2,
      phases: [
        "conditional", "speak_all", "vote", "score_calc", "summarize",
        "speak_all", "vote", "score_calc", "summarize"
      ],
      language: "en"
    )

    private static let aschConformityEn = GalleryScenario(
      id: "asch_conformity_v1_en",
      title: "Asch Conformity Experiment",
      category: .socialPsychology,
      description:
        "A recreation of the classic conformity experiment: four confederates and one real subject.",
      author: "tyabu12",
      recommendedModel: ModelRegistry.gemma4E2B.id,
      estimatedInferences: 15,
      yamlURL: stubURL("stub://gallery/asch_conformity_v1_en.yaml"),
      yamlSHA256: "444d0bd5f66e17b84268fb38ed92696f407335491301d3eadad664e2a6ff0fa5",
      addedAt: "2026-08-26",
      agentCount: 5,
      rounds: 3,
      phases: ["speak_each", "summarize"],
      language: "en"
    )

    // MARK: highlight bodies

    /// Verbatim contents of `docs/gallery/highlights/iiwake_battle_v1.json`.
    private static let iiwakeJaHighlightJSON: Data = Data(
      """
      {
        "schema_version": 1,
        "scenario_ref": {
          "id": "iiwake_battle_v1",
          "yaml_sha256": "6b35dbf5ac872170d480ca73f5c088dd34f5c727f21015a7d39eb7032d22ec9d"
        },
        "source": {
          "model": "gemma-4-e2b-q4-k-m",
          "run_id": "20260808-131915-59f5",
          "generated_at": "2026-08-08"
        },
        "excerpt": [
          {
            "agent": "国際派ジョージ",
            "round": 1,
            "phase": "speak_each",
            "phase_index": 1,
            "persona_index": 0,
            "source_field": "statement",
            "text": "サマータイムの廃止決定に伴う世界標準時への移行の混乱が、私のスケジュールに予期せぬ遅延をもたらしました。"
          },
          {
            "agent": "科学者リケ美",
            "round": 1,
            "phase": "speak_each",
            "phase_index": 1,
            "persona_index": 1,
            "source_field": "statement",
            "text": "私の遅刻は、予測不能な量子もつれ状態に陥ったため、時間軸の局所性が崩壊した結果です。"
          },
          {
            "agent": "浪花節たけし",
            "round": 1,
            "phase": "speak_each",
            "phase_index": 1,
            "persona_index": 2,
            "source_field": "statement",
            "text": "実は、その会議の直前、急な嵐で外が完全に水没し、私は避難するのに時間を費やしてしまいました。"
          },
          {
            "agent": "開き直りマコ",
            "round": 1,
            "phase": "speak_each",
            "phase_index": 1,
            "persona_index": 3,
            "source_field": "statement",
            "text": "私の遅刻は、単なる時間感覚の誤作動ではなく、会議そのものが持つべき神聖な儀式を尊重するために必要な儀式的な停滞でした。"
          }
        ],
        "yaml_hook": {
          "kind": "persona",
          "fragment": "  - name: 国際派ジョージ\\n    description: >\\n      【立場】何でも国際問題のせいにするスケール詐欺師\\n      【目的】時差・為替・外交問題など世界規模の理由に責任転嫁して笑いを取る。\\n      例:「サマータイムの廃止が決まった影響で」「円安がここまでとは」\\n  - name: 開き直りマコ\\n    description: >\\n      【立場】言い訳を放棄して堂々と開き直る確信犯\\n      【目的】謝るどころか逆に相手を説得し始める図々しさで笑いを取る。\\n      例:「むしろ感謝してほしい」「これは遅刻ではなく様式美」",
          "caption": "並んだ4人から、両極の2人を抜き出した設定。スケールで殴る詐欺師と、そもそも謝らない確信犯——芸風の正体は『例』に並ぶ一言だ。差し替えれば、言い訳の流派はまるごと入れ替わる。"
        },
        "teaser": "後から言うほど大胆にしないと埋もれる。4人の言い訳バトル、生き残るのは誰か、アプリで確かめよう。",
        "window_override": false,
        "content_filter_applied": true
      }
      """.utf8)

    /// Verbatim contents of `docs/gallery/highlights/iiwake_battle_v1_en.json`.
    private static let iiwakeEnHighlightJSON: Data = Data(
      """
      {
        "schema_version": 1,
        "scenario_ref": {
          "id": "iiwake_battle_v1_en",
          "yaml_sha256": "b47f37647dcc7890cba6eca655f9a3cbe66d9e0710fa4f76456ba01a466284f3"
        },
        "source": {
          "model": "gemma-4-e2b-q4-k-m",
          "run_id": "20260827-100042-d0e3",
          "generated_at": "2026-08-27"
        },
        "excerpt": [
          {
            "agent": "Global George",
            "round": 1,
            "phase": "speak_each",
            "phase_index": 1,
            "persona_index": 0,
            "source_field": "statement",
            "text": "I apologize, but the fluctuating global shipping lanes caused an unavoidable delay in my arrival."
          },
          {
            "agent": "Dr. Quantum",
            "round": 1,
            "phase": "speak_each",
            "phase_index": 1,
            "persona_index": 1,
            "source_field": "statement",
            "text": "My temporal coordinates were momentarily entangled with a localized distortion field, resulting in an unavoidable phase shift."
          },
          {
            "agent": "Sentimental Sam",
            "round": 1,
            "phase": "speak_each",
            "phase_index": 1,
            "persona_index": 2,
            "source_field": "statement",
            "text": "Oh, the sheer agony of missing that meeting was due to a sudden, heartbreaking realization that I had forgotten my favorite childhood teddy bear at home."
          }
        ],
        "yaml_hook": {
          "kind": "persona",
          "fragment": "  - name: Dr. Quantum\\n    description: >\\n      [Role] An excuse-maker armed with pseudo-science.\\n      [Goal] Blind everyone with plausible-sounding jargon.\\n      e.g. \\"Until observed, my lateness remains in superposition.\\" \\"It was the\\n      unanimous verdict of my gut microbiome.\\"\\n  - name: Sentimental Sam\\n    description: >\\n      [Role] A tear-jerking excuse-maker who tugs the heartstrings.\\n      [Goal] Spin a sob story so shamelessly moving the listener wants to forgive\\n      you anyway.\\n      e.g. \\"A stray kitten simply would not let go of me.\\" \\"It was a promise I made\\n      to my late grandmother.\\"",
          "caption": "Pseudo-science and a sob story: two of the four excuse-makers in the line-up. The act lives in the e.g. lines. Swap those and you have changed the school of excuse-making, not just the wording."
        },
        "teaser": "Speaking later means topping the excuse before yours, and laying it on too thick backfires. There is another screw-up to answer for after this one.",
        "window_override": false,
        "content_filter_applied": true
      }
      """.utf8)
  }

#endif

#if DEBUG

  import Foundation

  // MARK: - Store-marketing gallery fixture (#1612)

  extension StubGalleryService {
    /// A ten-entry gallery fixture used to capture App Store screenshots.
    ///
    /// This is a **hand copy** of the ten entries below from
    /// `docs/gallery/gallery.json`, taken as of 2026-09-08. There is no
    /// automatic sync — when the shots are re-taken against a newer curated
    /// feed, refresh these literals by hand (`jq` against `gallery.json` and
    /// `docs/gallery/highlights/*.json` is the fastest way to pull fresh
    /// values, as done for this fixture).
    ///
    /// `yamlSHA256` / `highlightSHA256` here are decorative: the stub never
    /// verifies a hash (`fetchScenarioYAML` / `fetchHighlightData` serve
    /// straight from the in-memory dictionaries), so a value going stale
    /// relative to the real feed has no effect on this fixture.
    ///
    /// Every entry's `phases` must keep passing
    /// `EngineSchemaVersion.isCompatible(phases:minEngineVersion:)` on the
    /// build that ships the screenshots. An incompatible entry gets an
    /// `.incompatible` suffix appended to its Browse-tab cell identifier
    /// (`SharedScenariosViewModel+InstallState.swift`), which the screenshot
    /// UI test's tap-by-identifier lookup does not expect — the tap would
    /// silently miss.
    public static func uiTestStoreGallery() -> StubGalleryService {
      let index = GalleryIndex(
        version: 1, updatedAt: "2026-09-01", scenarios: storeGalleryScenarios)
      return StubGalleryService(
        index: index,
        highlightsByURL: [
          shazaiJaHighlightURL: shazaiJaHighlightJSON,
          shazaiEnHighlightURL: shazaiEnHighlightJSON
        ])
    }

    /// The ten curated entries, ordered as `docs/gallery/gallery.json` lists
    /// them (ja block, then en block) — not the order the Browse tab will
    /// render them in, which is `addedAt`-descending (see the `addedAt`
    /// note below).
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
    private static let shazaiJaHighlightURL = stubURL(
      "stub://gallery/shazai_master_v1-highlight.json")

    /// `addedAt` is the newest date in this fixture (both `shazai_master_*`
    /// entries share it) — the Browse list sorts `addedAt` descending then
    /// `id` (`GalleryScenarioSearch`), and the screenshot UI test taps
    /// `shazai_master_v1` / `shazai_master_v1_en` without scrolling, so this
    /// entry must sort to the top of its language.
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
      addedAt: "2026-09-01",
      agentCount: 5,
      rounds: 4,
      phases: ["assign", "speak_all", "vote", "score_calc", "eliminate", "summarize"],
      language: "ja",
      highlightURL: shazaiJaHighlightURL,
      highlightSHA256: "4f6ffc60c6bc4eda5d1f4c42ee7e79e010ee017152d01db6e9d686c1c00d5e82"
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
      addedAt: "2026-08-28",
      agentCount: 4,
      rounds: 2,
      phases: ["assign", "speak_each", "vote", "score_calc", "summarize"],
      language: "ja"
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
    private static let shazaiEnHighlightURL = stubURL(
      "stub://gallery/shazai_master_v1_en-highlight.json")

    /// See the ja twin's note: shares the newest `addedAt` so it sorts first
    /// within the en language filter too.
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
      addedAt: "2026-09-01",
      agentCount: 5,
      rounds: 4,
      phases: ["assign", "speak_all", "vote", "score_calc", "eliminate", "summarize"],
      language: "en",
      highlightURL: shazaiEnHighlightURL,
      highlightSHA256: "e93b32f4ed8811e3c43506fa56d0b6e497b6065721413c74150ae3ae742fb2a9"
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
      addedAt: "2026-08-28",
      agentCount: 4,
      rounds: 2,
      phases: ["assign", "speak_each", "vote", "score_calc", "summarize"],
      language: "en"
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

    /// Verbatim contents of `docs/gallery/highlights/shazai_master_v1.json`.
    private static let shazaiJaHighlightJSON: Data = Data(
      """
      {
        "schema_version": 1,
        "scenario_ref": {
          "id": "shazai_master_v1",
          "yaml_sha256": "241b8b807be66aa4c37e01971cb7b6187e9e2b1d8ce4b3d7928d8d2c5b865058"
        },
        "source": {
          "model": "gemma-4-e2b-q4-k-m",
          "run_id": "20260828-090131-bd17",
          "generated_at": "2026-08-28"
        },
        "excerpt": [
          {
            "agent": "論点そらしのソラシ",
            "round": 1,
            "phase": "speak_all",
            "phase_index": 1,
            "persona_index": 2,
            "source_field": "statement",
            "text": "この件で、弊社は品質改善のための新たな取り組みを開始します。"
          },
          {
            "agent": "責任転嫁のテンカ",
            "round": 1,
            "phase": "speak_all",
            "phase_index": 1,
            "persona_index": 3,
            "source_field": "statement",
            "text": "私は何も関与していません。現場の作業員の管理体制が不十分だったのが実情です。"
          },
          {
            "agent": "過剰卑屈のヘコム",
            "round": 1,
            "phase": "speak_all",
            "phase_index": 1,
            "persona_index": 4,
            "source_field": "statement",
            "text": "私のような者が、この汚点を生み出したことに対し、存在そのものが許されぬと心より嘆願いたします。"
          }
        ],
        "yaml_hook": {
          "kind": "persona",
          "fragment": "  - name: 責任転嫁のテンカ\\n    description: >\\n      【立場】自分は一切悪くない体で、原因を必ず他へ押し付ける転嫁の名手。\\n      【目的】部下・システム・天候・時代——何にでも罪を着せ、自分は被害者面をする。\\n      例:「これは現場の担当者の判断でして、私はむしろ知らされていなかった側でして」",
          "caption": "この3人、誰ひとり「すみません」を言っていない。前向きな告知にすり替える者、罪を現場に置いてくる者、卑下が謝罪を追い越してしまう者——謝罪会見の体裁だけが残って、中身が全部よそへ行っている。"
        },
        "teaser": "不祥事お題は毎ラウンド更新。5つの芸風のうち、最初に『誠意がない』と投票で見切られるのはどれか。",
        "window_override": false,
        "content_filter_applied": true
      }
      """.utf8)

    /// Verbatim contents of `docs/gallery/highlights/shazai_master_v1_en.json`.
    private static let shazaiEnHighlightJSON: Data = Data(
      """
      {
        "schema_version": 1,
        "scenario_ref": {
          "id": "shazai_master_v1_en",
          "yaml_sha256": "b50e9539ef0c5b71332af1fc308fb6a5aff5ad35a62b48427e94d7203f9b91fc"
        },
        "source": {
          "model": "gemma-4-e2b-q4-k-m",
          "run_id": "20260828-095506-8e45",
          "generated_at": "2026-08-28"
        },
        "excerpt": [
          {
            "agent": "Sidestep Sid",
            "round": 1,
            "phase": "speak_all",
            "phase_index": 1,
            "persona_index": 2,
            "source_field": "statement",
            "text": "We are excited to announce a new line of eco-friendly products launching next Tuesday!"
          },
          {
            "agent": "Blame-Shift Blake",
            "round": 1,
            "phase": "speak_all",
            "phase_index": 1,
            "persona_index": 3,
            "source_field": "statement",
            "text": "This was clearly a lapse in quality control that the external supplier failed to monitor; I was simply trying my best."
          },
          {
            "agent": "Grovel Greg",
            "round": 1,
            "phase": "speak_all",
            "phase_index": 1,
            "persona_index": 4,
            "source_field": "statement",
            "text": "I am eternally sorry for this grievous oversight; my very existence is a stain on the earth."
          }
        ],
        "yaml_hook": {
          "kind": "persona",
          "fragment": "  - name: Grovel Greg\\n    description: >\\n      [Role] The excessive-groveling type who apologizes so much it gets unsettling.\\n      [Goal] Escalate self-abasement to a \\"someone like me has no right to exist\\" level,\\n      overshooting the apology entirely.\\n      e.g. \\"That someone like me was even breathing is itself an apology owed to all humankind.\\"",
          "caption": "Greg is the only one here who apologizes at all, and he overshoots so far that there is nothing left to forgive. The two beside him have already moved on to product launches and somebody else's paperwork."
        },
        "teaser": "Nobody on this stage has said what actually happened. At the end of every round, a vote removes whoever sounded least sincere.",
        "window_override": false,
        "content_filter_applied": true
      }
      """.utf8)
  }

#endif

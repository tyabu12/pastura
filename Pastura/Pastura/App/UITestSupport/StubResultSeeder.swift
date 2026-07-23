#if DEBUG

  import Foundation

  /// UI-test-only seeding for the Past Results screens.
  ///
  /// Inserts one **completed** simulation plus its timeline so `ResultsView`
  /// shows a tappable group and `ResultDetailView` renders a representative
  /// timeline. Which timeline is seeded is chosen by ``MarketingFixture``:
  ///
  /// - ``MarketingFixture/defaultAliceBob`` — the original two-round
  ///   `speak_all` fixture (Alice / Bob) backing the `08-result-detail` tour
  ///   shot. No code-phase events. Activated by `--ui-test-seed-results`.
  /// - ``MarketingFixture/wordWolf`` / ``MarketingFixture/prisoners`` — two
  ///   curated verbatim transcripts (Japanese) that reproduce real
  ///   AI-generated runs for the Zenn-article "inference screenshots". They
  ///   seed `TurnRecord`s *and* `CodePhaseEventRecord`s so the timeline
  ///   renders vote tallies / summaries. Activated by
  ///   `--ui-test-seed-results-wordwolf` / `--ui-test-seed-results-prisoners`.
  ///
  /// All fixtures reuse the single stable ``simulationId`` so the
  /// `results.row.ui_test_result_seed` row anchor and navigation keep working;
  /// exactly ONE fixture is seeded per launch. Plain `--ui-test` runs stay
  /// unseeded so navigation tests keep exercising the empty state.
  ///
  /// `#if DEBUG`-gated like the sibling stubs so Release-iphoneos binaries
  /// carry no UI-test plumbing (ADR-005 §8.5 dev-only exclusion — same
  /// convention as `AppDependencies.uiTestEditorSeedYAML`).
  nonisolated public enum StubResultSeeder {
    /// Simulation id for the seeded run. Stable so UI tests can target
    /// `results.row.ui_test_result_seed` by identifier.
    public static let simulationId = "ui_test_result_seed"

    /// Which curated timeline to seed. See the type doc-comment for the
    /// launch-argument mapping.
    public enum MarketingFixture: Sendable {
      case defaultAliceBob
      case wordWolf
      case prisoners
    }

    /// One fixture utterance for the default Alice/Bob timeline (struct rather
    /// than a labeled tuple — SwiftLint `large_tuple` caps tuples at 2 members).
    private struct SeedStatement {
      let round: Int
      let agent: String
      let text: String
      /// Private inner voice for this turn. Seeded so the timeline renders
      /// the ▸ THINKING section (speech + inner-voice bubbles) for App Store
      /// screenshots — the transcript replay is the store "observation" shot
      /// (`StoreScreenshotTests`). `showAllThoughts` defaults `true`.
      let thought: String
    }

    /// A fully-built fixture ready for persistence.
    fileprivate struct FixtureBundle {
      let record: SimulationRecord
      let turns: [TurnRecord]
      let events: [CodePhaseEventRecord]
    }

    /// Inserts the completed simulation and its timeline for `fixture`.
    ///
    /// Idempotent per repository upsert semantics. Called from
    /// `setupUITestState()`. The default fixture references
    /// ``StubScenarioSeeder/homeSeedScenarioId`` (whose Alice / Bob personas
    /// the turn `agentName`s match); the marketing fixtures are self-contained
    /// orphan runs (`scenarioId == nil`) whose `scenarioYamlSnapshot` carries
    /// the bundled preset YAML for persona / avatar resolution.
    public static func seed(
      simulationRepository: any SimulationRepository,
      turnRepository: any TurnRepository,
      codePhaseEventRepository: any CodePhaseEventRepository,
      fixture: MarketingFixture = .defaultAliceBob
    ) async throws {
      let base = Date()
      switch fixture {
      case .defaultAliceBob:
        // Default fixture has no code-phase events by design (speak_all only),
        // so it saves inline rather than through the `save(_:…)` helper the
        // marketing fixtures use for their turns + events.
        let record = defaultRecord(base: base)
        let turns = makeTurns(base: base)
        try await offMain {
          try simulationRepository.save(record)
          try turnRepository.saveBatch(turns)
        }
      case .wordWolf:
        let bundle = try makeWordWolfFixture(base: base)
        try await save(bundle, simulationRepository, turnRepository, codePhaseEventRepository)
      case .prisoners:
        let bundle = try makePrisonersFixture(base: base)
        try await save(bundle, simulationRepository, turnRepository, codePhaseEventRepository)
      }
    }

    private static func save(
      _ bundle: FixtureBundle,
      _ simulationRepository: any SimulationRepository,
      _ turnRepository: any TurnRepository,
      _ codePhaseEventRepository: any CodePhaseEventRepository
    ) async throws {
      try await offMain {
        try simulationRepository.save(bundle.record)
        try turnRepository.saveBatch(bundle.turns)
        try codePhaseEventRepository.saveBatch(bundle.events)
      }
    }

    // MARK: - Default Alice/Bob fixture

    private static func defaultRecord(base: Date) -> SimulationRecord {
      SimulationRecord(
        id: simulationId,
        scenarioId: StubScenarioSeeder.homeSeedScenarioId,
        status: SimulationStatus.completed.rawValue,
        currentRound: 2,
        currentPhaseIndex: 0,
        stateJSON: "{}",
        configJSON: nil,
        createdAt: base,
        updatedAt: base,
        modelIdentifier: "gemma-4-e2b-q4-k-m",
        llmBackend: "llamacpp"
      )
    }

    /// Builds the default fixture timeline: 2 rounds x 2 agents. Statements are
    /// display-only copy — long enough that chat bubbles wrap and the
    /// timeline's spacing / round-separator rhythm is reviewable in
    /// screenshots.
    private static func makeTurns(base: Date) -> [TurnRecord] {
      let statements: [SeedStatement] = [
        SeedStatement(
          round: 1, agent: "Alice",
          text: "Hello! I think we should start by sharing what each of us observed this morning.",
          thought: "If I sound organized, the others will follow my lead."
        ),
        SeedStatement(
          round: 1, agent: "Bob",
          text:
            "Agreed. The pasture by the north fence looked unusually quiet, which worries me a little.",
          thought: "I'll flag the north fence early — better than being blamed for it later."
        ),
        SeedStatement(
          round: 2, agent: "Alice",
          text:
            "Building on that — if the north side stays quiet tomorrow, I suggest we move the flock east.",
          thought: "Moving east keeps my own field clear of the risk. Don't make that obvious."
        ),
        SeedStatement(
          round: 2, agent: "Bob",
          text: "That sounds reasonable. Let's agree on the east plan and check again at sunrise.",
          thought: "Going along for now. I still want to see who benefits most from the east move."
        )
      ]
      return statements.enumerated().map { index, entry in
        TurnRecord(
          id: "\(simulationId)_t\(index)",
          simulationId: simulationId,
          roundNumber: entry.round,
          phaseType: "speak_all",
          agentName: entry.agent,
          rawOutput: #"{"statement": "\#(entry.text)", "inner_thought": "\#(entry.thought)"}"#,
          // TurnOutput's Codable shape nests fields under "fields"; `statement`
          // renders the speech bubble and `inner_thought` drives the ▸ THINKING
          // section (`TurnOutput.innerThought` reads `fields["inner_thought"]`).
          parsedOutputJSON:
            #"{"fields":{"statement":"\#(entry.text)","inner_thought":"\#(entry.thought)"}}"#,
          sequenceNumber: index,
          createdAt: base.addingTimeInterval(TimeInterval(index))
        )
      }
    }
  }

  // MARK: - Marketing fixtures (verbatim AI-generated transcripts)

  /// The two curated marketing timelines. Kept in an extension so the primary
  /// enum body stays within SwiftLint's `type_body_length`; `nonisolated` so
  /// these statics stay callable from the nonisolated `seed(...)` under
  /// default-MainActor isolation (swift-isolation.md Pattern 3).
  nonisolated extension StubResultSeeder {
    /// One turn to seed, bundled into a struct so the builder doesn't exceed
    /// SwiftLint's `function_parameter_count`.
    fileprivate struct TurnSpec {
      let seq: Int
      let round: Int
      let phaseType: String
      let agent: String
      let fields: [String: String]
    }

    /// One code-phase event to seed (see ``TurnSpec`` for why it's a struct).
    fileprivate struct EventSpec {
      let seq: Int
      let round: Int
      let phaseType: String
      let payload: CodePhaseEventPayload
    }

    /// Word Wolf transcript (round 1). `clue` is seeded for fidelity even
    /// though it has no dedicated renderer.
    fileprivate static func makeWordWolfFixture(base: Date) throws -> FixtureBundle {
      let turns = try [
        TurnSpec(
          seq: 0, round: 1, phaseType: "speak_each", agent: "レン",
          fields: [
            "statement":
              "皆さんが質感、季節、そして味について触れているのを聞いて、私はその対象が持つ全体の形について語りたいと思います。",
            "clue": "柑橘類特有の皮の香りの強さ"
          ]),
        TurnSpec(
          seq: 1, round: 1, phaseType: "vote", agent: "サクラ",
          fields: [
            "vote": "レン",
            "reason":
              "他の参加者は食感、味、季節といった具体的な感覚について語っているのに対し、レンさんは対象の全体の形について言及しており、特徴がズレています。"
          ]),
        TurnSpec(
          seq: 2, round: 1, phaseType: "vote", agent: "ユウキ",
          fields: [
            "vote": "レン",
            "reason":
              "他の参加者は食感、季節、味といった感覚的な特徴に言及しているのに対し、レンは対象の全体の形について語りたいと述べており、見た目の特徴に関する議論とのズレが見られます。"
          ])
      ].map { try makeTurn($0, base: base) }
      let events = try [
        EventSpec(
          seq: 3, round: 1, phaseType: "vote",
          payload: .voteResults(
            votes: [
              "アオイ": "ユウキ", "サクラ": "レン", "タクミ": "アオイ",
              "ユウキ": "レン", "レン": "ユウキ"
            ],
            tallies: ["アオイ": 1, "ユウキ": 2, "レン": 2])),
        EventSpec(
          seq: 4, round: 1, phaseType: "score_calc",
          payload: .summary(
            text:
              "🎯 ウルフ発見！ 最多得票の レン が少数派でした（{\"アオイ\": 1, \"ユウキ\": 2, \"レン\": 2}）。 多数派の勝利です。"))
      ].map { try makeCodeEvent($0, base: base) }
      return FixtureBundle(
        record: marketingRecord(
          base: base, scenarioName: "ワードウルフ", currentRound: 1, yamlResource: "word_wolf"),
        turns: turns, events: events)
    }

    /// Prisoner's Dilemma transcript (rounds 1–2). `declared_intent` on the
    /// round-1 statement is seeded for fidelity even without a renderer.
    fileprivate static func makePrisonersFixture(base: Date) throws -> FixtureBundle {
      let turns = try [
        TurnSpec(
          seq: 0, round: 1, phaseType: "speak_all", agent: "ハルカ",
          fields: [
            "statement": "皆さん、ここは一度、協力してみたいと思いませんか？",
            "declared_intent": "協力"
          ]),
        TurnSpec(
          seq: 1, round: 2, phaseType: "whisper", agent: "ハルカ",
          fields: [
            "statement":
              "ケンタさん、私はあなたとは協力して進みたいと思っています。最終ラウンドに向けて、今は表面上は協調するふりをして、あなたの動きを観察させてください。",
            "inner_thought":
              "彼の勢いを利用して、彼が油断した隙を突く準備をする必要がある。協力の雰囲気を作りつつも、最終的には自分の利益を最大化するつもりだ。",
            "whisper_to": "ケンタ"
          ])
      ].map { try makeTurn($0, base: base) }
      // FIRST LINE ONLY of the run's `[summary]` block — the doc's second line
      // (皮肉な着地 …) is human editorial annotation, not model output, so
      // seeding it would be fabrication.
      let events = try [
        EventSpec(
          seq: 2, round: 2, phaseType: "score_calc",
          payload: .summary(
            text:
              "ラウンド2結果: {\"アキラ\": 9, \"ケンタ\": 16, \"ハルカ\": 3, \"ミサキ\": 6, \"リュウジ\": 20}"))
      ].map { try makeCodeEvent($0, base: base) }
      return FixtureBundle(
        record: marketingRecord(
          base: base, scenarioName: "囚人のジレンマ", currentRound: 2, yamlResource: "prisoners_dilemma"),
        turns: turns, events: events)
    }

    fileprivate static func marketingRecord(
      base: Date, scenarioName: String, currentRound: Int, yamlResource: String
    ) -> SimulationRecord {
      SimulationRecord(
        id: simulationId,
        // Orphan run (nil FK): the marketing scenarios aren't seeded, so read
        // paths fall back to the snapshots below rather than a live scenario.
        scenarioId: nil,
        status: SimulationStatus.completed.rawValue,
        currentRound: currentRound,
        currentPhaseIndex: 0,
        stateJSON: "{}",
        configJSON: nil,
        createdAt: base,
        updatedAt: base,
        modelIdentifier: "gemma-4-e2b-q4-k-m",
        llmBackend: "llamacpp",
        // Best-effort — avatar color is cosmetic and row names come from
        // `turn.agentName`, so a missing preset degrades gracefully to nil.
        scenarioYamlSnapshot: loadPresetYAML(yamlResource),
        scenarioNameSnapshot: scenarioName)
    }

    /// Loads a bundled preset YAML by base filename, or `nil` if unavailable
    /// (persona / avatar resolution then degrades gracefully — see caller).
    fileprivate static func loadPresetYAML(_ name: String) -> String? {
      guard let url = Bundle.main.url(forResource: name, withExtension: "yaml") else {
        return nil
      }
      return try? String(contentsOf: url, encoding: .utf8)
    }

    fileprivate static func makeTurn(_ spec: TurnSpec, base: Date) throws -> TurnRecord {
      TurnRecord(
        id: "\(simulationId)_t\(spec.seq)",
        simulationId: simulationId,
        roundNumber: spec.round,
        phaseType: spec.phaseType,
        agentName: spec.agent,
        // `rawOutput` mirrors the raw fields; `parsedOutputJSON` uses
        // TurnOutput's `{"fields":{…}}` shape the display layer decodes.
        // Encoding (not hand-written JSON) escapes Japanese / quotes correctly.
        rawOutput: try jsonString(spec.fields),
        parsedOutputJSON: try jsonString(TurnOutput(fields: spec.fields)),
        sequenceNumber: spec.seq,
        createdAt: base.addingTimeInterval(TimeInterval(spec.seq)))
    }

    fileprivate static func makeCodeEvent(_ spec: EventSpec, base: Date) throws
      -> CodePhaseEventRecord {
      CodePhaseEventRecord(
        id: "\(simulationId)_c\(spec.seq)",
        simulationId: simulationId,
        roundNumber: spec.round,
        phaseType: spec.phaseType,
        sequenceNumber: spec.seq,
        // Encoded via CodePhaseEventPayload so the wire shape round-trips
        // through `ResultDetailTimelineBuilder`'s `JSONDecoder().decode(…)`.
        payloadJSON: try jsonString(spec.payload),
        createdAt: base.addingTimeInterval(TimeInterval(spec.seq)))
    }

    /// Encodes `value` to a JSON string. Bytes come straight from `JSONEncoder`
    /// so they are always valid UTF-8; the `?? "{}"` fallback is unreachable and
    /// present only because SwiftLint's `optional_data_string_conversion` bans
    /// the non-failable `String(decoding:as:)` form.
    fileprivate static func jsonString(_ value: some Encodable) throws -> String {
      let data = try JSONEncoder().encode(value)
      return String(bytes: data, encoding: .utf8) ?? "{}"
    }
  }

#endif

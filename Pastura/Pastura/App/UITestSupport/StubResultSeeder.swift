#if DEBUG

  import Foundation

  /// UI-test-only seeding for the Past Results screens.
  ///
  /// Inserts one **completed** simulation against
  /// ``StubScenarioSeeder/homeSeedScenarioId`` plus two rounds of
  /// `speak_all` turns, so `ResultsView` shows a tappable group and
  /// `ResultDetailView` renders a representative timeline. Activated by
  /// the `--ui-test-seed-results` launch argument (used by
  /// `ScreenshotTourTests`); plain `--ui-test` runs stay unseeded so
  /// navigation tests keep exercising the empty state.
  ///
  /// `#if DEBUG`-gated like the sibling stubs so Release-iphoneos binaries
  /// carry no UI-test plumbing (ADR-005 §8.5 dev-only exclusion — same
  /// convention as `AppDependencies.uiTestEditorSeedYAML`).
  nonisolated public enum StubResultSeeder {
    /// Simulation id for the seeded run. Stable so UI tests can target
    /// `results.row.ui_test_result_seed` by identifier.
    public static let simulationId = "ui_test_result_seed"

    /// One fixture utterance for the seeded timeline (struct rather than a
    /// labeled tuple — SwiftLint `large_tuple` caps tuples at 2 members).
    private struct SeedStatement {
      let round: Int
      let agent: String
      let text: String
    }

    /// Inserts the completed simulation and its turns.
    ///
    /// Idempotent per repository upsert semantics. Called from
    /// `setupUITestState()` after ``StubScenarioSeeder/seed(into:)`` —
    /// the simulation references that seed scenario, whose personas
    /// (Alice / Bob) the turn `agentName`s match so avatar ordering
    /// resolves position-based.
    public static func seed(
      simulationRepository: any SimulationRepository,
      turnRepository: any TurnRepository
    ) async throws {
      let base = Date()
      let record = SimulationRecord(
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

      let turns = makeTurns(base: base)

      try await offMain {
        try simulationRepository.save(record)
        try turnRepository.saveBatch(turns)
      }
    }

    /// Builds the fixture timeline: 2 rounds x 2 agents. Statements are
    /// display-only copy — long enough that chat bubbles wrap and the
    /// timeline's spacing / round-separator rhythm is reviewable in
    /// screenshots.
    private static func makeTurns(base: Date) -> [TurnRecord] {
      let statements: [SeedStatement] = [
        SeedStatement(
          round: 1, agent: "Alice",
          text: "Hello! I think we should start by sharing what each of us observed this morning."
        ),
        SeedStatement(
          round: 1, agent: "Bob",
          text:
            "Agreed. The pasture by the north fence looked unusually quiet, which worries me a little."
        ),
        SeedStatement(
          round: 2, agent: "Alice",
          text:
            "Building on that — if the north side stays quiet tomorrow, I suggest we move the flock east."
        ),
        SeedStatement(
          round: 2, agent: "Bob",
          text: "That sounds reasonable. Let's agree on the east plan and check again at sunrise."
        )
      ]
      return statements.enumerated().map { index, entry in
        TurnRecord(
          id: "\(simulationId)_t\(index)",
          simulationId: simulationId,
          roundNumber: entry.round,
          phaseType: "speak_all",
          agentName: entry.agent,
          rawOutput: #"{"statement": "\#(entry.text)"}"#,
          // TurnOutput's Codable shape nests under "fields" — a top-level
          // {"statement": ...} fails decode and renders an empty bubble.
          parsedOutputJSON: #"{"fields":{"statement":"\#(entry.text)"}}"#,
          sequenceNumber: index,
          createdAt: base.addingTimeInterval(TimeInterval(index))
        )
      }
    }
  }

#endif

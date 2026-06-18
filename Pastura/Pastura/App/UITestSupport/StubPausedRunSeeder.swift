#if DEBUG

  import Foundation

  /// UI-test-only seeding for the Home "resume" card (ADR-016 P2 / P3).
  ///
  /// Inserts one **paused** `SimulationRecord` against
  /// ``StubScenarioSeeder/richWordWolfScenarioId`` so `HomeView`'s resume card
  /// renders with a non-nil progress line. Activated by the
  /// `--ui-test-seed-paused` launch argument (used by `ScreenshotTourTests`'s
  /// `09-home-resume` capture); plain `--ui-test` runs stay without a paused
  /// run so the card stays hidden (d3-without).
  ///
  /// **Dependency:** the referenced scenario must be present, so callers pair
  /// this with ``StubScenarioSeeder/seedRichHome(into:)`` — the resume card's
  /// metadata (sheep · rounds · description) is read from that scenario's
  /// parsed row metadata. `PasturaApp.setupUITestState` enforces the pairing.
  ///
  /// `#if DEBUG`-gated like the sibling stubs so Release-iphoneos binaries
  /// carry no UI-test plumbing (ADR-005 §8.5 dev-only exclusion).
  nonisolated public enum StubPausedRunSeeder {
    /// Simulation id for the seeded paused run. Stable so UI tests can target
    /// it by identifier if ever needed.
    public static let simulationId = "ui_test_paused_seed"

    /// Round the paused run is interrupted on. Kept `< richWordWolfRounds` so
    /// `HomeScenarioRowFormat.pausedProgressLabel` renders "1 / 5" rather than
    /// hiding (the visual detail `09-home-resume` verifies).
    public static let currentRound = 1

    /// Inserts the paused simulation record.
    ///
    /// Idempotent per repository upsert semantics — safe to re-run after an
    /// in-test app relaunch. A debug-build assertion keeps `currentRound` below
    /// the referenced scenario's round count so a future edit can't silently
    /// hide the progress line (also test-covered in `StubPausedRunSeederTests`).
    public static func seed(simulationRepository: any SimulationRepository) async throws {
      assert(
        currentRound < StubScenarioSeeder.richWordWolfRounds,
        "Paused currentRound must stay below the scenario's rounds for a visible progress line.")
      let now = Date()
      let record = SimulationRecord(
        id: simulationId,
        scenarioId: StubScenarioSeeder.richWordWolfScenarioId,
        status: SimulationStatus.paused.rawValue,
        currentRound: currentRound,
        currentPhaseIndex: 0,
        stateJSON: "{}",
        configJSON: nil,
        createdAt: now,
        updatedAt: now,
        modelIdentifier: "gemma-4-e2b-q4-k-m",
        llmBackend: "llamacpp",
        // Fallback name if the scenario were ever orphaned; the live name from
        // the seeded scenario normally wins in makePausedSummary.
        scenarioNameSnapshot: StubScenarioSeeder.richWordWolfScenarioName
      )
      try await offMain {
        try simulationRepository.save(record)
      }
    }
  }

#endif

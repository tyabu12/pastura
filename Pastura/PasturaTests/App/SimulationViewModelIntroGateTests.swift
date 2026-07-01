import Testing

@testable import Pastura

/// Deterministic coverage for the opening-card intro gate (#853) — the
/// `beginIntro` / `introRevealDidComplete` / `awaitIntroReveal` handshake that
/// makes `run()` wait for the premise reveal before the conversation starts.
///
/// The continuation plumbing is MainActor-serialized (the VM is `@MainActor`),
/// so these tests exercise the pure state machine without any engine / model:
/// the latch semantics (a completion that fires *before* the await still
/// releases it — the common fast-reveal / slow-load case), the unarmed no-op,
/// and idempotent completion. The visual reveal timing itself stays device-QA
/// (ADR-009 rule 4).
@Suite(.serialized, .timeLimit(.minutes(1)))
@MainActor
struct SimulationViewModelIntroGateTests {
  private func makeSUT() throws -> SimulationViewModel {
    let db = try DatabaseManager.inMemory()
    return SimulationViewModel(
      simulationRepository: GRDBSimulationRepository(dbWriter: db.dbWriter),
      turnRepository: GRDBTurnRepository(dbWriter: db.dbWriter)
    )
  }

  @Test func notPlayingIntroBeforeArming() throws {
    let sut = try makeSUT()
    #expect(sut.isPlayingIntro == false)
  }

  @Test func beginIntroMarksPlayingIntro() throws {
    let sut = try makeSUT()
    sut.beginIntro(revealBackstop: 60)
    #expect(sut.isPlayingIntro == true)
  }

  @Test func completeClearsPlayingIntro() throws {
    let sut = try makeSUT()
    sut.beginIntro(revealBackstop: 60)
    sut.introRevealDidComplete()
    #expect(sut.isPlayingIntro == false)
  }

  /// Double completion must be a safe no-op (the stored-then-nilled continuation
  /// guarantees no `CheckedContinuation` double-resume trap).
  @Test func completeIsIdempotent() throws {
    let sut = try makeSUT()
    sut.beginIntro(revealBackstop: 60)
    sut.introRevealDidComplete()
    sut.introRevealDidComplete()
    #expect(sut.isPlayingIntro == false)
  }

  /// Unarmed gate returns immediately — a run with no opening card never waits.
  /// (A hang would trip the suite's 1-minute timeout.)
  @Test func awaitReturnsImmediatelyWhenUnarmed() async throws {
    let sut = try makeSUT()
    await sut.awaitIntroReveal()
    #expect(sut.isPlayingIntro == false)
  }

  /// The load-bearing latch (critic Axis 7): a completion that fires BEFORE the
  /// gate is awaited (fast reveal finishes during the slow model load) still
  /// releases the await — it does not suspend forever waiting for a signal that
  /// already passed.
  @Test func awaitReturnsImmediatelyWhenCompletedBeforeAwait() async throws {
    let sut = try makeSUT()
    sut.beginIntro(revealBackstop: 60)
    sut.introRevealDidComplete()
    await sut.awaitIntroReveal()  // must not hang
    #expect(sut.isPlayingIntro == false)
  }

  /// The suspend→resume path: the gate blocks until completion fires, then
  /// resumes. Single-threaded MainActor makes the ordering deterministic — the
  /// spawned waiter reaches its continuation suspension on the first yield.
  @Test func awaitSuspendsUntilCompletion() async throws {
    let sut = try makeSUT()
    sut.beginIntro(revealBackstop: 60)

    var resumed = false
    let waiter = Task { @MainActor in
      await sut.awaitIntroReveal()
      resumed = true
    }
    // Let the waiter run up to its continuation suspension.
    await Task.yield()
    #expect(resumed == false)
    #expect(sut.isPlayingIntro == true)

    sut.introRevealDidComplete()
    await waiter.value
    #expect(resumed == true)
    #expect(sut.isPlayingIntro == false)
  }
}

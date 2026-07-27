import Foundation
import Testing

@testable import Pastura

/// Behaviour tests for the review-prompt coordinator (#1279).
///
/// The pure threshold arithmetic is covered by `ReviewRequestPolicyTests`; what
/// lives *only* here is the risky part — the UI-test suppression gate, the
/// fail-closed unreadable-version guard, the swallow-on-DB-failure path, and
/// the stamp-before-fire ordering.
///
/// Every test drives an isolated `UserDefaults(suiteName:)` store rather than
/// `.standard`, so the version stamp never leaks across tests or into the
/// simulator's app defaults.
@Suite(.timeLimit(.minutes(1)))
@MainActor
struct ReviewRequestCoordinatorTests {

  // MARK: - Suppression gates

  @Test func doesNotFireOrEvenReadTheDatabaseUnderUITestMode() async throws {
    let env = try makeEnv(priorCompletedRuns: 10)

    let fired = await runCoordinator(env, isUITestMode: true)

    #expect(fired == false)
    // The gate is meant to short-circuit before any work, not merely to
    // suppress the dialog.
    #expect(env.repository.completedRunCountCallCount == 0)
    #expect(env.stampedVersion == nil)
  }

  @Test func doesNotFireWhenTheAppVersionIsUnreadable() async throws {
    for unreadable in [nil, ""] {
      let env = try makeEnv(priorCompletedRuns: 10)

      let fired = await runCoordinator(env, currentVersion: unreadable)

      #expect(fired == false)
      #expect(env.repository.completedRunCountCallCount == 0)
      #expect(env.stampedVersion == nil)
    }
  }

  // MARK: - Database failure is swallowed, and must not stamp

  @Test func databaseFailureNeitherFiresNorStamps() async throws {
    let env = try makeEnv(priorCompletedRuns: 10)
    env.repository.shouldThrow = true

    let fired = await runCoordinator(env)

    #expect(fired == false)
    // Pins that the outcome came from the FAILURE path, not from an earlier
    // bail-out that never reached the repository at all.
    #expect(env.repository.completedRunCountCallCount == 1)
    // Stamping on a failed read would silently burn the version's one chance
    // without ever having shown anything.
    #expect(env.stampedVersion == nil)
  }

  // MARK: - The happy path, and its ordering

  @Test func firesAndStampsWhenEligible() async throws {
    let env = try makeEnv(priorCompletedRuns: 2)

    let fired = await runCoordinator(env, currentVersion: "1.1")

    #expect(fired)
    #expect(env.stampedVersion == "1.1")
    #expect(env.repository.completedRunCountCallCount == 1)
  }

  /// The stamp must be observable *before* `requestReview()` runs — the
  /// coordinator's stated invariant, so a crash between the two re-arms
  /// nothing. Probed from inside the request closure rather than after the
  /// call, which would pass either way.
  @Test func stampLandsBeforeTheRequestFires() async throws {
    let env = try makeEnv(priorCompletedRuns: 2)
    var stampVisibleFromInsideRequest: String?

    await ReviewRequestCoordinator.requestIfEligible(
      repository: env.repository,
      currentRunId: "current",
      degradedTurnCount: 0,
      isUITestMode: false,
      currentVersion: "1.1",
      defaults: env.defaults,
      requestReview: {
        stampVisibleFromInsideRequest =
          ReviewRequestPolicy.lastRequestedVersion(defaults: env.defaults)
      })

    #expect(stampVisibleFromInsideRequest == "1.1")
  }

  @Test func doesNotFireASecondTimeForTheSameVersion() async throws {
    let env = try makeEnv(priorCompletedRuns: 10)

    let first = await runCoordinator(env, currentVersion: "1.1")
    let second = await runCoordinator(env, currentVersion: "1.1")

    #expect(first)
    #expect(second == false)
  }

  @Test func firesAgainAfterAVersionBump() async throws {
    let env = try makeEnv(priorCompletedRuns: 10)

    _ = await runCoordinator(env, currentVersion: "1.1")
    let afterBump = await runCoordinator(env, currentVersion: "1.2")

    #expect(afterBump)
    #expect(env.stampedVersion == "1.2")
  }

  // MARK: - Threshold + degradation reach the policy

  @Test func doesNotFireBelowTheRunThreshold() async throws {
    let env = try makeEnv(priorCompletedRuns: 1)

    #expect(await runCoordinator(env) == false)
    #expect(env.stampedVersion == nil)
  }

  @Test func doesNotFireAfterADegradedRun() async throws {
    let env = try makeEnv(priorCompletedRuns: 10)

    #expect(await runCoordinator(env, degradedTurnCount: 1) == false)
    #expect(env.stampedVersion == nil)
  }

  /// The run that just finished must not count toward its own threshold — the
  /// whole reason `excludingRunId:` exists. Asserted as a pass-through so a
  /// future refactor cannot quietly start counting it.
  @Test func excludesTheCurrentRunFromTheCount() async throws {
    let env = try makeEnv(priorCompletedRuns: 2)

    _ = await runCoordinator(env, currentRunId: "the-run-that-just-ended")

    #expect(env.repository.lastExcludedRunId == "the-run-that-just-ended")
  }
}

// MARK: - Harness

/// A class, not a struct, so `deinit` removes the persisted preference domain.
/// `UserDefaults(suiteName:)` is disk-backed like any other domain, so without
/// teardown every full test run would leave one leaked domain per test in the
/// host container.
private final class CoordinatorEnv {
  let repository: CountingSimulationRepository
  let defaults: UserDefaults
  private let suiteName: String

  init(repository: CountingSimulationRepository, defaults: UserDefaults, suiteName: String) {
    self.repository = repository
    self.defaults = defaults
    self.suiteName = suiteName
  }

  deinit {
    defaults.removePersistentDomain(forName: suiteName)
  }

  var stampedVersion: String? {
    ReviewRequestPolicy.lastRequestedVersion(defaults: defaults)
  }
}

/// Fresh isolated defaults per call, so no test observes another's stamp. The
/// name embeds a UUID, so the domain starts empty by construction — there is
/// nothing to clear on the way in, only on the way out (see `deinit`).
private func makeEnv(priorCompletedRuns: Int) throws -> CoordinatorEnv {
  let suiteName = "app.pastura.tests.review.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  return CoordinatorEnv(
    repository: CountingSimulationRepository(completedCount: priorCompletedRuns),
    defaults: defaults,
    suiteName: suiteName)
}

/// Returns whether the review request fired.
@MainActor
private func runCoordinator(
  _ env: CoordinatorEnv,
  currentRunId: String? = "current",
  degradedTurnCount: Int = 0,
  isUITestMode: Bool = false,
  currentVersion: String? = "1.1"
) async -> Bool {
  var fired = false
  await ReviewRequestCoordinator.requestIfEligible(
    repository: env.repository,
    currentRunId: currentRunId,
    degradedTurnCount: degradedTurnCount,
    isUITestMode: isUITestMode,
    currentVersion: currentVersion,
    defaults: env.defaults,
    requestReview: { fired = true })
  return fired
}

/// Records how the coordinator queried the count, and can fail on demand.
///
/// Only `completedRunCount(excludingRunId:)` is expected to be reached. Every
/// other requirement records an `Issue` and returns something benign rather
/// than trapping: `fatalError` in a test fake aborts the whole test *process*,
/// killing unrelated suites and truncating the `.xcresult`. `Issue.record`
/// fails the offending test, names the method, and lets the run finish.
private final class CountingSimulationRepository: SimulationRepository, @unchecked Sendable {
  private let completedCount: Int
  // Every mutable field sits behind this lock: `completedRunCount` runs
  // off-main (`offMain` is `Task.detached`) while the test drives the fake from
  // the MainActor, and `@unchecked Sendable` suppresses the diagnostic that
  // would otherwise catch an unguarded one.
  private let lock = NSLock()
  private var _callCount = 0
  // Plain optional, not `String??` — "never called" is already distinguishable
  // via `completedRunCountCallCount`.
  private var _lastExcludedRunId: String?
  private var _shouldThrow = false

  init(completedCount: Int) {
    self.completedCount = completedCount
  }

  var completedRunCountCallCount: Int {
    lock.withLock { _callCount }
  }

  var lastExcludedRunId: String? {
    lock.withLock { _lastExcludedRunId }
  }

  var shouldThrow: Bool {
    get { lock.withLock { _shouldThrow } }
    set { lock.withLock { _shouldThrow = newValue } }
  }

  func completedRunCount(excludingRunId: String?) throws -> Int {
    let mustThrow = lock.withLock {
      _callCount += 1
      _lastExcludedRunId = excludingRunId
      return _shouldThrow
    }
    if mustThrow { throw DataError.recordNotFound(type: "SimulationRecord", id: "boom") }
    return completedCount
  }

  func save(_ record: SimulationRecord) throws { unexpected() }
  func fetchById(_ id: String) throws -> SimulationRecord? { unexpected(); return nil }
  func fetchByScenarioId(_ scenarioId: String) throws -> [SimulationRecord] {
    unexpected()
    return []
  }
  func fetchRecentRunPage(
    nameQuery: String?, before: SimulationPageCursor?, limit: Int
  ) throws -> [PastRunListItem] {
    unexpected()
    return []
  }
  func fetchRunList(scenarioId: String) throws -> [PastRunListItem] {
    unexpected()
    return []
  }
  func fetchOrphaned() throws -> [SimulationRecord] {
    unexpected()
    return []
  }
  func fetchByStatus(_ status: SimulationStatus) throws -> [SimulationRecord] {
    unexpected()
    return []
  }
  func completedRunCountsByScenarioId() throws -> [String: Int] {
    unexpected()
    return [:]
  }
  func updateState(
    _ id: String, stateJSON: String, currentRound: Int, currentPhaseIndex: Int
  ) throws { unexpected() }
  func updateStatus(_ id: String, status: SimulationStatus) throws { unexpected() }
  func updateDegradedTurnCount(_ id: String, count: Int) throws { unexpected() }
  func totalRunCount(nameQuery: String?) throws -> Int {
    unexpected()
    return 0
  }
  func delete(_ id: String) throws { unexpected() }
  func deleteAll() throws { unexpected() }
  func pastResultsByteCount() throws -> Int64 {
    unexpected()
    return 0
  }

  private func unexpected(_ method: String = #function) {
    Issue.record("ReviewRequestCoordinator must not reach \(method)")
  }
}

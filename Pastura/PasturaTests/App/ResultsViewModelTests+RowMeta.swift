import Foundation
import Testing

@testable import Pastura

/// Row-meta resolution tests for ``ResultsViewModel`` (Home redesign P5 PR2):
/// each row carries the run's `agentCount` / total-rounds `N`, resolved from
/// the scenario YAML **snapshot-first** (run-time-faithful), falling back to the
/// live scenario YAML for pre-v7 runs and degrading to `nil` on a parse failure.
/// Sibling extension on the same suite — see `testing.md` § "Splitting a Suite
/// Across Files"; reuses the suite's internal `makeResultsSUT` helper.
extension ResultsViewModelTests {

  // MARK: - Snapshot-first agentCount / total-rounds resolution

  @Test func aggregateRowCarriesMetaFromSnapshot() async throws {
    let env = try makeResultsSUT()
    // Live scenario YAML is a stub that won't parse; the run's snapshot is the
    // real source, so meta must still resolve.
    try env.scenarioRepo.save(stubScenario(id: "s1", name: "Word Wolf"))
    try env.simRepo.save(
      runWithSnapshot(
        id: "sim1", scenarioId: "s1", snapshot: metaYAML(agents: 4, rounds: 5)))

    await env.sut.load(scope: .aggregate)

    let row = try #require(env.sut.sections.flatMap { $0.rows }.first)
    #expect(row.agentCount == 4)
    #expect(row.totalRounds == 5)
  }

  @Test func orphanRunResolvesMetaFromSnapshotOnly() async throws {
    let env = try makeResultsSUT()
    // No live scenario at all (scenarioId nil) — the snapshot is the only
    // source. P5 keeps such orphaned runs in the list, fully rendered.
    try env.simRepo.save(
      runWithSnapshot(
        id: "orphan", scenarioId: nil, snapshot: metaYAML(agents: 3, rounds: 7)))

    await env.sut.load(scope: .aggregate)

    let row = try #require(env.sut.sections.flatMap { $0.rows }.first)
    #expect(row.agentCount == 3)
    #expect(row.totalRounds == 7)
  }

  @Test func editedLiveScenarioStillReportsSnapshotTotal() async throws {
    let env = try makeResultsSUT()
    // Live scenario says 10 rounds (a later edit); the run actually ran 5.
    // Snapshot-first keeps the row faithful to what ran.
    try env.scenarioRepo.save(
      ScenarioRecord(
        id: "s1", name: "Edited", yamlDefinition: metaYAML(agents: 4, rounds: 10),
        isPreset: false, createdAt: Date(), updatedAt: Date()))
    try env.simRepo.save(
      runWithSnapshot(
        id: "sim1", scenarioId: "s1", snapshot: metaYAML(agents: 4, rounds: 5)))

    await env.sut.load(scope: .aggregate)

    let row = try #require(env.sut.sections.flatMap { $0.rows }.first)
    #expect(row.totalRounds == 5)  // snapshot wins over the edited live N
  }

  @Test func aggregatePreV7RunWithoutSnapshotDegradesToNilMeta() async throws {
    let env = try makeResultsSUT()
    // The aggregate index is the yamlDefinition-excluding ScenarioSummary
    // projection (#700: no bulk YAML in the list's memory), so a pre-v7 run with
    // no snapshot has no YAML source in the aggregate path → name-only meta.
    try env.scenarioRepo.save(
      ScenarioRecord(
        id: "s1", name: "Live", yamlDefinition: metaYAML(agents: 3, rounds: 7),
        isPreset: false, createdAt: Date(), updatedAt: Date()))
    try env.simRepo.save(runWithSnapshot(id: "sim1", scenarioId: "s1", snapshot: nil))

    await env.sut.load(scope: .aggregate)

    let row = try #require(env.sut.sections.flatMap { $0.rows }.first)
    #expect(row.agentCount == nil)
    #expect(row.totalRounds == nil)
  }

  @Test func detailPreV7RunFallsBackToLiveScenarioYAML() async throws {
    let env = try makeResultsSUT()
    // The detail path fetches the one scenario's full record, so its live YAML
    // is already in hand — a pre-v7 run (no snapshot) still resolves meta there.
    try env.scenarioRepo.save(
      ScenarioRecord(
        id: "s1", name: "Live", yamlDefinition: metaYAML(agents: 3, rounds: 7),
        isPreset: false, createdAt: Date(), updatedAt: Date()))
    try env.simRepo.save(runWithSnapshot(id: "sim1", scenarioId: "s1", snapshot: nil))

    await env.sut.load(scope: .scenario("s1"))

    let row = try #require(env.sut.sections.flatMap { $0.rows }.first)
    #expect(row.agentCount == 3)
    #expect(row.totalRounds == 7)
  }

  @Test func parseFailureDegradesToNilMeta() async throws {
    let env = try makeResultsSUT()
    // Unparseable snapshot + no live scenario → meta is nil (row draws no sheep,
    // summary falls back to its bare form) rather than crashing or blanking.
    try env.simRepo.save(
      runWithSnapshot(id: "orphan", scenarioId: nil, snapshot: "id: broken\n"))

    await env.sut.load(scope: .aggregate)

    let row = try #require(env.sut.sections.flatMap { $0.rows }.first)
    #expect(row.agentCount == nil)
    #expect(row.totalRounds == nil)
  }

  // MARK: - Snapshot-first description resolution (#747)

  @Test func aggregateRowCarriesDescriptionFromSnapshot() async throws {
    let env = try makeResultsSUT()
    try env.simRepo.save(
      runWithSnapshot(
        id: "sim1", scenarioId: nil,
        snapshot: metaYAML(agents: 3, rounds: 2, description: "A tense standoff")))

    await env.sut.load(scope: .aggregate)

    let row = try #require(env.sut.sections.flatMap { $0.rows }.first)
    #expect(row.description == "A tense standoff")
  }

  @Test func emptyDescriptionNormalizesToNil() async throws {
    let env = try makeResultsSUT()
    try env.simRepo.save(
      runWithSnapshot(
        id: "sim1", scenarioId: nil,
        snapshot: metaYAML(agents: 3, rounds: 2, description: "")))

    await env.sut.load(scope: .aggregate)

    let row = try #require(env.sut.sections.flatMap { $0.rows }.first)
    // Empty description → no description line (graceful degrade), but the row
    // still resolves the rest of its meta normally.
    #expect(row.description == nil)
    #expect(row.agentCount == 3)
  }

  @Test func whitespaceOnlyDescriptionNormalizesToNil() async throws {
    let env = try makeResultsSUT()
    try env.simRepo.save(
      runWithSnapshot(
        id: "sim1", scenarioId: nil,
        snapshot: metaYAML(agents: 3, rounds: 2, description: "   ")))

    await env.sut.load(scope: .aggregate)

    let row = try #require(env.sut.sections.flatMap { $0.rows }.first)
    #expect(row.description == nil)
  }

  @Test func missingSnapshotDegradesToNilDescription() async throws {
    let env = try makeResultsSUT()
    // Pre-v7 run with no snapshot in the aggregate path → no YAML source, so
    // description (like agentCount / rounds) degrades to nil.
    try env.scenarioRepo.save(
      ScenarioRecord(
        id: "s1", name: "Live", yamlDefinition: metaYAML(agents: 3, rounds: 7),
        isPreset: false, createdAt: Date(), updatedAt: Date()))
    try env.simRepo.save(runWithSnapshot(id: "sim1", scenarioId: "s1", snapshot: nil))

    await env.sut.load(scope: .aggregate)

    let row = try #require(env.sut.sections.flatMap { $0.rows }.first)
    #expect(row.description == nil)
  }

  // MARK: - currentRound (K) cross-surface consistency

  /// The paused "Round K で中断" summary reads `K` from the same
  /// `simulations.currentRound` column the Home paused-resume card uses, so the
  /// two surfaces report the same round for one run (critic Warning, Axis 5).
  @Test func pausedRowCarriesCurrentRoundFromColumn() async throws {
    let env = try makeResultsSUT()
    try env.scenarioRepo.save(stubScenario(id: "s1", name: "Paused One"))
    try env.simRepo.save(
      SimulationRecord(
        id: "paused", scenarioId: "s1",
        status: SimulationStatus.paused.rawValue,
        currentRound: 3, currentPhaseIndex: 0,
        stateJSON: "{}", configJSON: nil,
        createdAt: resultsTestToday, updatedAt: resultsTestToday,
        scenarioYamlSnapshot: metaYAML(agents: 4, rounds: 5)))

    await env.sut.load(scope: .aggregate)

    let row = try #require(env.sut.sections.flatMap { $0.rows }.first)
    #expect(row.item.currentRound == 3)  // the K the Home paused card also shows
    #expect(row.totalRounds == 5)  // N for "Round 3 / 5"
  }
}

// MARK: - File-scope helpers

/// A live `ScenarioRecord` whose YAML is a stub that will NOT parse to a
/// `Scenario` — used where the row's meta must come from the run snapshot, not
/// the live scenario.
private func stubScenario(id: String, name: String) -> ScenarioRecord {
  ScenarioRecord(
    id: id, name: name, yamlDefinition: "id: \(id)\nname: \(name)\n",
    isPreset: false, createdAt: Date(), updatedAt: Date())
}

/// A completed run carrying an optional captured YAML snapshot, landing in the
/// "today" bucket relative to `resultsTestNow`.
private func runWithSnapshot(
  id: String, scenarioId: String?, snapshot: String?
) -> SimulationRecord {
  SimulationRecord(
    id: id, scenarioId: scenarioId,
    status: SimulationStatus.completed.rawValue,
    currentRound: 1, currentPhaseIndex: 0,
    stateJSON: "{}", configJSON: nil,
    createdAt: resultsTestToday, updatedAt: resultsTestToday,
    scenarioYamlSnapshot: snapshot)
}

/// A structurally-valid scenario YAML (parseable by `ScenarioLoader.load`) with
/// the given agent / round counts — `agents` personas so the persona/agent-count
/// invariant holds. `description` is quoted so empty / whitespace-only values are
/// representable for the #747 normalization tests.
private func metaYAML(agents: Int, rounds: Int, description: String = "a fixture") -> String {
  let personas = (0..<agents)
    .map { "  - name: Agent\($0)\n    description: persona \($0)" }
    .joined(separator: "\n")
  return """
    id: meta
    name: Meta Scenario
    description: "\(description)"
    language: en
    agents: \(agents)
    rounds: \(rounds)
    context: ctx
    personas:
    \(personas)
    phases:
      - type: speak_all
        prompt: speak
        output: { statement: string }
    """
}

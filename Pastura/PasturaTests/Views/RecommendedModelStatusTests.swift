import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct RecommendedModelStatusTests {
  // Real registry ids — must match ModelRegistry catalog entries.
  let gemma = "gemma-4-e2b-q4-k-m"
  let qwen = "qwen-3-4b-q4-k-m"
  let unknown = "future-model-v9-q4-k-m"

  // MARK: - Rule 1: simulator suppresses all affordances

  @Test func rule1_simulatorAlwaysReturnsMatched() {
    // Even with a clearly-actionable state, isSimulator: true → .matched
    let status = RecommendedModelStatus.compute(
      recommendedID: gemma, activeID: qwen,
      state: [gemma: .ready(modelPath: "/tmp/g"), qwen: .ready(modelPath: "/tmp/q")],
      isSimulationActive: false, isSimulator: true)
    #expect(status == .matched)
  }

  // MARK: - Rule 2: unknown registry id

  @Test func rule2_unknownRegistryIDReturnsUnknownModel() {
    let status = RecommendedModelStatus.compute(
      recommendedID: unknown, activeID: gemma,
      state: [gemma: .ready(modelPath: "/tmp/g")],
      isSimulationActive: false, isSimulator: false)
    #expect(status == .unknownModel)
  }

  // MARK: - Rule 3: unsupported device

  @Test func rule3_unsupportedDeviceReturnsUnsupportedDevice() {
    let status = RecommendedModelStatus.compute(
      recommendedID: qwen, activeID: gemma,
      state: [qwen: .unsupportedDevice, gemma: .ready(modelPath: "/tmp/g")],
      isSimulationActive: false, isSimulator: false)
    #expect(status == .unsupportedDevice)
  }

  // MARK: - Rule 4: active matches recommended → matched regardless of state

  @Test func rule4_activeMatchesRecommendedReturnsMatched_evenWhileDownloading() {
    // recommendedID == activeID, but the state entry says .downloading —
    // Rule 4 fires before Rule 5, so we get .matched not .downloading.
    let status = RecommendedModelStatus.compute(
      recommendedID: gemma, activeID: gemma,
      state: [gemma: .downloading(progress: 0.5)],
      isSimulationActive: false, isSimulator: false)
    #expect(status == .matched)
  }

  @Test func rule4_activeMatchesRecommendedReturnsMatched_whenReady() {
    let status = RecommendedModelStatus.compute(
      recommendedID: gemma, activeID: gemma,
      state: [gemma: .ready(modelPath: "/tmp/g")],
      isSimulationActive: false, isSimulator: false)
    #expect(status == .matched)
  }

  // MARK: - Rule 5: recommended is downloading

  @Test func rule5_recommendedDownloadingReturnsDownloading() {
    let status = RecommendedModelStatus.compute(
      recommendedID: qwen, activeID: gemma,
      state: [qwen: .downloading(progress: 0.3), gemma: .ready(modelPath: "/tmp/g")],
      isSimulationActive: false, isSimulator: false)
    #expect(status == .downloading)
  }

  // MARK: - Rule 6: recommended needs download

  @Test func rule6_recommendedNotDownloadedReturnsDownloadAvailable_noOtherInFlight() {
    let status = RecommendedModelStatus.compute(
      recommendedID: qwen, activeID: gemma,
      state: [qwen: .notDownloaded, gemma: .ready(modelPath: "/tmp/g")],
      isSimulationActive: false, isSimulator: false)
    #expect(status == .downloadAvailable(otherDownloadInFlight: false))
  }

  @Test func rule6_recommendedNotDownloadedReturnsDownloadAvailable_otherInFlight() {
    // gemma is .downloading (another descriptor in flight) while qwen is .notDownloaded
    let status = RecommendedModelStatus.compute(
      recommendedID: qwen, activeID: gemma,
      state: [qwen: .notDownloaded, gemma: .downloading(progress: 0.7)],
      isSimulationActive: false, isSimulator: false)
    #expect(status == .downloadAvailable(otherDownloadInFlight: true))
  }

  @Test func rule6_recommendedErroredReturnsDownloadAvailable() {
    let status = RecommendedModelStatus.compute(
      recommendedID: qwen, activeID: gemma,
      state: [qwen: .error("checksum mismatch"), gemma: .ready(modelPath: "/tmp/g")],
      isSimulationActive: false, isSimulator: false)
    #expect(status == .downloadAvailable(otherDownloadInFlight: false))
  }

  // MARK: - Rule 7: recommended is ready and not active

  @Test func rule7_recommendedReadyReturnsSwitchAvailable_unlocked() {
    let status = RecommendedModelStatus.compute(
      recommendedID: qwen, activeID: gemma,
      state: [qwen: .ready(modelPath: "/tmp/q"), gemma: .ready(modelPath: "/tmp/g")],
      isSimulationActive: false, isSimulator: false)
    #expect(status == .switchAvailable(isLocked: false))
  }

  @Test func rule7_recommendedReadyReturnsSwitchAvailable_locked() {
    // Simulation is active → switch affordance is locked.
    let status = RecommendedModelStatus.compute(
      recommendedID: qwen, activeID: gemma,
      state: [qwen: .ready(modelPath: "/tmp/q"), gemma: .ready(modelPath: "/tmp/g")],
      isSimulationActive: true, isSimulator: false)
    #expect(status == .switchAvailable(isLocked: true))
  }

  // MARK: - Rule 8: transient .checking falls back to matched

  @Test func rule8_checkingFallsBackToMatched() {
    let status = RecommendedModelStatus.compute(
      recommendedID: qwen, activeID: gemma,
      state: [qwen: .checking, gemma: .ready(modelPath: "/tmp/g")],
      isSimulationActive: false, isSimulator: false)
    #expect(status == .matched)
  }

  // MARK: - Equatable payload axes

  @Test func equatable_switchAvailableLockBoolsAreDistinct() {
    #expect(
      RecommendedModelStatus.switchAvailable(isLocked: true)
        != .switchAvailable(isLocked: false))
  }

  @Test func equatable_downloadAvailableInFlightBoolsAreDistinct() {
    #expect(
      RecommendedModelStatus.downloadAvailable(otherDownloadInFlight: true)
        != .downloadAvailable(otherDownloadInFlight: false))
  }
}

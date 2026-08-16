import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct RecommendedModelStatusTests {
  // Real registry ids — must match ModelRegistry catalog entries.
  //
  // `gemma` is **replaced** by `qat` (`ModelRegistry` § "ADD-and-keep"), so a
  // recommendation naming it resolves forward before any rule below Rule 2 sees
  // it. Rule-order tests therefore use `qwen`, which replaces nothing and is
  // replaced by nothing — otherwise they would be pinning the resolution rather
  // than the ordering they are named for.
  let gemma = "gemma-4-e2b-q4-k-m"
  let qat = "gemma-4-e2b-qat-q4-k-xl"
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

  @Test func rule3_unsupportedDeviceWinsOverRule4_evenIfActiveMatchesRecommended() {
    // Pins Rule 3 (.unsupportedDevice) precedence over Rule 4 (active==recommended).
    // The two cases produce the same surface map today (no banner, no affordance)
    // but the distinction matters: a future copy revision for `.unsupportedDevice`
    // ("This device cannot run the recommended model") would silently revert
    // to `.matched` if the rule order ever flipped. This test guards that.
    let status = RecommendedModelStatus.compute(
      recommendedID: qwen, activeID: qwen,
      state: [qwen: .unsupportedDevice],
      isSimulationActive: false, isSimulator: false)
    #expect(status == .unsupportedDevice)
  }

  // MARK: - Rule 4: active matches recommended → matched regardless of state

  @Test func rule4_activeMatchesRecommendedReturnsMatched_evenWhileDownloading() {
    // recommendedID == activeID, but the state entry says .downloading —
    // Rule 4 fires before Rule 5, so we get .matched not .downloading.
    let status = RecommendedModelStatus.compute(
      recommendedID: qwen, activeID: qwen,
      state: [qwen: .downloading(progress: 0.5)],
      isSimulationActive: false, isSimulator: false)
    #expect(status == .matched)
  }

  @Test func rule4_activeMatchesRecommendedReturnsMatched_whenReady() {
    let status = RecommendedModelStatus.compute(
      recommendedID: qwen, activeID: qwen,
      state: [qwen: .ready(modelPath: "/tmp/q")],
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

  // MARK: - Recommendation resolution (ADD-and-keep, #1487)
  //
  // Every `docs/gallery/gallery.json` entry recommends `gemma`, which is now a
  // replaced build hidden from the picker / Settings / `ActiveModelChip` once it
  // is neither on the device nor the active model. These pin that a feed entry
  // naming it is classified as its successor, without nagging a user still
  // running the old one.

  /// Pins the `qat` literal above **and** the ADD-and-keep wiring it stands for.
  /// Without this, a drifted literal makes `state[qat]` miss, `compute` falls
  /// through to Rule 8, and both `.matched`-asserting arms below pass vacuously
  /// — `.matched` being the classifier's fall-through verdict means an
  /// input-shape mistake is indistinguishable from a correct result.
  @Test func resolution_pinsTheReplacementWiring() {
    #expect(ModelRegistry.replacement(for: gemma, in: ModelRegistry.catalog)?.id == qat)
  }

  @Test func resolution_activeIsTheReplacement_matches() {
    // The fresh-install path: QAT active, every gallery entry recommending the
    // replaced build. Must NOT offer to download the hidden 3.11 GB build.
    let status = RecommendedModelStatus.compute(
      recommendedID: gemma, activeID: qat,
      state: [qat: .ready(modelPath: "/tmp/qat"), gemma: .notDownloaded],
      isSimulationActive: false, isSimulator: false)
    #expect(status == .matched)
  }

  @Test func resolution_activeIsStillTheReplacedBuild_matches() {
    // The other side of Rule 4. Resolving alone would compare QAT against an
    // active `gemma` and offer a 2.62 GB download on all 45 gallery screens; the
    // declared-id arm is what keeps an existing user un-nagged.
    let status = RecommendedModelStatus.compute(
      recommendedID: gemma, activeID: gemma,
      state: [gemma: .ready(modelPath: "/tmp/g"), qat: .notDownloaded],
      isSimulationActive: false, isSimulator: false)
    #expect(status == .matched)
  }

  @Test func resolution_activeIsTheReplacementWithTheReplacedBuildAlsoOnDisk_matches() {
    // Why Rule 4 asks `replacement(for:)` and not the *target*. Here the target
    // is the replaced build (it is `.ready`), so a Rule 4 phrased against the
    // target would miss and fall through to Rule 7 — offering a QAT user a
    // *downgrade* switch to the build QAT replaced.
    let status = RecommendedModelStatus.compute(
      recommendedID: gemma, activeID: qat,
      state: [gemma: .ready(modelPath: "/tmp/g"), qat: .ready(modelPath: "/tmp/qat")],
      isSimulationActive: false, isSimulator: false)
    #expect(status == .matched)
  }

  @Test func resolution_prefersTheReplacedBuildWhenTheUserAlreadyHasIt() {
    // An existing user with the replaced build on disk and a *third* model
    // active is satisfied by a free switch. A flat forward-resolve would read
    // QAT `.notDownloaded` and return `.downloadAvailable` — a 2.62 GB transfer
    // to reach a model they already own a build of.
    let status = RecommendedModelStatus.compute(
      recommendedID: gemma, activeID: qwen,
      state: [
        gemma: .ready(modelPath: "/tmp/g"), qat: .notDownloaded,
        qwen: .ready(modelPath: "/tmp/q")
      ],
      isSimulationActive: false, isSimulator: false)
    #expect(status == .switchAvailable(isLocked: false))
  }

  @Test func resolution_offersTheReplacementWhenTheReplacedBuildIsAbsent() {
    // The other side of the target choice, and the discriminating shape for the
    // resolution itself: the two builds are in *different* states, so the
    // verdict names which one was classified. Target → QAT `.downloading` →
    // `.downloading`. Unresolved it would read `gemma` `.notDownloaded` and
    // return `.downloadAvailable`, i.e. offer the hidden build.
    let status = RecommendedModelStatus.compute(
      recommendedID: gemma, activeID: qwen,
      state: [
        gemma: .notDownloaded, qat: .downloading(progress: 0.3),
        qwen: .ready(modelPath: "/tmp/q")
      ],
      isSimulationActive: false, isSimulator: false)
    #expect(status == .downloading)
  }

  @Test func resolution_unsupportedDeviceOnTheReplacementStillWins() {
    // Rule 3 stays ahead of the two-sided Rule 4. `resolveInitialActiveID` picks
    // the default without consulting `state`, so "active satisfies the
    // recommendation" and "the recommended build cannot run here" are both true
    // on a 6 GB device — if the equivalence ran first, `.unsupportedDevice`
    // would be unreachable for every gemma-recommended gallery entry.
    // The replaced build is `.notDownloaded` rather than also
    // `.unsupportedDevice` so the target resolves forward to QAT: with both
    // unsupported the verdict is the same whether or not it resolved, and the
    // arm would pin the ordering while saying nothing about *which* build Rule 3
    // read. Measured — it passed against a build with resolution disabled until
    // the two states were split.
    let status = RecommendedModelStatus.compute(
      recommendedID: gemma, activeID: qat,
      state: [qat: .unsupportedDevice, gemma: .notDownloaded],
      isSimulationActive: false, isSimulator: false)
    #expect(status == .unsupportedDevice)
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

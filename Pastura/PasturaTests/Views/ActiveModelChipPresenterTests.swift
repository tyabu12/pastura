import Testing

@testable import Pastura

/// Pure-logic tests for `ActiveModelChipPresenter` (ADR-009 / view-testing:
/// assert computed display state, never rendered output). Uses real
/// `ModelRegistry` descriptors so `fileSize` / display names stay in lockstep
/// with the shipped catalog.
@Suite(.timeLimit(.minutes(1)))
struct ActiveModelChipPresenterTests {
  let gemmaID = "gemma-4-e2b-q4-k-m"
  let qwenID = "qwen-3-4b-q4-k-m"

  // Force-unwrap is test-exempt (Hard Rule 1); these are real catalog ids.
  var gemma: ModelDescriptor { ModelRegistry.lookup(id: gemmaID)! }
  var qwen: ModelDescriptor { ModelRegistry.lookup(id: qwenID)! }

  // MARK: - statusDot mapping

  @Test func statusDot_mapsEveryState() {
    #expect(ActiveModelChipPresenter.statusDot(for: .ready(modelPath: "/g")) == .ready)
    #expect(ActiveModelChipPresenter.statusDot(for: .downloading(progress: 0.4)) == .working)
    #expect(ActiveModelChipPresenter.statusDot(for: .checking) == .inactive)
    #expect(ActiveModelChipPresenter.statusDot(for: .notDownloaded) == .inactive)
    #expect(ActiveModelChipPresenter.statusDot(for: .error("boom")) == .problem)
    #expect(ActiveModelChipPresenter.statusDot(for: .unsupportedDevice) == .problem)
  }

  // MARK: - chipLabel

  @Test func chipLabel_prefersShortDisplayName() {
    let presenter = ActiveModelChipPresenter(
      activeDescriptor: gemma, activeState: .ready(modelPath: "/g"),
      catalog: [gemma], state: [gemmaID: .ready(modelPath: "/g")],
      activeModelID: gemmaID, isSimulationActive: false)
    #expect(presenter.chipLabel == (gemma.shortDisplayName ?? gemma.displayName))
  }

  @Test func chipLabel_nilWhenNoActiveDescriptor() {
    let presenter = ActiveModelChipPresenter(
      activeDescriptor: nil, activeState: .checking,
      catalog: [gemma], state: [:], activeModelID: gemmaID, isSimulationActive: false)
    #expect(presenter.chipLabel == nil)
  }

  // MARK: - rows: order, active flag, selectability, detail

  @Test func rows_preserveCatalogOrderAndFlagActive() {
    let presenter = ActiveModelChipPresenter(
      activeDescriptor: gemma, activeState: .ready(modelPath: "/g"),
      catalog: [gemma, qwen],
      state: [gemmaID: .ready(modelPath: "/g"), qwenID: .ready(modelPath: "/q")],
      activeModelID: gemmaID, isSimulationActive: false)
    #expect(presenter.rows.map(\.id) == [gemmaID, qwenID])
    #expect(presenter.rows[0].isActive == true)
    #expect(presenter.rows[1].isActive == false)
  }

  @Test func rows_readyModelsAreSelectableAndCarrySize() {
    let presenter = ActiveModelChipPresenter(
      activeDescriptor: gemma, activeState: .ready(modelPath: "/g"),
      catalog: [gemma, qwen],
      state: [gemmaID: .ready(modelPath: "/g"), qwenID: .ready(modelPath: "/q")],
      activeModelID: gemmaID, isSimulationActive: false)
    #expect(presenter.rows[0].isSelectable == true)
    #expect(presenter.rows[1].isSelectable == true)
    #expect(presenter.rows[0].detail == .size(gemma.fileSize))
    #expect(presenter.rows[1].detail == .size(qwen.fileSize))
  }

  @Test func rows_inFlightSimulationLocksEverySelection() {
    // Mirrors ModelSettingsRow.isSwitchLocked: switching is disabled while a
    // run is in flight, even for ready models.
    let presenter = ActiveModelChipPresenter(
      activeDescriptor: gemma, activeState: .ready(modelPath: "/g"),
      catalog: [gemma, qwen],
      state: [gemmaID: .ready(modelPath: "/g"), qwenID: .ready(modelPath: "/q")],
      activeModelID: gemmaID, isSimulationActive: true)
    #expect(presenter.rows.allSatisfy { !$0.isSelectable })
  }

  @Test func rows_notDownloadedIsNotSelectable() {
    let presenter = ActiveModelChipPresenter(
      activeDescriptor: gemma, activeState: .ready(modelPath: "/g"),
      catalog: [gemma, qwen],
      state: [gemmaID: .ready(modelPath: "/g"), qwenID: .notDownloaded],
      activeModelID: gemmaID, isSimulationActive: false)
    #expect(presenter.rows[1].isSelectable == false)
    #expect(presenter.rows[1].detail == .notDownloaded)
  }

  @Test func rows_downloadingShowsDownloadingDetail() {
    let presenter = ActiveModelChipPresenter(
      activeDescriptor: gemma, activeState: .ready(modelPath: "/g"),
      catalog: [gemma, qwen],
      state: [gemmaID: .ready(modelPath: "/g"), qwenID: .downloading(progress: 0.3)],
      activeModelID: gemmaID, isSimulationActive: false)
    #expect(presenter.rows[1].isSelectable == false)
    #expect(presenter.rows[1].detail == .downloading)
  }

  @Test func rows_missingStateTreatedAsUnavailable() {
    // qwen absent from the state dict → `.checking` fallback → `.unavailable`.
    let presenter = ActiveModelChipPresenter(
      activeDescriptor: gemma, activeState: .ready(modelPath: "/g"),
      catalog: [gemma, qwen],
      state: [gemmaID: .ready(modelPath: "/g")],
      activeModelID: gemmaID, isSimulationActive: false)
    #expect(presenter.rows[1].detail == .unavailable)
    #expect(presenter.rows[1].isSelectable == false)
  }
}

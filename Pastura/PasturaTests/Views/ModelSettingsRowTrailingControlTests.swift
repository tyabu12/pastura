import Testing

@testable import Pastura

/// Pins the trailing-slot control-kind derivation for `ModelSettingsRow`.
///
/// Load-bearing purpose: the `disabled:` payload on `.downloadButton` carries
/// the sequential-DL guard + cellular-consent multi-row guard
/// (`navigation.md` QA scenarios 16 & 17, ADR-007 §3.3 (c)). A future body
/// refactor that collapses `.downloadButton(disabled:)` into a payload-less
/// case would silently drop `.disabled(otherDownloadInProgress)` from the
/// direct download button — this suite catches that regression at compile time.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ModelSettingsRowTrailingControlTests {

  // MARK: - Fixture

  private let descriptor = ModelRegistry.gemma4E2B

  private func makeRow(
    state: ModelState,
    isActive: Bool,
    otherDownloadInProgress: Bool
  ) -> ModelSettingsRow {
    ModelSettingsRow(
      descriptor: descriptor,
      state: state,
      isActive: isActive,
      otherDownloadInProgress: otherDownloadInProgress,
      isSwitchLocked: false,
      onDownload: {},
      onCancel: {},
      onSwitchActive: {},
      onRequestDelete: {}
    )
  }

  // MARK: - .checking → .none (both isActive, both otherDL)

  @Test func checkingActiveOtherDLFalse() {
    #expect(
      makeRow(state: .checking, isActive: true, otherDownloadInProgress: false).trailingControl
        == .none)
  }

  @Test func checkingActiveOtherDLTrue() {
    #expect(
      makeRow(state: .checking, isActive: true, otherDownloadInProgress: true).trailingControl
        == .none)
  }

  @Test func checkingInactiveOtherDLFalse() {
    #expect(
      makeRow(state: .checking, isActive: false, otherDownloadInProgress: false).trailingControl
        == .none)
  }

  @Test func checkingInactiveOtherDLTrue() {
    #expect(
      makeRow(state: .checking, isActive: false, otherDownloadInProgress: true).trailingControl
        == .none)
  }

  // MARK: - .unsupportedDevice → .none (both isActive, both otherDL)

  @Test func unsupportedDeviceActiveOtherDLFalse() {
    #expect(
      makeRow(state: .unsupportedDevice, isActive: true, otherDownloadInProgress: false)
        .trailingControl == .none)
  }

  @Test func unsupportedDeviceActiveOtherDLTrue() {
    #expect(
      makeRow(state: .unsupportedDevice, isActive: true, otherDownloadInProgress: true)
        .trailingControl == .none)
  }

  @Test func unsupportedDeviceInactiveOtherDLFalse() {
    #expect(
      makeRow(state: .unsupportedDevice, isActive: false, otherDownloadInProgress: false)
        .trailingControl == .none)
  }

  @Test func unsupportedDeviceInactiveOtherDLTrue() {
    #expect(
      makeRow(state: .unsupportedDevice, isActive: false, otherDownloadInProgress: true)
        .trailingControl == .none)
  }

  // MARK: - .notDownloaded → .downloadButton (both isActive)

  @Test func notDownloadedActiveOtherDLFalse() {
    #expect(
      makeRow(state: .notDownloaded, isActive: true, otherDownloadInProgress: false).trailingControl
        == .downloadButton(disabled: false))
  }

  @Test func notDownloadedActiveOtherDLTrue() {
    #expect(
      makeRow(state: .notDownloaded, isActive: true, otherDownloadInProgress: true).trailingControl
        == .downloadButton(disabled: true))
  }

  @Test func notDownloadedInactiveOtherDLFalse() {
    #expect(
      makeRow(state: .notDownloaded, isActive: false, otherDownloadInProgress: false)
        .trailingControl == .downloadButton(disabled: false))
  }

  @Test func notDownloadedInactiveOtherDLTrue() {
    #expect(
      makeRow(state: .notDownloaded, isActive: false, otherDownloadInProgress: true).trailingControl
        == .downloadButton(disabled: true))
  }

  // MARK: - .downloading → .menu (both isActive, both otherDL)

  @Test func downloadingActiveOtherDLFalse() {
    #expect(
      makeRow(state: .downloading(progress: 0.5), isActive: true, otherDownloadInProgress: false)
        .trailingControl == .menu)
  }

  @Test func downloadingActiveOtherDLTrue() {
    #expect(
      makeRow(state: .downloading(progress: 0.5), isActive: true, otherDownloadInProgress: true)
        .trailingControl == .menu)
  }

  @Test func downloadingInactiveOtherDLFalse() {
    #expect(
      makeRow(state: .downloading(progress: 0.5), isActive: false, otherDownloadInProgress: false)
        .trailingControl == .menu)
  }

  @Test func downloadingInactiveOtherDLTrue() {
    #expect(
      makeRow(state: .downloading(progress: 0.5), isActive: false, otherDownloadInProgress: true)
        .trailingControl == .menu)
  }

  // MARK: - .ready → .none (active) / .menu (inactive)

  @Test func readyActiveOtherDLFalse() {
    #expect(
      makeRow(
        state: .ready(modelPath: "/tmp/fake.gguf"), isActive: true, otherDownloadInProgress: false
      ).trailingControl == .none)
  }

  @Test func readyActiveOtherDLTrue() {
    #expect(
      makeRow(
        state: .ready(modelPath: "/tmp/fake.gguf"), isActive: true, otherDownloadInProgress: true
      ).trailingControl == .none)
  }

  @Test func readyInactiveOtherDLFalse() {
    #expect(
      makeRow(
        state: .ready(modelPath: "/tmp/fake.gguf"), isActive: false, otherDownloadInProgress: false
      ).trailingControl == .menu)
  }

  @Test func readyInactiveOtherDLTrue() {
    #expect(
      makeRow(
        state: .ready(modelPath: "/tmp/fake.gguf"), isActive: false, otherDownloadInProgress: true
      ).trailingControl == .menu)
  }

  // MARK: - .error → .downloadButton (both isActive)

  @Test func errorActiveOtherDLFalse() {
    #expect(
      makeRow(state: .error("fake error"), isActive: true, otherDownloadInProgress: false)
        .trailingControl == .downloadButton(disabled: false))
  }

  @Test func errorActiveOtherDLTrue() {
    #expect(
      makeRow(state: .error("fake error"), isActive: true, otherDownloadInProgress: true)
        .trailingControl == .downloadButton(disabled: true))
  }

  @Test func errorInactiveOtherDLFalse() {
    #expect(
      makeRow(state: .error("fake error"), isActive: false, otherDownloadInProgress: false)
        .trailingControl == .downloadButton(disabled: false))
  }

  @Test func errorInactiveOtherDLTrue() {
    #expect(
      makeRow(state: .error("fake error"), isActive: false, otherDownloadInProgress: true)
        .trailingControl == .downloadButton(disabled: true))
  }
}

import Testing

@testable import Pastura

/// Playback-display tests (current-utterance focus opacity + reading-pause
/// display length), split from `SimulationViewModelStreamingTests` to keep
/// that suite under the `type_body_length` cap. Same suite via `extension` —
/// NOT a new `@Suite` (Swift Testing runs suites in parallel; see
/// `.claude/rules/testing.md`).
extension SimulationViewModelStreamingTests {

  // MARK: - Reading-pause display length (drives PlaybackSpeed.readingDwell)

  @Test func lastAgentOutputDisplayLengthCapturesPrimaryGraphemeCount() throws {
    let (sut, scenario) = try makeSUT()
    sut.handleEvent(
      .phaseStarted(phaseType: .speakAll, phasePath: [0]), scenario: scenario)
    let output = TurnOutput(fields: ["statement": "hello world"])
    sut.handleEvent(
      .agentOutput(agent: "Alice", output: output, phaseType: .speakAll),
      scenario: scenario)
    // Primary text length only (thought excluded), grapheme count.
    #expect(sut.lastAgentOutputDisplayLength == 11)
  }

  @Test func lastAgentOutputDisplayLengthCountsGraphemesNotUTF16() throws {
    let (sut, scenario) = try makeSUT()
    sut.handleEvent(
      .phaseStarted(phaseType: .speakAll, phasePath: [0]), scenario: scenario)
    // Two thumbs-up are 2 graphemes but 4 UTF-16 code units — pins the
    // grapheme-count reading-length proxy used by the VN reading pause.
    let output = TurnOutput(fields: ["statement": "👍👍"])
    sut.handleEvent(
      .agentOutput(agent: "Alice", output: output, phaseType: .speakAll),
      scenario: scenario)
    #expect(sut.lastAgentOutputDisplayLength == 2)
  }

  // MARK: - Current-utterance focus opacity

  @Test func pastFocusOpacityConstantPinned() {
    // Change-detector pin on the dim level for past rows during playback.
    #expect(SimulationViewModel.pastFocusOpacity == 0.65)
  }

  @Test func focusedOpacityMatrix() {
    // While running: current row full, past rows dimmed.
    #expect(SimulationViewModel.focusedOpacity(isRunning: true, isCurrent: true) == 1.0)
    #expect(
      SimulationViewModel.focusedOpacity(isRunning: true, isCurrent: false)
        == SimulationViewModel.pastFocusOpacity)
    // Not running (completed / paused review): everything full so the finished
    // log reads normally.
    #expect(SimulationViewModel.focusedOpacity(isRunning: false, isCurrent: true) == 1.0)
    #expect(SimulationViewModel.focusedOpacity(isRunning: false, isCurrent: false) == 1.0)
  }
}

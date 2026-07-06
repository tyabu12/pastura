import Testing

@testable import Pastura

/// Coverage for ``WhisperHandler`` — the secret pairwise `whisper` phase.
///
/// Whisper pairs off active agents, runs `subRounds` exchanges per pair, emits
/// each utterance as an `.agentOutput` (never touching the public conversation
/// log / `lastOutputs`), and writes each participant's view of their pair's
/// exchange to `whispers_<name>`.
@Suite(.timeLimit(.minutes(1)))
struct WhisperHandlerTests {
  let handler = WhisperHandler()

  private func whisperPhase(prompt: String? = "Whisper!", subRounds: Int? = nil) -> Phase {
    Phase(
      type: .whisper, prompt: prompt,
      outputSchema: ["statement": "string", "inner_thought": "string"],
      subRounds: subRounds)
  }

  // Prompt template that surfaces the running exchange transcript, so the test
  // can assert the handler threads it into each utterance's user prompt.
  private static let exchangeProbePrompt = "Whisper. So far: {whisper_exchange}"

  private func stmt(_ text: String) -> String {
    #"{"statement": "\#(text)", "inner_thought": "t"}"#
  }

  private struct WhisperOut {
    let agent: String
    let whisperTo: String?
    let statement: String?
  }

  /// Extracts `(agent, whisper_to, statement)` for each whisper `.agentOutput`.
  private func whisperOutputs(_ collector: EventCollector) -> [WhisperOut] {
    collector.events.compactMap { event in
      if case .agentOutput(let agent, let output, let phaseType) = event, phaseType == .whisper {
        return WhisperOut(
          agent: agent, whisperTo: output.fields["whisper_to"], statement: output.statement)
      }
      return nil
    }
  }

  @Test func fourAgentsRoundOnePairsAdjacentWithAttribution() async throws {
    let mock = MockLLMService(responses: [
      stmt("A to B"), stmt("B to A"), stmt("C to D"), stmt("D to C")
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob", "Carol", "Dave"],
      phases: [whisperPhase()])
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let outputs = whisperOutputs(collector)
    #expect(outputs.count == 4)
    #expect(outputs.map(\.agent) == ["Alice", "Bob", "Carol", "Dave"])
    #expect(outputs.map(\.whisperTo) == ["Bob", "Alice", "Dave", "Carol"])
    // rawText preserved through the whisper_to merge.
    for event in collector.events {
      if case .agentOutput(_, let output, .whisper) = event {
        #expect(output.rawText != nil)
        #expect(!(output.rawText ?? "").isEmpty)
      }
    }
  }

  @Test func roundTwoRotationShiftsPairs() async throws {
    let mock = MockLLMService(responses: [
      stmt("1"), stmt("2"), stmt("3"), stmt("4")
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob", "Carol", "Dave"],
      phases: [whisperPhase()])
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 2
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    // offset = (2-1) % 4 = 1 → rotated [Bob, Carol, Dave, Alice] → (Bob,Carol),(Dave,Alice)
    let outputs = whisperOutputs(collector)
    #expect(outputs.map(\.agent) == ["Bob", "Carol", "Dave", "Alice"])
    #expect(outputs.map(\.whisperTo) == ["Carol", "Bob", "Alice", "Dave"])
  }

  @Test func doesNotTouchConversationLogOrLastOutputs() async throws {
    let mock = MockLLMService(responses: [
      stmt("A to B"), stmt("B to A")
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [whisperPhase()])
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(state.conversationLog.isEmpty)
    #expect(state.lastOutputs.isEmpty)
  }

  @Test func writesPerParticipantChannelWithoutCrossPairLeak() async throws {
    let mock = MockLLMService(responses: [
      stmt("A to B"), stmt("B to A"), stmt("C to D"), stmt("D to C")
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob", "Carol", "Dave"],
      phases: [whisperPhase()])
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    // All four participants get a channel.
    for name in ["Alice", "Bob", "Carol", "Dave"] {
      #expect(state.variables["whispers_\(name)"] != nil)
    }
    let aliceChannel = try #require(state.variables["whispers_Alice"])
    #expect(aliceChannel.contains("A to B"))
    #expect(aliceChannel.contains("B to A"))
    // No leak of the other pair's content.
    #expect(!aliceChannel.contains("C to D"))
    #expect(!aliceChannel.contains("D to C"))
    #expect(aliceChannel.contains("Bob"))  // partner-identifying line
  }

  @Test func oddAgentSitsOutAndStaleChannelCleared() async throws {
    let mock = MockLLMService(responses: [
      stmt("A to B"), stmt("B to A"), stmt("C to D"), stmt("D to C")
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob", "Carol", "Dave", "Eve"],
      phases: [whisperPhase()])
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    state.variables["whispers_Eve"] = "stale from a prior round"
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    // Eve (last of rotated list) sits out; her stale channel is cleared.
    #expect(mock.generateCallCount == 4)
    #expect(state.variables["whispers_Eve"] == nil)
    let whisperers = Set(whisperOutputs(collector).map(\.agent))
    #expect(whisperers == ["Alice", "Bob", "Carol", "Dave"])
  }

  @Test func singleActiveAgentIsNoOp() async throws {
    let mock = MockLLMService(responses: [])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob", "Carol", "Dave"],
      phases: [whisperPhase()])
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    state.eliminated["Bob"] = true
    state.eliminated["Carol"] = true
    state.eliminated["Dave"] = true
    state.variables["whispers_Alice"] = "untouched"
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(mock.generateCallCount == 0)
    #expect(whisperOutputs(collector).isEmpty)
    // No-op path must not clear anyone's channel.
    #expect(state.variables["whispers_Alice"] == "untouched")
  }

  @Test func subRoundsAccumulatesExchangeTranscript() async throws {
    let mock = MockLLMService(responses: [
      stmt("A1"), stmt("B1"), stmt("A2"), stmt("B2"),  // pair (Alice, Bob), 2 exchanges
      stmt("C1"), stmt("D1"), stmt("C2"), stmt("D2")  // pair (Carol, Dave), 2 exchanges
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob", "Carol", "Dave"],
      phases: [whisperPhase(prompt: Self.exchangeProbePrompt, subRounds: 2)])
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(mock.generateCallCount == 8)
    // The Alice/Bob channel carries all four utterances of the two exchanges.
    let aliceChannel = try #require(state.variables["whispers_Alice"])
    for token in ["A1", "B1", "A2", "B2"] {
      #expect(aliceChannel.contains(token))
    }
    // The second exchange's prompt saw the first exchange's transcript.
    let secondSpeakerPrompt = mock.capturedPrompts[2].user  // Alice's 2nd utterance
    #expect(secondSpeakerPrompt.contains("A1"))
    #expect(secondSpeakerPrompt.contains("B1"))
  }

  @Test func eliminatedAgentsNeverPaired() async throws {
    let mock = MockLLMService(responses: [
      stmt("A to C"), stmt("C to A")
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob", "Carol", "Dave"],
      phases: [whisperPhase()])
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    state.eliminated["Bob"] = true
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    // active = [Alice, Carol, Dave] → (Alice, Carol); Dave sits out; Bob absent.
    let outputs = whisperOutputs(collector)
    #expect(outputs.map(\.agent) == ["Alice", "Carol"])
    #expect(outputs.map(\.whisperTo) == ["Carol", "Alice"])
    #expect(state.variables["whispers_Bob"] == nil)
    #expect(state.variables["whispers_Dave"] == nil)
  }
}

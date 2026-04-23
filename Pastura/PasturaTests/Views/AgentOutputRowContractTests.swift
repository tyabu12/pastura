import Testing

@testable import Pastura

/// Pre-refactor safety net for the #171 B2 ChatBubble rollout.
///
/// Why this suite exists (and what it does NOT test):
///
/// The critic pass on the B2 plan flagged a Critical risk — wrapping
/// ``AgentOutputRow`` inside a ChatBubble container could flush its
/// `@State` (visibleChars, animationTask, animationGeneration,
/// debugInstanceID) mid-stream, regressing #133's streaming stability
/// work. The agreed mitigation is **Approach B**: ChatBubble is extracted
/// as styling *primitives* (BubbleBackground / ThoughtLeftRule /
/// AvatarSlot modifiers) rather than a wrapper view, so AgentOutputRow's
/// root `VStack` structure stays identical and `@State` identity is
/// preserved by construction.
///
/// This suite guards **what is actually testable without a SwiftUI host**:
///
/// 1. **Public initializer signatures** — the three live call sites
///    (SimulationView log row, SimulationView streaming row,
///    ResultDetailView turnRow) continue to compile verbatim through the
///    refactor. Breaking any of these is an immediate surface-area
///    regression.
/// 2. **Pure computed properties** (`targetLength`, `shouldAnimate`) —
///    these derive from input parameters only, not `@State`, so they can
///    be exercised directly. `targetLength` especially governs the
///    reveal-animation upper bound; a regression there silently truncates
///    or over-reveals streaming text.
///
/// Explicitly **NOT** tested here (cannot be, without a rendering host):
///
/// - `@State` persistence across parent re-renders. PasturaTests has no
///   ViewInspector / SwiftUI host infrastructure; adding one is out of
///   scope for #171. Mitigation: manual QA on device per the #171 PR
///   body checklist, plus code-review gating on any structural change
///   to `AgentOutputRow.body`'s root `VStack`.
/// - `onAnimatingChange` callback timing. Relies on the reveal task's
///   lifecycle, which only runs under a real render pass.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AgentOutputRowContractTests {

  // MARK: - Public initializer signatures (call-site pins)

  @Test func agentOutputRowAcceptsSimulationViewLogRowCallSite() {
    // Matches SimulationView.swift `logEntryView` agent-output branch.
    _ = AgentOutputRow(
      agent: "Alice",
      output: TurnOutput(fields: ["statement": "hi"]),
      phaseType: .speakAll,
      showAllThoughts: false,
      isLatest: true,
      charsPerSecond: 60,
      onAnimatingChange: { _ in },
      debugRowID: "row-1"
    )
  }

  @Test func agentOutputRowAcceptsStreamingCallSite() {
    // Matches SimulationView.swift streaming row (streamingPrimary /
    // streamingThought non-nil, isLatest:false, dedicated debugRowID).
    _ = AgentOutputRow(
      agent: "Bob",
      output: TurnOutput(fields: [:]),
      phaseType: .vote,
      showAllThoughts: true,
      isLatest: false,
      charsPerSecond: 45,
      streamingPrimary: "partial token stream",
      streamingThought: "partial thought",
      debugRowID: "stream-Bob"
    )
  }

  @Test func agentOutputRowAcceptsResultDetailCallSite() {
    // Matches ResultDetailView.turnRow — the past-results replay path
    // uses defaults for isLatest / charsPerSecond / streaming overrides.
    _ = AgentOutputRow(
      agent: "Carol",
      output: TurnOutput(fields: ["vote": "Dave", "reason": "散歩"]),
      phaseType: .vote,
      showAllThoughts: true
    )
  }

  // MARK: - targetLength — pure computed

  @Test func targetLengthCoversPrimaryWhenThoughtHidden() {
    let row = AgentOutputRow(
      agent: "Alice",
      output: TurnOutput(fields: ["statement": "hello"]),  // 5 chars
      phaseType: .speakAll,
      showAllThoughts: false
    )
    #expect(row.targetLength == 5)
  }

  @Test func targetLengthCoversPrimaryPlusThoughtWhenThoughtShown() {
    let row = AgentOutputRow(
      agent: "Alice",
      output: TurnOutput(fields: [
        "statement": "hello",  // 5 chars
        "inner_thought": "quiet"  // 5 chars
      ]),
      phaseType: .speakAll,
      showAllThoughts: true
    )
    #expect(row.targetLength == 10)
  }

  @Test func targetLengthPrefersStreamingPrimaryOverPhaseField() {
    // Critical for #133: while streaming is active, targetLength must
    // track the streaming buffer, not the (nil / empty) phase-derived
    // value. Otherwise the reveal loop's upper bound would snap to the
    // phase field as soon as it commits — visible glitch.
    let row = AgentOutputRow(
      agent: "Alice",
      output: TurnOutput(fields: [:]),
      phaseType: .speakAll,
      showAllThoughts: false,
      streamingPrimary: "token stream growing"  // 20 chars
    )
    #expect(row.targetLength == 20)
  }

  @Test func targetLengthPrefersStreamingThoughtOverPhaseField() {
    let row = AgentOutputRow(
      agent: "Alice",
      output: TurnOutput(fields: ["statement": "hi"]),  // 2 chars
      phaseType: .speakAll,
      showAllThoughts: true,
      streamingThought: "partial inner"  // 13 chars
    )
    #expect(row.targetLength == 15)
  }

  @Test func targetLengthIgnoresThoughtWhenStreamingThoughtNilAndToggleOff() {
    // Button-toggle path: showAllThoughts=false means thought never
    // enters the counter — it reveals instantly via user tap.
    let row = AgentOutputRow(
      agent: "Alice",
      output: TurnOutput(fields: [
        "statement": "hi",  // 2 chars
        "inner_thought": "should not count"
      ]),
      phaseType: .speakAll,
      showAllThoughts: false
    )
    #expect(row.targetLength == 2)
  }

  @Test func targetLengthForVotePhaseFormatsArrowNotation() {
    // Vote phase primary text = "→ Target (reason)" — counted as chars
    // for typing reveal. Regression guard against a refactor that
    // changes the format string and silently shifts the reveal count.
    let row = AgentOutputRow(
      agent: "Alice",
      output: TurnOutput(fields: ["vote": "Dave", "reason": "散歩"]),
      phaseType: .vote,
      showAllThoughts: false
    )
    // "→ Dave (散歩)" — 1 arrow + 1 space + 4 "Dave" + 1 space + 1 "(" + 2 散歩 + 1 ")"
    let expected = "→ Dave (散歩)".count
    #expect(row.targetLength == expected)
  }
}

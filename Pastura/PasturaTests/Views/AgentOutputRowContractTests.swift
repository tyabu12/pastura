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

  @Test func agentOutputRowAcceptsShareHighlightCallSite() {
    // Matches the SimulationView / ResultDetailView committed-row call sites
    // that wire the highlight-share context menu (#1070). The closure is
    // optional (defaults nil); pin it so both entry points keep compiling.
    _ = AgentOutputRow(
      agent: "Alice",
      output: TurnOutput(fields: ["statement": "a line worth sharing"]),
      phaseType: .speakAll,
      showAllThoughts: false,
      agentPosition: 0,
      onAvatarTap: { _ in },
      onShareHighlight: {}
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

  /// Even when the parsed `output` already has a canonical primary field,
  /// a non-nil `streamingPrimary` must short-circuit. Pinned because the
  /// item-2 refactor delegates the non-streaming branch to
  /// ``TurnOutput/primaryText(for:)``; a future "consolidation" that drops
  /// the `if let streamingPrimary` short-circuit would silently revert
  /// live UI to materialising-from-final-fields and lose token-by-token
  /// growth.
  @Test func targetLengthPrefersStreamingPrimaryOverParsedPrimary() {
    let row = AgentOutputRow(
      agent: "Alice",
      output: TurnOutput(fields: ["statement": "FINAL TEN"]),  // 9 chars
      phaseType: .speakAll,
      showAllThoughts: false,
      streamingPrimary: "live"  // 4 chars — must win
    )
    #expect(row.targetLength == 4)
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
    // Vote phase primary text = "→ Target" (the `reason` is NOT appended
    // inline — it is the vote's private-thought field, shown in THINKING;
    // see #609). With thoughts hidden, only the arrow form counts toward
    // the typing reveal. Regression guard: re-appending `(reason)` here
    // would double-show the reason (inline + THINKING) and shift the count.
    let row = AgentOutputRow(
      agent: "Alice",
      output: TurnOutput(fields: ["vote": "Dave", "reason": "散歩"]),
      phaseType: .vote,
      showAllThoughts: false
    )
    // "→ Dave" — 1 arrow + 1 space + 4 "Dave"
    #expect(row.targetLength == "→ Dave".count)
  }

  @Test func targetLengthForVotePhaseDecoratesStreamingPrimaryWithArrow() {
    // #609 device-QA fix: during streaming the row receives the BARE vote
    // value (no arrow) from the extractor. The arrow must be applied to the
    // streaming primary too — otherwise it pops in only when the row commits.
    // targetLength tracking "→ Dave" (not bare "Dave") proves the decoration
    // is present while streaming.
    let row = AgentOutputRow(
      agent: "Alice",
      output: TurnOutput(fields: [:]),
      phaseType: .vote,
      showAllThoughts: false,
      streamingPrimary: "Dave"  // bare extractor value, no arrow
    )
    #expect(row.targetLength == "→ Dave".count)
  }

  @Test func targetLengthForVotePhaseCountsReasonAsThoughtWhenShown() {
    // #609: the vote `reason` flows into the THINKING section via
    // `TurnOutput.secondaryText(for:)`, so when thoughts are shown the
    // reveal counter covers the arrow primary PLUS the reason — exactly
    // like speak's statement + inner_thought.
    let row = AgentOutputRow(
      agent: "Alice",
      output: TurnOutput(fields: ["vote": "Dave", "reason": "散歩"]),
      phaseType: .vote,
      showAllThoughts: true
    )
    #expect(row.targetLength == "→ Dave".count + "散歩".count)
  }

  // MARK: - Thought-visibility seed contract
  //
  // Behavioral notes the suite cannot test directly (no SwiftUI host)
  // but that future refactors must preserve. The two `targetLength`
  // tests above (`*WhenThoughtHidden` / `*WhenThoughtShown`) implicitly
  // exercise the seed — they only pass because the custom `init`
  // applies `State(initialValue: showAllThoughts)` so `showInnerThought`
  // mirrors `showAllThoughts` at construction. Removing the seed
  // (e.g., reverting to `@State private var showInnerThought = false`)
  // would silently flip the `*WhenThoughtShown` test to expect-5-got-10.
  //
  // ## Seed timing on `@State` recreation
  //
  // `@State` lifetime is one cycle of view identity. LazyVStack recycle
  // (#133 Hyp B, tracked by `debugInstanceID`) re-creates `@State`,
  // which re-runs `State(initialValue: showAllThoughts)` and re-syncs
  // the recycled row to the *current* global mode. This is desirable —
  // a recycled slot represents a different agent / phase, so inheriting
  // the previous occupant's expand state would feel arbitrary.
  //
  // ## Cancel-free thought-visibility sync
  //
  // `handleThoughtVisibilityChange` (the renamed
  // `handleShowAllThoughtsChange`) MUST NOT call
  // `animationTask?.cancel()` — that re-opens the cancel-race surface
  // hardened in #133 / #134 / #147 / #150. Manual chevron taps fire
  // `onChange(of: showInnerThought)` on every interaction; combining
  // a tap + cancel + restart per tap would page in exactly the race
  // pattern those PRs fixed. The current contract:
  //
  //   - `!shouldAnimate`: snap visibleChars to target.
  //   - `visibleChars >= target` (collapse / over-revealed): no-op,
  //     loop terminates naturally on next iteration.
  //   - `visibleChars < target` + task running: no-op, loop reads
  //     new target on next tick.
  //   - `visibleChars < target` + no task: snap to target so the
  //     just-unhidden body has revealed content for the .transition
  //     fade. Restarting would slow-type after a deliberate user tap.
  //
  // ## Collapse → re-expand
  //
  // After a manual collapse, `visibleChars` is intentionally NOT
  // snapped down. Primary's concat trick uses `min(visibleChars,
  // primaryLen)` so it stays correct, and the thought view is hidden
  // by the `if showInnerThought` conditional in `thoughtSection`.
  // On re-expand, `visibleChars` may already be >= the new target
  // (if the row had previously been expanded and revealed) — in which
  // case the no-op branch fires and the body shows full text via the
  // .transition fade. If the user collapsed mid-stream and re-expanded
  // after more thought tokens arrived, `visibleChars < target` + no
  // task → instant snap to current buffer. Both flows feel like
  // "tap = immediate" to the user.
  @Test func targetLengthSeededFromShowAllThoughtsAtConstruction() {
    // Pin the seed contract: `showInnerThought` is `State(initialValue:
    // showAllThoughts)` per the custom init, so `targetLength` reflects
    // the constructor argument before any view rendering. Two rows with
    // identical content but opposite `showAllThoughts` produce different
    // `targetLength` values — that delta is the seed at work.
    let collapsed = AgentOutputRow(
      agent: "Alice",
      output: TurnOutput(fields: [
        "statement": "hello",
        "inner_thought": "quiet"
      ]),
      phaseType: .speakAll,
      showAllThoughts: false
    )
    let expanded = AgentOutputRow(
      agent: "Alice",
      output: TurnOutput(fields: [
        "statement": "hello",
        "inner_thought": "quiet"
      ]),
      phaseType: .speakAll,
      showAllThoughts: true
    )
    #expect(collapsed.targetLength == 5)  // primary only
    #expect(expanded.targetLength == 10)  // primary + thought
    #expect(expanded.targetLength - collapsed.targetLength == 5)  // = thought
  }

  // `shouldRevealThoughtSection(visibleChars:)` tests live in the sibling
  // file `AgentOutputRowContractTests+ThoughtSectionGate.swift` per
  // `.claude/rules/testing.md` § "Splitting a Suite Across Files" (this
  // file crossed the 400-line `file_length` cap when the gate landed).

  // MARK: - thoughtToggleAccessibilityLabel(showInnerThought:)

  @Test func thoughtToggleAccessibilityLabelOnStateContainsHide() {
    let label = AgentOutputRow.thoughtToggleAccessibilityLabel(
      showInnerThought: true)
    #expect(!label.isEmpty)
    #expect(label.contains("Hide"))
  }

  @Test func thoughtToggleAccessibilityLabelOffStateContainsShow() {
    let label = AgentOutputRow.thoughtToggleAccessibilityLabel(
      showInnerThought: false)
    #expect(!label.isEmpty)
    #expect(label.contains("Show"))
  }

  @Test func thoughtToggleAccessibilityLabelsForOnAndOffDiffer() {
    let onLabel = AgentOutputRow.thoughtToggleAccessibilityLabel(
      showInnerThought: true)
    let offLabel = AgentOutputRow.thoughtToggleAccessibilityLabel(
      showInnerThought: false)
    #expect(onLabel != offLabel)
  }

  // `shouldReserveHiddenTail(...)` truth-table lives in the sibling file
  // `AgentOutputRowContractTests+ReservedTail.swift` per
  // `.claude/rules/testing.md` § "Splitting a Suite Across Files" (this
  // file would cross the 400-line `file_length` cap otherwise).
}

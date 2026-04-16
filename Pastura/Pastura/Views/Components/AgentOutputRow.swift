import SwiftUI

/// Displays a single agent's output with an optional inner thought and an
/// LLM-chat-style typing animation for the latest row.
///
/// ## Typing animation
///
/// Only the latest row animates (`isLatest == true` and
/// `charsPerSecond != nil`). Older rows render full text immediately.
/// Animation unifies the statement and thought into a single counter that
/// advances through `primaryLength + (showAllThoughts ? thoughtLength : 0)` —
/// the thought types right after the statement, no gap, at the same rate.
///
/// ## Reflow-stable rendering
///
/// Text is rendered as `Text(visible) + Text(hidden).foregroundStyle(.clear)`
/// so the full string is laid out from the first frame. This keeps line-wrap
/// positions from shifting as characters appear and lets the parent
/// `ScrollViewReader` land its single `scrollTo(last.id)` correctly without
/// mid-typing follow-up scrolls.
///
/// ## Interactive paths
///
/// When `showAllThoughts` is false, the user can still reveal the thought via
/// the "Show thought" button. That path is deliberately animation-free (it's
/// a user action, not narrative reveal) and keeps its fade-in transition.
struct AgentOutputRow: View {
  let agent: String
  let output: TurnOutput
  let phaseType: PhaseType
  let showAllThoughts: Bool
  /// `true` when this row is the most recent agent output. Only the latest
  /// row animates typing; older rows render full text immediately.
  var isLatest: Bool = false
  /// Characters revealed per second during typing. `nil` = no animation.
  var charsPerSecond: Double?

  @State private var showInnerThought = false
  @State private var visibleChars: Int = 0
  @State private var animationTask: Task<Void, Never>?

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      // Agent name + phase
      HStack(alignment: .firstTextBaseline) {
        Text(agent)
          .font(.subheadline.bold())
        PhaseTypeLabel(phaseType: phaseType)
        Spacer()
      }

      // Primary text — pre-measured concat so line wraps don't shift.
      if let text = primaryText {
        primaryView(fullText: text)
      }

      // Thought: three branches depending on show-mode.
      thoughtSection()
    }
    .padding(.vertical, 4)
    .onAppear { startAnimationIfNeeded() }
    .onChange(of: isLatest) { _, newValue in
      if !newValue { snapToFull() }
    }
    .onChange(of: showAllThoughts) { _, _ in
      handleShowAllThoughtsChange()
    }
    .onDisappear { animationTask?.cancel() }
  }

  // MARK: - Subviews

  /// Renders the primary text with the concat trick so the final layout is
  /// established on first frame and the revealed prefix grows in place.
  private func primaryView(fullText: String) -> some View {
    let primaryLen = fullText.count
    let revealed = min(visibleChars, primaryLen)
    let splitIdx = fullText.index(fullText.startIndex, offsetBy: revealed)
    let visible = fullText[..<splitIdx]
    let hidden = fullText[splitIdx...]
    return (Text(visible) + Text(hidden).foregroundStyle(.clear))
      .font(.body)
  }

  @ViewBuilder
  private func thoughtSection() -> some View {
    if let thought = output.innerThought, !thought.isEmpty {
      if showAllThoughts {
        // Auto-reveal path — participates in the unified typing counter.
        autoThoughtView(fullText: thought)
      } else {
        // Button-toggle path — instant reveal with its own transition.
        buttonToggleThought(fullText: thought)
      }
    }
  }

  /// Auto-reveal thought (when `showAllThoughts == true`): pre-measured concat
  /// driven by the same counter, so the reveal visually continues from where
  /// the statement left off.
  private func autoThoughtView(fullText: String) -> some View {
    let primaryLen = (primaryText?.count ?? 0)
    let thoughtRevealed = max(0, min(visibleChars - primaryLen, fullText.count))
    let splitIdx = fullText.index(fullText.startIndex, offsetBy: thoughtRevealed)
    let visible = fullText[..<splitIdx]
    let hidden = fullText[splitIdx...]
    return (Text(visible) + Text(hidden).foregroundStyle(.clear))
      .font(.caption)
      .italic()
      .foregroundStyle(.secondary)
      .padding(.leading, 8)
  }

  /// Button-toggle path (when `showAllThoughts == false`): tapping the button
  /// reveals the full thought instantly with a fade/slide transition. No
  /// character-by-character typing — this is a user action, not narrative.
  @ViewBuilder
  private func buttonToggleThought(fullText: String) -> some View {
    Button {
      withAnimation(.easeInOut(duration: 0.2)) {
        showInnerThought.toggle()
      }
    } label: {
      HStack(spacing: 4) {
        Image(systemName: showInnerThought ? "eye.slash" : "eye")
        Text(showInnerThought ? "Hide thought" : "Show thought")
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .buttonStyle(.plain)

    if showInnerThought {
      Text(fullText)
        .font(.caption)
        .foregroundStyle(.secondary)
        .italic()
        .padding(.leading, 8)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
  }

  // MARK: - Derived lengths

  /// Total characters the counter should cover: primary plus thought when
  /// thoughts are globally visible. Button-toggle reveal bypasses this.
  private var targetLength: Int {
    let primary = primaryText?.count ?? 0
    let thought = showAllThoughts ? (output.innerThought?.count ?? 0) : 0
    return primary + thought
  }

  private var shouldAnimate: Bool {
    isLatest && charsPerSecond != nil
  }

  // MARK: - Animation control

  private func startAnimationIfNeeded() {
    let target = targetLength
    guard shouldAnimate, let cps = charsPerSecond, cps > 0 else {
      // Not animating (non-latest row OR instant speed) — snap to full.
      visibleChars = target
      return
    }
    if visibleChars >= target { return }  // already finished

    animationTask?.cancel()
    let delayNanos = UInt64(1_000_000_000.0 / cps)
    animationTask = Task { @MainActor in
      // Re-read `targetLength` each tick so a mid-typing `showAllThoughts`
      // flip to true extends the animation into the thought without restart.
      while !Task.isCancelled && visibleChars < targetLength {
        try? await Task.sleep(nanoseconds: delayNanos)
        if Task.isCancelled { return }
        visibleChars = min(visibleChars + 1, targetLength)
      }
    }
  }

  private func snapToFull() {
    animationTask?.cancel()
    visibleChars = targetLength
  }

  /// React to a mid-typing `showAllThoughts` flip on the latest row:
  /// - `true` → target extends; keep animating (the running loop re-reads target).
  ///   If the loop already finished primary and exited, restart it.
  /// - `false` → target shrinks; snap down so we don't render past new target.
  private func handleShowAllThoughtsChange() {
    let target = targetLength
    if !shouldAnimate {
      visibleChars = target
      return
    }
    if visibleChars > target {
      animationTask?.cancel()
      visibleChars = target
    } else if visibleChars < target, animationTask == nil || animationTask?.isCancelled == true {
      startAnimationIfNeeded()
    }
    // else: animation is running and will naturally advance to new target.
  }

  /// Extracts the primary display text from the output based on phase type.
  private var primaryText: String? {
    switch phaseType {
    case .speakAll, .speakEach:
      output.statement ?? output.declaration ?? output.boke
    case .vote:
      output.vote.map { vote in
        let reason = output.reason.map { " (\($0))" } ?? ""
        return "→ \(vote)\(reason)"
      }
    case .choose:
      output.action ?? output.declaration
    default:
      output.fields.values.first
    }
  }
}

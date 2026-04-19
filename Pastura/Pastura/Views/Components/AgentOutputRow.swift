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
  /// Invoked when this row's typing animation starts (`true`) or finishes /
  /// cancels / snaps to full (`false`). Parent uses this to gate other UI
  /// (e.g., "is thinking..." indicators) so they don't appear while text is
  /// still rendering.
  var onAnimatingChange: ((Bool) -> Void)?

  /// Live streaming override for the primary text. When non-nil, replaces
  /// the phase-derived value from `output` — used by ``SimulationView``
  /// for the in-flight agent row while token-by-token streaming grows
  /// the visible text. The reveal animation continues to apply (tokens
  /// arriving faster than `charsPerSecond` are queued, slower ones
  /// surface immediately), so UX stays consistent with playback speed.
  var streamingPrimary: String?

  /// Live streaming override for `inner_thought`. Same semantics as
  /// ``streamingPrimary``.
  var streamingThought: String?

  @State private var showInnerThought = false
  @State private var visibleChars: Int = 0
  @State private var animationTask: Task<Void, Never>?
  /// Monotonic counter bumped once per reveal-task creation. The task's
  /// `defer` uses it to skip both the `animationTask` nil-out and the
  /// `onAnimatingChange?(false)` notification when a newer task has
  /// already replaced it — otherwise a stale completion could clobber
  /// the reference, or flip the parent's animating-state back to `false`
  /// while the newer task is still revealing (`SimulationView` gates
  /// its thinking-indicator visibility and `scrollToBottom` on the
  /// parent-side `latestRowIsAnimating` flag).
  @State private var animationGeneration: Int = 0

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
    // Live streaming: when the parent-supplied snapshot grows, extend the
    // reveal. Target length is re-read on every animation tick, so if the
    // loop is already running it picks up the new target for free — but
    // the loop may have exited (previous target fully revealed), so we
    // also kick it back on.
    .onChange(of: streamingPrimary) { _, _ in handleStreamTargetChange() }
    .onChange(of: streamingThought) { _, _ in handleStreamTargetChange() }
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
    if let thought = resolvedThought, !thought.isEmpty {
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
    let thought = showAllThoughts ? (resolvedThought?.count ?? 0) : 0
    return primary + thought
  }

  /// Whether this row should run the character-reveal animation. The
  /// live-streaming path (``streamingPrimary`` / ``streamingThought``
  /// non-nil) always animates — the parent grows those values as tokens
  /// arrive, and the reveal loop re-reads the target each tick so the
  /// display tracks the incoming stream at `charsPerSecond`. The replay
  /// path (no streaming override) only animates when this is the latest
  /// row, matching past-results playback.
  private var shouldAnimate: Bool {
    guard charsPerSecond != nil else { return false }
    return isLatest || streamingPrimary != nil || streamingThought != nil
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

    // Bump generation so the task's `defer` can tell whether it is still
    // the "current" task when it completes. Without this, a naturally
    // finishing old task could null out `animationTask` after a newer
    // task was assigned to it.
    animationGeneration += 1
    let myGeneration = animationGeneration

    onAnimatingChange?(true)
    animationTask = Task { @MainActor in
      defer {
        // Gated on generation so a superseded task doesn't clobber the
        // newer task's reference or animating-state signal.
        if animationGeneration == myGeneration {
          onAnimatingChange?(false)
          animationTask = nil
        }
      }
      // Re-read `targetLength`, `primaryText`, and `resolvedThought`
      // every tick. `targetLength` covers `showAllThoughts` mid-typing
      // flips. The other two cover live streaming growth: under
      // ``streamingPrimary`` / ``streamingThought``, those values grow
      // token-by-token, and a one-shot capture at task creation would
      // leave punctuation lookup and the statement→thought boundary
      // check running against stale text.
      while !Task.isCancelled && visibleChars < targetLength {
        try? await Task.sleep(nanoseconds: delayNanos)
        if Task.isCancelled { return }
        let newPosition = min(visibleChars + 1, targetLength)
        visibleChars = newPosition

        let currentPrimaryLen = primaryText?.count ?? 0
        let currentFullContent = (primaryText ?? "") + (resolvedThought ?? "")

        // Punctuation-aware pause: after revealing a sentence terminator or
        // comma, wait a little longer so the reader registers the beat.
        let revealed = characterAt(index: newPosition - 1, in: currentFullContent)
        let extraMs = revealed.map(punctuationPauseMs(after:)) ?? 0
        if extraMs > 0 {
          try? await Task.sleep(nanoseconds: UInt64(extraMs) * 1_000_000)
          if Task.isCancelled { return }
        }

        // Statement → thought boundary beat: when we've just finished the
        // primary text and there's thought still to type, insert a rhetorical
        // pause before switching to italic thought reveal.
        if newPosition == currentPrimaryLen && currentPrimaryLen < targetLength {
          try? await Task.sleep(
            nanoseconds: UInt64(statementToThoughtPauseMs) * 1_000_000)
          if Task.isCancelled { return }
        }
      }
    }
  }

  /// Returns the character at `index` in `text`, or nil if out of range.
  /// O(index) because Swift's `String.Index` is not a constant-time offset,
  /// but tolerable here (typical outputs are a few hundred chars).
  private func characterAt(index: Int, in text: String) -> Character? {
    guard index >= 0, index < text.count else { return nil }
    return text[text.index(text.startIndex, offsetBy: index)]
  }

  private func snapToFull() {
    animationTask?.cancel()
    visibleChars = targetLength
  }

  /// React to a mid-stream primary / thought update.
  ///
  /// The reveal task re-reads `targetLength`, `primaryText`, and
  /// `resolvedThought` on every tick (see ``startAnimationIfNeeded``),
  /// so a running task absorbs streaming growth without needing a
  /// cancel/restart. The previous per-token cancel/restart was the
  /// suspected cause of B5 thought-tail flicker: the outgoing task's
  /// `defer` and the incoming task's initial `Task.sleep` opened a
  /// sub-frame window where `visibleChars` did not advance.
  ///
  /// The gate mirrors ``handleShowAllThoughtsChange``. When the reveal
  /// task finishes naturally between tokens (possible when `cps` exceeds
  /// the stream rate), its `defer` clears `animationTask` via the
  /// generation check, so the next growth tick falls into the restart
  /// branch instead of freezing until commit.
  private func handleStreamTargetChange() {
    let target = targetLength
    if !shouldAnimate {
      visibleChars = target
      return
    }
    if visibleChars < target, animationTask == nil || animationTask?.isCancelled == true {
      startAnimationIfNeeded()
    }
    // else: running task's loop picks up the new target on its next tick.
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

  /// Extracts the primary display text.
  ///
  /// Live streaming rows pass ``streamingPrimary``; this takes precedence
  /// over the phase-derived value from `output` so the partial LLM
  /// output grows in place instead of materialising from the final
  /// parsed fields. Completed rows (no streaming override) fall through
  /// to the existing phase-specific extraction.
  private var primaryText: String? {
    if let streamingPrimary { return streamingPrimary }
    switch phaseType {
    case .speakAll, .speakEach:
      return output.statement ?? output.declaration ?? output.boke
    case .vote:
      return output.vote.map { vote in
        let reason = output.reason.map { " (\($0))" } ?? ""
        return "→ \(vote)\(reason)"
      }
    case .choose:
      return output.action ?? output.declaration
    default:
      return output.fields.values.first
    }
  }

  /// Inner thought text, honouring the streaming override when present.
  private var resolvedThought: String? {
    streamingThought ?? output.innerThought
  }
}

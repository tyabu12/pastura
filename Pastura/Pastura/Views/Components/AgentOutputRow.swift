// swiftlint:disable file_length
// Intentionally long: the reveal-animation machinery
// (`startAnimationIfNeeded`, `characterAt`, `snapToFull`,
// `handleStreamTargetChange`, `handleShowAllThoughtsChange`) is all
// `private` so it stays internal to the reveal state machine. Splitting
// into a sibling extension file would force widening those to
// `internal` access (extensions in a separate file cannot see
// `private` members of the defining file), so the file stays in one
// piece. Diagnostic logging already lives in
// `AgentOutputRow+Diagnostic.swift`.
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
/// **Replay path (non-streaming):** text is rendered as
/// `Text(visible) + Text(hidden).foregroundStyle(.clear)` so the full string
/// is laid out from the first frame. This keeps line-wrap positions from
/// shifting as characters appear and lets the parent `ScrollViewReader`
/// land its single `scrollTo(last.id)` correctly without mid-typing
/// follow-up scrolls.
///
/// **Streaming path:** the concat trick degenerates because the "final
/// string" is the partial buffer and grows with each token. Layout
/// stability is carried instead by a trio of modifiers: the outer VStack
/// gets `.frame(maxWidth: .infinity, alignment: .leading)` +
/// `.fixedSize(horizontal: false, vertical: true)` to stabilize the row's
/// bounding box between token arrivals, and the primary text is tagged
/// `.animation(nil, value: streamingPrimary)` to suppress SwiftUI's
/// implicit animation on string growth. Applied unconditionally so the
/// replay path inherits the same stability guarantees without a
/// streaming-vs-replay branch.
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

  /// Whether to prepend a sheep avatar column to this row. Defaults to
  /// true — production call sites all want the avatar. Pass `false` for
  /// contexts where the row is rendered without avatar-space reservation
  /// (previews, tests, or legacy layouts that pre-date #171).
  var showAvatar: Bool = true

  /// Agent's zero-based index in the scenario's agent list. Threaded
  /// through to ``AvatarSlot`` → ``SheepAvatar/Character/forAgent(_:position:)``
  /// so scenarios with ≤4 agents get distinct avatar colors by
  /// construction instead of relying on the weak name-hash. Defaults
  /// to `nil` — call sites without scenario context fall back to the
  /// name-based resolution (direct canonical match + byte-sum hash).
  var agentPosition: Int?

  /// Row-identity tag for #133 PR#4 `StreamingDiag` logs — see
  /// `AgentOutputRow+Diagnostic.swift` for the consumers.
  var debugRowID: String?

  @State private var showInnerThought = false
  // Internal-only so `AgentOutputRow+Diagnostic.swift` can read — mutation surface is the animation-control methods below.
  @State var visibleChars: Int = 0
  @State var animationTask: Task<Void, Never>?
  /// Fresh UUID per `@State` recreation → LazyVStack recycle evidence (#133 Hyp B).
  @State var debugInstanceID = UUID()
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
    // Why the HStack wraps a VStack (and not the other way around): the
    // avatar column needs to align with the top of the bubble column,
    // while the bubble/thought stack still reads as a single vertical
    // block. `@State` identity lives on `AgentOutputRow` itself, not on
    // any body subtree — body rewrites are safe under #133 as long as
    // the view's position in its caller remains stable. The outer
    // layout-stability modifiers (`frame(maxWidth:)`, `fixedSize`, etc.)
    // still apply to the whole row below.
    // When `showAvatar` is false, drop the avatar-text gap to zero so
    // avatar-less rows don't carry a stray 10pt left indent where the
    // avatar column would have been.
    HStack(alignment: .top, spacing: showAvatar ? ChatBubbleLayout.avatarTextGap : 0) {
      if showAvatar {
        AvatarSlot(agentName: agent, position: agentPosition)
      }
      VStack(alignment: .leading, spacing: 6) {
        // Agent name + phase. Caption size + ink-secondary matches
        // `design-system.md` §3.2 `caption/name` and reference HTML
        // `.b-name { font-size: 10.5px; color: #7a7e68 }`.
        HStack(alignment: .firstTextBaseline) {
          Text(agent)
            .textStyle(Typography.captionName)
            .foregroundStyle(Color.inkSecondary)
          PhaseTypeLabel(phaseType: phaseType)
          Spacer()
        }

        // Primary text — pre-measured concat so line wraps don't shift.
        // Bubble background applied here (not around the whole row) so
        // the tail-corner shape hugs the text, not the name/avatar.
        if let text = primaryText {
          primaryView(fullText: text)
            .bubbleBackground()
        }

        // Thought: three branches depending on show-mode.
        thoughtSection()
      }
      // Push the VStack (name/bubble/thought column) down by the avatar's
      // visible-top inset so the agent-name row visually aligns with the
      // top of the sheep silhouette — `SheepAvatar`'s outer wool circle
      // has 7pt of transparent canvas above it inside the 48pt frame,
      // and without this shift the name reads as hovering above the
      // sheep. Applied only when an avatar is rendered; `0` is the
      // identity guide value so other call sites stay unaffected.
      .alignmentGuide(.top) { dim in
        showAvatar
          ? dim[.top] - SheepAvatar.visibleTopInset(forSize: ChatBubbleLayout.avatarSize)
          : dim[.top]
      }
    }
    // Layout-stability trio (applied unconditionally; see type doc-comment
    // §"Reflow-stable rendering"). Streaming growth re-runs the text
    // layout pass per token; pinning the row's horizontal extent and
    // letting it take its natural vertical size keeps neighbouring
    // elements from re-flowing on each arrival.
    .frame(maxWidth: .infinity, alignment: .leading)
    .fixedSize(horizontal: false, vertical: true)
    .padding(.vertical, 4)
    .onAppear {
      #if DEBUG
        logDebugLifecycle(event: "onAppear")
      #endif
      startAnimationIfNeeded()
    }
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
    .onDisappear {
      #if DEBUG
        logDebugLifecycle(event: "onDisappear")
      #endif
      animationTask?.cancel()
    }
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
    // Why: `.textStyle(_:)` on the concatenated `Text + Text` — uniform
    // lineSpacing/tracking keeps the concat trick stable (see type doc).
    return (Text(visible) + Text(hidden).foregroundStyle(.clear))
      .textStyle(Typography.bodyBubble)
      // Streaming grows `streamingPrimary` token-by-token; SwiftUI would
      // otherwise animate the Text's string change implicitly and the
      // re-laid-out glyphs cross-fade visibly. Keyed on `streamingPrimary`
      // (not `fullText`) so the replay path — where `streamingPrimary`
      // stays nil and the typing-reveal concat trick drives visible
      // changes through `visibleChars` — keeps its default animation
      // behaviour unchanged.
      .animation(nil, value: streamingPrimary)
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
      .textStyle(Typography.thinkingBody)
      .foregroundStyle(Color.muted)
      .thoughtLeftRule()
  }

  /// Tap-to-toggle path (when `showAllThoughts == false`): shows a
  /// `▸ THINKING` / `▾ THINKING` disclosure label; tapping it reveals
  /// the full thought body with a fade/slide transition. Matches
  /// `design-system.md` §5.2 + reference HTML's `.b-inner.collapsed`
  /// / `.b-inner.expanded::before` rules (moss triangle + mono UPPER
  /// tag + muted color). No character-by-character typing — this is
  /// a user action, not narrative.
  @ViewBuilder
  private func buttonToggleThought(fullText: String) -> some View {
    // Two siblings returned as an implicit `TupleView` — the enclosing
    // `thoughtSection` / outer `VStack` in `body` stacks them vertically
    // with the root 6pt spacing. A nested `VStack` would add a spurious
    // layout layer; keeping the two elements as siblings mirrors how
    // `autoThoughtView` composes primary + thought already.
    //
    // `▸` / `▾` triangle tints moss (accent prefix per reference
    // CSS `color: #8a9a6c`); "THINKING" stays muted + Typography
    // `thinkingTag` (8.5pt mono UPPER semibold). Concat preserves
    // per-segment foregroundStyle while sharing font/tracking/case.
    // `thinkingTag.textCase(.uppercase)` is a no-op on the triangle
    // glyphs `▸` / `▾` (Unicode uppercase = identity for arrows), so
    // the accent color is preserved by the per-segment foregroundStyle.
    (Text(showInnerThought ? "▾ " : "▸ ")
      .foregroundStyle(Color.moss)
      + Text("THINKING")
      .foregroundStyle(Color.muted))
      .textStyle(Typography.thinkingTag)
      // Intentionally no `.frame(minHeight: 44)` — the design calls
      // for a visually tight disclosure label, and inflating the tap
      // target added ~17pt of vertical whitespace above and below the
      // 8.5pt glyph. We trade strict iOS HIG compliance (44pt min)
      // for visual density on a secondary affordance; the bubble
      // itself remains non-interactive. `.contentShape` still makes
      // the natural text bounds reliably tappable.
      .contentShape(Rectangle())
      .onTapGesture {
        withAnimation(.easeInOut(duration: 0.2)) {
          showInnerThought.toggle()
        }
      }
      // Tap gesture has no built-in role; advertise the expand /
      // collapse semantic to VoiceOver so the label reads the way
      // a Button would.
      .accessibilityAddTraits(.isButton)
      .accessibilityLabel(showInnerThought ? "Hide thought" : "Show thought")

    if showInnerThought {
      Text(fullText)
        .textStyle(Typography.thinkingBody)
        .foregroundStyle(Color.muted)
        .thoughtLeftRule()
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
  }

  // MARK: - Derived lengths

  /// Total characters the counter should cover: primary plus thought when
  /// thoughts are globally visible. Button-toggle reveal bypasses this.
  var targetLength: Int {
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
    #if DEBUG
      logStreamTargetChange(newTarget: target)
    #endif
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

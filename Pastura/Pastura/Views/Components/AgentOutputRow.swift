// swiftlint:disable file_length
// Intentionally long: the reveal-animation machinery
// (`startAnimationIfNeeded`, `characterAt`, `snapToFull`,
// `handleStreamTargetChange`, `handleThoughtVisibilityChange`) is all
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
/// ## Thought visibility model
///
/// The thought area always carries a `▸ THINKING` / `▾ THINKING` chevron
/// toggle (per design-system.md §5.2). `showAllThoughts` is the **global
/// default** — its current value seeds each row's per-row
/// `showInnerThought` at construction (custom init, `State(initialValue:)`)
/// and re-syncs every row when the user toggles the master switch.
/// Between mode flips the user can fold/unfold any individual row by
/// tapping its chevron. Re-flipping the master switch clobbers all per-row
/// overrides — the strong-coupling choice keeps the mental model simple.
///
/// ## Typing animation
///
/// Only the latest row animates (`isLatest == true` and
/// `charsPerSecond != nil`); older rows render full text immediately. The
/// reveal counter advances through
/// `primaryLength + (showInnerThought ? thoughtLength : 0)` — when the
/// thought is currently visible (auto-default or manual expand), it types
/// right after the statement, no gap, at the same rate. When collapsed,
/// the counter only covers primary; the thought view is hidden by the
/// `if showInnerThought` conditional and any partial reveal carried over
/// from a previous expansion stays in `visibleChars` until the next sync.
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
/// ## Manual chevron tap — cancel-free target sync
///
/// Tapping the chevron mutates `showInnerThought`, which shifts
/// `targetLength`. The `onChange(of: showInnerThought)` handler is
/// **deliberately cancel-free** — it never `cancel()`s the running
/// reveal task. A running task absorbs the new target via its per-tick
/// re-read; when no task is running, `visibleChars` snaps to target so
/// the unhidden thought has revealed content for the `.transition` fade.
/// The cancel-restart pattern was rejected because it re-opens the
/// race surface that #133 / #134 / #147 / #150 hardened — see
/// `handleThoughtVisibilityChange` for the full rationale.
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

  /// Per-row thought visibility. Default `false` only when no init value
  /// is provided; the custom init below seeds this from `showAllThoughts`
  /// so a row constructed in "auto-expand" mode starts expanded, and a
  /// row constructed in "auto-collapse" mode starts collapsed.
  ///
  /// `@State` re-creation (LazyVStack recycle, see `debugInstanceID`)
  /// re-runs the seed, so a recycled row picks up the *current* value of
  /// `showAllThoughts` rather than carrying the previous occupant's
  /// expand state — desirable because the recycled row represents a
  /// different agent / phase.
  @State private var showInnerThought: Bool
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

  /// Custom init kept call-site-compatible with the previous synthesized
  /// memberwise init. Two reasons to write it by hand:
  ///
  ///   1. ``showInnerThought`` is `@State` without a default literal — its
  ///      initial value must be seeded from `showAllThoughts` so the row
  ///      starts expanded/collapsed to match the current global mode.
  ///      `State(initialValue:)` runs at `@State` construction (and
  ///      again on `@State` recreation in LazyVStack recycle), which is
  ///      exactly the lifecycle hook we want — `.onAppear` would fire
  ///      after the first render and contract tests don't render at all.
  ///   2. The contract tests construct ``AgentOutputRow`` directly to
  ///      read `targetLength` without a SwiftUI host. With the seed in
  ///      `init`, those tests see `showInnerThought == showAllThoughts`
  ///      and `targetLength` covers the thought iff `showAllThoughts`
  ///      was passed `true` — preserving the pre-refactor contract.
  init(
    agent: String,
    output: TurnOutput,
    phaseType: PhaseType,
    showAllThoughts: Bool,
    isLatest: Bool = false,
    charsPerSecond: Double? = nil,
    onAnimatingChange: ((Bool) -> Void)? = nil,
    streamingPrimary: String? = nil,
    streamingThought: String? = nil,
    showAvatar: Bool = true,
    agentPosition: Int? = nil,
    debugRowID: String? = nil
  ) {
    self.agent = agent
    self.output = output
    self.phaseType = phaseType
    self.showAllThoughts = showAllThoughts
    self.isLatest = isLatest
    self.charsPerSecond = charsPerSecond
    self.onAnimatingChange = onAnimatingChange
    self.streamingPrimary = streamingPrimary
    self.streamingThought = streamingThought
    self.showAvatar = showAvatar
    self.agentPosition = agentPosition
    self.debugRowID = debugRowID
    self._showInnerThought = State(initialValue: showAllThoughts)
  }

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
    .onChange(of: showAllThoughts) { _, new in
      // (A) strong coupling: the global toggle clobbers per-row state.
      // The chained `onChange(of: showInnerThought)` then fires and
      // runs the cancel-free target sync.
      showInnerThought = new
    }
    .onChange(of: showInnerThought) { _, _ in
      // Fired by both the global mode flip (via the line above) and
      // by per-row chevron tap. See `handleThoughtVisibilityChange`
      // for why this path is deliberately cancel-free.
      handleThoughtVisibilityChange()
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

  /// Single render path for the thought area: chevron toggle is **always**
  /// rendered when a thought exists; the body appears only when the user
  /// (or the `showAllThoughts` seed) has expanded the row. The previous
  /// `if showAllThoughts { auto } else { button }` split was an
  /// implementation accident — design-system.md §5.2 specifies one
  /// `▸ THINKING / ▾ タグ＋本文` structure regardless of mode, and the
  /// dual paths made the affordance disappear in auto mode.
  @ViewBuilder
  private func thoughtSection() -> some View {
    if let thought = resolvedThought, !thought.isEmpty {
      thoughtToggleHeader()
      if showInnerThought {
        thoughtBody(fullText: thought)
      }
    }
  }

  /// `▸ THINKING` / `▾ THINKING` chevron + tag. Tap toggles
  /// ``showInnerThought``; the resulting target shift is absorbed by the
  /// reveal pipeline through ``handleThoughtVisibilityChange`` (cancel-
  /// free — see that method's doc for the rationale).
  ///
  /// Matches `design-system.md` §5.2 + reference HTML
  /// `.b-inner.collapsed` / `.b-inner.expanded::before` (moss triangle
  /// + mono UPPER tag + muted color).
  private func thoughtToggleHeader() -> some View {
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
      // 44pt tap target via the **negative-padding trick**.
      //
      // ⚠️ The `.padding(.vertical, 16)` / `.padding(.vertical, -16)`
      // pair is **load-bearing** — DO NOT collapse to a single
      // `.padding(-16)`, strip both, or wrap an ancestor in
      // `.clipped()` (the glyph renders inside the negative-padding
      // region and would be cut off). Doing any of these breaks
      // either accessibility (HIG 44pt) or visual density (#171).
      //
      // Why this dance, in order of modifier application:
      //   1. `.padding(.vertical, 16)` grows the view's frame to
      //      ~46pt tall (8.5pt glyph + 32pt padding). `.contentShape`
      //      then snapshots THAT enlarged frame as the hit-test
      //      region — so taps anywhere in 46pt vertical resolve here.
      //   2. `.padding(.vertical, -16)` reverses the layout
      //      contribution (SwiftUI accepts negative padding as a
      //      negative size delta to the parent). The parent VStack
      //      sees this view as ~14pt tall, so visual density matches
      //      the design — no whitespace appears around the glyph.
      //
      // Net: hit region ≈ 46pt (HIG 44pt+), visible footprint ≈ 14pt.
      //
      // History: design-system.md §8 calls for 44pt tap targets and
      // explicitly names this THINKING toggle. A previous attempt
      // used `.frame(minHeight: 44)`, which inflated visible
      // whitespace to ~17pt above and below the glyph and was rolled
      // back in #171. The chevron tint stays `Color.moss` (lighter
      // accent) — paired with `Color.muted` for the THINKING text,
      // it mirrors the `BubbleBackground` / `ThoughtLeftRule` palette
      // (moss for prefixes, muted for body). `mossDark` would read
      // as a stronger accent than the design intends here.
      //
      // Sibling overlap: the +16/-16 hit-test region overlaps the
      // primary bubble above by ~10pt and the revealed thought below
      // (when `showInnerThought == true`) by ~10pt. Both siblings are
      // non-interactive `Text` — no tap theft. The bottom overlap
      // means tapping near the thought's top edge collapses it,
      // which is the intended affordance.
      //
      // VoiceOver caveat: the accessibility frame is the *visible*
      // ~14pt frame, not the 46pt hit area. The focus highlight is
      // small but the trait + label still announce correctly.
      .padding(.vertical, 16)
      .contentShape(Rectangle())
      .onTapGesture {
        withAnimation(.easeInOut(duration: 0.2)) {
          showInnerThought.toggle()
        }
      }
      .padding(.vertical, -16)
      // Tap gesture has no built-in role; advertise the expand /
      // collapse semantic to VoiceOver so the label reads the way
      // a Button would.
      .accessibilityAddTraits(.isButton)
      .accessibilityLabel(showInnerThought ? "Hide thought" : "Show thought")
  }

  /// Thought body — pre-measured concat driven by the unified reveal
  /// counter. When the row is mid-typing (latest, streaming, or auto-
  /// expanded on appear), characters surface as the loop advances. When
  /// not animating (older row, or post-completion manual expand), the
  /// `.onChange(of: showInnerThought)` handler snaps `visibleChars` to
  /// target so the body has revealed content for the
  /// `.transition(.opacity.combined(with: .move(edge: .top)))` fade.
  private func thoughtBody(fullText: String) -> some View {
    let primaryLen = (primaryText?.count ?? 0)
    let thoughtRevealed = max(0, min(visibleChars - primaryLen, fullText.count))
    let splitIdx = fullText.index(fullText.startIndex, offsetBy: thoughtRevealed)
    let visible = fullText[..<splitIdx]
    let hidden = fullText[splitIdx...]
    return (Text(visible) + Text(hidden).foregroundStyle(.clear))
      .textStyle(Typography.thinkingBody)
      .foregroundStyle(Color.muted)
      .thoughtLeftRule()
      .transition(.opacity.combined(with: .move(edge: .top)))
  }

  // MARK: - Derived lengths

  /// Total characters the counter should cover: primary plus thought when
  /// the thought is currently visible. Driven by ``showInnerThought``
  /// (per-row, seeded from `showAllThoughts` at init), so manual chevron
  /// taps grow / shrink the target the same way a global mode flip does.
  /// The reveal task re-reads this every tick, so target growth during
  /// active typing extends the reveal in place; growth between taps with
  /// no task running is handled by ``handleThoughtVisibilityChange``.
  var targetLength: Int {
    let primary = primaryText?.count ?? 0
    let thought = showInnerThought ? (resolvedThought?.count ?? 0) : 0
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
      // every tick. `targetLength` covers any mid-typing thought-
      // visibility flip — both global mode toggle (`showAllThoughts`)
      // and per-row chevron tap mutate ``showInnerThought``, which
      // shifts target. The other two cover live streaming growth:
      // under ``streamingPrimary`` / ``streamingThought``, those
      // values grow token-by-token, and a one-shot capture at task
      // creation would leave punctuation lookup and the
      // statement→thought boundary check running against stale text.
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

  /// React to a thought-visibility flip — fired both by global mode
  /// toggle (`onChange(of: showAllThoughts)` syncs the per-row state)
  /// and by per-row chevron tap (`onChange(of: showInnerThought)`).
  ///
  /// **Cancel-free by design.** Manual chevron taps must not enter the
  /// `cancel() + startAnimationIfNeeded()` path that the previous
  /// `handleShowAllThoughtsChange` used — that re-opens the cancel-race
  /// surface that `animationGeneration` and the `onAnimatingChange`
  /// generation gate were introduced to close (#133 / #134 / #147 /
  /// #150). The race symptom: a chevron tap during streaming would
  /// `cancel()` the running reveal, the new task would
  /// `start` a frame later, and the gap would leave
  /// `latestRowIsAnimating` flickering false→true→false — breaking
  /// SimulationView's thinking-indicator + scroll-to-bottom gating.
  ///
  /// What this method actually does, in three cases:
  ///
  ///   - `!shouldAnimate` (older replay row): snap `visibleChars` to
  ///     the new target. There is no task to coordinate with; the
  ///     rendered text just jumps to the new bound.
  ///   - `visibleChars >= target` (target shrank, e.g. user collapsed):
  ///     no-op. The running loop's `while visibleChars < targetLength`
  ///     condition stops it on the next iteration; the now-hidden
  ///     thought view is removed by the `if showInnerThought`
  ///     conditional in `thoughtSection()`. The dangling
  ///     `visibleChars > targetLength` is harmless — primary uses
  ///     `min(visibleChars, primaryLen)` and the body view is gone.
  ///   - `visibleChars < target` (target grew, expand path):
  ///       * task running → no-op; the loop reads the new target on
  ///         its next tick and types into the thought naturally.
  ///       * no task → snap `visibleChars = target` so the unhidden
  ///         body has revealed content for the `.transition` fade.
  ///         Restarting the task here would slow-type the thought
  ///         after a deliberate user tap, which is a UX regression
  ///         vs reference HTML's instant `.b-inner.expanded` semantics
  ///         (and matches how the previous button-toggle path felt).
  ///
  /// Sibling `handleStreamTargetChange` *does* restart on no-task +
  /// growth — that's correct for streaming (continued narrative reveal)
  /// but wrong here (deliberate user gesture wants instant response).
  /// The shape similarity is intentional but the no-task branches
  /// **must not** be unified.
  private func handleThoughtVisibilityChange() {
    let target = targetLength
    if !shouldAnimate {
      visibleChars = target
      return
    }
    if visibleChars >= target {
      // Collapse / over-revealed — let the loop's while-condition end
      // it naturally. Don't cancel: that's the cancel-race surface.
      return
    }
    // Expand path. Task running → loop absorbs growth. No task →
    // instant snap (UX: deliberate tap = immediate, not slow-type).
    if animationTask == nil || animationTask?.isCancelled == true {
      visibleChars = target
    }
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

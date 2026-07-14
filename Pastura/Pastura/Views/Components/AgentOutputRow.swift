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
/// **Replay path (non-streaming), default:** primary text is rendered as
/// `Text(visible) + Text(hidden).foregroundStyle(.clear)` so the full string
/// is laid out from the first frame. This keeps line-wrap positions from
/// shifting as characters appear and lets the parent `ScrollViewReader`
/// land its single `scrollTo(last.id)` correctly without per-character
/// follow-up scrolls. This is the default for Sim committed rows, Results,
/// and past-log replay.
///
/// **Replay path with ``growsWithReveal`` (demo opt-in):** the DL-time demo
/// host opts into a *growing* bubble — it drops the hidden `.clear` tail so
/// the bubble lays out only the visible prefix and grows as characters
/// surface (``shouldReserveHiddenTail`` is then `false`). This deliberately
/// **reverses** the reflow-stable choice above for the demo screen so its
/// playback feels like Sim's live token stream rather than a pre-sized
/// placeholder (#785). Two consequences, both accepted and confined to the
/// demo: (1) line wraps can reposition as the text grows — geometrically
/// identical to Sim's streaming path, which already lives with this; and
/// (2) the single-`scrollTo` guarantee is replaced by per-tick follow via
/// ``onRevealProgress`` (the demo host re-anchors on each reveal). The flag
/// folds in ``shouldAnimate``, so non-latest / `.instant` demo rows still
/// reserve the full layout (no growth) and stay visually unchanged. Sim /
/// Results / past-log never pass the flag, so their reflow-stable rendering
/// is untouched.
///
/// The thought section (`▸ THINKING` chevron + optional body) is the one
/// intentional exception: it is gated on
/// ``shouldRevealThoughtSection(visibleChars:)`` so it appears only after
/// the primary reveal counter catches up to the primary buffer length,
/// matching Sim's live-streaming behavior where `streamingThought` is
/// empty until the LLM emits the `inner_thought` key. This is a single
/// discrete height delta at chevron pop-in, not per-token growth, so the
/// parent's item-count-driven anchor remains correct in practice. See the
/// helper's doc-comment for the full rationale.
///
/// **Streaming path:** the live Sim in-flight row opts into
/// ``growsWithReveal`` so the bubble lays out only the visible prefix and
/// grows with the reveal counter — NOT the streaming buffer. This matters
/// because the reveal types at ``PlaybackSpeed/charsPerSecond`` (slower
/// than tokens arrive); reserving the hidden tail to the buffer made the
/// bubble expand ahead of the typed text. Width stability is still carried
/// by `.frame(maxWidth: .infinity, alignment: .leading)` +
/// `.fixedSize(horizontal: false, vertical: true)`, and the primary text is
/// tagged `.animation(nil, value: streamingPrimary)` to suppress SwiftUI's
/// implicit animation on string growth (applied unconditionally). The parent
/// follows the per-tick vertical growth via ``onRevealProgress`` (same as the
/// demo grow path), since the streaming-snapshot change alone fires only per
/// token — too coarse once the reveal is mid-character or catching up after
/// the buffer is complete.
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
  /// Invoked on every reveal-counter tick (`visibleChars` advance) while
  /// this row is typing. Unlike ``onAnimatingChange`` (which fires only at
  /// the start / end boundaries), this fires continuously through the
  /// reveal so a parent can follow the row's *growth* — e.g. keep the
  /// newest text scrolled into view while the bubble grows under
  /// ``growsWithReveal``. Used by both grow-path callers: the demo replay
  /// host and the live Sim streaming row. (The streaming-snapshot change
  /// `SimulationView` also observes fires only per token, so it is too coarse
  /// to follow per-character growth — or any growth after the buffer is
  /// complete but the reveal is still catching up.)
  var onRevealProgress: (() -> Void)?

  /// Invoked ONCE when the typewriter reveal reaches the full target length by
  /// running to completion — NOT when it is cancelled mid-reveal (early unmount)
  /// or snaps to full without animating. The live Sim latest row wires this so
  /// ``SimulationViewModel`` can record that the row finished revealing, so a
  /// later View re-projection (ADR-017 Phase B adopt / keep-running return)
  /// renders it static instead of re-typing (#934). Fired from the animation
  /// `Task` after its loop exits un-cancelled — deliberately NOT from the
  /// `defer` (which also runs on cancellation).
  var onRevealCompleted: (() -> Void)?

  /// Invoked on every reveal-counter tick with the current `visibleChars`.
  /// The **live Sim streaming row** passes this so ``SimulationViewModel``
  /// can record the reveal position and hand it off to the committed row at
  /// commit (reveal-position handoff, bug 2 — see
  /// ``SimulationViewModel/reportStreamingReveal(_:)``). Separate from
  /// ``onRevealProgress`` (a count-free scroll-follow signal) so the demo
  /// replay call site is untouched. Default `nil` — only the streaming row
  /// wires it.
  var onStreamingRevealProgress: ((Int) -> Void)?

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

  /// Opt-in: render the primary bubble (and thought body) sized to the
  /// *visible* prefix so it grows as characters surface, instead of the
  /// default reflow-stable concat that reserves the full layout from frame
  /// one. Used only by the DL-time demo host to mirror Sim's streaming feel
  /// (#785). Folds in ``shouldAnimate`` via ``shouldReserveHiddenTail``, so
  /// it has no effect on non-animating rows. See the type doc-comment
  /// §"Reflow-stable rendering" for the trade-off.
  var growsWithReveal: Bool = false

  /// Reveal-handoff seed: the `visibleChars` position to start the reveal
  /// from instead of `0`. Set by the live Sim committed row to the position
  /// its streaming row reached at commit (``SimulationViewModel/handoffSeed(forEntryId:)``),
  /// so the row continues typing the unrevealed tail / `inner_thought`
  /// rather than re-typing from the start or snapping to full (bug 2). Seeded
  /// into the `visibleChars` `@State` at init (clamped to ``targetLength``)
  /// so the first frame already shows the streamed prefix — no flicker. A
  /// filter-shrunk committed primary can push the seed into the thought
  /// region (early thought reveal); accepted (rare) — see the commit-site
  /// note in ``SimulationViewModel``. Default `0`: animate from the start.
  var initialVisibleChars: Int = 0

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

  /// Invoked with the agent's display name when the user taps this row's
  /// avatar or name to inspect the agent's persona. `nil` (default) keeps
  /// the avatar + name **decorative and non-interactive** — the pre-existing
  /// behavior for every call site that does not opt in. The three chat
  /// surfaces pass it only when a persona is actually resolvable (Past
  /// Results degrades to `nil` for pre-snapshot / unparseable runs). When
  /// non-nil: the avatar becomes a **sighted-only** tap target (it stays
  /// `.accessibilityHidden` — identity is carried by the name, and
  /// `SheepAvatar`'s color-slot label must not surface as a button), and the
  /// name `Text` gains a VoiceOver `.isButton` action, so both pointer and
  /// assistive users reach the persona sheet. Tap handling is attached to the
  /// leaf avatar / name views only — never by wrapping the row in a container
  /// (that would flush the load-bearing `@State`; see the `body` note).
  var onAvatarTap: ((String) -> Void)?

  /// Invoked when the user picks "Share as Card" from the row's context menu
  /// (#1070). `nil` (default) omits the menu entirely, so rows without a share
  /// handler carry no long-press affordance.
  var onShareHighlight: (() -> Void)?

  /// Playback-park probe. `nil` (default) = zero impact; a non-nil closure is
  /// evaluated once per reveal tick and, while it returns `true`, the reveal
  /// loop spins in place without advancing ``visibleChars`` — used to freeze
  /// the typewriter while the persona sheet is up (#942 PR2).
  ///
  /// **Closure form is load-bearing** — a *stored* `Bool` would be captured in
  /// the reveal `Task`'s struct snapshot at creation and freeze at its
  /// creation-time value. The closure dereferences the reference-type host VM
  /// for a live per-tick read, mirroring the ``targetLength`` re-read rationale
  /// on ``startAnimationIfNeeded``. Cancel-free and never nils `charsPerSecond`,
  /// so it does not reopen the #133 / #134 / #147 / #150 cancel-race surface.
  var isTypingParked: (() -> Bool)?

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
    onRevealProgress: (() -> Void)? = nil,
    onRevealCompleted: (() -> Void)? = nil,
    onStreamingRevealProgress: ((Int) -> Void)? = nil,
    streamingPrimary: String? = nil,
    streamingThought: String? = nil,
    growsWithReveal: Bool = false,
    initialVisibleChars: Int = 0,
    showAvatar: Bool = true,
    agentPosition: Int? = nil,
    debugRowID: String? = nil,
    onAvatarTap: ((String) -> Void)? = nil,
    onShareHighlight: (() -> Void)? = nil,
    isTypingParked: (() -> Bool)? = nil
  ) {
    self.agent = agent
    self.output = output
    self.phaseType = phaseType
    self.showAllThoughts = showAllThoughts
    self.isLatest = isLatest
    self.charsPerSecond = charsPerSecond
    self.onAnimatingChange = onAnimatingChange
    self.onRevealProgress = onRevealProgress
    self.onRevealCompleted = onRevealCompleted
    self.onStreamingRevealProgress = onStreamingRevealProgress
    self.streamingPrimary = streamingPrimary
    self.streamingThought = streamingThought
    self.growsWithReveal = growsWithReveal
    self.initialVisibleChars = initialVisibleChars
    self.showAvatar = showAvatar
    self.agentPosition = agentPosition
    self.debugRowID = debugRowID
    self.onAvatarTap = onAvatarTap
    self.onShareHighlight = onShareHighlight
    self.isTypingParked = isTypingParked
    self._showInnerThought = State(initialValue: showAllThoughts)
    // Seed the reveal counter from the handoff position so the first frame
    // already shows the streamed prefix (no 0→seed flicker). `showInnerThought`
    // is seeded from `showAllThoughts` above, so the target matches the body's
    // initial render. Clamp keeps an over-long seed (filter-shrunk committed
    // primary) from exceeding the reveal length. See ``revealTargetLength``.
    self._visibleChars = State(
      initialValue: Self.clampedInitialVisibleChars(
        initialVisibleChars,
        targetLength: Self.revealTargetLength(
          output: output, phaseType: phaseType,
          streamingPrimary: streamingPrimary, streamingThought: streamingThought,
          showInnerThought: showAllThoughts)))
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
        avatarColumn
      }
      VStack(alignment: .leading, spacing: 6) {
        // Agent name + phase. Caption size + ink-secondary matches
        // `design-system.md` §3.2 `caption/name` and reference HTML
        // `.b-name { font-size: 10.5px; color: #7a7e68 }`.
        HStack(alignment: .firstTextBaseline) {
          nameLabel
          PhaseTypeLabel(phaseType: phaseType)
          Spacer()
        }

        // Whisper (密談) pair-attribution header: "speaker → partner"
        // (#908 PR2). The PR1 `PhaseTypeLabel(.whisper)` badge already
        // carries the whisper glyph, so this line is iconless and only
        // names the recipient. Absent during streaming (`whisper_to`
        // arrives on the committed `.agentOutput`), so it pops in at
        // commit — a one-shot height delta strictly outside the reveal
        // path, never re-typed.
        if let attribution = whisperAttribution {
          Text(attribution)
            .textStyle(Typography.captionName)
            .foregroundStyle(Color.mossDark)
        }

        // Primary text — pre-measured concat so line wraps don't shift.
        // Bubble background applied here (not around the whole row) so
        // the tail-corner shape hugs the text, not the name/avatar.
        // Whisper rows get the hushed `whisperBubble` fill; the tint is
        // gated on the phase alone (not `whisper_to`) so streaming whisper
        // rows are already tinted before the partner name arrives.
        if let text = primaryText {
          primaryView(fullText: text)
            .bubbleBackground(fill: isWhisperPhase ? .whisperBubble : .bubbleBackground)
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
      // Visible share affordance (#1080). Placed as an overlay OUTSIDE the
      // `.firstTextBaseline` name row so its 44pt hit target never inflates
      // the name/phase baseline; pinned top-trailing where the name row's
      // trailing edge is empty (the `Spacer` above).
      .overlay(alignment: .topTrailing) {
        if let onShareHighlight {
          shareButton(action: onShareHighlight)
        }
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
    .modifier(HighlightShareContextMenu(action: onShareHighlight))
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
    // Growth signal for parents that follow the reveal (e.g. the demo host
    // keeps the newest text scrolled into view while a ``growsWithReveal``
    // bubble grows). Fires on every counter tick; only meaningful while
    // animating — older rows snap `visibleChars` once and never advance.
    .onChange(of: visibleChars) { _, newValue in
      onRevealProgress?()
      // Report the position so the live Sim can hand it off at commit (bug 2).
      onStreamingRevealProgress?(newValue)
    }
    .onDisappear {
      #if DEBUG
        logDebugLifecycle(event: "onDisappear")
      #endif
      animationTask?.cancel()
    }
  }

  // MARK: - Subviews

  /// Visible per-row share affordance (#1080): a quiet share glyph that
  /// triggers the same "Share as Card" action as the long-press
  /// ``HighlightShareContextMenu`` — the long-press alone was undiscoverable.
  /// A **direct button** (not a `•••` menu) because share is the only per-row
  /// action today: burying a sole action behind a menu costs a needless extra
  /// tap (HIG). If more per-row actions arrive, switch this to a `Menu`
  /// rendering ``highlightShareMenuItems``. Rendered only when `onShareHighlight`
  /// is non-nil (same nil-omission as the context menu — appears on committed
  /// Sim + Results rows, not the streaming in-flight row nor the DL-demo replay).
  ///
  /// `.buttonStyle(.borderless)` isolates the tap so it doesn't activate the
  /// enclosing row inside a `List`/`LazyVStack`, and the `.contentShape` on a
  /// 44pt-wide, trailing-aligned label gives a HIG hit target while the glyph
  /// stays pinned to the corner. The INNER VOICE expand chevron lives far
  /// below-left, so the two hit regions don't collide.
  @ViewBuilder
  private func shareButton(action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: "square.and.arrow.up")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color.muted)
        .frame(width: 44, height: 28, alignment: .trailing)
        .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .accessibilityLabel(String(localized: "Share as Card"))
  }

  /// Renders the primary text. Default: the concat trick so the final
  /// layout is established on first frame and the revealed prefix grows in
  /// place. Under ``growsWithReveal`` on an animating row
  /// (``shouldReserveHiddenTail`` == false), the hidden tail is dropped so
  /// the bubble grows with the visible prefix — see type doc-comment
  /// §"Reflow-stable rendering".
  private func primaryView(fullText: String) -> some View {
    let primaryLen = fullText.count
    let revealed = min(visibleChars, primaryLen)
    let splitIdx = fullText.index(fullText.startIndex, offsetBy: revealed)
    let visible = fullText[..<splitIdx]
    let hidden = fullText[splitIdx...]
    let tail = shouldReserveHiddenTail ? Text(hidden).foregroundStyle(.clear) : Text("")
    // Why: `.textStyle(_:)` on the concatenated `Text + Text` — uniform
    // lineSpacing/tracking keeps the concat trick stable (see type doc).
    return (Text(visible) + tail)
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

  /// Single render path for the thought area: chevron toggle is rendered
  /// when a thought exists **and** primary reveal has completed; the body
  /// appears only when the user (or the `showAllThoughts` seed) has
  /// expanded the row. The previous `if showAllThoughts { auto } else
  /// { button }` split was an implementation accident — design-system.md
  /// §5.2 specifies one `▸ THINKING / ▾ タグ＋本文` structure regardless of
  /// mode, and the dual paths made the affordance disappear in auto mode.
  ///
  /// The primary-reveal gate (``shouldRevealThoughtSection(visibleChars:)``)
  /// matches Sim's live-streaming two-phase behavior on replay paths
  /// (DL Demo, Results, past-log replay), where `resolvedThought` is a
  /// fully-known string from frame 1 and the chevron would otherwise
  /// pop in while primary is still typing.
  @ViewBuilder
  private func thoughtSection() -> some View {
    if shouldRevealThoughtSection(visibleChars: visibleChars),
      let thought = resolvedThought {
      thoughtToggleHeader()
      if showInnerThought {
        thoughtBody(fullText: thought)
      }
    }
  }

  /// Whether the `▸ THINKING` chevron + optional body should render at
  /// the given reveal counter.
  ///
  /// Pure over `(shouldAnimate, resolvedThought presence, primaryText
  /// length, visibleChars)` so ``AgentOutputRowContractTests`` can
  /// exercise the gate across the animating / non-animating split
  /// without a SwiftUI host. The `@ViewBuilder` body in
  /// ``thoughtSection()`` reads its own `@State visibleChars`; tests
  /// pass the value explicitly.
  ///
  /// **Why a gate at all:** the Sim path naturally suppresses the chevron
  /// until primary completes because `streamingThought` is empty until the
  /// LLM emits the `inner_thought` key. Replay paths (DL Demo, Results,
  /// past logs) fall back to `output.innerThought` — a fully-known
  /// string — so without this gate the chevron would render from frame 1
  /// while primary is still typing in. The counter-driven gate unifies
  /// behavior across all four call sites: chevron appears at the moment
  /// the reveal counter reaches the primary buffer length, regardless of
  /// whether thought content is streaming or pre-known.
  ///
  /// **Non-animating rows short-circuit to `true`.** Older rows,
  /// `ResultDetailView` turnRow, and any row with `!shouldAnimate` snap
  /// `visibleChars` to target inside `.onAppear` — but the first body
  /// pass runs before `.onAppear` with `visibleChars == 0`, which would
  /// hide the chevron for one frame and produce a visible flicker on
  /// row mount. Suppressing the gate in this case keeps non-animating
  /// rows visually identical to the pre-fix behavior.
  ///
  /// **Gate scope is chevron presence only.** Body visibility (the
  /// thought text itself) is driven independently by `showInnerThought`
  /// inside ``thoughtSection()`` — `showInnerThought` MUST NOT be folded
  /// into this gate, or manual chevron taps in collapsed mode would
  /// nuke chevron presence too.
  func shouldRevealThoughtSection(visibleChars: Int) -> Bool {
    guard let thought = resolvedThought, !thought.isEmpty else { return false }
    if !shouldAnimate { return true }
    return visibleChars >= (primaryText?.count ?? 0)
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
    (Text(verbatim: showInnerThought ? "▾ " : "▸ ")
      .foregroundStyle(Color.moss)
      + Text(String(localized: "INNER VOICE"))
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
      .accessibilityLabel(
        Self.thoughtToggleAccessibilityLabel(showInnerThought: showInnerThought))
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
    // Same grow-vs-reserve choice as `primaryView` so the thought body grows
    // with the demo opt-in instead of pre-sizing to the full thought height.
    let tail = shouldReserveHiddenTail ? Text(hidden).foregroundStyle(.clear) : Text("")
    return (Text(visible) + tail)
      .textStyle(Typography.thinkingBody)
      .foregroundStyle(Color.muted)
      .thoughtLeftRule()
      .transition(.opacity.combined(with: .move(edge: .top)))
  }

  // Pure helpers (VoiceOver label) + derived lengths (`targetLength`,
  // `shouldAnimate`, `shouldReserveHiddenTail`) live in the same-file
  // `extension AgentOutputRow` at the bottom — extracted out of the struct
  // body to stay under swiftlint's `type_body_length` cap while remaining
  // unit-test reachable per ADR-009.

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

}

// MARK: - Pure helpers + derived lengths
//
// Extracted from the struct body (same file, so `private` members stay
// reachable) to keep `AgentOutputRow` under swiftlint's `type_body_length`
// cap. These are the unit-test-reachable pure-logic surface per ADR-009 —
// `AgentOutputRowContractTests` exercises them without a SwiftUI host.
extension AgentOutputRow {

  /// Extracts the primary display text.
  ///
  /// Live streaming rows pass ``streamingPrimary``; this takes precedence
  /// over the phase-derived value from `output` so the partial LLM
  /// output grows in place instead of materialising from the final
  /// parsed fields. Completed rows (no streaming override) fall through
  /// to ``TurnOutput/primaryText(for:)`` — the canonical per-phase
  /// extraction, keyed by ``ScenarioConventions``.
  var primaryText: String? {
    // Decorate the streamed value with the same phase affordance the
    // committed path applies (vote → `→ <voted>`), so the arrow is present
    // from the first reveal tick instead of popping in at commit (#609).
    if let streamingPrimary {
      return ScenarioConventions.decoratePrimary(streamingPrimary, for: phaseType)
    }
    return output.primaryText(for: phaseType)
  }

  /// Private-thought text for the THINKING section, honouring the streaming
  /// override when present.
  ///
  /// Falls back to the phase's private-thought field via
  /// ``TurnOutput/secondaryText(for:)`` — `reason` for `.vote`,
  /// `inner_thought` otherwise — so a vote's reason is surfaced in THINKING
  /// rather than inline (#609). The streaming override already carries the
  /// phase-appropriate field (``LLMCaller`` feeds the schema-derived thought
  /// key to ``PartialOutputExtractor``), so live + committed stay consistent.
  var resolvedThought: String? {
    streamingThought ?? output.secondaryText(for: phaseType)
  }

  /// True for whisper (密談) rows — drives the hushed `whisperBubble` fill.
  /// Gated on the phase alone (not the partner name) so a streaming whisper
  /// row is tinted before `whisper_to` arrives at commit (#908 PR2).
  var isWhisperPhase: Bool { phaseType == .whisper }

  /// Pair-attribution header text for a whisper row (`"speaker → partner"`),
  /// or `nil` when this isn't a whisper row / the partner is absent — the
  /// caller then renders no header and falls back to the plain name row.
  var whisperAttribution: String? {
    Self.whisperAttribution(phaseType: phaseType, speaker: agent, fields: output.fields)
  }

  /// Pure resolver for the whisper pair-attribution header. Returns `nil`
  /// unless the row is a whisper AND the reserved `whisper_to` field holds a
  /// non-blank partner name — streaming rows carry no `whisper_to` yet, and a
  /// malformed / blocklist-redacted commit could blank it, so both fall back
  /// to the iconless plain row rather than rendering a dangling `"speaker → "`.
  /// Extracted for `AgentOutputRowContractTests` (ADR-009 pure-logic surface).
  static func whisperAttribution(
    phaseType: PhaseType, speaker: String, fields: [String: String]
  ) -> String? {
    guard phaseType == .whisper else { return nil }
    let partner = (fields["whisper_to"] ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !partner.isEmpty else { return nil }
    return String(format: String(localized: "%@ → %@"), speaker, partner)
  }

  /// Per-row thought-toggle VoiceOver label. Singular form, intentionally
  /// distinct from the global toggle's plural "Hide / Show all thoughts"
  /// (`ThoughtVisibilityToggle.accessibilityLabel(for:)`) so a screen-reader
  /// user can tell whether the next tap collapses just this row or every
  /// row on screen.
  static func thoughtToggleAccessibilityLabel(showInnerThought: Bool) -> String {
    showInnerThought
      ? String(localized: "Hide thought")
      : String(localized: "Show thought")
  }

  /// Total characters the counter should cover: primary plus thought when
  /// the thought is currently visible. Driven by ``showInnerThought``
  /// (per-row, seeded from `showAllThoughts` at init), so manual chevron
  /// taps grow / shrink the target the same way a global mode flip does.
  /// The reveal task re-reads this every tick, so target growth during
  /// active typing extends the reveal in place; growth between taps with
  /// no task running is handled by ``handleThoughtVisibilityChange``.
  var targetLength: Int {
    Self.revealTargetLength(
      output: output, phaseType: phaseType,
      streamingPrimary: streamingPrimary, streamingThought: streamingThought,
      showInnerThought: showInnerThought)
  }

  /// Pure form of ``targetLength`` over raw inputs, so `init` can size the
  /// reveal-handoff seed clamp before `self` is available (and the two can
  /// never drift — the instance property delegates here). Mirrors
  /// ``primaryText`` / ``resolvedThought``: the streaming overrides win, the
  /// vote arrow is applied to the primary, and the thought counts only when
  /// shown.
  static func revealTargetLength(
    output: TurnOutput, phaseType: PhaseType,
    streamingPrimary: String?, streamingThought: String?, showInnerThought: Bool
  ) -> Int {
    let primary =
      (streamingPrimary.map { ScenarioConventions.decoratePrimary($0, for: phaseType) }
      ?? output.primaryText(for: phaseType))?.count ?? 0
    let thought =
      showInnerThought
      ? ((streamingThought ?? output.secondaryText(for: phaseType))?.count ?? 0) : 0
    return primary + thought
  }

  /// Clamp a reveal-handoff seed to `[0, targetLength]`. Seeds below zero
  /// (none expected) start at the beginning; a seed past the row's reveal
  /// length (e.g. a filter-shrunk committed primary vs. a longer streamed
  /// one) clamps to fully-revealed rather than overshooting the counter.
  static func clampedInitialVisibleChars(_ seed: Int, targetLength: Int) -> Int {
    min(max(0, seed), max(0, targetLength))
  }

  /// Returns the character at `index` in `text`, or nil if out of range.
  /// O(index) because Swift's `String.Index` is not a constant-time offset,
  /// but tolerable here (typical outputs are a few hundred chars).
  func characterAt(index: Int, in text: String) -> Character? {
    guard index >= 0, index < text.count else { return nil }
    return text[text.index(text.startIndex, offsetBy: index)]
  }

  /// Cancel any in-flight reveal and jump straight to the full text.
  func snapToFull() {
    animationTask?.cancel()
    visibleChars = targetLength
  }

  // MARK: - Reveal animation state machine

  /// Kick off (or restart) the character-reveal task. The task re-reads
  /// `targetLength`, `primaryText`, and `resolvedThought` every tick so it
  /// absorbs mid-typing thought-visibility flips and live streaming growth
  /// without a cancel/restart (the cancel-race surface #133 / #134 / #147 /
  /// #150 was introduced to close). Lives in this same-file extension —
  /// alongside ``snapToFull`` — to keep the primary struct body under
  /// swiftlint's `type_body_length` cap while retaining `private`-member
  /// access (a sibling *file* would not).
  private func startAnimationIfNeeded() {
    let target = targetLength
    guard shouldAnimate, let cps = charsPerSecond, cps > 0 else {
      // Not animating (non-latest row OR instant speed) — snap to full. The row
      // IS fully revealed at this instant, so signal completion too: the
      // animated loop's `onRevealCompleted` (below) never runs on this path, and
      // the completion chrome must not wait on a callback that will never come.
      // Idempotent, and the SimulationView closure guards `if isLatest`, so a
      // non-latest / history snap is a safe no-op.
      visibleChars = target
      onRevealCompleted?()
      return
    }
    if visibleChars >= target {
      // Seeded already fully-revealed (e.g. a streamed prefix that covered the
      // whole row by commit) — same reasoning as the snap branch: no loop runs,
      // so signal completion here rather than never.
      onRevealCompleted?()
      return
    }

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
        // Park gate: freeze the typewriter in place while the persona
        // sheet holds playback (#942 PR2), resuming exactly where it
        // stopped. Cancellation while parked is caught by the existing
        // post-sleep `Task.isCancelled` guard below (a cancelled sleep
        // throws immediately), so this stays branch-free for complexity.
        await awaitUnparked()
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
      // Natural completion: the loop exited because the reveal reached the
      // target, NOT via a cancellation `return` above. Record it so a later
      // View re-projection (ADR-017 Phase B adopt) renders this row static
      // instead of re-typing (#934). Deliberately here, not in the `defer` —
      // the `defer` also runs on the cancellation paths.
      if !Task.isCancelled && visibleChars >= targetLength {
        onRevealCompleted?()
      }
    }
  }

  /// Spin (without advancing ``visibleChars``) while the host holds playback
  /// via ``isTypingParked``. The closure is re-evaluated per poll so a live
  /// host-VM flip is observed mid-reveal (a stored `Bool` would freeze in the
  /// task's struct snapshot). Returns on unpark *or* cancellation — the caller
  /// re-checks `Task.isCancelled` after its next sleep. #942 PR2.
  ///
  /// The 50 ms poll here mirrors the Layer-B consume-loop gates
  /// `SimulationViewModel.awaitPlaybackUnheld()` and
  /// `ReplayViewModel.awaitPlaybackUnheld()` — keep the interval in step if
  /// tuning one (they span the Views/ and App/ layers, so no shared constant).
  private func awaitUnparked() async {
    while (isTypingParked?() ?? false) && !Task.isCancelled {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }
  }

  /// Whether this row should run the character-reveal animation. The
  /// live-streaming path (``streamingPrimary`` / ``streamingThought``
  /// non-nil) always animates — the parent grows those values as tokens
  /// arrive, and the reveal loop re-reads the target each tick so the
  /// display tracks the incoming stream at `charsPerSecond`. The replay
  /// path (no streaming override) only animates when this is the latest
  /// row, matching past-results playback.
  var shouldAnimate: Bool {
    guard charsPerSecond != nil else { return false }
    return isLatest || streamingPrimary != nil || streamingThought != nil
  }

  /// Whether `primaryView` / `thoughtBody` keep the hidden `.clear` tail
  /// that reserves the full layout from frame one (reflow-stable rendering).
  ///
  /// `true` (default); `false` only when ``growsWithReveal`` is set AND the
  /// row is animating (``shouldAnimate``) — then the tail is dropped so the
  /// bubble grows with the visible prefix instead of pre-reserving the full
  /// (or, for a streaming row, the *buffer*) height. Two opt-in callers:
  /// the DL-time demo replay rows (#785) and the **live Sim streaming row**
  /// (its reveal types at ``PlaybackSpeed/charsPerSecond`` — slower than
  /// tokens arrive — so reserving to the streaming buffer made the bubble
  /// outrun the typed text; the demo-proven grow path keeps box and text in
  /// step). Both grow callers pass ``onRevealProgress`` for per-tick
  /// scroll-follow, required once the bubble grows between (or after) token
  /// arrivals.
  ///
  /// Folding in ``shouldAnimate`` keeps non-latest / `.instant` rows
  /// reserving the full layout (their `visibleChars` is snapped to target, so
  /// the tail is empty anyway — the guard makes the no-growth intent
  /// explicit). Internal for ``AgentOutputRowContractTests``.
  var shouldReserveHiddenTail: Bool {
    !(growsWithReveal && shouldAnimate)
  }
}

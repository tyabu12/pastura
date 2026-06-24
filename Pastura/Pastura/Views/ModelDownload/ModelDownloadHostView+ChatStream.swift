import SwiftUI

// Demo-replay chat-stream rendering, split out of `ModelDownloadHostView`
// so the host stays under swiftlint's 400-line `file_length` cap. The host
// owns lifecycle / state-dispatch; this extension owns the scrolling
// message list, its scroll-follow wiring, and the bottom PromoCard inset.
extension ModelDownloadHostView {

  func chatStream(viewModel: ReplayViewModel) -> some View {
    VStack(spacing: 0) {
      gameHeader(viewModel: viewModel)

      ScrollViewReader { proxy in
        ScrollView {
          // `spacing` uses the ChatBubbleLayout.bubbleSpacing token so a
          // future design-system tweak flows through Demo / Sim / Results
          // in one place. Production value is 8pt project-wide (#273 PR 2);
          // see the token's docstring for the historical 14pt prototype
          // reference and the divergence rationale.
          LazyVStack(alignment: .leading, spacing: ChatBubbleLayout.bubbleSpacing) {
            // `isLatest` keys off the last agent output, not the last
            // chatItem (#208), so a `.demoBoundary` does not retrigger
            // the typing animation on the bubble that precedes it.
            let lastAgentId = viewModel.agentOutputs.last?.id
            ForEach(viewModel.chatItems) { item in
              switch item {
              case .agentOutput(let entry):
                demoAgentRow(
                  entry, lastAgentId: lastAgentId, proxy: proxy, viewModel: viewModel)
              case .demoBoundary(let id, let scenarioName):
                DemoBoundaryRow(scenarioName: scenarioName)
                  .id(id)
                  .transition(reduceMotion ? .identity : .opacity)
              }
            }
          }
          // Screen-level gutters (20pt horizontal / 8pt top) match the
          // reference HTML `.stream { padding: 8px 20px 16px }`. Intentional
          // literals — these are container-level, not per-bubble.
          .padding(.horizontal, 20)
          .padding(.top, 8)
          .animation(
            reduceMotion ? nil : .easeOut(duration: 0.7),
            value: viewModel.chatItems.count)
        }
        .onChange(of: viewModel.chatItems.count) { _, _ in
          guard let lastId = viewModel.chatItems.last?.id else { return }
          withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
            proxy.scrollTo(lastId, anchor: .bottom)
          }
        }
      }

      // Sim-style frosted controlBar (#273): mirrors `SimulationView.controlBar`
      // shape so users learn the layout before the live simulation. Pause /
      // Speed / Toggle interactive — Pause → `viewModel.userPause()`/
      // `userResume()`, Speed → `viewModel.playbackSpeed` (#290).
      controlBar(viewModel: viewModel)
    }
    .background(Color.screenBackground.ignoresSafeArea())
    .safeAreaInset(edge: .bottom, spacing: Spacing.l) { promoCardInset }
  }

  /// One agent bubble in the demo stream. Opts into ``growsWithReveal`` so
  /// the bubble grows as characters surface (Sim-parity streaming feel,
  /// #785), and wires scroll-follow through the in-scope `proxy`:
  /// - ``AgentOutputRow/onRevealProgress`` raw-scrolls on every reveal tick
  ///   so the growing text stays pinned to the bottom (it would otherwise
  ///   type off-screen and jump into view at completion). No `withAnimation`
  ///   — mirrors `SimulationView`'s per-token `streamingSnapshot` follow; the
  ///   implicit 0.35s animation would compound across ~30 ticks/s into
  ///   visible stutter. Idempotent once pinned.
  /// - ``AgentOutputRow/onAnimatingChange`` animated-scrolls once typing
  ///   finishes to settle the final position (e.g. the `▸ INNER VOICE`
  ///   chevron pop-in). Mirrors Sim's `latestRowIsAnimating` gate.
  ///
  /// Both are guarded to the latest agent row — older rows snap
  /// `visibleChars` once on appear (one tick) but must not steal the scroll.
  private func demoAgentRow(
    _ entry: ReplayViewModel.AgentOutputEntry,
    lastAgentId: UUID?,
    proxy: ScrollViewProxy,
    viewModel: ReplayViewModel
  ) -> some View {
    AgentOutputRow(
      agent: entry.agent,
      output: entry.output,
      phaseType: entry.phaseType,
      showAllThoughts: viewModel.showAllThoughts,
      isLatest: entry.id == lastAgentId,
      charsPerSecond: viewModel.typingCharsPerSecond,
      onAnimatingChange: { animating in
        guard entry.id == lastAgentId, !animating else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
          proxy.scrollTo(entry.id, anchor: .bottom)
        }
      },
      onRevealProgress: {
        guard entry.id == lastAgentId else { return }
        proxy.scrollTo(entry.id, anchor: .bottom)
      },
      growsWithReveal: true,
      agentPosition: agentPosition(for: entry.agent, viewModel: viewModel)
    )
    .id(entry.id)
    .transition(reduceMotion ? .identity : .opacity)
  }

  /// PromoCard lives in the bottom safe area (not a ZStack overlay) so the
  /// ScrollView viewport shrinks to exclude the card's footprint;
  /// `scrollTo(lastId, anchor: .bottom)` then lands the newest message
  /// above the card. The earlier `.padding(.bottom, 160)` reserved space
  /// but didn't shrink the viewport — the anchor slid under the overlay.
  private var promoCardInset: some View {
    PromoCard(
      modelState: currentState,
      replayHadStarted: replayHadStarted,
      totalBytes: descriptor.fileSize,
      onRetry: { modelManager.startDownload(descriptor: descriptor) },
      onCancel: triggerCancelConfirmation)
  }

  /// Agent's zero-based index in the current replay's agent list, used
  /// by ``AvatarSlot`` for position-priority avatar color assignment.
  /// Returns `nil` when no replay is active or the agent isn't in the
  /// current source's `agents` list; the row then falls back to the
  /// name-based avatar resolution.
  private func agentPosition(
    for agentName: String, viewModel: ReplayViewModel
  ) -> Int? {
    guard let sourceIndex = viewModel.currentSourceIndex,
      sourceIndex < sources.count
    else { return nil }
    return sources[sourceIndex].scenario.personas.firstIndex(where: { $0.name == agentName })
  }
}

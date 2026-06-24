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
                AgentOutputRow(
                  agent: entry.agent,
                  output: entry.output,
                  phaseType: entry.phaseType,
                  showAllThoughts: viewModel.showAllThoughts,
                  isLatest: entry.id == lastAgentId,
                  charsPerSecond: viewModel.typingCharsPerSecond,
                  agentPosition: agentPosition(for: entry.agent, viewModel: viewModel)
                )
                .id(entry.id)
                .transition(reduceMotion ? .identity : .opacity)
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

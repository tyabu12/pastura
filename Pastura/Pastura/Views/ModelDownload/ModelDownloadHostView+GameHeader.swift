import SwiftUI

/// Demo-side composition of the shared `GameHeader` component (PR 3
/// of #273 — header content unification). Lifted into a sibling file
/// so the host view's `chatStream(_:)` body and the host file itself
/// stay under SwiftLint's `function_body_length` and `file_length`
/// ceilings.
///
/// `extendsIntoTopSafeArea: true` is intentional — the demo presents
/// inside `.fullScreenCover` / the `.needsModelDownload` slot with no
/// system nav bar above it, so the frosted material needs to fill
/// behind the status bar / Dynamic Island. Sim/Results stay at the
/// default `false` because their NavigationStack-pushed nav bar
/// already paints the top safe area. See
/// `Views/Components/GameHeader.swift` for the contract.
///
/// Demo passes:
/// - `scenarioName` — preset display name (e.g. "ワードウルフ")
/// - ROUND fragment — pseudo `currentPhaseIndex` / `totalPhaseCount`
///   from `ReplayViewModel`. Demo's preset scenarios use a single
///   game-round across multiple phases, so the real `currentRound`
///   sits at 1/1 the whole time; the pseudo-ROUND walks every phase
///   for visible progression.
/// - `phaseLabel` — phase display name only (e.g. "個別発言"),
///   without the round-suffix the legacy `PhaseHeader` baked in.
///   The round portion is now the GameHeader's row-2 ROUND fragment.
/// - `tokensPerSecond: nil` — Demo replays pre-recorded text, so
///   showing a fake tok/s would violate the "no synthetic numbers"
///   product principle (memory: project_product_vision).
extension ModelDownloadHostView {

  @ViewBuilder
  func gameHeader(viewModel: ReplayViewModel) -> some View {
    GameHeader(
      scenarioName: currentPresetName(viewModel: viewModel),
      status: viewModel.status,
      currentRound: viewModel.currentPhaseIndex,
      totalRounds: viewModel.totalPhaseCount,
      phaseLabel: phaseDisplayLabel(viewModel: viewModel),
      tokensPerSecond: nil,
      extendsIntoTopSafeArea: true
    )
  }

  /// Phase display label without the round-suffix. The GameHeader's
  /// row-2 layout splits ROUND and phase into separate slots, so the
  /// suffix the legacy `currentPhaseLabel(viewModel:)` baked in is
  /// no longer needed here. `currentPhaseLabel` is preserved in the
  /// `+PhaseLabels.swift` extension for potential future callers
  /// (chat-stream separator, etc.) that want the combined form.
  private func phaseDisplayLabel(viewModel: ReplayViewModel) -> String? {
    guard let phase = viewModel.currentPhase else { return nil }
    return Self.phaseDisplayName(phase)
  }
}

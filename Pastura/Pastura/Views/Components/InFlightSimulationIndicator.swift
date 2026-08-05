import SwiftUI
import UIKit

/// A persistent "return to your running simulation" pill shown across the tab
/// bar while a run is parked-away (Phase B, ADR-017 #682).
///
/// Mounted once on the `RootTabView` overlay. It is the Phase-B re-consumer of
/// the `isSimulationOnTop` any-tab fold (ADR-016 D5 / ADR-017 D6) that the ADRs
/// warned not to delete: the pill appears only when a run is active **and** not
/// already on top of some tab's stack. Tapping it re-selects the host tab and
/// re-pushes the sim route, where the re-mounted `SimulationView` adopts the
/// still-live session (instant reconnect).
///
/// Because a parked-away run has no `SimulationView` mounted, this host also
/// carries the away-case lifecycle observers — memory-warning and scene-phase —
/// routing both through the single owners on ``SimulationSession`` (one throttle,
/// one park gate). The present-view case is handled by `SimulationView`; the two
/// are mutually exclusive (`isSimulationOnTop` is true for exactly one).
///
/// Pattern: the iOS recording pill / Maps "return to navigation" affordance.
struct InFlightSimulationIndicator: View {
  @Environment(AppDependencies.self) private var dependencies
  @Environment(TabCoordinator.self) private var tabCoordinator
  @Environment(\.scenePhase) private var scenePhase
  // Suppress the repeating waveform under the XCUITest harness — a continuous
  // symbol effect never lets XCUITest reach "idle" (#728).
  @Environment(\.isUITestMode) private var isUITestMode

  /// Pure visibility predicate — mirrors `SimulationView.shouldGuardLeave`'s
  /// extract-for-testing shape. Show only when a run is active and not already
  /// the top of some tab's stack (where the user is already watching it).
  static func shouldShowIndicator(isActive: Bool, isSimulationOnTop: Bool) -> Bool {
    isActive && !isSimulationOnTop
  }

  private var isShown: Bool {
    Self.shouldShowIndicator(
      isActive: dependencies.simulationActivityRegistry.isActive,
      isSimulationOnTop: tabCoordinator.isSimulationOnTop)
  }

  var body: some View {
    if isShown {
      pill
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // Clear the tab bar; exact placement is a device-QA visual detail.
        .padding(.bottom, 56)
        .padding(.horizontal, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        // Away-case lifecycle observers (present-view case lives on
        // SimulationView; the two are mutually exclusive via isSimulationOnTop).
        .onReceive(
          NotificationCenter.default.publisher(
            for: UIApplication.didReceiveMemoryWarningNotification)
        ) { _ in
          dependencies.simulationSession.handleMemoryWarning(isAppActive: scenePhase == .active)
        }
        .onChange(of: scenePhase) { _, newPhase in
          handleAwayScenePhase(newPhase)
        }
    }
  }

  private var pill: some View {
    Button(action: returnToRun) {
      HStack(spacing: 8) {
        Image(systemName: "waveform")
          .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !isUITestMode)
          .accessibilityHidden(true)
        Text(label)
          .textStyle(Typography.metaValue)
          .lineLimit(1)
        Image(systemName: "chevron.right")
          .font(.caption2)
          .accessibilityHidden(true)
      }
      .foregroundStyle(Color.ink)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(.regularMaterial, in: Capsule())
      .overlay(Capsule().stroke(Color.ink.opacity(0.08)))
      // Occluder — §4.3.1's fixed near-black, not a paired alias and not a
      // raw light token either. This pill is a root `.overlay` on
      // `RootTabView`, so its ground is *every* screen including `nightPage`;
      // `PasturaPalette.ink` was fixed but still composited above the night
      // ground. The stroke above is a different case: a hairline meant to read
      // against the surface, so it follows the appearance.
      .shadow(
        color: PasturaOccluderShadows.inFlightPill.color.color,
        radius: PasturaOccluderShadows.inFlightPill.radius,
        y: PasturaOccluderShadows.inFlightPill.y)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
    .accessibilityHint(String(localized: "Returns to the running simulation"))
    .accessibilityIdentifier("inFlightSimulationIndicator")
  }

  /// "Round X / Y — tap to return", or a generic line before the first round
  /// lands. Reuses the run's live `headerRound` so the pill tracks progress.
  private var label: String {
    if let round = dependencies.simulationSession.viewModel?.headerRound {
      return String(
        format: String(localized: "Round %lld / %lld — tap to return"),
        round.current, round.total)
    }
    return String(localized: "Simulation running — tap to return")
  }

  private func returnToRun() {
    let session = dependencies.simulationSession
    guard let tab = session.tab, let route = session.returnRoute else { return }
    tabCoordinator.returnToRunningSimulation(tab: tab, route: route)
  }

  /// Bridges scene-phase for a parked-away run (no `SimulationView` mounted) into
  /// the VM's handlers, which route suspend/resume through the session gate.
  private func handleAwayScenePhase(_ newPhase: ScenePhase) {
    guard let viewModel = dependencies.simulationSession.viewModel, viewModel.isRunning else {
      return
    }
    switch newPhase {
    case .background:
      viewModel.isAppBackgrounded = true
      viewModel.handleScenePhaseBackground()
    case .active:
      viewModel.isAppBackgrounded = false
      Task { await viewModel.handleScenePhaseForeground() }
    default:
      break
    }
  }
}

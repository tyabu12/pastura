import SwiftUI

extension ModelDownloadHostView {

  /// Sim-style frosted controlBar for the DL-time demo. Mirrors
  /// `SimulationView.controlBar` shape so users learn the layout
  /// before reaching the live simulation (issue #273).
  ///
  /// **Disabled-mirror layout** — Pause and Speed are visually
  /// present but `.disabled(true)` and styled with `Color.disabledText`
  /// (design-system §2.7 — Interactive States); only
  /// `ThoughtVisibilityToggle` is interactive. PR 1b enables Pause /
  /// Speed by adding a user-driven pause / resume API to
  /// `ReplayViewModel`; at that point `.disabled(true)` is removed
  /// and the controls wire to the new API. Until then, the disabled
  /// layout serves as tutorial preview.
  ///
  /// Does **not** apply `.ignoresSafeArea(.container, edges: .bottom)`
  /// (unlike `SimulationView.controlBar`). The host's
  /// `.safeAreaInset(edge: .bottom)` already absorbs the bottom region
  /// for `PromoCard`; adding the ignore would extend tint into the
  /// inset region with unpredictable interaction with the
  /// PromoCard layer (#273 critic Axis 2).
  ///
  /// `.buttonStyle(.plain)` is used on the disabled controls to
  /// suppress the system's default button decoration so the explicit
  /// `Color.disabledText` token is the dominant rendered color rather
  /// than the system's accent-tint × disabled-opacity composite.
  @ViewBuilder
  func controlBar() -> some View {
    HStack(spacing: 16) {
      pausePreviewButton
      speedPreviewButton

      Spacer()

      ThoughtVisibilityToggle(isOn: $showAllThoughts)
        .font(.title3)
    }
    .padding(.horizontal)
    .padding(.vertical, 10)
    .background {
      ZStack {
        Color.screenBackground.opacity(0.78)
        Rectangle().fill(.ultraThinMaterial)
      }
    }
    .overlay(alignment: .top) {
      Rectangle().fill(Color.ink.opacity(0.07)).frame(height: 1)
    }
  }

  /// Disabled "preview" Pause button — same icon as Sim's running-state
  /// Pause (`pause.fill`). PR 1b wires the action to
  /// `replayVM?.userPause()` and removes `.disabled(true)`.
  @ViewBuilder
  private var pausePreviewButton: some View {
    Button {
    } label: {
      Image(systemName: "pause.fill").font(.title3)
    }
    .buttonStyle(.plain)
    .foregroundStyle(Color.disabledText)
    .disabled(true)
    .accessibilityLabel(
      String(localized: "Pause (available during simulation)"))
  }

  /// Disabled "preview" Speed picker — same label structure as Sim's
  /// `speedOrExportControl` Menu (gauge icon + value + chevron). Static
  /// `1×` since `ReplayViewModel` runs at a fixed `speedMultiplier`.
  /// PR 1b replaces this with a real `Menu` over `PlaybackSpeed.allCases`.
  @ViewBuilder
  private var speedPreviewButton: some View {
    Button {
    } label: {
      HStack(spacing: 4) {
        Image(systemName: "gauge.with.dots.needle.50percent")
        Text(verbatim: "1×")
        Image(systemName: "chevron.down").font(.caption2)
      }
      .textStyle(Typography.titlePhase)
    }
    .buttonStyle(.plain)
    .foregroundStyle(Color.disabledText)
    .disabled(true)
    .accessibilityLabel(
      String(localized: "Playback speed (available during simulation)"))
  }
}

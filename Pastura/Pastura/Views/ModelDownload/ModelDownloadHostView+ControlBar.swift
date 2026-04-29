import SwiftUI

extension ModelDownloadHostView {

  /// Sim-style frosted controlBar for the DL-time demo. Mirrors
  /// `SimulationView.controlBar` shape so users learn the layout
  /// before reaching the live simulation (issue #273 / PR 1a).
  ///
  /// All three controls are interactive (PR 1b / #290):
  /// - Pause toggles via `viewModel.userPause()` / `userResume()`,
  ///   icon flips between `pause.fill` and `play.fill` based on
  ///   ``ReplayViewModel/isUserPaused``.
  /// - Speed Menu binds directly to ``ReplayViewModel/playbackSpeed``
  ///   over `PlaybackSpeed.allCases`, matching Sim's pattern at
  ///   `SimulationView.swift:434`.
  /// - Thought toggle remains bound to `showAllThoughts` (Sim and
  ///   Replay diverge here — Sim's is a per-VM property, Demo's is a
  ///   View-local `@State`).
  ///
  /// Does **not** apply `.ignoresSafeArea(.container, edges: .bottom)`
  /// (unlike `SimulationView.controlBar`). The host's
  /// `.safeAreaInset(edge: .bottom)` already absorbs the bottom region
  /// for `PromoCard`; adding the ignore would extend tint into the
  /// inset region with unpredictable interaction with the
  /// PromoCard layer (#273 critic Axis 2).
  @ViewBuilder
  func controlBar(viewModel: ReplayViewModel) -> some View {
    HStack(spacing: 16) {
      pauseButton(viewModel: viewModel)
      speedMenu(viewModel: viewModel)

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

  /// Pause / Resume button. Action toggles via
  /// ``ReplayViewModel/isUserPaused``; icon mirrors the same flag
  /// (`play.fill` while user-paused, otherwise `pause.fill`).
  /// Scene-phase pause does **not** flip the icon — the UI is hidden
  /// during BG anyway, but the boundary is meaningful for the
  /// transient redraw frame on FG return.
  @ViewBuilder
  private func pauseButton(viewModel: ReplayViewModel) -> some View {
    Button {
      if viewModel.isUserPaused {
        viewModel.userResume()
      } else {
        viewModel.userPause()
      }
    } label: {
      Image(systemName: viewModel.isUserPaused ? "play.fill" : "pause.fill")
        .font(.title3)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      viewModel.isUserPaused
        ? String(localized: "Resume playback")
        : String(localized: "Pause playback"))
  }

  /// Speed Menu — drives ``ReplayViewModel/playbackSpeed`` over
  /// `PlaybackSpeed.allCases`. Mirrors `SimulationView.speedOrExportControl`'s
  /// Menu-with-explicit-buttons pattern (`SimulationView.swift:433`)
  /// rather than `Picker.pickerStyle(.menu)` to avoid the iOS 17/18
  /// reparenting warnings + label-wrap quirks documented there.
  @ViewBuilder
  private func speedMenu(viewModel: ReplayViewModel) -> some View {
    Menu {
      ForEach(PlaybackSpeed.allCases) { speed in
        Button {
          viewModel.playbackSpeed = speed
        } label: {
          if speed == viewModel.playbackSpeed {
            Label(speed.label, systemImage: "checkmark")
          } else {
            Text(speed.label)
          }
        }
      }
    } label: {
      HStack(spacing: 4) {
        Image(systemName: "gauge.with.dots.needle.50percent")
        Text(viewModel.playbackSpeed.label)
        Image(systemName: "chevron.down").font(.caption2)
      }
      .textStyle(Typography.titlePhase)
    }
    .accessibilityLabel(String(localized: "Playback speed"))
  }
}

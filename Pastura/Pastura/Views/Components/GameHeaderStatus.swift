import SwiftUI

/// Status presented in the trailing pill of `GameHeader` (Demo / Sim
/// shared 2-row header — see `GameHeader.swift`).
///
/// Seven cases cover all activity modes (`simulating` / `demoing` /
/// `replaying`) plus terminal exception states (`paused` / `completed`
/// / `cancelled` / `error`). The pill is **always visible** so the
/// user can tell at a glance whether the screen is real inference, a
/// pre-recorded demo, or a past-result replay.
///
/// `replaying` has no producer in the current Phase 2 surface — it is
/// included ahead of need so the future Results-screen `GameHeader`
/// adoption can reuse this enum without an additive API change.
///
/// Color grouping (background = `foreground.opacity(0.14)`):
/// - **active** (`simulating` / `demoing` / `replaying`) → `moss`
/// - **completed** → `mossDark` (distinct accent for "successfully done")
/// - **terminal-exception** (`paused` / `cancelled` / `error`) → `muted`
///
/// Cancelled and error currently share the muted palette with paused; if
/// later UX work calls for differentiating them (e.g. red accent for
/// `error`), update the color groupings here. The semantic distinction
/// (`.cancelled` vs `.error` vs `.paused`) is preserved at the enum
/// level so consumers like `SimulationViewModelStatusTests` can pin
/// derivation precedence even when colors collapse.
public enum GameHeaderStatus: String, Sendable, CaseIterable {
  /// Real LLM inference is running (Sim screen).
  case simulating
  /// Pre-recorded demo replay (DL-time demo, ModelDownloadHostView).
  case demoing
  /// Past-result replay (future Results-screen adoption — no producer
  /// in the current Phase 2 PR; reserved so adoption is additive).
  case replaying
  /// User-paused. Shared label across all three active modes.
  case paused
  /// Successfully completed — Sim run terminated normally.
  case completed
  /// User-cancelled — distinct from `completed` (incomplete result) but
  /// shares terminal-exception color with `paused` / `error`.
  case cancelled
  /// Unrecoverable inference error.
  case error

  /// Localized label rendered inside the pill. Catalog keys live in
  /// `Localizable.xcstrings`; `localization-coverage` CI gate enforces
  /// non-empty `ja` translations for each.
  public var label: String {
    switch self {
    case .simulating: return String(localized: "Simulating")
    case .demoing: return String(localized: "Demoing")
    case .replaying: return String(localized: "Replaying")
    case .paused: return String(localized: "Paused")
    case .completed: return String(localized: "Completed")
    case .cancelled: return String(localized: "Cancelled")
    case .error: return String(localized: "Error")
    }
  }

  /// Foreground (text) color for the pill.
  public var foreground: Color {
    switch self {
    case .simulating, .demoing, .replaying:
      return Color.moss
    case .completed:
      return Color.mossDark
    case .paused, .cancelled, .error:
      return Color.muted
    }
  }

  /// Background tint for the pill (capsule fill). Computed as
  /// `foreground.opacity(0.14)` per design hand-off.
  public var background: Color {
    foreground.opacity(0.14)
  }
}

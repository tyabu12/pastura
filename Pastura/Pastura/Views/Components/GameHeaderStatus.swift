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
/// Color grouping — the label (``foreground``) and the capsule wash
/// (``washToken``) are **separate** tokens, so the pill reads as
/// `<label> on <wash>`:
/// - **active** (`simulating` / `demoing` / `replaying`) → `mossOnWash`
///   on a `moss` wash
/// - **completed** → `mossInk` on a `mossDark` wash (distinct accent for
///   "successfully done", kept distinct at the *label* level too)
/// - **terminal-exception** (`paused` / `cancelled` / `error`) → `muted`
///   on a `muted` wash
///
/// The label used to be the wash's own token at 100% (`background` was
/// `foreground.opacity(0.14)`), which made all four moss arms self-washes
/// under WCAG AA in light — 2.561 and 3.832 against a 4.5:1 bar, since
/// ``Typography/pillStatus`` is 9pt. Raising the wash alpha cannot repair
/// that: `moss`'s alpha→0 ceiling on `screenBackground` is 2.908, i.e.
/// below the bar even with the capsule erased. So the label moved to the
/// family's role tokens and the washes were left byte-identical (#1455).
///
/// Separating the two is the established shape, not a local exception —
/// every other translucent-wash site in the app already does it, and the
/// `mossWashSites` / `inkWashSites` fixtures enumerate them. `.completed`
/// reads `mossInk` rather than `mossOnWash` because §2.3 assigns that
/// token the "完了タイトル" role and `ResultsView`'s own completed pill
/// already renders it on a moss wash; design-system §8 and ADR-028
/// § Amendment 2026-08-14 carry the discriminator and its limits.
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

  /// Opacity applied to ``washToken`` to produce ``background``, per the
  /// original design hand-off (HEADER_UPDATE.md / §2.12 status pill spec).
  ///
  /// Held apart from the token — rather than folded into `background` —
  /// so a routing pin can compare the *token* by alias. A `Color` carrying
  /// an applied opacity compares unequal to the token it came from, which
  /// would make such a pin impossible. `ScenarioBadgeStyle.fillOpacity` is
  /// the same shape for the same reason.
  static let washAlpha: Double = 0.14

  /// Foreground (text) color for the pill. See the type's doc comment for
  /// why this is not the same token as ``washToken``.
  public var foreground: Color {
    switch self {
    case .simulating, .demoing, .replaying:
      return Color.mossOnWash
    case .completed:
      return Color.mossInk
    case .paused, .cancelled, .error:
      return Color.muted
    }
  }

  /// Base color of the capsule fill, before ``washAlpha`` is applied.
  ///
  /// Unchanged by #1455 — all three washes are byte-identical to what
  /// shipped before the label moved off them, so the pill's visual weight
  /// and the active-vs-completed wash difference are untouched.
  var washToken: Color {
    switch self {
    case .simulating, .demoing, .replaying:
      return Color.moss
    case .completed:
      return Color.mossDark
    case .paused, .cancelled, .error:
      return Color.muted
    }
  }

  /// Background tint for the pill (capsule fill).
  public var background: Color {
    washToken.opacity(Self.washAlpha)
  }
}

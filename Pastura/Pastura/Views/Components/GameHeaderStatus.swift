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
/// below WCAG AA in light — 2.561 and 3.832 against a 4.5:1 bar, since
/// ``Typography/pillStatus`` is 9pt. Wash alpha cannot repair that:
/// `moss`'s alpha→0 ceiling on `screenBackground` is 2.908, i.e. below the
/// bar even with the capsule erased. So the labels moved to the family's
/// role tokens and the washes were left byte-identical. Splitting the two
/// is the established shape — every translucent-wash site that owes AA
/// already does it — and the carve-out is §8's quietude tier, which is why
/// the `muted` arms stay a self-wash. `.completed` takes `mossInk` rather
/// than `mossOnWash` under §8's one exception; design-system §8 and ADR-028
/// § Amendment 2026-08-14 carry the discriminator and its limits (#1455).
///
/// Cancelled and error currently share the muted palette with paused; if
/// later UX work calls for differentiating them (e.g. red accent for
/// `error`), update the color groupings here — **and take the contrast
/// obligation with you.** The contrast guards are keyed on site names, not
/// on `allCases`: a new arm on a wash no existing row covers goes green
/// across `GameHeaderStatusTests` the moment its row is added there, while
/// reaching **no** contrast fixture at all. So route the new label to that
/// family's `*-on-wash` role
/// token, or take design-system §8's exception explicitly, and add the arm
/// to `DesignTokensTests+MossOnWash`'s `mossWashSites` or
/// `+MossInkAsWashLabel`'s `mossInkWashSites`. The semantic distinction
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

  /// Opacity applied to ``washToken`` to produce ``background``, carried over
  /// unchanged from the design hand-off (HEADER_UPDATE.md). design-system
  /// records the alpha nowhere — §2.12's table is header *slot* tokens and has
  /// no pill row — so this declaration is its only home; the pill's tokens live
  /// in §2.3 / §8 and its size in §3's `pill/status`.
  ///
  /// Held apart from the token, rather than folded into `background`, so a
  /// routing pin can compare the *token* by alias: a `Color` carrying an
  /// applied opacity compares unequal to the token it came from.
  /// `ScenarioBadgeStyle.fillOpacity` is the same shape for the same reason.
  ///
  /// `internal` on a `public` enum by intent — a routing detail, not part of
  /// the pill's contract, so an out-of-module consumer gets *what to paint*
  /// (label and fill) without the derivation. `@testable` crosses module
  /// boundaries too, so an SPM extraction would not cost the pins their
  /// access; what it would straddle is the app test target reading this and
  /// `PasturaPalette` from two modules.
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
  /// Byte-identical to the pre-#1455 fills — only the labels moved, so the
  /// capsule's visual weight and the active-vs-completed wash difference are
  /// untouched.
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

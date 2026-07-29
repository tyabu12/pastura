import SwiftUI

/// The badge shown next to a scenario title on the さがす (Browse) catalog card
/// — ``installed`` / ``update`` / ``updateRequired`` / ``new``. Resolved from a
/// gallery entry's engine compatibility, local install state, and recency by
/// ``GalleryCatalogRowFormat/badge(compatible:hasUpdate:isInstalled:isNew:)``,
/// which is the only production construction site; ``GalleryCatalogRow`` is the
/// only renderer.
///
/// Home carries provenance in its row caption instead of a badge
/// (``HomeScenarioRowFormat/provenanceCaption(isPreset:category:)``), so there
/// is no `preset` case: it existed only for the shared summary row retired in
/// #1296 and was removed with it rather than kept as an unreachable case.
/// Reintroduce one here if a surface ever needs a bundled-scenario badge.
nonisolated enum ScenarioBadge: Equatable {
  case installed
  case update
  /// The scenario needs a newer engine than this build provides (ADR-020
  /// D2/D3) — surfaced by Browse on an incompatible, non-tappable (dimmed)
  /// card in place of the install/update badges. A distinct warning colour +
  /// an App Store deep-link are deferred to the first post-baseline release
  /// that can actually grey a row (ADR-020 § deferred scope).
  case updateRequired
  /// Recently added to the gallery (within
  /// ``GalleryCatalogRowFormat/newBadgeWindowDays``) — a discovery highlight
  /// on the Browse catalog card (ADR-025). Fills the single badge slot only
  /// when the entry is otherwise unbadged (install-state wins), so it never
  /// competes with `installed` / `update`.
  case new

  /// Localized badge label.
  var label: String {
    switch self {
    case .installed: return String(localized: "Installed")
    case .update: return String(localized: "Update")
    case .updateRequired: return String(localized: "Update app")
    case .new: return String(localized: "New")
    }
  }

  /// Visual emphasis. The "this scenario changed" `update`, the "your app is
  /// too old" `updateRequired`, and the "recently added" `new` discovery
  /// highlight use the accent tint; the provenance badge (`installed`) is
  /// quieter.
  var style: ScenarioBadgeStyle {
    switch self {
    case .installed: return .secondary
    case .update, .updateRequired, .new: return .tint
    }
  }
}

/// Badge visual emphasis — kept separate from ``ScenarioBadge`` so the
/// case → emphasis mapping is unit-testable without rendering.
nonisolated enum ScenarioBadgeStyle: Equatable {
  case secondary
  case tint
}

/// The badge's colour contract, hoisted off ``GalleryCatalogRow``'s renderer so
/// the one surviving badge has a single, assertable definition of its tokens
/// (#1296). Before this, the pair was inlined in two renderers that had to be
/// kept byte-identical by hand.
///
/// Token choice follows the ``PhaseTypeLabel`` precedent. Design-system § 2.3
/// lists `mossDark` for accent text (links, status labels), and § 2.2's
/// `--ink-on-accent` bullets carry the constraint that forces the split: text on
/// base `moss` is ≈3.03:1, short of the 4.5:1 bar, while `mossDark` clears it at
/// ≈4.7:1. So the tinted badge takes `moss` for its wash and `mossDark` for its
/// label; the quieter `secondary` uses `inkSecondary` for both. The wash
/// opacities are **not** shared with `PhaseTypeLabel` (which uses 0.15 for
/// both) — the tinted badge sits on a card background and needs 0.2 to read.
///
/// These are trait-resolving `Color.*` aliases on purpose: the badge renders
/// live on-device, so it must follow the device appearance. A
/// fixed-appearance consumer (`ImageRenderer`) would have to read
/// `PasturaPalette.<token>.color` directly instead — see ADR-028.
///
/// The members are **MainActor-isolated** even though ``ScenarioBadgeStyle``
/// itself is `nonisolated` — an extension does not inherit the type's
/// annotation, and that boundary is intended: these are UI values whose only
/// legitimate caller is a View, while the pure case → emphasis mapping stays
/// nonisolated. Do **not** add `nonisolated` here to "match the type"; see
/// ``ScenarioBadgeStyleTokenTests`` for the probe that established the current
/// isolation (the target compiles either way, so a build alone proves nothing).
extension ScenarioBadgeStyle {
  /// Capsule wash colour, before ``fillOpacity`` is applied.
  var fillToken: Color {
    switch self {
    case .tint: return Color.moss
    case .secondary: return Color.inkSecondary
    }
  }

  /// Label colour.
  var labelToken: Color {
    switch self {
    case .tint: return Color.mossDark
    case .secondary: return Color.inkSecondary
    }
  }

  /// Opacity applied to ``fillToken``. Kept separate from the token so the
  /// change-detector test can compare bare aliases rather than derived colours.
  var fillOpacity: Double {
    switch self {
    case .tint: return 0.2
    case .secondary: return 0.15
    }
  }
}

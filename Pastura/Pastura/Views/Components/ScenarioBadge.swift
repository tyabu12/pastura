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
/// Token choice follows the ``PhaseTypeLabel`` precedent and design-system
/// § 2.3, which lists `mossDark` for accent text (links, status labels) and
/// keeps base `moss` for fills / borders. `mossDark` is the readable half of
/// that pair in either framing, so the tinted badge takes `moss` for its wash
/// and `mossDark` for its label; the quieter `secondary` uses `inkSecondary`
/// for both. The wash opacities are **not** shared with `PhaseTypeLabel` (which
/// uses 0.15 for both) — the tinted badge sits on a card background and needs
/// 0.2 to read.
///
/// Measured on the composited wash (`mossDark` over `moss` @0.2 over
/// `bubbleBackground`), **light appearance**: **≈3.92:1**, versus ≈2.51:1 if the
/// label were `moss`. So the token split is what makes the badge legible, but at
/// `caption2.bold` it does **not** reach the 4.5:1 text bar — a pre-existing
/// property of the shipped design, unchanged by the hoist. `secondary` measures
/// ≈5.57:1, also light.
///
/// All four tokens in that composite are paired since ADR-028 slice 4, so these
/// are light-appearance figures rather than absolutes. Measured on the dark
/// composite (`nightMossDark` label over a `nightMoss` wash at the same 0.2
/// fill opacity, composited over `nightBubble` → composited wash #454A3B):
/// **≈4.79:1** — for the **tinted** badge, dark **passes** the 4.5:1 text bar,
/// so the known light-mode contrast gap (#1327 part 1) does not extend to it.
/// The `secondary` style is the opposite trade: `nightInkSecondary` over its own
/// token at 0.15 measures **≈4.5:1**, i.e. it lands ON the bar in dark where
/// light clears it at ≈5.57:1. Neither figure is a regression from this branch;
/// both are the designed values, measured.
/// Do not read § 2.2's ≈3.03 / ≈4.74 figures as covering either appearance:
/// those are `inkOnAccent` on a **solid** fill (white only in light), a
/// different pairing.
///
/// These are trait-resolving `Color.*` aliases on purpose: the badge renders
/// live on-device, so it must follow the device appearance. A
/// fixed-appearance consumer (`ImageRenderer`) would have to read
/// `PasturaPalette.<token>.color` directly instead — see ADR-028.
///
/// The members are **MainActor-isolated** even though ``ScenarioBadgeStyle``
/// itself is `nonisolated`: an extension does not inherit the type's
/// annotation, same-file or sibling. That boundary is intended — these are UI
/// values whose only legitimate caller is a View, while the pure
/// case → emphasis mapping stays nonisolated. Do **not** add `nonisolated`
/// here to "match the type": it fails the build on all four `Color.*` reads
/// (`main actor-isolated static property 'moss' can not be referenced from a
/// nonisolated context`), which is `.claude/rules/swift-isolation.md`
/// Pattern 5's non-test table, row 2. Pattern 5's cross-module corollary does
/// not apply — these reads are in-module.
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

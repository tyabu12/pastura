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
/// § 2.3, which keeps base `moss` for fills / borders. So the tinted badge takes
/// `moss` for its wash; the quieter `secondary` uses `inkSecondary` for both.
/// The wash opacities are **not** shared with `PhaseTypeLabel` (which uses 0.15
/// for both) — the tinted badge sits on a card background and needs 0.2 to read.
///
/// The tinted **label** is the `mossOnWash` role token, not the `mossDark` that
/// §2.3 lists for accent text. `mossDark` was the shipped choice and it did not
/// reach the 4.5:1 bar on any wash the app renders: measured on this composite
/// (label over `moss` @0.2 over `bubbleBackground`), **light appearance**,
/// `mossDark` gives **≈3.92:1** — better than the ≈2.51:1 a `moss` label would
/// give, but still short. `mossOnWash` brings it to **≈5.78:1** (#1327).
/// `secondary` measures ≈5.57:1, also light.
///
/// Every token in that composite is paired, so these are light-appearance
/// figures rather than absolutes — the three grounds since ADR-028 slice 4,
/// and `mossOnWash` from birth as the 68th pair (#1327), which is *not* from
/// any slice. Measured on the dark
/// composite (`nightMossOnWash` label over a `nightMoss` wash at the same 0.2
/// fill opacity, composited over `nightBubble` → composited wash #454A3B):
/// **≈5.11:1**, up from ≈4.77:1 under `nightMossDark`. Dark already passed the
/// bar before this change — the #1327 gap was light-only — so the swap buys
/// margin here rather than fixing a failure.
/// The `secondary` style is the opposite trade: `nightInkSecondary` over its own
/// token at 0.15 measures **≈4.5:1**, i.e. it lands ON the bar in dark where
/// light clears it at ≈5.57:1. That one is not fixed here — `mossOnWash` is a
/// moss-family token and does not reach the ink family; tracked in #1408.
/// Do not read § 2.2's ≈3.03 / ≈4.74 figures as covering either appearance:
/// those are `inkOnAccent` on a **solid** fill (white only in light), a
/// different pairing.
///
/// These are trait-resolving `Color.*` aliases on purpose: the badge renders
/// live on-device, so it must follow the device appearance. A fixed-appearance
/// consumer (`ImageRenderer`) would have to **inject** its appearance and read
/// `PasturaPalette.<token>.color` directly instead — the injection is the half
/// that breaks if omitted; the raw read keeps `light` and `dark` distinct. See
/// ADR-028 § Amendment 2026-08-06 (#1337).
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
    case .tint: return Color.mossOnWash
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

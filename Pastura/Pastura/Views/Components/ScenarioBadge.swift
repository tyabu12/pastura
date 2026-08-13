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
/// `moss` for its wash and the quieter `secondary` takes `inkSecondary`; each
/// **label** then reads its family's `*OnWash` role token rather than the wash
/// token itself. The wash opacities are **not** shared with `PhaseTypeLabel`
/// (which uses 0.15 for both) — the tinted badge sits on a card background and
/// needs 0.2 to read.
///
/// The tinted label is `mossOnWash`, not the `mossDark` §2.3 lists for accent
/// text. `mossDark` was the shipped choice and reached the 4.5:1 bar on no wash
/// the app renders: over `moss` @0.2, **light**, it gives ≈3.92:1 — better than
/// the ≈2.51:1 a `moss` label would give, but short. `mossOnWash` brings it to
/// ≈5.78:1 (#1327). In dark it was already passing at ≈4.77:1 and goes to
/// ≈5.11:1, so that swap bought margin rather than fixing a failure.
///
/// `secondary` broke in the other appearance, and was a real failure rather
/// than a margin buy: `inkSecondary` over its own token at 0.15 measures 5.350:1
/// in light but **4.501:1** in dark — green by 0.001, with no room for a later
/// wash tweak. `mossOnWash` cannot reach it (wrong family), so #1408 minted
/// `inkOnWash`, whose light half is `inkSecondary` byte-for-byte and whose dark
/// half takes this site to 5.090:1.
///
/// **The two sets of figures use different grounds** and are not a before/after
/// of each other: the moss ones are per-site over `bubbleBackground` /
/// `nightBubble`, the card this badge sits on; the `secondary` ones are the
/// worst-case-per-appearance convention `DesignTokensTests+InkOnWash` asserts.
/// Every token in these composites is paired, so all of them are per-appearance
/// figures rather than absolutes. Do not read § 2.2's ≈3.03 / ≈4.74 figures as
/// covering either appearance: those are `inkOnAccent` on a **solid** fill
/// (white only in light), a different pairing.
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
    case .secondary: return Color.inkOnWash
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

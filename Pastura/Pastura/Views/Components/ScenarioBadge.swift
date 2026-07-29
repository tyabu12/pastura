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

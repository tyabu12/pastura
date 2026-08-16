import Foundation

/// Classifies how `GalleryScenarioDetailView` should render its
/// recommended-model affordances given a snapshot of model-manager state.
///
/// Surface map (see PR2 of #302 for context):
/// - `matched`, `unknownModel`, `unsupportedDevice` → no banner, no affordance
/// - `downloading` → banner only (informational; user can't intervene from gallery)
/// - `switchAvailable`, `downloadAvailable` → banner + affordance button
///
/// Every state below except `matched` and `unknownModel` describes the
/// **target** build — `ModelRegistry.recommendationTarget(for:state:)`, which
/// the consuming affordances resolve through as well, so the build a button
/// acts on is the one this classified. `matched` is the exception on purpose;
/// see Rule 4.
///
/// Pure-logic enum: lives in Views/ for proximity to the consuming view but
/// `compute(...)` takes a value-typed snapshot so the test suite is fully
/// deterministic without mocking `ModelManager`.
///
/// Marked `nonisolated` so `compute(...)` and `Equatable` conformance are
/// callable from test code without a `MainActor` context — same pattern as
/// `InferenceStatsFormatter` (pure helper in Views/ with no SwiftUI dependency).
nonisolated enum RecommendedModelStatus: Equatable {
  /// Active model already satisfies the recommendation — it is either the id the
  /// feed names or the id that replaces it (`ModelRegistry` § "ADD-and-keep") —
  /// OR there is no actionable mismatch (simulator builds, transient
  /// `.checking` state).
  case matched

  /// Recommended model is on disk but not active. `isLocked` is `true`
  /// when a simulation is in flight (mirrors `ModelSettingsRow.isSwitchLocked`).
  case switchAvailable(isLocked: Bool)

  /// Recommended model is not on disk. `otherDownloadInFlight` is `true`
  /// when another descriptor is currently downloading (sequential-DL
  /// policy disables a fresh tap; mirrors
  /// `SettingsView.isOtherDownloading(excluding:)`).
  case downloadAvailable(otherDownloadInFlight: Bool)

  /// Recommended model is currently downloading. Banner is informational —
  /// no gallery-side affordance because intervention happens from
  /// Settings → Models cover.
  case downloading

  /// Device fails the 6.5 GB minimum-RAM floor. Phase 2 leaves these users
  /// fully unsupported; gallery suppresses both banner and affordance.
  case unsupportedDevice

  /// `ModelRegistry.recommendationTarget(for:state:)` returned nil — forward-compat
  /// case for an older app reading a newer `gallery.json` whose model id
  /// is unknown to this build. That helper is also where the "`nil` only for an
  /// id in no catalog entry" contract is written. Suppress UI; PR1's
  /// "Unknown model (id)" display fallback handles the read-only surface.
  case unknownModel

  /// Pure classifier. Rule order is the contract — tests pin one rule per case.
  static func compute(
    recommendedID: ModelID,
    activeID: ModelID,
    state: [ModelID: ModelState],
    isSimulationActive: Bool,
    isSimulator: Bool
  ) -> RecommendedModelStatus {
    // Rule 1: simulator suppresses all affordances; PR1 display fallback
    // still renders. Param form (vs `#if`-strip) keeps the path testable.
    if isSimulator { return .matched }

    // Rule 2: forward-compat — unknown id from a newer gallery.json
    // degrades to PR1's "Unknown model (rawId)" display only. Resolving the
    // recommendation forward through ADD-and-keep happens in the same step, so
    // every rule below reasons about the build the app would actually offer:
    // the whole gallery feed recommends the Q4_K_M Gemma, and that build is
    // hidden from the list surfaces once it is neither on the device nor the
    // active model.
    guard
      let target = ModelRegistry.recommendationTarget(for: recommendedID, state: state)
    else {
      return .unknownModel
    }

    let recommendedState = state[target.id] ?? .checking

    // Rule 3: device-class mismatch — Phase 2 leaves 6 GB devices unsupported.
    // Stays ahead of Rule 4: `resolveInitialActiveID` picks the default without
    // consulting `state`, so "active model satisfies the recommendation" and
    // "the recommended build cannot run here" are both true on a 6 GB device,
    // and this one has to win or the case becomes unreachable.
    if case .unsupportedDevice = recommendedState { return .unsupportedDevice }

    // Rule 4: short-circuit before .downloading so an active-model
    // re-download (rare but reachable) doesn't fire a noise banner.
    //
    // Two-sided since #1487, and deliberately **not** asked of `target`: the
    // active model satisfies the recommendation when it is the id the feed
    // names (which un-nags a user still on the replaced build) or the id that
    // replaces it (which keeps a fresh install matched). Asking `target`
    // instead would offer a user who runs the replacement, but still has the
    // replaced build on disk, a *downgrade* switch to it — `target` answers
    // "which build do we act on", a different question.
    // Production-pinned on purpose, matching `recommendationTarget`'s own
    // internal read: the two must answer about the same array, and this
    // classifier is only ever driven by the production registry. A future
    // preview/test catalog injection has to thread both, not one.
    let replacementID = ModelRegistry.replacement(
      for: recommendedID, in: ModelRegistry.catalog)?.id
    if activeID == recommendedID || activeID == replacementID { return .matched }

    // Rule 5: in-flight download — banner only.
    if case .downloading = recommendedState { return .downloading }

    // Rule 6: needs download. `otherDownloadInFlight` derived from sibling
    // states (excluding self, but self is .notDownloaded/.error here so
    // the contains check is naturally exclusive).
    switch recommendedState {
    case .notDownloaded, .error:
      let otherInFlight = state.values.contains { state in
        if case .downloading = state { return true }
        return false
      }
      return .downloadAvailable(otherDownloadInFlight: otherInFlight)
    default:
      break
    }

    // Rule 7: ready and != active → switch is available; lock if a sim is running.
    if case .ready = recommendedState {
      return .switchAvailable(isLocked: isSimulationActive)
    }

    // Rule 8: .checking transient (or any unanticipated future state) —
    // conservative: no affordance, no banner.
    return .matched
  }
}

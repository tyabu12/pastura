import SwiftUI
import Testing

@testable import Pastura

/// Change-detector for the result pill's colour routing
/// (`.claude/rules/view-testing.md` § "Change-detector tripwire for
/// code-review-gated tokens"). Sibling in shape to
/// ``ScenarioBadgeStyleTokenTests``.
///
/// **Why this is not tautological.** `pillForeground` is read twice — by the
/// pill label in `ResultsView.resultPill` and by the timeline node's `Circle`
/// fill in `ResultsView+Timeline.timelineRow`, which is the whole reason it is
/// `internal` rather than `private`. Neither surface has automated visual
/// coverage (ADR-009 rules out snapshot tests), so until this suite the routing
/// was code-review-gated only, and the map is exactly the kind of thing an
/// unrelated palette sweep edits in passing.
///
/// **This pin does not go blind to `body`.** The rule warns that extracting a
/// View's colours into an accessor leaves the pin unable to see a `body` that
/// re-inlines a token. That failure mode needs *two* places deciding the colour;
/// here there is one. `rg 'Color\.'` over
/// `Pastura/Pastura/Views/Results/ResultsView+Timeline.swift` does return hits —
/// seven, when this was written — but every one belongs to a **different**
/// element: the record-count subtitle, the rail, the day-section node's border
/// and fill, the day title, the card surface and its stroke. The day node is
/// deliberately independent of the
/// run node and is not governed by this map. The run node's own fill is
/// `pillForeground(pill.style)` and carries no `Color.` literal, which is the
/// property that keeps this pin honest — re-run the grep rather than trusting
/// the count, since a new element would add hits without invalidating anything.
///
/// **A failure here is not a bug.** It means a code-review-gated token drifted.
/// Confirm the change was intended and passed review, then update the
/// expectation.
///
/// **Why assert the alias, not the hex.** All three tokens are trait-resolving
/// (`PasturaDynamicPalette`), so an alias comparison follows a pairing slice
/// without edits here while still reddening on a swap to a *different* token —
/// the drift actually being guarded. Note this matters more than usual for
/// `.paused`: `inkOnWash` and `inkSecondary` are **byte-identical in light**, so
/// a value-based comparison could not tell them apart at all. `Color` compares
/// by provider instance, which is what makes the arm meaningful; deliberately no
/// "these two differ" assertion anywhere in this file, since that direction
/// passes vacuously for the same reason.
///
/// Token *values* are `DesignTokensTests`' contract, and the contrast claims
/// behind `.paused`'s token are `DesignTokensTests+InkOnWash`'s. This suite
/// guards only which token each arm routes to.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ResultsPillTokenTests {

  /// The memberwise initializer is already reached this way in production —
  /// `RootTabView` constructs `ResultsView(scope: .aggregate)` from another file
  /// in the same module — which is the checkable half of "this construction is
  /// sound". The rest follows: `@Environment` resolves at render time and
  /// `pillForeground` never reads `dependencies`, so no dependency graph is
  /// needed to reach the colour map.
  private let sut = ResultsView(scope: .aggregate)

  @Test func completedRoutesToTheAccentInkStep() {
    #expect(sut.pillForeground(.completed) == Color.mossInk)
  }

  @Test func pausedRoutesToTheInkWashRoleToken() {
    // Not `inkSecondary`, which still fills the capsule under it (#1408). This
    // site was already clearing the bar in dark at 4.773:1 — the repoint buys
    // margin (5.397:1) and family consistency rather than fixing a failure, and
    // is a no-op in light.
    #expect(sut.pillForeground(.paused) == Color.inkOnWash)
  }

  @Test func pendingStaysOnTheQuietudeTier() {
    // `muted` is design-system §8's deliberately sub-AA quietude tier and is NOT
    // in scope for the self-wash work — its own `muted`-on-`muted` pill is swept
    // app-wide by #1448. Pinned here so that sweep cannot silently take this arm
    // with it.
    #expect(sut.pillForeground(.pending) == Color.muted)
  }
}

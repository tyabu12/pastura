import SwiftUI
import Testing

@testable import Pastura

/// Change-detector for `PredictionOutcomeBadge`'s colour contract
/// (`.claude/rules/view-testing.md` § "Change-detector tripwire for
/// code-review-gated tokens").
///
/// **Not tautological**: the badge is a purely visual surface with no logic to
/// assert and no automated visual coverage (ADR-009 rules out snapshots). Until
/// #1427 its colours were inline in `body` and could not be pinned at all.
///
/// **A failure here is not a bug** — a code-review-gated token drifted, most
/// likely in an unrelated refactor or an ADR-028 pairing slice. Confirm the
/// change passed review, then update the expectation.
///
/// **What it cannot see**: `body`. Re-inlining a colour there diverges from the
/// accessor with these pins still green — held by the badge's doc comment and by
/// review, per `.claude/rules/view-testing.md`.
///
/// Aliases are asserted rather than hex values: every token here is
/// trait-resolving, so this pins *which token* the badge reads and leaves *what
/// value* it carries to `DesignTokensTests`. Asserting two aliases **differ**
/// would be structurally blind (`ScenarioBadgeStyleTokenTests`' closing note).
///
/// `@MainActor` because the accessors and `Color.*` statics are MainActor-isolated
/// (`.claude/rules/swift-isolation.md` Pattern 5, fix order 1).
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PredictionOutcomeBadgeTokenTests {

  /// The §2.6 `<family>Soft` + `<family>Ink` pairing, 6.537 light / 6.505 dark
  /// — the shape #1407 established for text on an opaque `mossSoft` ground.
  @Test func hitArmReadsTheMossSoftInkPairing() {
    let badge = PredictionOutcomeBadge(isHit: true)
    #expect(badge.fillToken == Color.mossSoft)
    #expect(badge.labelToken == Color.mossInk)
  }

  /// `inkSecondary` on `bubbleBackground` = 6.934 / 5.975, replacing `muted`'s
  /// sub-AA 3.475 / 3.021 (#1427). Not `metaBaseL3` (8.577 / 8.161) — it clears
  /// the bar but out-shouts the hit arm's 6.5.
  @Test func missArmReadsInkSecondaryOnTheNeutralGround() {
    let badge = PredictionOutcomeBadge(isHit: false)
    #expect(badge.fillToken == Color.bubbleBackground)
    #expect(badge.labelToken == Color.inkSecondary)
  }

  /// Ground is always the opaque `mossSoft` capsule, so this is the hit label's
  /// pairing again (6.537 / 6.505), replacing `muted`'s 2.136 / 2.413.
  ///
  /// Sharing ``PredictionOutcomeBadge/labelToken``'s token is deliberate, not an
  /// oversight to "fix" with a quieter one — the rejected candidates are pinned
  /// as still-failing in `DesignTokensTests+MutedAsContent`, and subordination
  /// rides on weight instead.
  @Test func streakSubLabelTakesTheSameMossInkAsItsGroundRequires() {
    let badge = PredictionOutcomeBadge(isHit: true, streak: 3)
    #expect(badge.streakToken == Color.mossInk)
  }

  /// The streak accessor is ground-determined, not streak-value-determined —
  /// it must not quietly acquire a branch on `streak`, which would put a
  /// colour decision somewhere this suite's other arms do not look.
  @Test func streakTokenDoesNotVaryWithTheStreakValue() {
    #expect(PredictionOutcomeBadge(isHit: true, streak: 2).streakToken == Color.mossInk)
    #expect(PredictionOutcomeBadge(isHit: true, streak: 99).streakToken == Color.mossInk)
  }
}

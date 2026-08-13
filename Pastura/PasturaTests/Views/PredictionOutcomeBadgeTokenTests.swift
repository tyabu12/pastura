import SwiftUI
import Testing

@testable import Pastura

/// Change-detector for `PredictionOutcomeBadge`'s colour contract
/// (`.claude/rules/view-testing.md` § "Change-detector tripwire for
/// code-review-gated tokens").
///
/// **Why this is not tautological.** The badge is a purely visual surface with
/// no logic to assert and no automated visual coverage — ADR-009 rules out
/// snapshot tests. Until #1427 it was not pinnable at all: it built its colours
/// inline in `body` with no extractable style type, which
/// `DesignTokensTests+MossSoftGround` recorded as the reason only the
/// `HighlightCandidatesSection` chip carried a consumer pin. The accessors this
/// suite reads exist to close that.
///
/// **A failure here is not a bug.** It means a code-review-gated token drifted —
/// most likely in an unrelated refactor or an ADR-028 pairing slice. Confirm the
/// change was intended and passed review, then update the expectation.
///
/// **What this suite cannot see.** It reads the accessors, not `body`. If a
/// future edit re-inlines a colour in `body`, the accessor and the rendered
/// value diverge and these pins stay green while the app ships wrong. That gap
/// is held by the badge's own doc comment ("keep `body` free of `Color.`
/// references") and by review, not by this file — a snapshot is the only
/// mechanical closure and ADR-009 refuses it.
///
/// **Why assert the alias, not the hex.** Every token read here is
/// trait-resolving (`PasturaDynamicPalette`), so an alias comparison pins *which
/// token* the badge reads and leaves *what value* it carries to
/// `DesignTokensTests`. Asserting two aliases **differ** would be structurally
/// blind — see `ScenarioBadgeStyleTokenTests`' closing note for the probe.
///
/// `@MainActor` is required because the suite reads `Color.*` statics and the
/// accessors are themselves MainActor-isolated (`.claude/rules/swift-isolation.md`
/// Pattern 5, fix order 1).
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
  /// 3.475 / 3.021 (sub-AA in both appearances, #1427). Not `metaBaseL3`
  /// (8.577 / 8.161): that clears the bar but out-shouts the hit arm's 6.5, and
  /// ADR-028 holds that a supporting element must not become the loudest thing
  /// in the row.
  @Test func missArmReadsInkSecondaryOnTheNeutralGround() {
    let badge = PredictionOutcomeBadge(isHit: false)
    #expect(badge.fillToken == Color.bubbleBackground)
    #expect(badge.labelToken == Color.inkSecondary)
  }

  /// The streak sub-label renders only on the hit arm, so its ground is always
  /// the opaque `mossSoft` capsule — same pairing as the hit label, 6.537 /
  /// 6.505, replacing `muted`'s 2.136 / 2.413.
  ///
  /// Reading the *same* token as ``PredictionOutcomeBadge/labelToken``'s hit arm
  /// is deliberate, not an oversight to be "fixed" by reaching for a quieter
  /// one: the two rejected candidates are pinned as still-failing in
  /// `DesignTokensTests+MutedAsContent`, and the §2.4 rung that would have
  /// worked is refused by ADR-028 § "Three narrower rejections". Subordination
  /// to "Correct!" is carried by weight (`.medium` vs `.semibold`).
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

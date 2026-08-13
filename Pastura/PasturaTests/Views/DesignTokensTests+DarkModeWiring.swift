import SwiftUI
import Testing
import UIKit

@testable import Pastura

// Wiring half of the §2.9 dark-mode token-pair tests: that the `Color.*`
// aliases are actually dynamic, and that the unpaired ones are not.
//
// Split out of `DesignTokensTests+DarkMode.swift` at #1313. The axis is the
// per-pair enumerations: these two tests carry a hand-written row per pair, so
// they grow with every gate-1 slice while the mechanism gate, the pair table
// and the distinguishability control do not. That file was at 327 lines
// against swiftlint's 400-line `file_length` cap.
//
// Sibling-file extension of `DesignTokensTests` per `.claude/rules/testing.md`
// § "Splitting a Suite Across Files" — a fresh `@Suite` would run in parallel
// with the parent and is explicitly forbidden. Inherits the parent's
// `@MainActor` (required for auto-synth conformance lookup from these
// assertions — `swift-isolation.md` Pattern 5) and `.timeLimit(.minutes(1))`,
// and reaches the environment / comparison helpers in
// `DesignTokensTests+DarkMode.swift`, which are internal-not-private for
// exactly this reason.
extension DesignTokensTests {

  // MARK: - Wiring (the `Color.*` aliases are dynamic, not static)
  //
  // Asserting only the pair contents would pass even if
  // `DesignTokens+SwiftUI.swift` were reverted to static aliases, so these
  // probe `Color.*` itself.
  //
  // The tolerance absorbs the **UIColor round trip**: the alias side goes
  // `Color(UIColor(dynamicProvider:))` → UIKit resolve → `Color.Resolved`,
  // while the expected side is `Color(.sRGB, …)` → `Color.Resolved`. Only the
  // final linear conversion is shared, so these are NOT one pipeline and an
  // exact equality check would be a false red. Note the tolerance is in
  // **linear** space and therefore non-uniform — measured, ~16 8-bit steps of
  // slack near black but only ~0.6 of a step near white. Metric: the **minimum
  // per-channel gap** after the sRGB→linear transform (the conservative
  // aggregation; a max-channel reading gives larger multiples), computed over
  // RGB — including alpha collapses every opaque pair to 0, since both sides
  // are 1.0.
  //
  // By that metric the closest opaque pair is `metaBaseL1`↔`nightMetaBaseL1` at
  // 6.8x the tolerance since #1313 — mid-tone pairs are intrinsically close,
  // because a grey placed correctly on a pale ground and one placed correctly on
  // a dark ground land near each other. Before that the narrowest was
  // `muted`↔`nightMuted` at 11.9x, then `moss` and `focusRing` at 19.2x. The
  // three §2.7 overlays are the exception —
  // their RGB gap is 19.2x but their alpha gap is only 4.0x (`hover`), 8.0x
  // (`pressed`) and 12.0x (`selected`).
  //
  // Do NOT extend this note for a new pair by recomputing the number. The
  // arithmetic is no longer what guards the bound —
  // `everyPairsTwoSidesAreDistinguishableAtTolerance` below asserts the property
  // this paragraph used to estimate, for every pair, including the alpha
  // channel and whatever `Color.Resolved` does to it.

  @Test func pairedAliasesResolveDarkUnderDarkColorScheme() {
    let cases: [(alias: Color, dark: PasturaColorValue)] =
      [
        (.screenBackground, PasturaPalette.nightBackground),
        (.bubbleBackground, PasturaPalette.nightBubble),
        (.whisperBubble, PasturaPalette.nightWhisperBubble),
        (.ink, PasturaPalette.nightInk),
        (.inkSecondary, PasturaPalette.nightInkSecondary),
        (.muted, PasturaPalette.nightMuted),
        (.rule, PasturaPalette.nightRule),
        (.moss, PasturaPalette.nightMoss),
        (.info, PasturaPalette.nightInfo),
        (.infoSoft, PasturaPalette.nightInfoSoft),
        (.infoInk, PasturaPalette.nightInfoInk),
        (.success, PasturaPalette.nightSuccess),
        (.successSoft, PasturaPalette.nightSuccessSoft),
        (.successInk, PasturaPalette.nightSuccessInk),
        (.warning, PasturaPalette.nightWarning),
        (.warningSoft, PasturaPalette.nightWarningSoft),
        (.warningInk, PasturaPalette.nightWarningInk),
        (.danger, PasturaPalette.nightDanger),
        (.dangerSoft, PasturaPalette.nightDangerSoft),
        (.dangerInk, PasturaPalette.nightDangerInk),
        (.hover, PasturaPalette.nightHover),
        (.pressed, PasturaPalette.nightPressed),
        (.selected, PasturaPalette.nightSelected),
        (.focusRing, PasturaPalette.nightFocusRing),
        (.disabledText, PasturaPalette.nightDisabledText),
        (.disabledBackground, PasturaPalette.nightDisabledBackground),
        (.metaBaseL1, PasturaPalette.nightMetaBaseL1),
        (.metaStrongL1, PasturaPalette.nightMetaStrongL1),
        (.metaDotOnL1, PasturaPalette.nightMetaDotOnL1),
        (.metaBaseL2, PasturaPalette.nightMetaBaseL2),
        (.metaStrongL2, PasturaPalette.nightMetaStrongL2),
        (.metaDotOnL2, PasturaPalette.nightMetaDotOnL2),
        (.metaBaseL3, PasturaPalette.nightMetaBaseL3),
        (.metaStrongL3, PasturaPalette.nightMetaStrongL3),
        (.metaDotOnL3, PasturaPalette.nightMetaDotOnL3),
        (.metaBaseL4, PasturaPalette.nightMetaBaseL4),
        (.metaStrongL4, PasturaPalette.nightMetaStrongL4),
        (.metaDotOnL4, PasturaPalette.nightMetaDotOnL4),
        (.headerRule, PasturaPalette.nightHeaderRule),
        (.headerMetaInk, PasturaPalette.nightHeaderMetaInk)
      ] + avatarDarkPairs() + remainderDarkPairs()

    // The list is hand-written on purpose — it is what proves the *alias* is
    // wired, which iterating `all` cannot show. This pins its size to the
    // registry so a pair added to one and not the other is caught.
    #expect(cases.count == PasturaDynamicPalette.all.count)

    for (alias, dark) in cases {
      let resolvedAlias = alias.resolve(in: darkEnvironment())
      let resolvedExpected = dark.color.resolve(in: darkEnvironment())
      #expect(resolvedComponentsMatch(resolvedAlias, resolvedExpected))
    }
  }

  @Test func pairedAliasesStillResolveLightUnderLightColorScheme() {
    let cases: [(alias: Color, light: PasturaColorValue)] =
      [
        (.screenBackground, PasturaPalette.screenBackground),
        (.bubbleBackground, PasturaPalette.bubbleBackground),
        (.whisperBubble, PasturaPalette.whisperBubble),
        (.ink, PasturaPalette.ink),
        (.inkSecondary, PasturaPalette.inkSecondary),
        (.muted, PasturaPalette.muted),
        (.rule, PasturaPalette.rule),
        (.moss, PasturaPalette.moss),
        (.info, PasturaPalette.info),
        (.infoSoft, PasturaPalette.infoSoft),
        (.infoInk, PasturaPalette.infoInk),
        (.success, PasturaPalette.success),
        (.successSoft, PasturaPalette.successSoft),
        (.successInk, PasturaPalette.successInk),
        (.warning, PasturaPalette.warning),
        (.warningSoft, PasturaPalette.warningSoft),
        (.warningInk, PasturaPalette.warningInk),
        (.danger, PasturaPalette.danger),
        (.dangerSoft, PasturaPalette.dangerSoft),
        (.dangerInk, PasturaPalette.dangerInk),
        (.hover, PasturaPalette.hover),
        (.pressed, PasturaPalette.pressed),
        (.selected, PasturaPalette.selected),
        (.focusRing, PasturaPalette.focusRing),
        (.disabledText, PasturaPalette.disabledText),
        (.disabledBackground, PasturaPalette.disabledBackground),
        (.metaBaseL1, PasturaPalette.metaBaseL1),
        (.metaStrongL1, PasturaPalette.metaStrongL1),
        (.metaDotOnL1, PasturaPalette.metaDotOnL1),
        (.metaBaseL2, PasturaPalette.metaBaseL2),
        (.metaStrongL2, PasturaPalette.metaStrongL2),
        (.metaDotOnL2, PasturaPalette.metaDotOnL2),
        (.metaBaseL3, PasturaPalette.metaBaseL3),
        (.metaStrongL3, PasturaPalette.metaStrongL3),
        (.metaDotOnL3, PasturaPalette.metaDotOnL3),
        (.metaBaseL4, PasturaPalette.metaBaseL4),
        (.metaStrongL4, PasturaPalette.metaStrongL4),
        (.metaDotOnL4, PasturaPalette.metaDotOnL4),
        (.headerRule, PasturaPalette.headerRule),
        (.headerMetaInk, PasturaPalette.headerMetaInk)
      ] + avatarLightPairs() + remainderLightPairs()

    #expect(cases.count == PasturaDynamicPalette.all.count)

    for (alias, light) in cases {
      let resolvedAlias = alias.resolve(in: lightEnvironment())
      let resolvedExpected = light.color.resolve(in: lightEnvironment())
      #expect(resolvedComponentsMatch(resolvedAlias, resolvedExpected))
    }
  }

  /// Smoke test that the one unpaired token stays scheme-invariant. Honest about
  /// its strength: it is a plain `Color(.sRGB, …)` value with no trait dependency,
  /// so invariance holds by *type*, not by wiring, and it has no `night*`
  /// counterpart — so no plausible edit to this feature reddens it. It documents
  /// the intended light-only boundary; it does not police it. A real control would
  /// need an over-application mechanism to exist first.
  @Test func unpairedAliasesDoNotChangeAcrossColorSchemes() {
    // Refilled four times as slices landed — `.warning` / `.danger` left with
    // #1282, `.metaBaseL3` with #1313, `.avatarBodyAlice` with #1319 — and slice
    // 4 emptied it of that kind of member entirely: `.page`, `.promoBackground`,
    // `.mossSoft`, `.inkOnAccent` and `.link` all became paired at once, which is
    // what closing gate 1 means.
    //
    // What is left is the **other** kind, and it is the only member that was never
    // expected to leave: `.headerMetaSubdued` is unpaired *by decision* rather
    // than by not-yet-designed (ADR-028 gate 1 admits a recorded fixed value in
    // place of a designed one). Why fixing is right for it is asserted separately
    // in `DesignTokensTests+NightMeta` (it moved there with §2.4/§2.12 in slice 4).
    //
    // So this list is now terminal rather than draining. If a future change pairs
    // `headerMetaSubdued`, delete the test rather than emptying the array — an
    // empty `for` loop asserts nothing while still passing.
    let lightOnly: [Color] = [.headerMetaSubdued]

    for alias in lightOnly {
      let underLight = alias.resolve(in: lightEnvironment())
      let underDark = alias.resolve(in: darkEnvironment())
      #expect(resolvedComponentsMatch(underLight, underDark))
    }
  }

  // MARK: - §2.5 rows, extracted

  // Extracted from the two tables above purely for swiftlint's
  // `function_body_length` (50): the §2.5 slice added 17 rows to each and both
  // bodies crossed the cap. Deliberately still HAND-WRITTEN per alias rather
  // than driven from `PasturaDynamicPalette.all` — driving them from the
  // registry would make the wiring tests assert the registry against itself,
  // which is exactly the independence that makes them worth having.

  /// §2.1/§2.2/§2.3/§2.8 rows, extracted for the same reason as the §2.5 ones
  /// above: appending twelve more rows inline pushes both table bodies past
  /// swiftlint's `function_body_length`, and `build-traps.md` rules out the
  /// disable-directive route on a declaration carrying a doc comment.
  func remainderDarkPairs() -> [(alias: Color, dark: PasturaColorValue)] {
    [
      (.page, PasturaPalette.nightPage),
      (.promoBackground, PasturaPalette.nightPromoBackground),
      (.promoBorder, PasturaPalette.nightPromoBorder),
      (.inkOnAccent, PasturaPalette.nightInkOnAccent),
      (.mossDark, PasturaPalette.nightMossDark),
      (.mossInk, PasturaPalette.nightMossInk),
      (.mossSoft, PasturaPalette.nightMossSoft),
      (.mossOnWash, PasturaPalette.nightMossOnWash),
      (.inkOnWash, PasturaPalette.nightInkOnWash),
      (.link, PasturaPalette.nightLink),
      (.linkVisited, PasturaPalette.nightLinkVisited),
      (.linkHover, PasturaPalette.nightLinkHover)
    ]
  }

  /// Light halves of the same twelve. See `remainderDarkPairs()`.
  func remainderLightPairs() -> [(alias: Color, light: PasturaColorValue)] {
    [
      (.page, PasturaPalette.page),
      (.promoBackground, PasturaPalette.promoBackground),
      (.promoBorder, PasturaPalette.promoBorder),
      (.inkOnAccent, PasturaPalette.inkOnAccent),
      (.mossDark, PasturaPalette.mossDark),
      (.mossInk, PasturaPalette.mossInk),
      (.mossSoft, PasturaPalette.mossSoft),
      (.mossOnWash, PasturaPalette.mossOnWash),
      (.inkOnWash, PasturaPalette.inkOnWash),
      (.link, PasturaPalette.link),
      (.linkVisited, PasturaPalette.linkVisited),
      (.linkHover, PasturaPalette.linkHover)
    ]
  }

  func avatarDarkPairs() -> [(alias: Color, dark: PasturaColorValue)] {
    [
      (.avatarBodyAlice, PasturaPalette.nightAvatarBodyAlice),
      (.avatarBodyBob, PasturaPalette.nightAvatarBodyBob),
      (.avatarBodyCarol, PasturaPalette.nightAvatarBodyCarol),
      (.avatarBodyDave, PasturaPalette.nightAvatarBodyDave),
      (.avatarFaceAlice, PasturaPalette.nightAvatarFaceAlice),
      (.avatarFaceBob, PasturaPalette.nightAvatarFaceBob),
      (.avatarFaceCarol, PasturaPalette.nightAvatarFaceCarol),
      (.avatarFaceDave, PasturaPalette.nightAvatarFaceDave),
      (.avatarHornAlice, PasturaPalette.nightAvatarHornAlice),
      (.avatarHornBob, PasturaPalette.nightAvatarHornBob),
      (.avatarHornCarol, PasturaPalette.nightAvatarHornCarol),
      (.avatarHornDave, PasturaPalette.nightAvatarHornDave),
      (.avatarEar, PasturaPalette.nightAvatarEar),
      (.avatarEarInner, PasturaPalette.nightAvatarEarInner),
      (.avatarNose, PasturaPalette.nightAvatarNose),
      (.avatarEye, PasturaPalette.nightAvatarEye),
      (.avatarHighlight, PasturaPalette.nightAvatarHighlight)
    ]
  }

  func avatarLightPairs() -> [(alias: Color, light: PasturaColorValue)] {
    [
      (.avatarBodyAlice, PasturaPalette.avatarBodyAlice),
      (.avatarBodyBob, PasturaPalette.avatarBodyBob),
      (.avatarBodyCarol, PasturaPalette.avatarBodyCarol),
      (.avatarBodyDave, PasturaPalette.avatarBodyDave),
      (.avatarFaceAlice, PasturaPalette.avatarFaceAlice),
      (.avatarFaceBob, PasturaPalette.avatarFaceBob),
      (.avatarFaceCarol, PasturaPalette.avatarFaceCarol),
      (.avatarFaceDave, PasturaPalette.avatarFaceDave),
      (.avatarHornAlice, PasturaPalette.avatarHornAlice),
      (.avatarHornBob, PasturaPalette.avatarHornBob),
      (.avatarHornCarol, PasturaPalette.avatarHornCarol),
      (.avatarHornDave, PasturaPalette.avatarHornDave),
      (.avatarEar, PasturaPalette.avatarEar),
      (.avatarEarInner, PasturaPalette.avatarEarInner),
      (.avatarNose, PasturaPalette.avatarNose),
      (.avatarEye, PasturaPalette.avatarEye),
      (.avatarHighlight, PasturaPalette.avatarHighlight)
    ]
  }
}

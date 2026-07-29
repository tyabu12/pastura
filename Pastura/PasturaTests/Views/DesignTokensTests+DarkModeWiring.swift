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
  // By that metric the closest opaque pair is `muted`↔`nightMuted` at 11.9x the
  // tolerance, next `moss` and `focusRing` at 19.2x; #1282's slice adds nothing
  // tighter than `warning` at 15.2x. The three §2.7 overlays are the exception —
  // their RGB gap is 19.2x but their alpha gap is only 4.0x (`hover`), 8.0x
  // (`pressed`) and 12.0x (`selected`).
  //
  // Do NOT extend this note for a new pair by recomputing the number. The
  // arithmetic is no longer what guards the bound —
  // `everyPairsTwoSidesAreDistinguishableAtTolerance` below asserts the property
  // this paragraph used to estimate, for every pair, including the alpha
  // channel and whatever `Color.Resolved` does to it.

  @Test func pairedAliasesResolveDarkUnderDarkColorScheme() {
    let cases: [(alias: Color, dark: PasturaColorValue)] = [
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
      (.disabledBackground, PasturaPalette.nightDisabledBackground)
    ]

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
    let cases: [(alias: Color, light: PasturaColorValue)] = [
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
      (.disabledBackground, PasturaPalette.disabledBackground)
    ]

    #expect(cases.count == PasturaDynamicPalette.all.count)

    for (alias, light) in cases {
      let resolvedAlias = alias.resolve(in: lightEnvironment())
      let resolvedExpected = light.color.resolve(in: lightEnvironment())
      #expect(resolvedComponentsMatch(resolvedAlias, resolvedExpected))
    }
  }

  /// Smoke test that unpaired tokens stay scheme-invariant. Honest about its
  /// strength: these are plain `Color(.sRGB, …)` values with no trait
  /// dependency, so invariance holds by *type*, not by wiring — and none has a
  /// `night*` counterpart, so no plausible edit to this feature reddens it. It
  /// documents the intended light-only boundary; it does not police it. A real
  /// control would need an over-application mechanism to exist first.
  @Test func unpairedAliasesDoNotChangeAcrossColorSchemes() {
    // `.warning` / `.danger` used to sit here and were paired by #1282's slice;
    // refilled from the 42 that remain unpaired, spread across §2.1/§2.3/§2.4/
    // §2.5/§2.8 so a future slice removing one leaves the rest.
    let lightOnly: [Color] = [
      .page, .promoBackground, .mossSoft, .inkOnAccent, .metaBaseL3, .avatarBodyAlice, .link
    ]

    for alias in lightOnly {
      let underLight = alias.resolve(in: lightEnvironment())
      let underDark = alias.resolve(in: darkEnvironment())
      #expect(resolvedComponentsMatch(underLight, underDark))
    }
  }
}

import Foundation
import Testing

@testable import Pastura

// sRGB component assertions for the §2.9 dark counterparts added by #1282's
// slice 1 (ADR-028 § Rollout gate 1) — the §2.6 alert family and the §2.7
// interactive states.
//
// Lives here rather than in `DesignTokensTests.swift` because that file sits at
// 349 lines and these assertions would push it past swiftlint's 400-line
// `file_length` cap.
//
// §2.4's meta presets and §2.12's header slots were asserted here too until
// slice 4 moved them to `DesignTokensTests+NightMeta.swift`, on the per-section
// axis, to make room for that slice's own §2.1/§2.3/§2.8 invariants. The shared
// colour-maths helpers stayed at the foot of this file — see their doc comments.
//
// Sibling-file extension of `DesignTokensTests` per `.claude/rules/testing.md`
// § "Splitting a Suite Across Files" — a fresh `@Suite` would run in parallel
// with the parent and is explicitly forbidden. Inherits the parent's
// `@MainActor` and `.timeLimit(.minutes(1))`, and reaches its `approxEqual`
// helper, which is internal-not-private for exactly this reason.
//
// These assert the VALUES. That the aliases are actually *wired* to them is a
// separate concern, covered in `DesignTokensTests+DarkMode.swift`.
extension DesignTokensTests {

  // MARK: - §2.9 dark counterparts of the §2.6 alert family

  @Test func nightAlertFamilyMatchesSpec() {
    let cases: [(token: PasturaColorValue, hex: UInt32)] = [
      (PasturaPalette.nightInfo, 0x97ABC4),
      (PasturaPalette.nightInfoSoft, 0x252D37),
      (PasturaPalette.nightInfoInk, 0xB3C5DB),
      (PasturaPalette.nightSuccess, 0x95B189),
      (PasturaPalette.nightSuccessSoft, 0x2A3725),
      (PasturaPalette.nightSuccessInk, 0xBFDBB3),
      (PasturaPalette.nightWarning, 0xD4B67E),
      (PasturaPalette.nightWarningSoft, 0x383124),
      (PasturaPalette.nightWarningInk, 0xE0CEAE),
      (PasturaPalette.nightDanger, 0xCE9790),
      (PasturaPalette.nightDangerSoft, 0x382624),
      (PasturaPalette.nightDangerInk, 0xE0B4AE)
    ]

    for (token, hex) in cases {
      #expect(approxEqual(token.red, Double((hex >> 16) & 0xFF) / 255.0))
      #expect(approxEqual(token.green, Double((hex >> 8) & 0xFF) / 255.0))
      #expect(approxEqual(token.blue, Double(hex & 0xFF) / 255.0))
      #expect(approxEqual(token.opacity, 1.0))
    }
  }

  // MARK: - §2.9 dark counterparts of the §2.7 interactive states

  /// The three washes carry their own alpha, so they are asserted apart from the
  /// opaque tokens below. All three share `nightMoss`'s RGB — that is the point
  /// (they are the brand accent at three depths), so a wrong value here shows up
  /// as a wrong *alpha*.
  @Test func nightInteractiveWashesMatchSpec() {
    let cases: [(token: PasturaColorValue, opacity: Double)] = [
      (PasturaPalette.nightHover, 0.08),
      (PasturaPalette.nightPressed, 0.16),
      (PasturaPalette.nightSelected, 0.24)
    ]

    for (token, opacity) in cases {
      #expect(approxEqual(token.red, 168.0 / 255.0))
      #expect(approxEqual(token.green, 184.0 / 255.0))
      #expect(approxEqual(token.blue, 136.0 / 255.0))
      #expect(approxEqual(token.opacity, opacity))
    }
  }

  @Test func nightOpaqueInteractiveStatesMatchSpec() {
    let cases: [(token: PasturaColorValue, hex: UInt32)] = [
      (PasturaPalette.nightFocusRing, 0xA8B888),
      (PasturaPalette.nightDisabledText, 0x605F54),
      (PasturaPalette.nightDisabledBackground, 0x222420)
    ]

    for (token, hex) in cases {
      #expect(approxEqual(token.red, Double((hex >> 16) & 0xFF) / 255.0))
      #expect(approxEqual(token.green, Double((hex >> 8) & 0xFF) / 255.0))
      #expect(approxEqual(token.blue, Double(hex & 0xFF) / 255.0))
      #expect(approxEqual(token.opacity, 1.0))
    }
  }

  /// `nightFocusRing` deliberately re-states `nightMoss`'s hex, exactly as
  /// `focusRing` re-states `moss` in light: a separate semantic anchor so a
  /// future shift in the brand accent does not silently redefine focus
  /// appearance. Pinned because the equality is intentional — a reader finding
  /// two identical hexes would otherwise reasonably collapse them.
  @Test func nightFocusRingIntentionallyMatchesNightMoss() {
    #expect(PasturaPalette.nightFocusRing == PasturaPalette.nightMoss)
  }

  /// `nightDisabledBackground` must sit BELOW `nightBubble` in luminance. In
  /// dark, "lighter" already means "raised" — that is what the §2.7 washes do —
  /// so an inert surface has to go the other way. A future edit that lifts it
  /// above the card surface would make disabled read as *selected*.
  @Test func nightDisabledBackgroundSinksBelowTheCardSurface() {
    #expect(
      relativeLuminance(PasturaPalette.nightDisabledBackground)
        < relativeLuminance(PasturaPalette.nightBubble))
  }

}

// MARK: - Helpers

/// WCAG relative luminance of a token — used here by the `nightDisabledBackground`
/// ordering assertion, and by `contrastRatio` below.
///
/// File-scope and **internal, not `private`**: this and `contrastRatio` /
/// `composite` below are the shared colour maths for the whole §2.9 test family —
/// `DesignTokensTests+NightMeta.swift` (§2.4/§2.12) and
/// `DesignTokensTests+NightAvatarInvariants.swift` (§2.5) both build on them, and
/// `private` at file scope is invisible to a sibling file (see
/// `.claude/rules/testing.md` § "Splitting a Suite Across Files"). Kept out of
/// the parent suite so `DesignTokensTests.swift` stays under its line budget.
///
/// Two of the three therefore have **no caller in this file** — that is the
/// split's doing, not dead code. Do not follow the callers and move them:
/// they are declared once for three consumers, and this file is the §2.9 root.
///
/// `@MainActor` is load-bearing, and is the cross-module corollary in
/// `.claude/rules/swift-isolation.md` § "Same cause, two non-test shapes":
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set on the app target only, so
/// a file-scope `private func` here is nonisolated — and Swift's exemption for
/// reading immutable `Sendable` `let` storage of a global-actor-isolated type
/// applies only *within* the declaring module. Without it the component reads
/// below fail with "Main actor-isolated property 'red' can not be referenced
/// from a nonisolated context". Same shape as `sRGBComponentsMatch` in
/// `DesignTokensTests+DarkMode.swift`.
@MainActor
func relativeLuminance(_ token: PasturaColorValue) -> Double {
  func channel(_ value: Double) -> Double {
    value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
  }
  return 0.2126 * channel(token.red)
    + 0.7152 * channel(token.green)
    + 0.0722 * channel(token.blue)
}

/// WCAG contrast ratio between two tokens. Same `@MainActor` reasoning as
/// `relativeLuminance` above, which it builds on.
@MainActor
func contrastRatio(_ lhs: PasturaColorValue, _ rhs: PasturaColorValue) -> Double {
  let left = relativeLuminance(lhs)
  let right = relativeLuminance(rhs)
  return (max(left, right) + 0.05) / (min(left, right) + 0.05)
}

/// Source-over composite of `token` at `alpha` onto `background`, for the
/// unlit-progress-dot floor in `DesignTokensTests+NightMeta.swift`.
/// `PromoCard` renders the unlit dots as
/// `Color.moss.opacity(0.38)`, and `moss` is a paired token, so in dark that
/// resolves to `nightMoss` at the same alpha over the card surface.
@MainActor
func composite(
  _ token: PasturaColorValue, over background: PasturaColorValue, alpha: Double
) -> PasturaColorValue {
  PasturaColorValue(
    red: token.red * alpha + background.red * (1 - alpha),
    green: token.green * alpha + background.green * (1 - alpha),
    blue: token.blue * alpha + background.blue * (1 - alpha),
    opacity: 1.0)
}

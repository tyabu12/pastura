import SwiftUI
import Testing
import UIKit

@testable import Pastura

// §2.9 dark-mode token-pair tests. Protects ADR-028's mechanism decision:
// `PasturaDynamicColor` resolves a light/dark pair through a `UIColor` dynamic
// provider, and the eight paired `Color.*` aliases are actually wired to it.
//
// Sibling-file extension of `DesignTokensTests` per `.claude/rules/testing.md`
// § "Splitting a Suite Across Files" — a fresh `@Suite` would run in parallel
// with the parent and is explicitly forbidden. Inherits the parent's
// `@MainActor` (required for auto-synth conformance lookup from these
// assertions — `swift-isolation.md` Pattern 5) and `.timeLimit(.minutes(1))`.
extension DesignTokensTests {

  // MARK: - Mechanism gate (UIColor dynamic provider)
  //
  // This is the load-bearing observation of ADR-028's mechanism claim. It goes
  // through `UIColor.resolvedColor(with:)` rather than SwiftUI, because that is
  // deterministic and does not pass through `Color.Resolved`, which
  // `DesignTokens.swift` documents as linear-light and lossy. If THIS reddens,
  // the mechanism itself is wrong.

  @Test func dynamicPairResolvesEachSideViaTraitCollection() {
    let pair = PasturaDynamicColor(
      light: PasturaPalette.ink, dark: PasturaPalette.nightInk)

    let resolvedLight = pair.uiColor.resolvedColor(
      with: UITraitCollection(userInterfaceStyle: .light))
    let resolvedDark = pair.uiColor.resolvedColor(
      with: UITraitCollection(userInterfaceStyle: .dark))

    #expect(sRGBComponentsMatch(resolvedLight, PasturaPalette.ink))
    #expect(sRGBComponentsMatch(resolvedDark, PasturaPalette.nightInk))
  }

  /// `.unspecified` must fall to the light value — the provider branches on
  /// `== .dark`, so an inverted condition would surface here.
  @Test func dynamicPairFallsToLightOnUnspecifiedTrait() {
    let pair = PasturaDynamicColor(
      light: PasturaPalette.moss, dark: PasturaPalette.nightMoss)

    let resolved = pair.uiColor.resolvedColor(
      with: UITraitCollection(userInterfaceStyle: .unspecified))

    #expect(sRGBComponentsMatch(resolved, PasturaPalette.moss))
  }

  // MARK: - Wiring (the `Color.*` aliases are dynamic, not static)
  //
  // Asserting only the pair contents would pass even if
  // `DesignTokens+SwiftUI.swift` were reverted to static aliases, so these
  // probe `Color.*` itself. Comparison is tolerance-based and always between
  // two resolutions from the SAME pipeline, so `Color.Resolved`'s
  // linear-light encoding cancels out — do NOT "fix" this into an equality
  // check against a raw sRGB component, which would be a false red.

  @Test func pairedAliasesResolveDarkUnderDarkColorScheme() {
    let cases: [(alias: Color, dark: PasturaColorValue)] = [
      (.screenBackground, PasturaPalette.nightBackground),
      (.bubbleBackground, PasturaPalette.nightBubble),
      (.whisperBubble, PasturaPalette.nightWhisperBubble),
      (.ink, PasturaPalette.nightInk),
      (.inkSecondary, PasturaPalette.nightInkSecondary),
      (.muted, PasturaPalette.nightMuted),
      (.rule, PasturaPalette.nightRule),
      (.moss, PasturaPalette.nightMoss)
    ]

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
      (.moss, PasturaPalette.moss)
    ]

    for (alias, light) in cases {
      let resolvedAlias = alias.resolve(in: lightEnvironment())
      let resolvedExpected = light.color.resolve(in: lightEnvironment())
      #expect(resolvedComponentsMatch(resolvedAlias, resolvedExpected))
    }
  }

  /// Negative control. An unpaired token must resolve IDENTICALLY under both
  /// schemes — without this, a hypothetical bug that made *every* alias
  /// dark-shifted would still satisfy the assertions above.
  @Test func unpairedAliasesDoNotChangeAcrossColorSchemes() {
    let lightOnly: [Color] = [.page, .promoBackground, .warning, .danger, .mossSoft]

    for alias in lightOnly {
      let underLight = alias.resolve(in: lightEnvironment())
      let underDark = alias.resolve(in: darkEnvironment())
      #expect(resolvedComponentsMatch(underLight, underDark))
    }
  }

  // MARK: - Pair table (matches design-system.md §2.9)

  @Test func declaredPairsMatchTheDesignSystemTable() {
    #expect(PasturaDynamicPalette.screenBackground.dark == PasturaPalette.nightBackground)
    #expect(PasturaDynamicPalette.bubbleBackground.dark == PasturaPalette.nightBubble)
    #expect(PasturaDynamicPalette.whisperBubble.dark == PasturaPalette.nightWhisperBubble)
    #expect(PasturaDynamicPalette.ink.dark == PasturaPalette.nightInk)
    #expect(PasturaDynamicPalette.inkSecondary.dark == PasturaPalette.nightInkSecondary)
    #expect(PasturaDynamicPalette.muted.dark == PasturaPalette.nightMuted)
    #expect(PasturaDynamicPalette.rule.dark == PasturaPalette.nightRule)
    #expect(PasturaDynamicPalette.moss.dark == PasturaPalette.nightMoss)
  }

  /// Drift guard, not a tautology: §2.9 defines NINE `night*` tokens but only
  /// EIGHT are pairable, because `nightSurface` and `nightBubble` both claim
  /// `bubbleBackground` as their day partner. A future contributor wiring a
  /// ninth pair must first resolve that double-mapping (ADR-028 §
  /// "nightSurface"), so this count is a deliberate speed bump.
  @Test func exactlyEightPairsAreWired() {
    #expect(PasturaDynamicPalette.all.count == 8)
    #expect(Set(PasturaDynamicPalette.all.map(\.name)).count == 8)
  }

  /// `nightSurface` is defined in the palette but deliberately unwired. If it
  /// ever gains a light partner this test should be deleted along with the
  /// ADR-028 deferral.
  @Test func nightSurfaceIsDefinedButNotWired() {
    #expect(PasturaPalette.nightSurface.opacity == 1.0)
    #expect(!PasturaDynamicPalette.all.contains { $0.pair.dark == PasturaPalette.nightSurface })
  }
}

// MARK: - Helpers

/// `EnvironmentValues` pinned to dark, for `Color.resolve(in:)`.
private func darkEnvironment() -> EnvironmentValues {
  var env = EnvironmentValues()
  env.colorScheme = .dark
  return env
}

/// `EnvironmentValues` pinned to light, for `Color.resolve(in:)`.
private func lightEnvironment() -> EnvironmentValues {
  var env = EnvironmentValues()
  env.colorScheme = .light
  return env
}

/// Compares a resolved `UIColor`'s sRGB components against a token. Exact
/// (0.001) because this path does not go through `Color.Resolved`.
///
/// `@MainActor` is required, not decorative: `PasturaColorValue`'s stored
/// properties are MainActor-isolated under `Views/`'s default isolation, so a
/// nonisolated file-scope helper cannot read them.
@MainActor
private func sRGBComponentsMatch(
  _ resolved: UIColor, _ token: PasturaColorValue, tolerance: CGFloat = 0.001
) -> Bool {
  var red: CGFloat = 0
  var green: CGFloat = 0
  var blue: CGFloat = 0
  var alpha: CGFloat = 0
  guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return false }
  return abs(red - token.red) < tolerance
    && abs(green - token.green) < tolerance
    && abs(blue - token.blue) < tolerance
    && abs(alpha - token.opacity) < tolerance
}

/// Compares two `Color.Resolved` values. Tolerance is looser than the UIColor
/// path because both sides have been through SwiftUI's linear-light round trip.
private func resolvedComponentsMatch(
  _ lhs: Color.Resolved, _ rhs: Color.Resolved, tolerance: Float = 0.005
) -> Bool {
  abs(lhs.red - rhs.red) < tolerance
    && abs(lhs.green - rhs.green) < tolerance
    && abs(lhs.blue - rhs.blue) < tolerance
    && abs(lhs.opacity - rhs.opacity) < tolerance
}

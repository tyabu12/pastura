import SwiftUI

// The §2.9 dark half of the palette — every `night*` raw token, in one file.
//
// Split out of `DesignTokens+ExtendedPalette.swift` when ADR-028 gate 1's
// slice 2 landed (#1313). The split axis is "the night data leaves the day
// file", chosen so the §2.9 family stays whole: slice 1 was talked out of a
// split on the grounds that it would fragment that family, and splitting by
// section (§2.6-2.7 here, §2.4/§2.12 there) would have done exactly that.
// Arithmetic behind it: at ~4.4 net lines per token, the remaining gate-1
// slices put `DesignTokens+ExtendedPalette.swift` near 470 lines, past
// swiftlint's 400-line `file_length` cap.
//
// **Keep the `DesignTokens` filename prefix.** `check_design_tokens_css.py`
// globs `Pastura/Pastura/Views/DesignTokens*.swift`, and this file is where
// the `night*` hex literals now live — rename it out of that glob and the
// `tokens.css` mirror gate goes blind with no signal.
//
// Every token here is the dark half of a `PasturaDynamicPalette` pair
// (`DesignTokens+DynamicPalette.swift`), reached through the repointed light
// `Color.*` alias rather than through `Color.night*`. Dark never actually
// renders while `Info.plist` pins `UIUserInterfaceStyle` to Light.

extension PasturaPalette {

  // MARK: §2.9 Dark Mode (night pasture)
  //
  // Day tones translated to a "night pasture" variant — moss brightened,
  // cream replaced by warm dark surfaces. These are **wired**: every token
  // below is the dark half of a `PasturaDynamicPalette` pair, reached through
  // the repointed light `Color.*` alias rather than through `Color.night*`.
  // Dark still never renders, because `Info.plist` pins the app to light
  // until the remaining 42 light tokens have dark values (ADR-028 § Rollout).

  /// Outermost background under dark mode.
  static let nightBackground = PasturaColorValue(hex: 0x1B1D17)
  /// Speech bubble fill under dark mode.
  static let nightBubble = PasturaColorValue(hex: 0x2C2F28)
  /// Whisper (密談) speech bubble fill under dark mode — a touch mossier
  /// than `nightBubble` so the hushed variant stays legible on the dark
  /// surface. Dark counterpart of `whisperBubble` (#908 PR2).
  static let nightWhisperBubble = PasturaColorValue(hex: 0x2F3626)
  /// Primary body text under dark mode.
  static let nightInk = PasturaColorValue(hex: 0xE8E5D8)
  /// Subtext / section labels under dark mode.
  static let nightInkSecondary = PasturaColorValue(hex: 0xB0AC9C)
  /// Meta info / footnotes under dark mode.
  static let nightMuted = PasturaColorValue(hex: 0x7A7768)
  /// Rule / divider lines under dark mode.
  static let nightRule = PasturaColorValue(hex: 0x353830)
  /// Brand accent under dark mode (brighter to survive the dark surface).
  static let nightMoss = PasturaColorValue(hex: 0xA8B888)

  // MARK: §2.9 Dark counterparts of the §2.6 alert family
  //
  // `*Soft` and `*Ink` INVERT their roles here. Light's pale-fill-plus-dark-text
  // becomes dark-fill-plus-pale-text, so these are NOT the light values run
  // through the base hues' lightness transform — that would put a glaring pale
  // card on a dark surface, against §1's calm voice. Each Ink is placed by
  // target contrast rather than by transform, landing 7.7-8.4:1 over its own
  // Soft. The four Soft fills sit at 1.02-1.08 against `nightBubble`, so hue
  // alone carries the temperature.
  //
  // Design record and the rendered sign-off: `docs/design/ds/colors-states-dark.html`.

  /// Neutral notification under dark mode.
  static let nightInfo = PasturaColorValue(hex: 0x97ABC4)
  /// Dark tinted fill paired with `nightInfo`.
  static let nightInfoSoft = PasturaColorValue(hex: 0x252D37)
  /// High-contrast text over `nightInfoSoft` (7.90:1).
  static let nightInfoInk = PasturaColorValue(hex: 0xB3C5DB)

  /// Positive completion under dark mode.
  static let nightSuccess = PasturaColorValue(hex: 0x95B189)
  /// Dark tinted fill paired with `nightSuccess`.
  ///
  /// Near-identical to `nightWhisperBubble` (contrast 1.003). That is a
  /// faithful mapping, not a collision to fix: light's `successSoft` and
  /// `whisperBubble` are equally close (1.026), and a toast never shares a
  /// surface with a 密談 bubble.
  static let nightSuccessSoft = PasturaColorValue(hex: 0x2A3725)
  /// High-contrast text over `nightSuccessSoft` (8.37:1).
  static let nightSuccessInk = PasturaColorValue(hex: 0xBFDBB3)

  /// Caution / awaiting confirmation under dark mode.
  ///
  /// Deliberately NOT the value a faithful luminance mapping gives (#DBBF8A,
  /// 9.58:1). Preserving luminance order inverts *perceptual* order: in light,
  /// `warning` is the quietest of the four bases against its own ground
  /// (2.23:1, where the others are 3.18-3.42), and mapping luminance faithfully
  /// would make it the loudest in dark. 8.74:1 narrows that gap toward the
  /// other three (6.85-7.24:1) while keeping amber legibly amber.
  static let nightWarning = PasturaColorValue(hex: 0xD4B67E)
  /// Dark tinted fill paired with `nightWarning`.
  static let nightWarningSoft = PasturaColorValue(hex: 0x383124)
  /// High-contrast text over `nightWarningSoft` (8.33:1).
  static let nightWarningInk = PasturaColorValue(hex: 0xE0CEAE)

  /// Destructive / irrevocable action under dark mode. A muted salmon — the
  /// §2.6 rule that red never shouts holds in both appearances.
  static let nightDanger = PasturaColorValue(hex: 0xCE9790)
  /// Dark tinted fill paired with `nightDanger`.
  static let nightDangerSoft = PasturaColorValue(hex: 0x382624)
  /// High-contrast text over `nightDangerSoft` (7.69:1).
  static let nightDangerInk = PasturaColorValue(hex: 0xE0B4AE)

  // MARK: §2.9 Dark counterparts of the §2.7 interactive states
  //
  // The moss tints re-base onto `nightMoss` and raise alpha ~1.33x: a 6% wash
  // of a light moss over #1B1D17 is imperceptible.

  /// Hover-state moss tint under dark mode, rgba(168, 184, 136, 0.08).
  static let nightHover = PasturaColorValue(
    red: 168.0 / 255.0, green: 184.0 / 255.0, blue: 136.0 / 255.0, opacity: 0.08)
  /// Pressed-state moss tint under dark mode, rgba(168, 184, 136, 0.16).
  static let nightPressed = PasturaColorValue(
    red: 168.0 / 255.0, green: 184.0 / 255.0, blue: 136.0 / 255.0, opacity: 0.16)
  /// Selected-state moss tint under dark mode, rgba(168, 184, 136, 0.24).
  static let nightSelected = PasturaColorValue(
    red: 168.0 / 255.0, green: 184.0 / 255.0, blue: 136.0 / 255.0, opacity: 0.24)
  /// Focus-ring stroke under dark mode. Same hex as `nightMoss`, kept as its
  /// own semantic anchor exactly as `focusRing` re-states `moss` in light.
  static let nightFocusRing = PasturaColorValue(hex: 0xA8B888)
  /// Disabled-state text color under dark mode (drained night ink).
  static let nightDisabledText = PasturaColorValue(hex: 0x605F54)
  /// Disabled-state surface fill under dark mode.
  ///
  /// Sinks BELOW `nightBubble` (1.151) rather than rising above it: in dark,
  /// "lighter" already means "raised" — that is what the state washes above do
  /// — so an inert surface has to go the other way. Light's `disabledBackground`
  /// is visible against both the card and the ground (1.235 / 1.183); this
  /// holds the same property (1.151 / 1.086).
  static let nightDisabledBackground = PasturaColorValue(hex: 0x222420)
}

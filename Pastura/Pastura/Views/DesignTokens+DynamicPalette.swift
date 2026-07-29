import SwiftUI

// The declared light↔dark token pairs. The mechanism they are built on —
// `PasturaDynamicColor` — lives in `DesignTokens+DynamicColor.swift`; this file
// is the data.
//
// Split out when ADR-028 gate 1's slice 2 landed (#1313), on the same axis as
// `DesignTokens+NightPalette.swift`: the table grows by one entry per designed
// pair (~4 lines with its registry row), so the remaining gate-1 slices would
// have pushed the combined file past swiftlint's 400-line `file_length` cap.
// The mechanism does not grow, so type and table part cleanly.
//
// Like the mechanism file, this one deliberately introduces **no**
// `PasturaColorValue(hex:)` literal — every value references an existing
// `PasturaPalette` token. `scripts/check_design_tokens_css.py` globs
// `DesignTokens*.swift` and requires each hex literal to be mirrored in
// `docs/design/ds/tokens.css`; keeping both files literal-free keeps that CI
// gate green with no mirror edit. The hexes themselves live in
// `DesignTokens+NightPalette.swift` and `DesignTokens.swift`.

// MARK: - The declared pairs

/// The light↔dark token pairs wired into the app's `Color.*` aliases.
///
/// **26 pairs.** The original eight (ADR-028), plus the §2.6 alert family and
/// §2.7 interactive states designed in slice 1 of gate 1 (#1282).
///
/// The remaining 42 light tokens still owe a dark value and stay light-only;
/// the app is pinned to light via `Info.plist`'s `UIUserInterfaceStyle` until
/// they are designed, so no half-dark surface can render.
///
/// Unlike ``PasturaDynamicColor`` this namespace is deliberately NOT
/// `nonisolated`: its static initializers read `PasturaPalette`, which is
/// MainActor-isolated under `Views/`'s default isolation, and a `nonisolated`
/// namespace fails to compile — observed, not predicted: "Main actor-isolated
/// default value in a nonisolated context", once per static. Nothing is lost — the isolation that matters is on the
/// provider closure inside ``PasturaDynamicColor/uiColor``, which UIKit may
/// invoke off the main actor; reading these statics only ever happens from the
/// MainActor `Color` extension.
enum PasturaDynamicPalette {

  /// §2.1 — app body background.
  static let screenBackground = PasturaDynamicColor(
    light: PasturaPalette.screenBackground, dark: PasturaPalette.nightBackground)
  /// §2.1 — public speech-bubble fill.
  static let bubbleBackground = PasturaDynamicColor(
    light: PasturaPalette.bubbleBackground, dark: PasturaPalette.nightBubble)
  /// §2.1 — whisper (密談) speech-bubble fill.
  static let whisperBubble = PasturaDynamicColor(
    light: PasturaPalette.whisperBubble, dark: PasturaPalette.nightWhisperBubble)

  /// §2.2 — primary body text.
  static let ink = PasturaDynamicColor(
    light: PasturaPalette.ink, dark: PasturaPalette.nightInk)
  /// §2.2 — subtext / section labels.
  static let inkSecondary = PasturaDynamicColor(
    light: PasturaPalette.inkSecondary, dark: PasturaPalette.nightInkSecondary)
  /// §2.2 — meta info / footnotes.
  static let muted = PasturaDynamicColor(
    light: PasturaPalette.muted, dark: PasturaPalette.nightMuted)
  /// §2.2 — rule / divider lines.
  static let rule = PasturaDynamicColor(
    light: PasturaPalette.rule, dark: PasturaPalette.nightRule)

  /// §2.3 — brand accent.
  static let moss = PasturaDynamicColor(
    light: PasturaPalette.moss, dark: PasturaPalette.nightMoss)

  /// §2.6 — neutral notification.
  static let info = PasturaDynamicColor(
    light: PasturaPalette.info, dark: PasturaPalette.nightInfo)
  /// §2.6 — background fill paired with `info`.
  static let infoSoft = PasturaDynamicColor(
    light: PasturaPalette.infoSoft, dark: PasturaPalette.nightInfoSoft)
  /// §2.6 — text over `infoSoft`.
  static let infoInk = PasturaDynamicColor(
    light: PasturaPalette.infoInk, dark: PasturaPalette.nightInfoInk)

  /// §2.6 — positive completion.
  static let success = PasturaDynamicColor(
    light: PasturaPalette.success, dark: PasturaPalette.nightSuccess)
  /// §2.6 — background fill paired with `success`.
  static let successSoft = PasturaDynamicColor(
    light: PasturaPalette.successSoft, dark: PasturaPalette.nightSuccessSoft)
  /// §2.6 — text over `successSoft`.
  static let successInk = PasturaDynamicColor(
    light: PasturaPalette.successInk, dark: PasturaPalette.nightSuccessInk)

  /// §2.6 — caution / awaiting confirmation.
  static let warning = PasturaDynamicColor(
    light: PasturaPalette.warning, dark: PasturaPalette.nightWarning)
  /// §2.6 — background fill paired with `warning`.
  static let warningSoft = PasturaDynamicColor(
    light: PasturaPalette.warningSoft, dark: PasturaPalette.nightWarningSoft)
  /// §2.6 — text over `warningSoft`.
  static let warningInk = PasturaDynamicColor(
    light: PasturaPalette.warningInk, dark: PasturaPalette.nightWarningInk)

  /// §2.6 — destructive / irrevocable action.
  static let danger = PasturaDynamicColor(
    light: PasturaPalette.danger, dark: PasturaPalette.nightDanger)
  /// §2.6 — background fill paired with `danger`.
  static let dangerSoft = PasturaDynamicColor(
    light: PasturaPalette.dangerSoft, dark: PasturaPalette.nightDangerSoft)
  /// §2.6 — text over `dangerSoft`.
  static let dangerInk = PasturaDynamicColor(
    light: PasturaPalette.dangerInk, dark: PasturaPalette.nightDangerInk)

  /// §2.7 — hover-state accent wash.
  static let hover = PasturaDynamicColor(
    light: PasturaPalette.hover, dark: PasturaPalette.nightHover)
  /// §2.7 — pressed-state accent wash.
  static let pressed = PasturaDynamicColor(
    light: PasturaPalette.pressed, dark: PasturaPalette.nightPressed)
  /// §2.7 — selected-state accent wash.
  static let selected = PasturaDynamicColor(
    light: PasturaPalette.selected, dark: PasturaPalette.nightSelected)
  /// §2.7 — focus-ring stroke.
  static let focusRing = PasturaDynamicColor(
    light: PasturaPalette.focusRing, dark: PasturaPalette.nightFocusRing)
  /// §2.7 — disabled-state text.
  static let disabledText = PasturaDynamicColor(
    light: PasturaPalette.disabledText, dark: PasturaPalette.nightDisabledText)
  /// §2.7 — disabled-state surface fill.
  static let disabledBackground = PasturaDynamicColor(
    light: PasturaPalette.disabledBackground, dark: PasturaPalette.nightDisabledBackground)

  /// Every declared pair, keyed by its light-token name.
  ///
  /// Consumed by `DesignTokensTests+DarkMode`'s count assertion. Note what that
  /// does and does not catch: the registry is hand-maintained, so declaring a
  /// 27th pair and *not* appending it here leaves `all.count == 26` and passes.
  /// The count guards this list against its own documented size, nothing more —
  /// the real per-alias coverage is the wiring tests, which resolve each of the
  /// 26 `Color.*` aliases under both schemes.
  static let all: [(name: String, pair: PasturaDynamicColor)] = [
    ("screenBackground", screenBackground),
    ("bubbleBackground", bubbleBackground),
    ("whisperBubble", whisperBubble),
    ("ink", ink),
    ("inkSecondary", inkSecondary),
    ("muted", muted),
    ("rule", rule),
    ("moss", moss),
    ("info", info),
    ("infoSoft", infoSoft),
    ("infoInk", infoInk),
    ("success", success),
    ("successSoft", successSoft),
    ("successInk", successInk),
    ("warning", warning),
    ("warningSoft", warningSoft),
    ("warningInk", warningInk),
    ("danger", danger),
    ("dangerSoft", dangerSoft),
    ("dangerInk", dangerInk),
    ("hover", hover),
    ("pressed", pressed),
    ("selected", selected),
    ("focusRing", focusRing),
    ("disabledText", disabledText),
    ("disabledBackground", disabledBackground)
  ]
}

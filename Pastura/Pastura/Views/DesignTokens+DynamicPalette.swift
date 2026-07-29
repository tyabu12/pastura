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
/// **40 pairs.** The original eight (ADR-028), plus the §2.6 alert family and
/// §2.7 interactive states from slice 1 of gate 1 (#1282), plus the §2.4 meta
/// presets and two of the three §2.12 header slots from slice 2 (#1313).
///
/// 28 light tokens remain unpaired, and gate 1 still owes an answer for **27**
/// of them — the two counts differ because `headerMetaSubdued` is resolved but
/// unpaired: slice 2 recorded it as fixed in both appearances, which gate 1
/// admits as an equal alternative to a designed dark value. The app is pinned
/// to light via `Info.plist`'s `UIUserInterfaceStyle` until the rest are
/// designed, so no half-dark surface can render.
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

  /// §2.4 — meta text, preset L1 (quietest).
  static let metaBaseL1 = PasturaDynamicColor(
    light: PasturaPalette.metaBaseL1, dark: PasturaPalette.nightMetaBaseL1)
  /// §2.4 — emphasis within preset L1.
  static let metaStrongL1 = PasturaDynamicColor(
    light: PasturaPalette.metaStrongL1, dark: PasturaPalette.nightMetaStrongL1)
  /// §2.4 — lit progress dot, preset L1.
  static let metaDotOnL1 = PasturaDynamicColor(
    light: PasturaPalette.metaDotOnL1, dark: PasturaPalette.nightMetaDotOnL1)
  /// §2.4 — meta text, preset L2.
  static let metaBaseL2 = PasturaDynamicColor(
    light: PasturaPalette.metaBaseL2, dark: PasturaPalette.nightMetaBaseL2)
  /// §2.4 — emphasis within preset L2.
  static let metaStrongL2 = PasturaDynamicColor(
    light: PasturaPalette.metaStrongL2, dark: PasturaPalette.nightMetaStrongL2)
  /// §2.4 — lit progress dot, preset L2.
  static let metaDotOnL2 = PasturaDynamicColor(
    light: PasturaPalette.metaDotOnL2, dark: PasturaPalette.nightMetaDotOnL2)
  /// §2.4 — meta text, preset L3 (default).
  static let metaBaseL3 = PasturaDynamicColor(
    light: PasturaPalette.metaBaseL3, dark: PasturaPalette.nightMetaBaseL3)
  /// §2.4 — emphasis within preset L3.
  static let metaStrongL3 = PasturaDynamicColor(
    light: PasturaPalette.metaStrongL3, dark: PasturaPalette.nightMetaStrongL3)
  /// §2.4 — lit progress dot, preset L3.
  static let metaDotOnL3 = PasturaDynamicColor(
    light: PasturaPalette.metaDotOnL3, dark: PasturaPalette.nightMetaDotOnL3)
  /// §2.4 — meta text, preset L4 (loudest).
  static let metaBaseL4 = PasturaDynamicColor(
    light: PasturaPalette.metaBaseL4, dark: PasturaPalette.nightMetaBaseL4)
  /// §2.4 — emphasis within preset L4.
  static let metaStrongL4 = PasturaDynamicColor(
    light: PasturaPalette.metaStrongL4, dark: PasturaPalette.nightMetaStrongL4)
  /// §2.4 — lit progress dot, preset L4.
  static let metaDotOnL4 = PasturaDynamicColor(
    light: PasturaPalette.metaDotOnL4, dark: PasturaPalette.nightMetaDotOnL4)
  /// §2.12 — GameHeader meta-row separator.
  static let headerRule = PasturaDynamicColor(
    light: PasturaPalette.headerRule, dark: PasturaPalette.nightHeaderRule)
  /// §2.12 — GameHeader meta-row phase name.
  static let headerMetaInk = PasturaDynamicColor(
    light: PasturaPalette.headerMetaInk, dark: PasturaPalette.nightHeaderMetaInk)

  /// Every declared pair, keyed by its light-token name.
  ///
  /// Consumed by `DesignTokensTests+DarkMode`'s count assertion. Note what that
  /// does and does not catch: the registry is hand-maintained, so declaring a
  /// 41st pair and *not* appending it here leaves `all.count == 40` and passes.
  /// The count guards this list against its own documented size, nothing more —
  /// the real per-alias coverage is the wiring tests in
  /// `DesignTokensTests+DarkModeWiring`, which resolve each of the 40 `Color.*`
  /// aliases under both schemes.
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
    ("disabledBackground", disabledBackground),
    ("metaBaseL1", metaBaseL1),
    ("metaStrongL1", metaStrongL1),
    ("metaDotOnL1", metaDotOnL1),
    ("metaBaseL2", metaBaseL2),
    ("metaStrongL2", metaStrongL2),
    ("metaDotOnL2", metaDotOnL2),
    ("metaBaseL3", metaBaseL3),
    ("metaStrongL3", metaStrongL3),
    ("metaDotOnL3", metaDotOnL3),
    ("metaBaseL4", metaBaseL4),
    ("metaStrongL4", metaStrongL4),
    ("metaDotOnL4", metaDotOnL4),
    ("headerRule", headerRule),
    ("headerMetaInk", headerMetaInk)
  ]
}

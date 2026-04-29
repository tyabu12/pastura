import SwiftUI

// Extended typography tokens for the GameHeader 2-row layout (#297 PR 3).
// Lives in an extension so `DesignTokens.swift` stays under swiftlint's
// 400-line `file_length` cap. Source of truth in
// `docs/design/design-system.md` §3.2 (the GameHeader rows added in this
// PR).
//
// Design intent: each token is role-anchored to a specific GameHeader
// slot (title row, meta-row ROUND counter, meta-row inline fragments,
// trailing status pill). They are NOT a generic typography expansion —
// adding a new GameHeader-only token below should require a clear
// new-slot rationale, not a "this size happens to work elsewhere" reuse.

extension Typography {

  // MARK: §5.1 GameHeader (Demo / Sim shared 2-row header)

  /// title/scenario — GameHeader row 1 main title (シナリオ名).
  /// Sits a step above `titlePhase` (13pt) because the scenario name is
  /// the row's primary anchor, not a sub-label.
  static let titleScenario = PasturaTextStyle(
    size: 16, weight: .semibold, design: .default,
    lineHeight: 1.2, letterSpacingEm: 0.02,
    isItalic: false, textCase: nil)

  /// meta/round — GameHeader row 2 ROUND counter (`ROUND 1 / 3`).
  /// Mono UPPER for typographic distinction from the phase name (which
  /// uses Japanese mixed-case). Intentionally heavier than `metaInline`
  /// so the round counter reads as the row's anchor.
  static let metaRound = PasturaTextStyle(
    size: 10, weight: .semibold, design: .monospaced,
    lineHeight: 1.2, letterSpacingEm: 0.06,
    isItalic: false, textCase: .uppercase)

  /// meta/inline — GameHeader row 2 inline secondary fragments (phase
  /// name, tok/s). Same size as `metaRound` (10pt) for vertical-rhythm
  /// alignment, but regular weight + mixed-case to recede behind the
  /// ROUND anchor.
  static let metaInline = PasturaTextStyle(
    size: 10, weight: .regular, design: .monospaced,
    lineHeight: 1.2, letterSpacingEm: 0.04,
    isItalic: false, textCase: nil)

  /// pill/status — GameHeader row 1 trailing status pill (`Simulating`,
  /// `Demoing`, `Paused`, `Completed`, ...). Wider tracking than
  /// `metaLabel` (0.06em) so the small caps-y feel reads at the pill's
  /// reduced size.
  static let pillStatus = PasturaTextStyle(
    size: 9, weight: .semibold, design: .monospaced,
    lineHeight: 1.2, letterSpacingEm: 0.18,
    isItalic: false, textCase: nil)
}

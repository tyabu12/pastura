import Foundation

/// Localized human-readable label for a `PhaseType`, suitable for the
/// `GameHeader` row-2 phase fragment in both Sim and Demo. Single
/// source of truth — replaces the formerly-duplicated 10-case switches
/// that previously lived in `SimulationView` and the
/// `ModelDownloadHostView+PhaseLabels` extension.
///
/// Each label routes through `String(localized:)` so it lands in
/// `Localizable.xcstrings` and gets a `ja` translation, satisfying
/// the project's i18n mandate (CLAUDE.md "User-facing String literals").
///
/// ## Scope
///
/// Compact labels suitable for header / status surfaces (1-2 words).
/// For the long-form phase descriptions used in the editor's helper
/// text (e.g. "All agents speak simultaneously"), see
/// `PhaseEditorSheet.phaseTypeDescription` — that surface is
/// intentionally separate (sentence form vs compact label) and the
/// two should not be merged. `PhaseTypeLabel` in `Views/Components/`
/// (the moss/ink capsule badge) now renders **this** label rather than
/// `PhaseType.rawValue`, so its inline log markers and phase-boundary
/// separators stay snake_case-free and localized (#882).
public enum PhaseDisplayName {

  // Pure name-mapping switch (one line per phase type). The 13-case count
  // exceeds SwiftLint's cyclomatic threshold but carries no branching logic.
  // swiftlint:disable cyclomatic_complexity
  /// Compact display label for `phase`. The English source string is
  /// the xcstrings key (literal-en convention used throughout the
  /// catalog); `ja` translations are authored in
  /// `Localizable.xcstrings`.
  public static func label(for phase: PhaseType) -> String {
    switch phase {
    case .speakAll: return String(localized: "Speak")
    case .speakEach: return String(localized: "Speak Each")
    case .vote: return String(localized: "Vote")
    case .choose: return String(localized: "Choose")
    case .reflect: return String(localized: "Reflect")
    case .whisper: return String(localized: "Whisper")
    case .scoreCalc: return String(localized: "Score Calc")
    case .assign: return String(localized: "Assign")
    case .eliminate: return String(localized: "Eliminate")
    case .summarize: return String(localized: "Summarize")
    case .conditional: return String(localized: "Conditional")
    case .eventInject: return String(localized: "Event")
    case .relationshipUpdate: return String(localized: "Relationships")
    case .narrate: return String(localized: "Narrate")
    }
  }
  // swiftlint:enable cyclomatic_complexity
}

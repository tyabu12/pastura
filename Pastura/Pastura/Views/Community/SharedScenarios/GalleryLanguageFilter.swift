import Foundation

/// One selectable option in the Browse tab's language-filter menu: either the
/// "All" option (nil filter) or a single ISO 639-1 language code.
///
/// Kept `nonisolated` and side-effect-free so the option projection,
/// default-language resolution, and the option → `selectedLanguage` mapping
/// are unit-testable without rendering (ADR-009 /
/// `.claude/rules/view-testing.md`). The actual filtering stays in
/// `SharedScenariosViewModel` / `GalleryScenarioSearch`; this type only
/// models the menu options and device-default resolution.
nonisolated enum GalleryLanguageFilter: Hashable {
  /// The "All" option: clears the language filter (shows every language).
  case all
  /// An option scoped to a single ISO 639-1 language code.
  case language(String)

  /// The options in canonical order for the languages actually present in the
  /// feed: the "All" option first, then one option per available language in a
  /// canonical order ("ja", "en", then any others alphabetically). Derived
  /// from the feed (not a static list) so an "English" option never shows when
  /// the feed has no English content.
  static func options(available: Set<String>) -> [GalleryLanguageFilter] {
    let canonical = ["ja", "en"]
    let known = canonical.filter { available.contains($0) }
    let extras = available.subtracting(canonical).sorted()
    return [.all] + (known + extras).map(GalleryLanguageFilter.language)
  }

  /// The `selectedLanguage` value this option represents — `nil` for `.all`.
  var selectedLanguage: String? {
    switch self {
    case .all: return nil
    case .language(let code): return code
    }
  }

  /// The default language filter for first load: the device language if the
  /// feed actually carries scenarios in it, else `nil` (`.all`) so the Browse
  /// list is never empty for a language with no content (ADR-010 D6 fallback).
  static func resolveDefault(device: String, available: Set<String>) -> String? {
    available.contains(device) ? device : nil
  }
}

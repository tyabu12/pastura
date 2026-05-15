import Foundation
import Yams

/// ViewModel for the home screen scenario list.
///
/// Fetches scenarios from the repository and splits them into presets
/// and user-created groups. Supports pull-to-refresh and deletion.
/// Also exposes a set of scenario ids with a pending gallery update,
/// populated from the cached gallery index.
///
/// **Preset variant collapsing (ADR-010 D6).** Bundled presets ship in
/// per-language sibling files (Step D); this VM surfaces ONE row per
/// canonical `sourceId`, picking the device-language variant via
/// ``LocaleResolver``. When the device-language variant is absent the
/// picker falls back to any available variant (D6 line 217). User-
/// authored scenarios are not collapsed — only bundled presets share
/// a canonical id across languages.
@Observable
final class HomeViewModel {
  private(set) var presets: [ScenarioRecord] = []
  private(set) var userScenarios: [ScenarioRecord] = []
  private(set) var isLoading = false
  private(set) var errorMessage: String?

  /// `ScenarioRecord.id`s for rows whose `sourceHash` differs from the
  /// cached gallery's `yaml_sha256`. Empty when no cache exists. The view
  /// reads this as an inline badge on each row.
  private(set) var galleryUpdateBadges: Set<String> = []

  private let repository: any ScenarioRepository

  init(repository: any ScenarioRepository) {
    self.repository = repository
  }

  func loadScenarios() async {
    isLoading = true
    errorMessage = nil

    do {
      let all = try await offMain { [repository] in
        try repository.fetchAll()
      }
      let allPresets = all.filter(\.isPreset)
      presets = Self.presetsResolvedForLanguage(
        allPresets, deviceLanguage: LocaleResolver.deviceDefault())
      userScenarios = all.filter { !$0.isPreset }
    } catch {
      errorMessage = String(localized: "Failed to load scenarios: \(error.localizedDescription)")
    }

    isLoading = false
  }

  /// ADR-010 D6 variant collapsing: groups bundled presets by canonical
  /// `sourceId` (legacy rows with `sourceId == nil` group by `id`),
  /// then surfaces the device-language variant per group. Falls back to
  /// any available variant when the device-language sibling isn't
  /// shipped (D6 line 217 "falls back to any available variant if the
  /// device-default's variant is absent").
  ///
  /// Light parse only — Yams reads the top-level `language` field
  /// without invoking ``ScenarioLoader``'s full schema gate. For the
  /// 4-8 preset row range the cost is negligible. A parse failure
  /// (malformed `yamlDefinition`) is treated as `"ja"` (Phase 1
  /// convention) so the row stays visible rather than silently
  /// disappearing from the picker.
  internal static func presetsResolvedForLanguage(
    _ presets: [ScenarioRecord],
    deviceLanguage: String
  ) -> [ScenarioRecord] {
    let grouped = Dictionary(grouping: presets) { $0.sourceId ?? $0.id }

    var resolved: [ScenarioRecord] = []
    for (_, variants) in grouped {
      let withLang = variants.map {
        (record: $0, lang: parseLanguage(from: $0.yamlDefinition))
      }
      let picked =
        withLang.first(where: { $0.lang == deviceLanguage })?.record
        ?? withLang.first?.record
      if let picked { resolved.append(picked) }
    }

    // Stable order — sort by canonical key so reloads don't flicker.
    return resolved.sorted { ($0.sourceId ?? $0.id) < ($1.sourceId ?? $1.id) }
  }

  private static func parseLanguage(from yaml: String) -> String {
    guard
      let root = try? Yams.load(yaml: yaml) as? [String: Any],
      let language = root["language"] as? String
    else {
      return "ja"
    }
    return language
  }

  func deleteScenario(_ id: String) async {
    do {
      try await offMain { [repository] in
        try repository.delete(id)
      }
      userScenarios.removeAll { $0.id == id }
    } catch {
      errorMessage = String(localized: "Failed to delete scenario: \(error.localizedDescription)")
    }
  }

  /// Recomputes `galleryUpdateBadges` by comparing each locally-stored
  /// gallery row's `sourceHash` with the hash from the cached gallery
  /// index. Non-gallery rows and rows lacking a `sourceId` are ignored.
  /// Silent no-op when no cached index is available.
  func refreshGalleryUpdateBadges(using service: any GalleryService) async {
    // Cache read is file I/O — dispatch off MainActor to avoid blocking
    // list rendering on a synchronous disk read. Double-optional: inner
    // nil = no cache file, outer nil = offMain threw.
    let fetched = try? await offMain { [service] in try service.loadCachedIndex() }
    guard let cached = fetched.flatMap({ $0 }) else {
      galleryUpdateBadges = []
      return
    }
    let hashBySourceId = Dictionary(
      uniqueKeysWithValues: cached.scenarios.map { ($0.id, $0.yamlSHA256) })
    var ids: Set<String> = []
    // Only `userScenarios` can be gallery-sourced — presets are bundled.
    for record in userScenarios
    where record.sourceType == ScenarioSourceType.gallery {
      guard
        let sourceId = record.sourceId,
        let galleryHash = hashBySourceId[sourceId]
      else { continue }
      if record.sourceHash != galleryHash {
        ids.insert(record.id)
      }
    }
    galleryUpdateBadges = ids
  }
}

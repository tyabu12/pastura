import Foundation
import OSLog
import Yams

/// How the app should draw a highlight's `yaml_hook` (ADR-029 § Amendment
/// 2026-08-08).
///
/// The web renders every hook as YAML, because it has no editor to show the
/// fragment's meaning in. The app has one (ADR-018), so a fragment whose shape
/// is *declared* — today only `kind: "persona"` — is drawn in that editor's
/// vocabulary instead. The divergence is deliberate, not drift.
///
/// **Falling back is a presentation decision, never a content one.** Every
/// rejection here lands on ``rawYAML``, which prints the fragment verbatim, so
/// nothing is dropped or altered. That is why this does not follow the
/// whole-section hide § Amendment 2026-08-07 mandates for an unrenderable
/// excerpt: an excerpt is a quotation, and silently dropping a line from one
/// misrepresents the record.
enum GalleryHighlightHookRendition: Equatable {

  /// The fragment parsed as a persona list — draw it as editor-style rows.
  ///
  /// The entries are an **excerpt** of the scenario's personas, not its cast:
  /// both shipped hooks quote a subset. The app cannot check that (a
  /// non-installed gallery scenario's persona list is never fetched), so the
  /// section's heading is what has to say so.
  case personas([Entry])

  /// Draw the fragment as a YAML block — either because `kind` says so, or
  /// because nothing better could be derived.
  case rawYAML

  /// One persona's editable fields, in the two the visual editor exposes
  /// alongside `secret` (`PersonaEditorSheet`).
  struct Entry: Equatable {
    let name: String
    let description: String
  }

  private static let logger = Logger(
    subsystem: "app.pastura.Pastura", category: "GalleryHighlight")

  /// `kind: "persona"`, and only that, promises the shape ``personaEntries(in:)``
  /// requires.
  static let personaKind = "persona"

  /// Picks the rendition for `hook`, logging any *unintended* fallback.
  ///
  /// `kind: "raw"` is not a fallback — it is a curator declaring that the
  /// fragment has no structured form — so it logs nothing. The two cases that
  /// do are a `kind` this build does not know (a feed newer than the app,
  /// ADR-029 revisit trigger) and a `persona` fragment that failed to parse (a
  /// supply-side defect that got past the gate). ADR-029 Decision 4 requires
  /// those not be silent to developers even though they are silent to users.
  ///
  /// `check=yaml_hook_unrenderable` follows the loader's log vocabulary but is
  /// **not** one of its names: `GalleryHighlightLoader`'s nine all *hide* the
  /// section, and this one hides nothing.
  static func resolve(
    _ hook: GalleryHighlightYAMLHook, scenarioID: String
  ) -> GalleryHighlightHookRendition {
    guard hook.kind == personaKind else {
      if hook.kind != "raw" {
        log(reason: "unknown_kind", scenarioID: scenarioID)
      }
      return .rawYAML
    }
    guard let entries = personaEntries(in: hook.fragment) else {
      log(reason: "persona_fragment_unparsed", scenarioID: scenarioID)
      return .rawYAML
    }
    return .personas(entries)
  }

  /// Parses a `kind: "persona"` fragment, or `nil` when it is not one.
  ///
  /// Accepts the two shapes ADR-029 Decision 1 pins: a bare block sequence of
  /// mappings (what both shipped hooks use — Yams reads one at any indent, so
  /// no dedent is needed) or a `personas:`-keyed mapping holding one.
  ///
  /// Keys beyond `name` / `description` are **ignored rather than rejected**,
  /// which matters most for the one that cannot legally be here. The gate
  /// rejects `secret:` by name in every kind, but were one to arrive anyway,
  /// rejecting the fragment here would send the caller to ``rawYAML`` and
  /// *print the hidden agenda* — so dropping it is the safer read. Same
  /// strict-supply / lenient-read asymmetry as
  /// ``GalleryHighlightYAMLHook/kind``.
  ///
  /// ⚠️ **This drops a secret only when every entry in the fragment is
  /// well-formed.** Parsing is necessary but not sufficient. Rejection
  /// is per-*fragment*, not per-entry: a missing `name` or `description` on the
  /// offending entry — or on any **sibling** — rejects all of it, and the
  /// fallback then prints it, secret included. So the publish-time gate is the
  /// actual defence and this is the second layer, not the first. Both paths are
  /// pinned rather than implied:
  /// `secretSurvivesWhenTheEntryItselfIsMalformed` and
  /// `secretSurvivesWhenAMalformedSiblingRejectsAWellFormedEntry`.
  static func personaEntries(in fragment: String) -> [Entry]? {
    guard let loaded = try? Yams.load(yaml: fragment),
      let items = sequence(in: loaded)
    else { return nil }

    var entries: [Entry] = []
    entries.reserveCapacity(items.count)
    for item in items {
      guard let mapping = item as? [String: Any],
        let name = nonEmptyString(mapping["name"]),
        let description = nonEmptyString(mapping["description"])
      else { return nil }
      entries.append(Entry(name: name, description: description))
    }
    return entries.isEmpty ? nil : entries
  }

  private static func sequence(in loaded: Any) -> [Any]? {
    if let list = loaded as? [Any] { return list }
    if let mapping = loaded as? [String: Any], mapping.count == 1,
      let list = mapping["personas"] as? [Any] {
      return list
    }
    return nil
  }

  /// Trims both ends, unlike `GalleryScenarioDetailFormat.yamlFragmentForDisplay`,
  /// which must preserve leading indentation. This is a scalar *value*, not YAML
  /// source: a folded scalar (`description: >`) keeps a trailing newline under
  /// clip chomping, which would render as a stray blank line.
  private static func nonEmptyString(_ value: Any?) -> String? {
    guard let text = value as? String else { return nil }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func log(reason: String, scenarioID: String) {
    logger.info(
      """
      highlight hook fell back to YAML: check=yaml_hook_unrenderable \
      reason=\(reason, privacy: .public) scenario=\(scenarioID, privacy: .public)
      """)
  }
}

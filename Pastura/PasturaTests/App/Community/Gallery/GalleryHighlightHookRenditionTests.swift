import Foundation
import Testing

@testable import Pastura

/// Parsing + fallback contract for a highlight's `yaml_hook`
/// (ADR-029 § Amendment 2026-08-08).
///
/// `@MainActor` per `.claude/rules/swift-isolation.md` § Pattern 5: the type
/// lives in `App/`, which is default-MainActor, so a nonisolated suite could
/// not use its auto-synthesized `Equatable` conformance.
@Suite(.timeLimit(.minutes(1)))
@MainActor
struct GalleryHighlightHookRenditionTests {

  private typealias Rendition = GalleryHighlightHookRendition
  private typealias Entry = GalleryHighlightHookRendition.Entry

  // MARK: - Supply ⟺ consumption

  /// The repo-side gate parses these fragments with **PyYAML**; the app parses
  /// them with **Yams**. Nothing makes two implementations agree, and the
  /// single-definition move ADR-029 used for phases (`renderablePhase`) is not
  /// available across a language boundary — so the agreement is *measured*,
  /// against the real published bytes rather than a copy of them. A fragment
  /// the gate accepts and Yams rejects would silently degrade a shipped
  /// highlight to the raw block, with only an `.info` line to show for it.
  @Test func everyShippedPersonaFragmentParses() throws {
    let dir = GallerySeedYAMLTests.repoRoot()
      .appendingPathComponent("docs/gallery/highlights")
    let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
      .filter { $0.hasSuffix(".json") }
    #expect(!files.isEmpty, "Expected at least one shipped highlight file")

    var personaHooksSeen = 0
    for name in files {
      let data = try Data(contentsOf: dir.appendingPathComponent(name))
      let highlight = try JSONDecoder().decode(GalleryHighlight.self, from: data)
      guard highlight.yamlHook.kind == Rendition.personaKind else { continue }
      personaHooksSeen += 1

      // The `#require` is the measurement. Asserting non-empty names or a
      // non-empty list here would restate `personaEntries`' own postcondition
      // (`nonEmptyString`, and `nil` for an empty list) and could not fail —
      // so instead assert what the parser does *not* promise: that the entry
      // count matches what the fragment's own top-level `- name:` lines say,
      // which is the property a silent parser divergence would break.
      let entries = try #require(
        Rendition.personaEntries(in: highlight.yamlHook.fragment),
        "\(name): the gate accepts this as kind=persona but Yams rejected it")
      let authoredNames = highlight.yamlHook.fragment
        .split(separator: "\n")
        .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- name:") }
        .count
      #expect(
        entries.count == authoredNames,
        "\(name): parsed \(entries.count) personas from \(authoredNames) authored entries")
    }
    // Without this the loop is vacuous the moment the shipped inventory stops
    // carrying a persona hook, and the suite would keep passing on nothing.
    #expect(personaHooksSeen > 0, "No shipped highlight declares kind=persona")
  }

  // MARK: - Accepted shapes (ADR-029 Decision 1)

  @Test func bareBlockSequenceParses() {
    let fragment = """
        - name: アヤ
          description: 率直な被験者。
        - name: ケン
          description: 場を読む同調者。
      """
    #expect(
      Rendition.personaEntries(in: fragment) == [
        Entry(name: "アヤ", description: "率直な被験者。"),
        Entry(name: "ケン", description: "場を読む同調者。")
      ])
  }

  @Test func personasKeyedMappingParses() {
    let fragment = """
      personas:
        - name: アヤ
          description: 率直な被験者。
      """
    #expect(
      Rendition.personaEntries(in: fragment)
        == [Entry(name: "アヤ", description: "率直な被験者。")])
  }

  /// A folded scalar (`description: >`) collapses its line breaks and keeps a
  /// trailing newline under YAML clip chomping. ADR-029 § Amendment 2026-08-08
  /// accepts the fold — it is the value the engine receives and the value
  /// `PersonaEditorSheet` shows after install — but the trailing newline is
  /// presentation noise and is trimmed.
  @Test func foldedScalarKeepsTheFoldAndDropsTrailingWhitespace() throws {
    let fragment = """
        - name: アヤ
          description: >
            【立場】真の被験者。
            【目的】正直に答える。
      """
    let entries = try #require(Rendition.personaEntries(in: fragment))
    #expect(entries == [Entry(name: "アヤ", description: "【立場】真の被験者。 【目的】正直に答える。")])
  }

  // MARK: - Rejected shapes → the caller draws the raw block

  @Test func nonPersonaFragmentIsRejected() {
    #expect(Rendition.personaEntries(in: "phases:\n  - type: speak_each") == nil)
  }

  @Test func unparseableFragmentIsRejected() {
    #expect(Rendition.personaEntries(in: "  - name: [アヤ\n    description: 壊れ") == nil)
  }

  @Test func emptyFragmentIsRejected() {
    #expect(Rendition.personaEntries(in: "") == nil)
    #expect(Rendition.personaEntries(in: "   \n  ") == nil)
  }

  @Test func entryMissingDescriptionIsRejected() {
    #expect(Rendition.personaEntries(in: "  - name: アヤ") == nil)
  }

  @Test func entryMissingNameIsRejected() {
    #expect(Rendition.personaEntries(in: "  - description: 率直な被験者。") == nil)
  }

  // MARK: - Spoiler safety

  /// A `secret:` key cannot reach a published fragment — the gate rejects it by
  /// name. This pins what happens if one ever did: the entry renders **without**
  /// it, and the fragment is *not* rejected.
  ///
  /// Rejecting is the intuitive fail-closed move and is exactly backwards here.
  /// The fallback for a rejected fragment is to print it verbatim as YAML, so
  /// refusing to parse would *display* the hidden agenda. Parsing is what drops
  /// it.
  @Test func secretKeyIsDroppedRatherThanRejected() throws {
    let fragment = """
        - name: アヤ
          description: 率直な被験者。
          secret: 本当は協力者。
      """
    let entries = try #require(Rendition.personaEntries(in: fragment))
    #expect(entries == [Entry(name: "アヤ", description: "率直な被験者。")])
    for entry in entries {
      #expect(!entry.name.contains("協力者"))
      #expect(!entry.description.contains("協力者"))
    }
  }

  /// The negative control for the test above, and the reason the gate — not
  /// this parser — is the actual defence against a published secret.
  ///
  /// Dropping only happens on the paths where the fragment otherwise parses.
  /// Here the entry has no `description`, so the *whole* fragment is rejected,
  /// the caller falls back to `.rawYAML`, and the block prints the fragment
  /// verbatim — secret included. Asserting the success case alone would have
  /// left "parsing is what drops it" reading as unconditional, which it is not.
  @Test func secretSurvivesWhenAMalformedSiblingForcesTheFallback() {
    let fragment = """
        - name: アヤ
          secret: 本当は協力者。
      """
    #expect(Rendition.personaEntries(in: fragment) == nil)

    let hook = GalleryHighlightYAMLHook(kind: "persona", fragment: fragment, caption: "cap")
    #expect(Rendition.resolve(hook, scenarioID: "demo_v1") == .rawYAML)
  }

  // MARK: - resolve()

  @Test func personaKindResolvesToRows() {
    let hook = GalleryHighlightYAMLHook(
      kind: "persona",
      fragment: "  - name: アヤ\n    description: 率直な被験者。",
      caption: "cap")
    #expect(
      Rendition.resolve(hook, scenarioID: "demo_v1")
        == .personas([Entry(name: "アヤ", description: "率直な被験者。")]))
  }

  @Test func rawKindResolvesToTheYAMLBlock() {
    let hook = GalleryHighlightYAMLHook(
      kind: "raw", fragment: "phases:\n  - type: speak_each", caption: "cap")
    #expect(Rendition.resolve(hook, scenarioID: "demo_v1") == .rawYAML)
  }

  /// A kind newer than this build degrades rather than breaking — the reading
  /// side of ADR-029's "adding a kind is safe on its own" revisit trigger.
  @Test func unknownKindDegradesToTheYAMLBlock() {
    let hook = GalleryHighlightYAMLHook(
      kind: "phases", fragment: "phases:\n  - type: speak_each", caption: "cap")
    #expect(Rendition.resolve(hook, scenarioID: "demo_v1") == .rawYAML)
  }

  /// `kind: persona` over a fragment that is not one. Distinct path from the
  /// unknown-kind case above: this one got past the gate, so it is a supply
  /// defect rather than version skew.
  @Test func personaKindOverANonPersonaFragmentDegrades() {
    let hook = GalleryHighlightYAMLHook(
      kind: "persona", fragment: "phases:\n  - type: speak_each", caption: "cap")
    #expect(Rendition.resolve(hook, scenarioID: "demo_v1") == .rawYAML)
  }
}

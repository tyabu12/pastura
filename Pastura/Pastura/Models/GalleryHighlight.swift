import Foundation

/// A curated, spoiler-safe excerpt of a gallery scenario's run (ADR-029).
///
/// Decodes one `docs/gallery/highlights/<id>.json` file, fetched by the app
/// only when the detail screen shows (no cache, unconditional hash-verified
/// fetch — ADR-029 Decision 4). All fields are **required**: `schema_version`
/// 1 pins the exact shape, and the feature's fail-closed posture means a
/// malformed or partial file must throw at decode time so the caller hides
/// the section, rather than silently rendering a degraded one.
nonisolated public struct GalleryHighlight: Codable, Equatable, Sendable {
  /// Schema version of this highlight file (currently `1`). Not validated
  /// against a known set here — an unrecognised version is still decodable
  /// structurally; the repo-side gate is what pins the shape per version.
  public let schemaVersion: Int

  /// Identifies which gallery scenario (and which pinned YAML content) this
  /// highlight was generated from.
  public let scenarioRef: GalleryHighlightScenarioRef

  /// Provenance of the harness run this highlight was extracted from.
  public let source: GalleryHighlightSource

  /// Ordered, spoiler-filtered excerpt of persona utterances (ADR-029
  /// Decision 3). Schema-capped at 8 entries by the generation pipeline —
  /// not re-enforced at decode time.
  public let excerpt: [GalleryHighlightExcerptEntry]

  /// A snippet of the scenario's backing YAML, shown alongside the excerpt
  /// to invite editing.
  public let yamlHook: GalleryHighlightYAMLHook

  /// A single spoiler-free line teasing the scenario's outcome.
  public let teaser: String

  /// `true` if the excerpt draws from later than the default round window
  /// (rounds 1 through ⌈N/2⌉) — an explicit, auditable override recorded by
  /// the curator (ADR-029 Decision 3, "Position rule").
  public let windowOverride: Bool

  /// Attests the published strings (`excerpt[].text`, `yamlHook`, `teaser`)
  /// passed the `ContentBlocklist` audit at generation time (ADR-029
  /// Decision 2). Required (not optional-defaulting-to-false) and the
  /// caller must additionally check it is `true` before rendering: a
  /// missing key must fail the *decode*, not silently attest a pass, per
  /// the ADR-029 Decision 4 fail-closed policy — a lenient default here
  /// would let a malformed file through as if it had been audited.
  public let contentFilterApplied: Bool

  public init(
    schemaVersion: Int,
    scenarioRef: GalleryHighlightScenarioRef,
    source: GalleryHighlightSource,
    excerpt: [GalleryHighlightExcerptEntry],
    yamlHook: GalleryHighlightYAMLHook,
    teaser: String,
    windowOverride: Bool,
    contentFilterApplied: Bool
  ) {
    self.schemaVersion = schemaVersion
    self.scenarioRef = scenarioRef
    self.source = source
    self.excerpt = excerpt
    self.yamlHook = yamlHook
    self.teaser = teaser
    self.windowOverride = windowOverride
    self.contentFilterApplied = contentFilterApplied
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case scenarioRef = "scenario_ref"
    case source
    case excerpt
    case yamlHook = "yaml_hook"
    case teaser
    case windowOverride = "window_override"
    case contentFilterApplied = "content_filter_applied"
  }
}

/// Pins this highlight to the exact gallery scenario + YAML content it was
/// extracted from.
nonisolated public struct GalleryHighlightScenarioRef: Codable, Equatable, Sendable {
  /// The gallery scenario's canonical identifier (matches
  /// ``GalleryScenario/id``).
  public let id: String

  /// SHA-256 of the backing YAML this highlight was generated from.
  /// Editing the YAML obligates regenerating (or deleting) the highlight
  /// — enforced by the repo-side gate, not re-checked by the app.
  public let yamlSHA256: String

  public init(id: String, yamlSHA256: String) {
    self.id = id
    self.yamlSHA256 = yamlSHA256
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case yamlSHA256 = "yaml_sha256"
  }
}

/// Provenance of the pastura-harness run a highlight was extracted from.
nonisolated public struct GalleryHighlightSource: Codable, Equatable, Sendable {
  /// Identifier of the LLM model used for the run.
  public let model: String

  /// The harness run's identifier.
  public let runID: String

  /// ISO 8601 date-only string (e.g. `"2026-08-06"`) the run was
  /// generated on. Kept as `String` for the same reason as
  /// ``GalleryScenario/addedAt``.
  public let generatedAt: String

  public init(model: String, runID: String, generatedAt: String) {
    self.model = model
    self.runID = runID
    self.generatedAt = generatedAt
  }

  private enum CodingKeys: String, CodingKey {
    case model
    case runID = "run_id"
    case generatedAt = "generated_at"
  }
}

/// One spoiler-eligible persona utterance in the excerpt (ADR-029
/// Decision 3 — `speak_all` / `speak_each` output, `statement` field
/// only).
nonisolated public struct GalleryHighlightExcerptEntry: Codable, Equatable, Sendable {
  /// Display name of the persona who spoke this line.
  public let agent: String

  /// 1-based round number the utterance occurred in.
  public let round: Int

  /// Raw phase-type value the utterance came from (e.g. `"speak_each"`).
  /// Kept as `String` rather than `PhaseType` for the same forward-compat
  /// reason as ``GalleryScenario/phases``.
  public let phase: String

  /// Index of this phase within its round's phase list — the value the
  /// repo-side gate checks against the entry's `phases` list to enforce
  /// the within-round spoiler bound.
  public let phaseIndex: Int

  /// Which field of the phase's output this excerpt was drawn from
  /// (currently always `"statement"` — the Decision 1 allowlist).
  public let sourceField: String

  /// The excerpted line itself.
  public let text: String

  public init(
    agent: String,
    round: Int,
    phase: String,
    phaseIndex: Int,
    sourceField: String,
    text: String
  ) {
    self.agent = agent
    self.round = round
    self.phase = phase
    self.phaseIndex = phaseIndex
    self.sourceField = sourceField
    self.text = text
  }

  private enum CodingKeys: String, CodingKey {
    case agent
    case round
    case phase
    case phaseIndex = "phase_index"
    case sourceField = "source_field"
    case text
  }
}

/// A snippet of the scenario's backing YAML shown alongside the excerpt,
/// inviting the reader to open and edit it in-app.
nonisolated public struct GalleryHighlightYAMLHook: Codable, Equatable, Sendable {
  /// The YAML fragment itself (e.g. one persona's `description:` block).
  public let fragment: String

  /// Human-readable caption explaining what to try editing.
  public let caption: String

  public init(fragment: String, caption: String) {
    self.fragment = fragment
    self.caption = caption
  }

  // No snake_case mapping needed today; explicit per the file-family
  // convention so a future mapped field cannot be added without noticing.
  private enum CodingKeys: String, CodingKey {
    case fragment
    case caption
  }
}

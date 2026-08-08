import Foundation

/// A curated, spoiler-safe excerpt of a gallery scenario's run (ADR-029).
///
/// Decodes one `docs/gallery/highlights/<id>.json` file, fetched by the app
/// only when the detail screen shows (no cache, unconditional hash-verified
/// fetch — ADR-029 Decision 4). All fields are **required**: the feature's
/// fail-closed posture means a malformed or partial file must throw at decode
/// time so the caller hides the section, rather than silently rendering a
/// degraded one.
///
/// `schema_version` names *which* key set applies; the repo-side gate is what
/// pins that shape, not this type. Do not read the two as interchangeable —
/// v1's required keys were widened in place once, when `yaml_hook.kind` landed
/// (ADR-029 § Amendment 2026-08-08). That was licensed by no artifact bearing
/// the older shape surviving anywhere — a precondition that fails on the first
/// release to carry this reader, whatever it is numbered. Any required key
/// added after that **bumps the version**.
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

  /// Index of ``agent`` in the scenario's `personas:` list — the value a real
  /// run resolves the speaker's avatar colour from
  /// (``SheepAvatar/Character/forAgent(_:position:)`` → `allCases[position % 4]`,
  /// fed by `SimulationView.personaItem(for:)`).
  ///
  /// Carried in the file rather than inferred because an excerpt is not a run:
  /// the speaker's rank *within the excerpt* equals their persona index only
  /// when the excerpt's speakers happen to be a prefix of `personas:`. The
  /// extractor derives it from the sibling YAML and the repo-side gate
  /// cross-checks it against that same YAML, so a curator may excerpt any lines
  /// and still get the run's colours.
  public let personaIndex: Int

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
    personaIndex: Int,
    sourceField: String,
    text: String
  ) {
    self.agent = agent
    self.round = round
    self.phase = phase
    self.phaseIndex = phaseIndex
    self.personaIndex = personaIndex
    self.sourceField = sourceField
    self.text = text
  }

  private enum CodingKeys: String, CodingKey {
    case agent
    case round
    case phase
    case phaseIndex = "phase_index"
    case personaIndex = "persona_index"
    case sourceField = "source_field"
    case text
  }

  /// The phase this line was published under, paired with the output field
  /// that phase declares its line in — or `nil` when either cannot be
  /// resolved, so no consumer can place the line in a `TurnOutput`.
  ///
  /// The two causes are deliberately not distinguished: an unmappable
  /// ``phase`` (a feed newer than this build — ADR-029 revisit trigger 1), or
  /// a phase that declares no primary output field, which is every code phase
  /// **and** `narrate`, whose `{ commentary }` shape is Engine-fixed rather
  /// than author-declared. `ScenarioConventionsTests` pins the `narrate` half,
  /// which ADR-029's amendment leans on.
  ///
  /// **This is the single definition of the rule.** Both consumers read it —
  /// `GalleryHighlightLoader` to decide whether to publish the highlight at
  /// all (ADR-029 § Amendment 2026-08-07,
  /// `check=excerpt_phase_unrenderable`), and
  /// `GalleryScenarioDetailFormat.excerptRows` to build the row. They were
  /// briefly two hand-written predicates kept in step by comments; one symbol
  /// removes the drift, whose failure mode was a highlight the loader
  /// published rendering as a teaser with no figure.
  public var renderablePhase: (type: PhaseType, primaryField: String)? {
    guard let phaseType = PhaseType(rawValue: phase),
      let primaryField = ScenarioConventions.primaryField(for: phaseType)
    else { return nil }
    return (phaseType, primaryField)
  }
}

/// A snippet of the scenario's backing YAML shown alongside the excerpt,
/// inviting the reader to open and edit it in-app.
nonisolated public struct GalleryHighlightYAMLHook: Codable, Equatable, Sendable {
  /// What shape the fragment is in, and therefore how a consumer may draw it
  /// (ADR-029 Decision 1). `"persona"` licenses the app's editor-vocabulary
  /// rendition; `"raw"` claims no structure and publishes the fragment as a
  /// YAML block.
  ///
  /// Kept as `String` rather than an enum for the same forward-compat reason as
  /// ``GalleryHighlightExcerptEntry/phase``: the supply side is strict (the
  /// gate allowlists the value) while a **reader** must tolerate a kind newer
  /// than its build and fall back to the YAML block, rather than failing the
  /// decode and hiding a section that is otherwise entirely valid.
  public let kind: String

  /// The YAML fragment itself (e.g. one persona's `description:` block).
  public let fragment: String

  /// Human-readable caption explaining what to try editing.
  public let caption: String

  public init(kind: String, fragment: String, caption: String) {
    self.kind = kind
    self.fragment = fragment
    self.caption = caption
  }

  // No snake_case mapping needed today; explicit per the file-family
  // convention so a future mapped field cannot be added without noticing.
  private enum CodingKeys: String, CodingKey {
    case kind
    case fragment
    case caption
  }
}

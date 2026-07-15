import Foundation

/// The category taxonomy for gallery scenarios.
///
/// Raw values map directly to the snake_case strings used in `gallery.json`.
/// Decoding an unrecognised raw value will throw — an unknown category means
/// either a schema bump the app hasn't been updated for (fail loudly) or a
/// typo in the remote data (reject). All six cases must be handled to decode
/// successfully.
nonisolated public enum GalleryCategory: String, Codable, Sendable, Equatable, CaseIterable {
  case socialPsychology = "social_psychology"
  case gameTheory = "game_theory"
  case ethics = "ethics"
  case roleplay = "roleplay"
  case creative = "creative"
  case experimental = "experimental"
}

nonisolated extension GalleryCategory {
  /// Human-readable, localized display name for the category.
  ///
  /// Co-located with the enum (rather than a View file) so every surface that
  /// renders a persisted category — Browse, Home, Past Results (#748) — shares
  /// one mapping. `nonisolated` so non-MainActor callers (e.g. tests) can read
  /// it; the strings land in `Localizable.xcstrings` for `ja` translation.
  public var displayName: String {
    switch self {
    case .socialPsychology: return String(localized: "Social Psychology")
    case .gameTheory: return String(localized: "Game Theory")
    case .ethics: return String(localized: "Ethics")
    case .roleplay: return String(localized: "Roleplay")
    case .creative: return String(localized: "Creative")
    case .experimental: return String(localized: "Experimental")
    }
  }
}

/// A single scenario entry in the remote gallery.
///
/// Maps to one element of the `scenarios` array in `gallery.json`.
/// `yamlURL` is decoded as `URL` for type safety; callers are responsible
/// for verifying the download against `yamlSHA256`.
nonisolated public struct GalleryScenario: Codable, Sendable, Equatable, Hashable {
  /// Canonical identifier for this gallery entry (e.g. `"asch_conformity_v1"`).
  public let id: String

  /// Human-readable scenario title.
  public let title: String

  /// Subject-matter category.
  public let category: GalleryCategory

  /// Brief description of what the scenario simulates.
  public let description: String

  /// Display name of the scenario author.
  public let author: String

  /// Identifier of the LLM model recommended for this scenario.
  ///
  /// Validated only via the `recommendedModelMatchesRegistry` curation test,
  /// NOT at decode time, to preserve forward compatibility for older app
  /// versions reading a newer `gallery.json` containing model ids they
  /// don't yet know about. A future contributor "hardening" this with a
  /// throwing decoder would silently break those old installs.
  public let recommendedModel: ModelID

  /// Approximate number of LLM inferences the scenario requires.
  public let estimatedInferences: Int

  /// Number of agents (personas) the scenario runs, surfaced as the sheep
  /// avatars in the Browse-tab row meta line.
  ///
  /// Optional and decoded leniently (never throws on absence) so an older
  /// app reading a newer feed — or a newer app reading a feed predating this
  /// key — still decodes; an absent value surfaces as `nil` and the meta
  /// line is hidden. Same forward-compat posture as ``recommendedModel``;
  /// a future contributor making this required would break older installs.
  public let agentCount: Int?

  /// Number of rounds the scenario runs, surfaced in the Browse-tab row meta
  /// line. Optional and forward-compat for the same reason as ``agentCount``
  /// — see its note.
  public let rounds: Int?

  /// Ordered list of the scenario's phase-type raw values (e.g.
  /// `["assign", "speak_all", "vote", "eliminate", "summarize"]`), derived
  /// from the backing YAML at curation time. Drives the Browse-tab art tile's
  /// signature-phase glyph badge (the client picks the "headline" phase via a
  /// fixed priority order — see ``GalleryCatalogRowFormat/signaturePhase(phases:)``).
  ///
  /// Decoded as `[String]` — **not** `[PhaseType]` — on purpose: a throwing
  /// `[PhaseType]` decode would fail the **entire** ``GalleryIndex`` parse the
  /// moment a future feed adds one phase kind this app build doesn't know,
  /// breaking the older-app × newer-feed direction. The lenient `[String]`
  /// passes unknown kinds through and the signature derivation falls back when
  /// it can't map a kind. Optional + forward-compat like ``agentCount`` /
  /// ``rounds`` (absent → `nil` → the badge is simply hidden); making it
  /// required would break older installs reading a feed predating this key.
  public let phases: [String]?

  /// ISO 639-1 language of this scenario's content (`"ja"` / `"en"`), as
  /// declared at the top level of the backing YAML (ADR-010 D1) and
  /// denormalized into the index so the Browse (さがす) tab can filter by
  /// language **before** downloading any YAML.
  ///
  /// Optional + lenient decode (absent → `nil`) for the same forward-compat
  /// reason as ``agentCount`` / ``rounds`` / ``phases``: an old cached
  /// `gallery.json` on-device — or an older app reading a newer feed —
  /// predates this key and must still decode. Read through
  /// ``effectiveLanguage`` rather than this raw optional, which applies the
  /// `"ja"` legacy default. A future contributor making this required would
  /// break those older installs.
  public let language: String?

  /// The minimum `ENGINE_SCHEMA_VERSION` this scenario's backing YAML
  /// requires (ADR-020 D3 declared escape hatch), for capability-derived
  /// gaps the automatic `phases`⊄`PhaseType.allCases` gate can't catch —
  /// e.g. a semantic change to an existing phase's meaning rather than a
  /// wholly new phase kind.
  ///
  /// Optional + lenient decode (absent → `nil`) for the same forward-compat
  /// reason as ``agentCount`` / ``rounds`` / ``phases`` / ``language``: an
  /// old cached `gallery.json` — or an older app reading a newer feed —
  /// predates this key and must still decode. At baseline every current
  /// entry decodes to `nil` (unconstrained); the value is only set,
  /// author-raised or tooling-computed, once a post-baseline feature
  /// requires a specific engine floor. A future contributor making this
  /// required would break older installs.
  public let minEngineVersion: Int?

  /// Curator-assigned pin rank for gallery ordering (ADR-025). Lower number
  /// = higher priority (pinned toward the top of the Browse listing);
  /// `nil` = not pinned, and the entry falls through to the default
  /// `added_at`-descending recency order.
  ///
  /// Optional + lenient decode (absent → `nil`) for the same forward-compat
  /// reason as ``agentCount`` / ``rounds`` / ``phases`` / ``language`` /
  /// ``minEngineVersion``: an old cached `gallery.json` — or an older app
  /// reading a newer feed — predates this key and must still decode. A
  /// future contributor making this required would break older installs.
  public let featured: Int?

  /// The language to filter / group this entry by, defaulting an absent
  /// ``language`` to `"ja"`.
  ///
  /// The default exists **only** as a safety net for legacy cached indices
  /// that predate the `language` key — the launch gallery is entirely
  /// Japanese. Every entry the curated feed ships populates `language`
  /// explicitly (pinned by `GallerySeedYAMLTests`), so the default never
  /// fires for current feed data. This is the index-side counterpart to
  /// ADR-010 D2's "no silent `ja` fill" rule for *YAML* parsing: that rule
  /// governs `ScenarioLoader`; this denormalized index field is a separate
  /// distribution artifact whose only `nil` source is an outdated on-device
  /// cache.
  public var effectiveLanguage: String { language ?? "ja" }

  /// Remote URL from which the YAML definition can be fetched.
  public let yamlURL: URL

  /// Lowercase hex SHA-256 of the YAML file at `yamlURL` for integrity verification.
  public let yamlSHA256: String

  /// Date the scenario was added to the gallery, as an ISO 8601 date-only string
  /// (e.g. `"2026-04-14"`). Kept as `String` so no date formatter config is
  /// required at the call site; the View layer can parse it as needed.
  public let addedAt: String

  public init(
    id: String,
    title: String,
    category: GalleryCategory,
    description: String,
    author: String,
    recommendedModel: ModelID,
    estimatedInferences: Int,
    yamlURL: URL,
    yamlSHA256: String,
    addedAt: String,
    agentCount: Int? = nil,
    rounds: Int? = nil,
    phases: [String]? = nil,
    language: String? = nil,
    minEngineVersion: Int? = nil,
    featured: Int? = nil
  ) {
    self.id = id
    self.title = title
    self.category = category
    self.description = description
    self.author = author
    self.recommendedModel = recommendedModel
    self.estimatedInferences = estimatedInferences
    self.yamlURL = yamlURL
    self.yamlSHA256 = yamlSHA256
    self.addedAt = addedAt
    self.agentCount = agentCount
    self.rounds = rounds
    self.phases = phases
    self.language = language
    self.minEngineVersion = minEngineVersion
    self.featured = featured
  }

  // Explicit CodingKeys so the JSON snake_case ↔ Swift camelCase mapping is
  // visible here rather than relying on a decoder-wide keyDecodingStrategy,
  // which callers would need to remember to configure.
  private enum CodingKeys: String, CodingKey {
    case id
    case title
    case category
    case description
    case author
    case recommendedModel = "recommended_model"
    case estimatedInferences = "estimated_inferences"
    case agentCount = "agent_count"
    case rounds
    case phases
    case language
    case minEngineVersion = "min_engine_version"
    case featured
    case yamlURL = "yaml_url"
    case yamlSHA256 = "yaml_sha256"
    case addedAt = "added_at"
  }
}

/// The top-level envelope returned by `gallery.json`.
///
/// `updatedAt` is stored as a raw ISO 8601 string rather than `Date` so that
/// callers are not required to configure a custom `dateDecodingStrategy` on
/// their `JSONDecoder` instance.
nonisolated public struct GalleryIndex: Codable, Sendable, Equatable {
  /// Schema version of the gallery feed (currently `1`).
  public let version: Int

  /// ISO 8601 timestamp string indicating when the gallery was last updated.
  public let updatedAt: String

  /// Ordered list of available gallery scenarios.
  public let scenarios: [GalleryScenario]

  public init(version: Int, updatedAt: String, scenarios: [GalleryScenario]) {
    self.version = version
    self.updatedAt = updatedAt
    self.scenarios = scenarios
  }

  private enum CodingKeys: String, CodingKey {
    case version
    case updatedAt = "updated_at"
    case scenarios
  }
}

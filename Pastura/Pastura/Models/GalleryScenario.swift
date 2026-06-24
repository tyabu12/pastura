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
    phases: [String]? = nil
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

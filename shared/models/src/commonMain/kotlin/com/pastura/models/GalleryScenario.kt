package com.pastura.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Alias for the canonical model identifier string (e.g. `"gemma_4_e2b"`).
 *
 * Kotlin port of `Pastura/Pastura/Models/ModelDescriptor.swift:ModelID`.
 * The full `ModelDescriptor` is deferred from PR-A (App-layer-only, not
 * `Codable`, Foundation `URL` coupled) — gallery references the identifier
 * via this alias only.
 */
public typealias ModelID = String

/**
 * The category taxonomy for gallery scenarios.
 *
 * Kotlin port of `Pastura/Pastura/Models/GalleryScenario.swift:GalleryCategory`.
 *
 * Raw values map directly to the snake_case strings used in `gallery.json`.
 * Decoding an unrecognised raw value will throw — an unknown category means
 * either a schema bump the app hasn't been updated for (fail loudly) or a
 * typo in the remote data (reject).
 */
@Serializable
public enum class GalleryCategory {
    @SerialName("social_psychology")
    SOCIAL_PSYCHOLOGY,

    @SerialName("game_theory")
    GAME_THEORY,

    @SerialName("ethics")
    ETHICS,

    @SerialName("roleplay")
    ROLEPLAY,

    @SerialName("creative")
    CREATIVE,

    @SerialName("experimental")
    EXPERIMENTAL,
}

/**
 * A single scenario entry in the remote gallery.
 *
 * Kotlin port of `Pastura/Pastura/Models/GalleryScenario.swift:GalleryScenario`.
 * Maps to one element of the `scenarios` array in `gallery.json`.
 *
 * **Wire-key convention (snake_case — production-relevant):**
 * Unlike [Phase] and [Scenario] which use camelCase (Swift Codable default),
 * `GalleryScenario` has **explicit `CodingKeys` in Swift** mapping every
 * multi-word property to snake_case — `gallery.json` is fetched from a
 * remote URL and uses snake_case keys by contract. The Kotlin port mirrors
 * this via `@SerialName`.
 *
 * **`yamlURL` divergence from Swift:** Swift uses Foundation `URL` for type
 * safety. KMP commonMain has no built-in URL type, so the Kotlin port uses
 * `String`. Callers needing parsed-URL operations should validate at the
 * platform-actual layer (W3+ scope if KMP gallery loading is implemented).
 *
 * @property id                   Canonical identifier (e.g. `"asch_conformity_v1"`).
 * @property title                Human-readable scenario title.
 * @property category             Subject-matter category.
 * @property description          Brief description of what the scenario simulates.
 * @property author               Display name of the scenario author.
 * @property recommendedModel     Identifier of the recommended LLM model. Validated
 *                                only via curation tests (forward-compatible:
 *                                older app versions reading newer `gallery.json`
 *                                with unknown model ids must still parse).
 * @property estimatedInferences  Approximate number of LLM inferences required.
 * @property yamlURL              Remote URL string from which the YAML definition
 *                                can be fetched.
 * @property yamlSHA256           Lowercase hex SHA-256 of the YAML at [yamlURL]
 *                                for integrity verification.
 * @property addedAt              ISO 8601 date-only string (e.g. `"2026-04-14"`).
 *                                Kept as String so no date formatter config is
 *                                required at the call site.
 * @property agentCount           Number of agents (personas), Browse-tab row meta.
 * @property rounds               Number of rounds, Browse-tab row meta.
 * @property phases               Ordered phase-type raw values (e.g.
 *                                `["assign", "speak_all", "vote"]`), for the art
 *                                tile's signature-phase glyph. Decoded as
 *                                `List<String>` — **not** `List<PhaseType>` — on
 *                                purpose: a throwing typed decode would fail the
 *                                whole index the moment a newer feed adds a phase
 *                                kind this build doesn't know (Swift forbids this).
 * @property language             ISO 639-1 content language (`"ja"` / `"en"`),
 *                                denormalized so Browse can filter before download.
 * @property minEngineVersion     Minimum `ENGINE_SCHEMA_VERSION` the backing YAML
 *                                requires (ADR-020 D3 escape hatch); `null` =
 *                                unconstrained.
 * @property featured             Curator pin rank (ADR-025); lower = higher
 *                                priority, `null` = not pinned.
 *
 * The six trailing properties are all optional with `= null` defaults so an
 * older feed / cached index predating any of these keys still decodes
 * (forward-compat — Swift makes each one lenient-optional for the same reason;
 * making any required would break older installs). Wire keys via `@SerialName`
 * mirror Swift's explicit `CodingKeys`.
 */
@Serializable
public data class GalleryScenario(
    public val id: String,
    public val title: String,
    public val category: GalleryCategory,
    public val description: String,
    public val author: String,
    @SerialName("recommended_model")
    public val recommendedModel: ModelID,
    @SerialName("estimated_inferences")
    public val estimatedInferences: Int,
    @SerialName("yaml_url")
    public val yamlURL: String,
    @SerialName("yaml_sha256")
    public val yamlSHA256: String,
    @SerialName("added_at")
    public val addedAt: String,
    @SerialName("agent_count")
    public val agentCount: Int? = null,
    public val rounds: Int? = null,
    public val phases: List<String>? = null,
    public val language: String? = null,
    @SerialName("min_engine_version")
    public val minEngineVersion: Int? = null,
    public val featured: Int? = null,
)

/**
 * The top-level envelope returned by `gallery.json`.
 *
 * Kotlin port of `Pastura/Pastura/Models/GalleryScenario.swift:GalleryIndex`.
 *
 * `updatedAt` is stored as a raw ISO 8601 string rather than a `kotlinx-datetime`
 * `Instant` so callers are not required to add the datetime library dependency.
 * Same Swift-side rationale (no `dateDecodingStrategy` config required).
 *
 * @property version    Schema version of the gallery feed (currently `1`).
 * @property updatedAt  ISO 8601 timestamp string of last gallery update.
 * @property scenarios  Ordered list of available gallery scenarios.
 */
@Serializable
public data class GalleryIndex(
    public val version: Int,
    @SerialName("updated_at")
    public val updatedAt: String,
    public val scenarios: List<GalleryScenario>,
)

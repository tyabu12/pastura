import Foundation

/// Display-prep metadata for a Home scenario row, resolved from a
/// ``ScenarioRecord``'s stored YAML via ``ScenarioLoader``.
///
/// On a successful parse, `agentCount` / `rounds` / `description` carry the
/// scenario meta for the row's secondary line (ADR-016 D3 layout — the
/// consuming View lands in P2). On a parse failure the row **degrades to
/// name-only**: `name` always reflects ``ScenarioRecord/name`` (authoritative
/// for the row title) and the optional fields are `nil`. A parse failure for
/// one row must never propagate to ``HomeViewModel/errorMessage`` — a single
/// broken preset cannot be allowed to blank the whole list.
///
/// `nonisolated` (App layer defaults to MainActor) because it is pure display
/// data resolved off the `ScenarioLoader` parse and compared/constructed from
/// `nonisolated` contexts (the cache below); see
/// `.claude/rules/swift-isolation.md` Pattern 2/5.
nonisolated struct ScenarioRowMetadata: Equatable, Sendable {
  /// Row title — always the record's `name`, even on parse failure.
  let name: String
  /// Agent count from the parsed scenario; `nil` when the YAML failed to parse.
  let agentCount: Int?
  /// Round count from the parsed scenario; `nil` on parse failure.
  let rounds: Int?
  /// One-line description from the parsed scenario; `nil` on parse failure.
  let description: String?
  /// Approximate LLM inference count for one run, from
  /// ``ScenarioLoader/estimateInferenceCount(_:)`` — a static per-phase × rounds
  /// *estimate*. This is the app's formula; the Shared Scenarios gallery instead
  /// shows a *measured* `n` from a real factory run, so the two are independent
  /// approximations and need not match for the same scenario. `nil` on parse
  /// failure.
  let estimatedInferences: Int?

  init(
    name: String,
    agentCount: Int? = nil,
    rounds: Int? = nil,
    description: String? = nil,
    estimatedInferences: Int? = nil
  ) {
    self.name = name
    self.agentCount = agentCount
    self.rounds = rounds
    self.description = description
    self.estimatedInferences = estimatedInferences
  }
}

/// In-process parse memo for Home scenario-row metadata.
///
/// Keyed by ``ScenarioRecord/id`` + ``ScenarioRecord/updatedAt`` so an
/// unchanged row is not re-parsed across reloads (pull-to-refresh). The memo
/// is **not** persisted and **not** keyed by `sourceId`: keying by `sourceId`
/// would collapse variants and desync from ADR-010 D6, which collapses
/// variants for *display* but must parse each concrete variant independently.
/// A bumped `updatedAt` (e.g. a gallery update) changes the key, so the stale
/// entry is no longer found and the row is re-parsed.
///
/// ``resolve(_:parse:)`` rebuilds the memo to exactly the current key set on
/// every call, so entries for deleted or superseded rows are dropped — the
/// memo cannot grow unbounded across the app's lifetime.
nonisolated struct ScenarioRowMetadataCache {
  private var memo: [Key: ScenarioRowMetadata] = [:]

  private struct Key: Hashable {
    let id: String
    let updatedAt: Date
  }

  init() {}

  /// Resolves metadata for `records`, reusing memoized parses for unchanged
  /// `(id, updatedAt)` keys and rebuilding the memo to exactly the current key
  /// set (stale entries dropped).
  ///
  /// - Parameters:
  ///   - records: the rows to resolve, **after** ADR-010 D6 variant collapsing
  ///     — never the pre-collapse variant set, so the returned keys stay a
  ///     subset of the displayed row ids.
  ///   - parse: invoked only on a cache miss. Injected so the heavy
  ///     ``ScenarioLoader`` call (and, in tests, a miss counter) stays under
  ///     the caller's control.
  /// - Returns: row metadata keyed by ``ScenarioRecord/id``.
  mutating func resolve(
    _ records: [ScenarioRecord],
    parse: (ScenarioRecord) -> ScenarioRowMetadata
  ) -> [String: ScenarioRowMetadata] {
    var rebuilt: [Key: ScenarioRowMetadata] = [:]
    var result: [String: ScenarioRowMetadata] = [:]
    for record in records {
      let key = Key(id: record.id, updatedAt: record.updatedAt)
      let meta = memo[key] ?? parse(record)
      rebuilt[key] = meta
      result[record.id] = meta
    }
    memo = rebuilt
    return result
  }
}

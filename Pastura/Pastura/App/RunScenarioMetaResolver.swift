import Foundation

/// In-process resolver for a Past Results (観察履歴) row's scenario meta —
/// `agentCount` and total-rounds `N` — parsed from a run's scenario YAML.
///
/// Mirrors ``ScenarioRowMetadataCache`` but keyed by YAML **content** rather
/// than `(id, updatedAt)`: a History run resolves its meta **snapshot-first**
/// (run-time-faithful, surviving scenario edits and deletion — see
/// ``ScenarioSnapshotResolver``), and an orphaned run has no live scenario id,
/// so the YAML string is the only stable key. Two runs of the same un-edited
/// scenario therefore share a single parse. ``resolve(_:)`` rebuilds the memo to
/// exactly the passed key set, so it can't grow unbounded as the keyset window
/// pages deeper.
///
/// `nonisolated` (the App layer defaults to MainActor) because it is a pure
/// value cache constructed and mutated from ``ResultsViewModel`` with no
/// MainActor state of its own (see `.claude/rules/swift-isolation.md` Pattern 2).
nonisolated struct RunScenarioMetaResolver {
  /// The two scenario-definition fields the redesigned row needs. Both `nil`
  /// when the YAML is absent or failed to parse — the row then degrades to
  /// name-only (no sheep avatars, bare completion summary) rather than blanking.
  struct Meta: Equatable, Sendable {
    let agentCount: Int?
    let rounds: Int?
    static let unknown = Meta(agentCount: nil, rounds: nil)
  }

  /// YAML→`Scenario` parsing lives in `Engine`, which `Data` may not import, so
  /// this resolution is necessarily App-layer (mirrors `ScenarioRowMetadata` /
  /// `HomeViewModel`). `load` does only structural mapping — no run-validation —
  /// which is correct for re-parsing already-persisted YAML (Engine § "Parse vs
  /// validate boundary").
  private let loader = ScenarioLoader()
  private var memo: [String: Meta] = [:]

  init() {}

  /// Resolves `Meta` for each run keyed by its resolved YAML source — the caller
  /// supplies `snapshot ?? liveYAML` per run, so snapshot-first precedence lives
  /// at the callsite. Reuses a memoized parse for unchanged YAML and rebuilds
  /// the memo to exactly the passed key set (stale entries dropped).
  ///
  /// - Parameter runs: `(id, yaml)` per row; a `nil` `yaml` resolves to
  ///   ``Meta/unknown``.
  /// - Returns: meta keyed by run id (an entry for every run).
  mutating func resolve(_ runs: [(id: String, yaml: String?)]) -> [String: Meta] {
    var rebuilt: [String: Meta] = [:]
    var result: [String: Meta] = [:]
    for run in runs {
      guard let yaml = run.yaml else {
        result[run.id] = .unknown
        continue
      }
      let meta = rebuilt[yaml] ?? memo[yaml] ?? parse(yaml)
      rebuilt[yaml] = meta
      result[run.id] = meta
    }
    memo = rebuilt
    return result
  }

  /// Parses YAML to its `agentCount` / `rounds`; a parse failure degrades to
  /// ``Meta/unknown`` (one broken snapshot must never blank the row).
  private func parse(_ yaml: String) -> Meta {
    guard let scenario = try? loader.load(yaml: yaml) else { return .unknown }
    return Meta(agentCount: scenario.agentCount, rounds: scenario.rounds)
  }
}

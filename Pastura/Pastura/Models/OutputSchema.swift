import Foundation

/// Structured representation of an LLM phase's expected JSON output shape.
///
/// Threaded through ``LLMService/generate(system:user:schema:)`` so each
/// backend can translate it to its native constrained-decoding mechanism
/// (llama.cpp: GBNF grammar, Ollama: `format:"json"`, Mock: recorded for
/// tests, future LiteRT-LM: JSON Schema adapter).
///
/// Field order is **not alphabetical** — primary (user-visible) keys like
/// `statement` / `action` / `vote` precede secondary keys like
/// `inner_thought` / `reason`. This is load-bearing for the streaming UX:
/// ``PartialOutputExtractor`` gates visible content on seeing a recognised
/// primary key, so if grammar forced `inner_thought` first (as alphabetical
/// ordering would) the streaming row would stay empty for most of the
/// stream. See ADR-002 §12 and the PR #194 plan for the critic-driven
/// rationale.
///
/// Vocabulary is intentionally minimal (``Kind/string`` + ``Kind/choice``)
/// — matches Pastura's actual scenario shape. Future backends needing
/// richer JSON Schema features (integers, booleans, regex formats) should
/// add an adapter, not extend this enum.
nonisolated public struct OutputSchema: Codable, Sendable, Equatable {

  /// Ordered list of expected output fields. Order reflects the
  /// primary-first policy (see type-level doc) and is the single source
  /// of truth consumed by both ``GBNFGrammarBuilder`` and
  /// ``PromptBuilder`` so grammar order and prompt example order
  /// cannot drift.
  public let fields: [Field]

  /// Known primary-output field names, in the order they should appear
  /// in generated output. Kept in sync with
  /// ``PartialOutputExtractor/primaryKeys`` — the consistency is
  /// verified by `OutputSchemaTests.primaryKeySuperset`.
  ///
  /// Matches the canonical fields advertised by
  /// ``ScenarioConventions/primaryField(for:)`` (one canonical field per
  /// LLM phase: speak → `statement`, choose → `action`, vote → `vote`,
  /// reflect → `note`).
  public static let knownPrimaryKeys: [String] = [
    "statement", "action", "vote", "note"
  ]

  /// Known secondary-output field names (reasoning / justification).
  /// Emitted after primary keys so the streaming row populates
  /// progressively.
  public static let knownSecondaryKeys: [String] = [
    "inner_thought", "reason"
  ]

  /// The declared private-thought (secondary) field name for this schema,
  /// or `nil` if it declares none. Picks the schema's secondary field in
  /// ``knownSecondaryKeys`` priority order (`inner_thought` before `reason`).
  /// Real scenarios author exactly one secondary key per phase (speak →
  /// `inner_thought`, vote → `reason`), so the order only disambiguates the
  /// degenerate both-present case.
  ///
  /// Consumed by ``LLMCaller`` to feed ``PartialOutputExtractor`` the phase's
  /// thought key, so the live streaming THINKING section surfaces the vote
  /// `reason` (not only `inner_thought`). Mirrors the committed-display
  /// resolver ``ScenarioConventions/thoughtField(for:)`` /
  /// ``TurnOutput/secondaryText(for:)`` for all preset shapes (#609).
  public var thoughtFieldName: String? {
    let declared = Set(fields.map(\.name))
    return Self.knownSecondaryKeys.first { declared.contains($0) }
  }

  public init(fields: [Field]) {
    self.fields = fields
  }

  /// Build an ``OutputSchema`` from a ``Phase``'s schema dictionary.
  ///
  /// - Returns: `nil` when the phase has no output schema (code phases)
  ///   or an empty schema — callers should treat `nil` as "no
  ///   constrained decoding" and skip grammar injection.
  ///
  /// For `.choose` phases with non-empty `options`, the `action` field
  /// (if present in the schema) becomes ``Kind/choice`` — a marker that
  /// the field carries an author-defined choice token. The value is NOT
  /// grammar-constrained (see ``Kind/choice`` for the model-agnostic
  /// safety rationale, #599); the runtime ``ChooseHandler`` `validateAction`
  /// fallback constrains it instead.
  public static func from(phase: Phase) -> OutputSchema? {
    guard let raw = phase.outputSchema, !raw.isEmpty else { return nil }
    let orderedNames = orderKeys(Array(raw.keys))
    let isChooseWithOptions =
      phase.type == .choose && !(phase.options ?? []).isEmpty
    let fields = orderedNames.map { name -> Field in
      if isChooseWithOptions, name == "action" {
        return Field(name: name, kind: .choice)
      }
      return Field(name: name, kind: .string)
    }
    return OutputSchema(fields: fields)
  }

  /// Apply primary-first ordering policy to a raw list of field names.
  /// Primary keys appear in ``knownPrimaryKeys`` order; secondary keys
  /// in ``knownSecondaryKeys`` order; unknown keys sorted alphabetically
  /// at the end. Keys not present in the input are skipped.
  private static func orderKeys(_ keys: [String]) -> [String] {
    let present = Set(keys)
    var ordered: [String] = []
    for key in knownPrimaryKeys where present.contains(key) {
      ordered.append(key)
    }
    for key in knownSecondaryKeys where present.contains(key) {
      ordered.append(key)
    }
    let knownSet = Set(knownPrimaryKeys + knownSecondaryKeys)
    let unknown = keys.filter { !knownSet.contains($0) }.sorted()
    ordered.append(contentsOf: unknown)
    return ordered
  }

  /// A single named field in an ``OutputSchema``.
  nonisolated public struct Field: Codable, Sendable, Equatable {
    public let name: String
    public let kind: Kind

    public init(name: String, kind: Kind) {
      self.name = name
      self.kind = kind
    }
  }

  /// The kind of value a ``Field`` accepts.
  ///
  /// Intentionally narrow — Pastura's presets only ever express "a free
  /// string" or "an author-defined choice token". Future scenario shapes
  /// should prefer an adapter to JSON Schema over extending this enum.
  nonisolated public enum Kind: Codable, Sendable, Equatable {
    /// Any string value (UTF-8, including CJK / emoji).
    case string
    /// An author-defined choice field (the `action` of a `.choose`
    /// phase with non-empty ``Phase/options``).
    ///
    /// Carries **no** option payload by design. The choice options were
    /// once enumerated directly into the GBNF grammar as alternation
    /// literals, but that crashed llama.cpp's sampler on CJK / dynamic
    /// option values — the crash is token-dependent, so a char-class
    /// guard cannot make it safe across models (#597 vote precedent,
    /// #599). The grammar now constrains JSON **structure** only; this
    /// case is grammar-equivalent to ``string`` (emits the shared
    /// `string` production). The value is constrained at runtime by
    /// ``ChooseHandler`` `validateAction`, which normalizes then
    /// canonicalizes and returns `String?` — an off-menu answer is
    /// **dropped** (emitting `.actionRejected`), never coerced to a
    /// menu entry. The model still learns the valid options from the
    /// prompt (``PromptBuilder``).
    ///
    /// This comment previously cited an `options[0]` fallback as the
    /// runtime constraint. ADR-021 § "Amendment 2026-07-17" removed that
    /// fallback as a fabrication — it scored an agent that emitted
    /// `betray!` or `裏切る` as having cooperated — and also supersedes
    /// ADR-002 § "Amendment 2026-06-14", which had called `options[0]`
    /// "the correctness floor".
    ///
    /// The marker is retained (rather than collapsing to ``string``) so
    /// the language-adherence detector can exclude author-fixed tokens
    /// like `cooperate` / `betray` from its verdict — see
    /// `LLMCaller.naturalLanguageFieldValues` (ADR-010 Step E, #405).
    case choice
  }
}

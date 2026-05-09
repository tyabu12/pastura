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
/// Vocabulary is intentionally minimal (``Kind/string`` + ``Kind/enumeration(_:)``)
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
  /// LLM phase: speak → `statement`, choose → `action`, vote → `vote`).
  public static let knownPrimaryKeys: [String] = [
    "statement", "action", "vote"
  ]

  /// Known secondary-output field names (reasoning / justification).
  /// Emitted after primary keys so the streaming row populates
  /// progressively.
  public static let knownSecondaryKeys: [String] = [
    "inner_thought", "reason"
  ]

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
  /// (if present in the schema) becomes ``Kind/enumeration(_:)``
  /// carrying those options — stronger than the runtime
  /// `validateAction` fallback.
  public static func from(phase: Phase) -> OutputSchema? {
    guard let raw = phase.outputSchema, !raw.isEmpty else { return nil }
    let orderedNames = orderKeys(Array(raw.keys))
    let isChooseWithOptions =
      phase.type == .choose && !(phase.options ?? []).isEmpty
    let fields = orderedNames.map { name -> Field in
      if isChooseWithOptions, name == "action", let options = phase.options {
        return Field(name: name, kind: .enumeration(options))
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
  /// Intentionally narrow — Pastura's presets only ever express "a
  /// string" or "one of these literal string options". Future scenario
  /// shapes should prefer an adapter to JSON Schema over extending this
  /// enum.
  nonisolated public enum Kind: Codable, Sendable, Equatable {
    /// Any string value (UTF-8, including CJK / emoji).
    case string
    /// One of a fixed set of string literals — used for
    /// ``Phase/options`` on `.choose` phases.
    case enumeration([String])
  }
}

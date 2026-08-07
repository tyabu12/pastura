import Foundation

/// Naming conventions for scenario authoring.
///
/// LLM phases each have a single canonical primary output field that the
/// engine and UI key on:
///
/// | Phase | Canonical primary field |
/// |-------|-------------------------|
/// | `.speakAll`, `.speakEach`, `.whisper` | `statement` |
/// | `.choose` | `action` |
/// | `.vote` | `vote` |
/// | `.reflect` | `note` |
///
/// `.narrate` is the one LLM phase absent from the table: its
/// `{ commentary }` schema is engine-fixed rather than author-declared, so
/// there is no canonical `output:` field to key on.
///
/// Speak phases route the canonical field's value into the conversation log
/// (read by ``PromptBuilder``) and into the agent's primary display text
/// (rendered by ``AgentOutputRow``). Choose reads the canonical field back
/// directly in ``ChooseHandler``, which validates it against the phase
/// options at runtime (the value is not grammar-constrained — see
/// ``OutputSchema/from(phase:)`` and ADR-002 §Amendment 2026-06-14). Vote
/// is similarly read directly by
/// ``VoteHandler`` and surfaces composite formatting via
/// ``TurnOutput/primaryText(for:)``.
///
/// Code phases (`.scoreCalc`, `.assign`, `.eliminate`, `.summarize`,
/// `.conditional`, `.eventInject`, `.relationshipUpdate`) emit no LLM output
/// and therefore have no primary field — ``primaryField(for:)`` returns `nil`.
///
/// This convention is enforced at scenario-commit time by
/// ``ScenarioValidator/validateForCommit(_:)``; it is not re-checked at
/// run-time because ``SimulationRunner`` accepts already-persisted scenarios
/// as-is.
nonisolated public enum ScenarioConventions {
  /// Returns the canonical primary output field name expected on `output:`
  /// for the given phase type — the mapping tabled on ``ScenarioConventions``.
  ///
  /// `nil` does NOT mean "code phase": it means the phase declares no
  /// author-facing primary, which covers every code phase **and** `.narrate`.
  /// Callers branching on `nil` (ADR-021 § Amendment 2026-08-06's skip rule)
  /// depend on that wider reading.
  public static func primaryField(for phaseType: PhaseType) -> String? {
    switch phaseType {
    case .speakAll, .speakEach:
      return "statement"
    case .choose:
      return "action"
    case .vote:
      return "vote"
    case .reflect:
      return "note"
    case .whisper:
      return "statement"
    // `.narrate` is an LLM phase, but its output shape is **Engine-fixed**
    // (a single `{ commentary }` schema built by `NarrateHandler`), not
    // author-declared — so there is no canonical author `output:` field to
    // enforce here. Returning `nil` keeps `validateForCommit`'s
    // canonical-field check off narrate (it needs no `output:` block).
    case .scoreCalc, .assign, .eliminate, .summarize, .conditional, .eventInject,
      .relationshipUpdate, .narrate:
      return nil
    }
  }

  /// Returns the private-thought (secondary) output field name expected on
  /// `output:` for the given LLM phase, or `nil` for code phases.
  ///
  /// Vote returns `"reason"`; `reflect` returns `nil` (its canonical `note`
  /// output *is* the agent's private reasoning, so there is no separate
  /// secondary thought field — a reflect note is authored as a single-field
  /// `{ note }` schema); every other LLM phase returns `"inner_thought"`.
  /// Both fields are display-only private reasoning (never routed into the
  /// conversation log, so invisible to other agents) — `reason` is simply the
  /// vote-phase spelling of the same concept (vote schemas author
  /// `{ vote, reason }`, speak schemas `{ statement, inner_thought }`). This is
  /// the single source of truth that keeps the THINKING section's content
  /// source consistent across the committed-display path
  /// (``TurnOutput/secondaryText(for:)``) and the live streaming path
  /// (``PartialOutputExtractor`` driven by ``LLMCaller``).
  ///
  /// Phase-aware (not a blind `inner_thought` fallback) so a stray `reason` on
  /// a speak/choose output never leaks into THINKING, and a vote's `reason` is
  /// never dropped in favour of an `inner_thought` vote schemas don't author.
  ///
  /// **Do not widen this to a `inner_thought ?? reason` fallback.** That would
  /// re-leak a stray `reason` into a speak/choose THINKING section and re-open
  /// the divergence against the schema-driven streaming resolver
  /// (``OutputSchema/thoughtFieldName``). Consistency between the two resolvers
  /// is held by **authoring enforcement** — `ScenarioValidator.validateForCommit`
  /// rejects a non-canonical secondary key at commit time — NOT by runtime
  /// reconciliation here (#760).
  public static func thoughtField(for phaseType: PhaseType) -> String? {
    switch phaseType {
    case .vote:
      return "reason"
    case .speakAll, .speakEach, .choose, .whisper:
      return "inner_thought"
    // `.reflect`'s canonical `note` output is itself the private reasoning, so
    // it declares no secondary thought field (single-field `{ note }` schema).
    // `.narrate` is a single-field `{ commentary }` schema (Engine-fixed) with
    // no secondary thought field either.
    case .reflect, .scoreCalc, .assign, .eliminate, .summarize, .conditional, .eventInject,
      .relationshipUpdate, .narrate:
      return nil
    }
  }

  /// Decorates a raw primary value for display. Vote prefixes the `→ ` arrow
  /// affordance (`→ <voted>`); all other phases return the value unchanged.
  ///
  /// Single source of truth for the vote arrow so the live-streaming path
  /// (``AgentOutputRow`` over a bare ``PartialSnapshot/primary``) and the
  /// committed / export path (``TurnOutput/primaryText(for:)``) render
  /// identically. Without this, the arrow was only added at commit time and
  /// "popped in" after the streamed bare value (#609 device QA).
  public static func decoratePrimary(_ value: String, for phaseType: PhaseType) -> String {
    phaseType == .vote ? "→ \(value)" : value
  }

  /// Returns `true` if `name` is a valid scenario `output:` field name.
  ///
  /// Output field names (the `output:` block keys) are emitted verbatim as
  /// JSON-key literals (`"\"<name>\""`) into every LLM-phase GBNF grammar by
  /// ``GBNFGrammarBuilder``. A non-ASCII / multi-byte key reaches llama.cpp's
  /// sampler as a literal and crashes it at accept-time on-device — an
  /// uncatchable SIGABRT (the "empty grammar stack" class). This is the same
  /// mechanism that forced CJK choose-option *values* out of the grammar in
  /// #599; field names are the residual key surface (#607). The trigger is the
  /// model's BPE tokenizer, so it is per-model and there is no model-agnostic
  /// "safe non-ASCII" predicate — ASCII-only is the only durable boundary.
  ///
  /// Field names carry no user-visible value: they are machine-internal keys
  /// the model maps to via the localized prompt (``PromptBuilder``). Agent text
  /// *values* stay unconstrained and may be any language — only the keys are
  /// gated here.
  ///
  /// Rule: non-empty, first character an ASCII letter (`[A-Za-z]`), every
  /// subsequent character an ASCII letter, digit, or underscore
  /// (`[A-Za-z0-9_]`). Leading `_` / `-` / digit are rejected. Single source of
  /// truth for both the ``GBNFGrammarBuilder`` crash backstop and the
  /// ``ScenarioValidator`` load-gate.
  public static func isValidFieldName(_ name: String) -> Bool {
    guard let first = name.first, first.isASCII, first.isLetter else {
      return false
    }
    for char in name where !(char.isASCII && (char.isLetter || char.isNumber || char == "_")) {
      return false
    }
    return true
  }
}

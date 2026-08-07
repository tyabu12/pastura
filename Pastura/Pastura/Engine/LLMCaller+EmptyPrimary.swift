import Foundation

// Empty-field retry + canonical-primary skip, factored out of `LLMCaller` so
// the core file stays under SwiftLint's `file_length` budget (mirrors
// `LLMCaller+Logging` / `LLMCaller+StreamFailure`).
//
// `nonisolated` on the extension is required because `LLMCaller` is a
// `nonisolated` Engine type split across sibling files (a plain `extension`
// would inherit MainActor under the project's default-actor isolation and
// break the nonisolated callers in `call`).
nonisolated extension LLMCaller {

  /// Applies ADR-021 § Amendment 2026-08-06 to one parsed attempt: emits the
  /// retry diagnostics and reports whether `call` should retry, or throws to
  /// hand the turn to ``TurnFailureGate``.
  ///
  /// Shaped like `handleLanguageAdherence` — returns `true` to `continue` the
  /// retry loop — so both post-parse checks read the same way at the call site.
  ///
  /// Two clauses, deliberately separate:
  ///
  /// 1. **Retry trigger.** The all-fields scan is unchanged, so an empty
  ///    secondary (`inner_thought` / `reason`) still consumes the budget. It is
  ///    widened only by ``canonicalPrimaryIsMissing``, which also catches a
  ///    declared primary that is *absent*: ``hasEmptyFields`` inspects values,
  ///    not keys, so an absent key would otherwise return at attempt 0 and hand
  ///    the handler a primary-less turn to read as `nil` — leaving no final
  ///    attempt for clause 2 to fire on.
  /// 2. **Exhaustion.** Throw only when the canonical primary is the thing
  ///    missing. Scoped that way because omitting a turn that carries a good
  ///    `statement` alongside an empty `inner_thought` would discard content the
  ///    model *did* produce — D2 inverted rather than applied.
  ///
  /// - Returns: `true` when the caller should retry this attempt.
  /// - Throws: ``SimulationError/retriesExhausted`` on the final attempt when
  ///   the declared canonical primary is absent/empty.
  func shouldRetryEmptyFields(
    output: TurnOutput,
    phaseType: PhaseType,
    expectedKeys: Set<String>,
    attempt: Int,
    agentName: String
  ) throws -> Bool {
    let primaryMissing = canonicalPrimaryIsMissing(
      output, phaseType: phaseType, expectedKeys: expectedKeys)
    guard hasEmptyFields(output) || primaryMissing else { return false }

    if attempt < Self.maxRetries {
      logEmptyFields(fields: output.fields, attempt: attempt)
      emitRetryCause(agent: agentName, attempt: attempt + 1, cause: "empty_field")
      return true
    }
    if primaryMissing {
      throw SimulationError.retriesExhausted
    }
    return false
  }

  func hasEmptyFields(_ output: TurnOutput) -> Bool {
    output.fields.values.contains { $0 == "..." || $0.isEmpty }
  }

  /// True when the phase's canonical primary field is *declared* by the schema
  /// yet arrives absent, empty, or as the `"..."` filler.
  ///
  /// The `expectedKeys` precondition is a **compatibility guard, not a
  /// refinement**. ``ScenarioValidator/validateForCommit(_:)`` enforces the
  /// canonical field at commit time and nothing re-checks it at run time, so a
  /// scenario persisted before that gate — or imported under ADR-020
  /// backward-compat — can omit it from `output:` entirely. The grammar never
  /// generates an undeclared key, so without this guard the field would read
  /// absent on every attempt of every turn of that phase, tripping
  /// ``TurnFailureGate``'s consecutive-skip limit and making a scenario that ran
  /// yesterday unrunnable.
  ///
  /// The lookup is keyed on the **phase type**, never on the schema:
  /// ``OutputSchema`` carries no phase identity, and resolving through its
  /// `knownPrimaryKeys` would treat a stray `statement` declared on a `vote`
  /// phase as canonical. `.narrate` returns `nil` here (engine-fixed schema),
  /// which is what structurally exempts the one call site not wrapped in
  /// `turnGate.attempt`. Concretely: `NarrateHandler` catches around its
  /// `call`, so a throw there is swallowed and the round loses its narration
  /// with no `.turnSkipped` and no breaker increment — degradation the gate
  /// never sees, not a run abort. A future un-gated site with **no** catch
  /// would abort instead; see `.claude/rules/engine.md` § "Adding a new
  /// `PhaseType`".
  func canonicalPrimaryIsMissing(
    _ output: TurnOutput, phaseType: PhaseType, expectedKeys: Set<String>
  ) -> Bool {
    guard let key = ScenarioConventions.primaryField(for: phaseType),
      expectedKeys.contains(key)
    else { return false }
    guard let value = output.fields[key] else { return true }
    return value == "..." || value.isEmpty
  }
}

import Foundation

/// The linter-owned single source of truth for per-phase `{token}` placeholder
/// availability (ADR-024 D4).
///
/// Resolves #920's open model-shape question in favor of a **`PhaseType` key
/// plus one narrow qualifier** (`chooseRoundRobin`) rather than a full
/// per-phase descriptor type: the only known intra-phase supply split is
/// `choose` round-robin vs individual (round-robin additionally injects
/// `{opponent_name}` and the whisper channel). Every other phase's supplied set
/// is fully determined by its `PhaseType`.
///
/// Two orthogonal facets, derived by reading the handler code:
///
/// - ``supplied(for:chooseRoundRobin:)`` — the tokens a phase type **writes into
///   the expansion namespace** (injected for its own LLM prompt, or written to
///   `state.variables` for downstream phases). A token in this set is guaranteed
///   *present* when the phase expands — it may still resolve to the empty string
///   if its producer hasn't run (that's the producer relation below). A token
///   *absent* here leaks its literal braces to the LLM (rules R10/R12).
/// - ``producers(of:)`` — for a producer-gated token, the phase type(s) that must
///   have run **earlier in the phase list** for the token to resolve to a
///   non-empty value (rule R11). Tokens with no producer (`scoreboard`,
///   `conversation_log`, `candidates`, …) are always resolvable in a phase that
///   supplies them and return `nil` here.
///
/// The lint rules (R10–R12) and #920's phase-aware `PhaseEditorSheet` hint both
/// read this map — the ADR's absorption of #920(B) is exactly "retarget the
/// editor hint to read the linter-owned map". This type is pure data + lookups;
/// it applies no logic to a `Scenario` (the rules do that).
///
/// - Important: the *union* of ``supplied(for:chooseRoundRobin:)`` over all phase
///   types equals `PromptPlaceholders.engineSupplied` **plus**
///   ``tokensBeyondEngineSupplied`` — a handful of genuinely handler-injected
///   tokens that `engineSupplied` (a curated coverage-guard subset, #890) never
///   registered. The equality is asserted in tests so a new handler-supplied
///   placeholder must update this map.
nonisolated public enum PlaceholderAvailability {

  // MARK: - Supplied tokens per phase type

  /// Every engine-supplied `{token}` the given phase type writes into the
  /// expansion namespace — see the type doc for the "present but possibly empty"
  /// vs "absent → literal leak" distinction.
  ///
  /// - Parameters:
  ///   - phaseType: The phase whose supplied set is requested.
  ///   - chooseRoundRobin: Only meaningful for `.choose`. `true` selects the
  ///     round-robin branch (`ChooseHandler.callAgent`, which adds
  ///     `{opponent_name}` and injects the whisper channel); `false` selects the
  ///     individual branch (no `{opponent_name}`, and — matching the handler's
  ///     asymmetry — no `{my_whispers}`). Ignored for every other phase type.
  /// - Returns: The supplied token set (may be empty for pure code phases that
  ///   neither expand a template nor write a consumer-facing variable).
  public static func supplied(for phaseType: PhaseType, chooseRoundRobin: Bool) -> Set<String> {
    switch phaseType {
    case .speakAll, .speakEach, .reflect:
      // SpeakAll/SpeakEach/Reflect handlers all call inject{Assigned,Notes,Whispers,Relationships}.
      return baseInjected.union(perPersonaInjected).union(whisperSelfInjected)

    case .vote:
      // VoteHandler additionally builds {candidates} and writes {vote_results} to state.
      return baseInjected.union(perPersonaInjected).union(whisperSelfInjected)
        .union(["candidates", "vote_results"])

    case .choose:
      if chooseRoundRobin {
        // ChooseHandler.callAgent adds {opponent_name} and injects the whisper channel.
        return baseInjected.union(perPersonaInjected).union(whisperSelfInjected)
          .union(["opponent_name"])
      }
      // executeIndividual omits injectWhispers (a real handler asymmetry) → no
      // {my_whispers}, and never pairs so no {opponent_name}.
      return baseInjected.union(perPersonaInjected)

    case .whisper:
      // WhisperHandler adds the in-phase {whisper_partner}/{whisper_exchange} tokens.
      return baseInjected.union(perPersonaInjected).union(whisperSelfInjected)
        .union(["whisper_partner", "whisper_exchange"])

    case .summarize:
      // SummarizeHandler never calls the inject* helpers, so no per-persona
      // tokens. The {agent1}-family + score tokens exist only in its pairing
      // branch (state.pairings non-empty + template contains "{agent1}").
      return baseInjected.union(pairingInjected)

    case .assign:
      // AssignHandler writes assigned_<name> (surfaced as {assigned}/{assigned_word}),
      // {assigned_topic} (all mode) and {wolf_name} (random_one mode).
      return assignProduced

    case .eventInject:
      // EventInjectHandler writes the default event variable {current_event}
      // (a custom `as:` name is scenario-specific and resolved by the rule layer).
      return ["current_event"]

    case .relationshipUpdate:
      // RelationshipUpdateHandler writes relationships_<name>, surfaced downstream
      // as {relationships} via PromptBuilder.injectRelationships.
      return ["relationships"]

    case .scoreCalc, .eliminate, .conditional:
      // Pure control / scoring code phases: no template expansion, no
      // consumer-facing variable written.
      return []
    }
  }

  // MARK: - Producer relation

  /// The phase type(s) that must have run earlier for `token` to resolve to a
  /// non-empty value, or `nil` when `token` is not producer-gated (always
  /// resolvable in any phase that supplies it).
  ///
  /// - Note: pairing tokens (`{agent1}`-family) are producer-gated on a
  ///   *round-robin* `choose` (they read `state.pairings`), which this
  ///   phase-type-granular map cannot express precisely — that relation is
  ///   R9's lane, checked with the `chooseRoundRobin` qualifier in the rule
  ///   layer, so they are deliberately absent here. Likewise a custom
  ///   `event_inject` `as:` name is resolved from the scenario's phases, not
  ///   this static map (which covers only the default `current_event`).
  public static func producers(of token: String) -> Set<PhaseType>? {
    producerMap[token]
  }

  // MARK: - Token groups (handler-derived)

  /// Tokens every LLM handler writes unconditionally: `{scoreboard}` /
  /// `{conversation_log}` (built per call) and `{current_round}` (written to
  /// `state.variables` by `SimulationRunner` each round).
  static let baseInjected: Set<String> = [
    "scoreboard", "conversation_log", "current_round"
  ]

  /// Per-persona tokens injected by `inject{Assigned,Notes,Relationships}` in
  /// **every** LLM handler (including `choose` individual). Always written — so
  /// present even when the producer hasn't run — but absent from
  /// `summarize`/code phases, which never call the inject* helpers (rule R12).
  static let perPersonaInjected: Set<String> = [
    "assigned", "assigned_word", "my_notes", "relationships"
  ]

  /// The whisper-channel token injected by `injectWhispers` — every LLM handler
  /// **except** `choose` individual (`executeIndividual` omits the call).
  static let whisperSelfInjected: Set<String> = ["my_whispers"]

  /// Pairing tokens `SummarizeHandler` writes in its per-pairing branch.
  static let pairingInjected: Set<String> = [
    "agent1", "action1", "agent2", "action2", "score1", "score2"
  ]

  /// Tokens `AssignHandler` makes resolvable downstream.
  static let assignProduced: Set<String> = [
    "assigned", "assigned_word", "assigned_topic", "wolf_name"
  ]

  /// Handler-injected tokens genuinely supplied by the engine but **not**
  /// registered in `PromptPlaceholders.engineSupplied` (a curated coverage-guard
  /// subset scoped to placeholders bundled presets actually reference, #890).
  /// Named here so the union-equality maintenance test can state the delta
  /// explicitly instead of hiding it.
  static let tokensBeyondEngineSupplied: Set<String> = [
    "my_notes",  // reflect's channel — promote to engineSupplied when a bundled preset first references {my_notes}
    "whisper_partner", "whisper_exchange",
    "agent1", "action1", "agent2", "action2", "score1", "score2"
  ]

  /// Tokens a producer phase writes into `state.variables` and that ANY later
  /// LLM phase's prompt can read via generic `{token}` expansion — the
  /// cross-phase-readable complement of the per-persona `inject*` tokens (whose
  /// availability is phase-type-specific and already modeled by
  /// ``supplied(for:chooseRoundRobin:)``). Derived as the producer-gated tokens
  /// minus the per-persona / whisper injected forms so it stays in lockstep with
  /// ``producerMap``: `{assigned_topic, wolf_name, vote_results, current_event}`.
  ///
  /// The editor's phase-aware prompt hint (#920 B) unions this into every LLM
  /// phase's supplied set, so an author still discovers `{assigned_topic}` /
  /// `{current_event}` — usable when an upstream `assign` / `event_inject` ran,
  /// and permitted by the R10/R11 linter's global known-token set. Whether a
  /// producer actually runs earlier stays R11's lane, not the hint's. A custom
  /// `event_inject` `as:` name is scenario-specific and intentionally absent
  /// (the editor sheet has no scenario context; only the default is listed).
  static let crossPhaseStateReadable: Set<String> =
    Set(producerMap.keys)
    .subtracting(perPersonaInjected)
    .subtracting(whisperSelfInjected)

  /// Producer-gated token → producing phase type(s). Cross-checked against
  /// ``supplied(for:chooseRoundRobin:)`` in tests: every producer's output token
  /// is also in that producer's supplied set.
  static let producerMap: [String: Set<PhaseType>] = [
    "assigned": [.assign],
    "assigned_word": [.assign],
    "assigned_topic": [.assign],
    "wolf_name": [.assign],
    "my_notes": [.reflect],
    "my_whispers": [.whisper],
    "relationships": [.relationshipUpdate],
    "vote_results": [.vote],
    "current_event": [.eventInject]
  ]
}

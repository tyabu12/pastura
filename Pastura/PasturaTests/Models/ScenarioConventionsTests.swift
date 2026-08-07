import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct ScenarioConventionsTests {
  @Test func primaryFieldForSpeakAllReturnsStatement() {
    #expect(ScenarioConventions.primaryField(for: .speakAll) == "statement")
  }

  @Test func primaryFieldForSpeakEachReturnsStatement() {
    #expect(ScenarioConventions.primaryField(for: .speakEach) == "statement")
  }

  @Test func primaryFieldForChooseReturnsAction() {
    #expect(ScenarioConventions.primaryField(for: .choose) == "action")
  }

  @Test func primaryFieldForVoteReturnsVote() {
    #expect(ScenarioConventions.primaryField(for: .vote) == "vote")
  }

  @Test func primaryFieldForReflectReturnsNote() {
    #expect(ScenarioConventions.primaryField(for: .reflect) == "note")
  }

  /// Code phases emit no LLM output — `nil` is the contract for callers that
  /// need to distinguish "no primary field expected" from "primary field
  /// missing".
  @Test func primaryFieldForCodePhasesReturnsNil() {
    let codePhases: [PhaseType] = [
      .scoreCalc, .assign, .eliminate, .summarize, .conditional, .eventInject,
      .relationshipUpdate
    ]
    for phase in codePhases {
      #expect(
        ScenarioConventions.primaryField(for: phase) == nil,
        "expected nil for code phase \(phase.rawValue)")
    }
  }

  /// `narrate` is an **LLM** phase, so it sits outside the code-phase list
  /// above, yet it also has no primary field: its `{ commentary }` shape is
  /// built by `NarrateHandler` rather than author-declared.
  ///
  /// Pinned separately because ADR-029 § Amendment 2026-08-07 now leans on it.
  /// A highlight excerpt is hidden unless every line's phase declares a primary
  /// field, so giving narration one would silently make narrate excerptable —
  /// falsifying that amendment's "one widening is blocked outright" paragraph,
  /// the loader's "the six" comment, and `GalleryHighlightExcerptEntry`'s doc,
  /// with nothing else going red.
  @Test func primaryFieldForNarrateReturnsNilDespiteBeingAnLLMPhase() {
    #expect(PhaseType.narrate.requiresLLM)
    #expect(ScenarioConventions.primaryField(for: .narrate) == nil)
  }

  /// Defends against drift if a new `PhaseType` case lands with a non-canonical
  /// value (e.g. someone returns `"speech"` for a new speak-shape phase). Pins
  /// the partition: every case maps to one of `{statement, action, vote}` or
  /// `nil` (code phases). Compiler exhaustiveness already catches a *missing*
  /// case in `primaryField(for:)`; this test catches a *wrong* classification.
  @Test func everyPhaseTypeMapsToCanonicalSetOrNil() {
    let canonical: Set<String> = ["statement", "action", "vote", "note"]
    for phaseType in PhaseType.allCases {
      let field = ScenarioConventions.primaryField(for: phaseType)
      if let field {
        #expect(
          canonical.contains(field),
          "phase \(phaseType.rawValue) returned non-canonical primary field '\(field)'")
      }
    }
  }

  // MARK: - thoughtField (#609)

  /// Vote's private-thought field is `reason`; every other LLM phase uses
  /// `inner_thought`. This is the single source of truth consumed by both the
  /// committed-display path (`TurnOutput.secondaryText(for:)`) and the
  /// streaming path (`PartialOutputExtractor` via `LLMCaller`), keeping the
  /// THINKING section's source consistent across live + replay.
  @Test func thoughtFieldForVoteReturnsReason() {
    #expect(ScenarioConventions.thoughtField(for: .vote) == "reason")
  }

  @Test func thoughtFieldForSpeakAndChooseReturnsInnerThought() {
    #expect(ScenarioConventions.thoughtField(for: .speakAll) == "inner_thought")
    #expect(ScenarioConventions.thoughtField(for: .speakEach) == "inner_thought")
    #expect(ScenarioConventions.thoughtField(for: .choose) == "inner_thought")
  }

  /// Reflect has no secondary thought field: its canonical `note` output *is*
  /// the agent's private reasoning (single-field `{ note }` schema).
  @Test func thoughtFieldForReflectReturnsNil() {
    #expect(ScenarioConventions.thoughtField(for: .reflect) == nil)
  }

  /// Code phases emit no LLM output, so they have no private-thought field.
  @Test func thoughtFieldForCodePhasesReturnsNil() {
    let codePhases: [PhaseType] = [
      .scoreCalc, .assign, .eliminate, .summarize, .conditional, .eventInject
    ]
    for phase in codePhases {
      #expect(
        ScenarioConventions.thoughtField(for: phase) == nil,
        "expected nil for code phase \(phase.rawValue)")
    }
  }

  // MARK: - decoratePrimary (#609)

  /// Vote prefixes the `→ ` arrow; other phases pass the value through. The
  /// shared decorator keeps the live-streaming path (bare snapshot value) and
  /// the committed/export path rendering the same string — so the arrow no
  /// longer pops in only at commit time.
  @Test func decoratePrimaryPrefixesArrowForVote() {
    #expect(ScenarioConventions.decoratePrimary("ハルト", for: .vote) == "→ ハルト")
  }

  @Test func decoratePrimaryPassesThroughForNonVote() {
    #expect(ScenarioConventions.decoratePrimary("Hello", for: .speakAll) == "Hello")
    #expect(ScenarioConventions.decoratePrimary("cooperate", for: .choose) == "cooperate")
  }

  // MARK: - isValidFieldName (#607)

  /// ASCII snake_case identifiers — the shape every bundled preset uses
  /// (`statement`, `inner_thought`, `action`, `vote`, `reason`). Underscores in
  /// the body and trailing digits are allowed.
  @Test func isValidFieldNameAcceptsAsciiIdentifiers() {
    let valid = ["statement", "inner_thought", "action", "vote", "reason", "a1b2", "X"]
    for name in valid {
      #expect(
        ScenarioConventions.isValidFieldName(name), "'\(name)' should be valid")
    }
  }

  /// Non-ASCII keys (CJK / emoji) are rejected: they would emit as GBNF JSON-key
  /// literals and crash llama.cpp's sampler at accept-time on-device (#607, same
  /// mechanism as the #599 CJK choose-option removal). Leading `_` / `-` / digit
  /// and structural breakers (space, dot, dash, empty) stay rejected too.
  @Test func isValidFieldNameRejectsNonAsciiAndStructuralBreakers() {
    let invalid = [
      "内なる思考", "思考", "naïve", "café", "emoji😀key",  // non-ASCII
      "1badName", "_leading", "-leading", "with space",  // leading / structural
      "dot.name", "dash-only", "", "_", "-"
    ]
    for name in invalid {
      #expect(
        !ScenarioConventions.isValidFieldName(name), "'\(name)' should be rejected")
    }
  }
}

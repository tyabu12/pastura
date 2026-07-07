// Placeholder-resolution rules R10/R11/R12 (ADR-022 D3). Extension of the
// existing suite (not a new @Suite) per .claude/rules/testing.md splitting
// pattern — reuses `linter` / `makeScenario` / `makeEventScenario` from the
// base file / the Ordering split.
import Testing

@testable import Pastura

extension ScenarioSemanticLinterTests {

  // MARK: - R10 unresolvable-placeholder (warning)

  @Test func unknownPlaceholderTypoFiresR10() {
    let scenario = makeScenario(
      agents: 2, rounds: 1, phases: [Phase(type: .speakAll, prompt: "Scores: {scorebord}")])
    let findings = linter.lint(scenario)
    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == "unresolvable-placeholder")
    #expect(findings.first?.severity == .warning)
    #expect(findings.first?.phaseIndex == 0)
  }

  @Test func engineSuppliedBaseTokensPassR10() {
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [
        Phase(
          type: .speakAll,
          prompt: "Score {scoreboard}, log {conversation_log}, round {current_round}")
      ])
    #expect(linter.lint(scenario).isEmpty)
  }

  @Test func declaredExtraDataKeyPassesR10() {
    // An `extraData` key referenced in a prompt is a declared variable — known,
    // so it must not trip R10 (ADR-022 R10's resolvable set includes extraData).
    let scenario = makeEventScenario(
      phases: [Phase(type: .speakAll, prompt: "The events are {events}")],
      events: .array(["a", "b"]))
    #expect(linter.lint(scenario).isEmpty)
  }

  @Test func sameConditionalProducerBeforeConsumerPassesR11() {
    // Regression (gallery kasei_sanso_touban): an `event_inject` and its
    // consumer sit in the SAME conditional branch, producer first. Both anchor
    // to the conditional's top-level index, so R11's comparison must accept
    // same-index producers (`<=`, may-run leniency) or this false-positives.
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [
        Phase(type: .vote, prompt: "Vote"),
        Phase(
          type: .conditional, condition: "current_round >= 1",
          thenPhases: [Phase(type: .summarize, template: "done")],
          elsePhases: [
            Phase(type: .eventInject),
            Phase(type: .speakAll, prompt: "It got worse: {current_event}")
          ])
      ])
    #expect(linter.lint(scenario).isEmpty)
  }

  @Test func customEventVariableReferencedDownstreamPassesR10() {
    // A custom `event_inject` `as:` name is resolvable downstream — known (no
    // R10) and, placed before the consumer, ordered correctly (no R11).
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [
        Phase(type: .eventInject, eventVariable: "storm"),
        Phase(type: .speakAll, prompt: "A {storm} approaches")
      ])
    #expect(linter.lint(scenario).isEmpty)
  }

  // MARK: - JSON-example braces must NOT trip

  @Test func jsonExampleBracesDoNotFire() {
    // Identifier-only `{token}` shape never matches a JSON-example brace whose
    // first inner char is a quote / space / dot.
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [
        Phase(
          type: .speakAll,
          prompt: "Reply with {\"statement\": \"...\"} or { \"vote\": \"x\" }. Shape: {...}")
      ])
    #expect(linter.lint(scenario).isEmpty)
  }

  // MARK: - R11 placeholder-phase-availability (warning)

  @Test func producerTokenBeforeItsProducerFiresR11() {
    // `{wolf_name}` is a known producer-gated token; referenced before the
    // `assign` that produces it, it resolves empty → R11 (not R10).
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [
        Phase(type: .speakAll, prompt: "The wolf is {wolf_name}"),
        Phase(type: .assign, target: .randomOne)
      ])
    let findings = linter.lint(scenario)
    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == "placeholder-phase-availability")
    #expect(findings.first?.severity == .warning)
    #expect(findings.first?.phaseIndex == 0)
  }

  @Test func producerTokenAfterItsProducerPasses() {
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [
        Phase(type: .assign, target: .randomOne),
        Phase(type: .speakAll, prompt: "The wolf is {wolf_name}")
      ])
    #expect(linter.lint(scenario).isEmpty)
  }

  @Test func whisperOwnTokenIsSelfSuppliedNoR11() {
    // A whisper's own `{my_whispers}` / `{whisper_partner}` are in its supplied
    // set (self-supplied), so R11 must not gate them on an earlier producer.
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [Phase(type: .whisper, prompt: "Recall {my_whispers} with {whisper_partner}")])
    #expect(linter.lint(scenario).isEmpty)
  }

  // MARK: - candidates: vote-supplied, not a producer token

  @Test func candidatesInVotePasses() {
    let scenario = makeScenario(
      agents: 2, rounds: 1, phases: [Phase(type: .vote, prompt: "Choose among {candidates}")])
    #expect(linter.lint(scenario).isEmpty)
  }

  @Test func candidatesInSpeakAllFiresR10() {
    // `candidates` is vote-supplied only and has no producer entry, so in a
    // speak_all it is unknown → R10 (classification decision, ADR-022 note).
    let scenario = makeScenario(
      agents: 2, rounds: 1, phases: [Phase(type: .speakAll, prompt: "Pick from {candidates}")])
    let findings = linter.lint(scenario)
    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == "unresolvable-placeholder")
    #expect(findings.first?.phaseIndex == 0)
  }

  // MARK: - R12 per-persona-placeholder-in-summarize (warning)

  @Test func perPersonaTokenInSummarizeFiresR12ExactlyOnce() {
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [Phase(type: .summarize, template: "Your notes: {my_notes}")])
    let findings = linter.lint(scenario)
    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == "per-persona-placeholder-in-summarize")
    #expect(findings.first?.severity == .warning)
    #expect(findings.first?.phaseIndex == 0)
  }

  @Test func perPersonaTokenInLLMPhasePassesNotR12() {
    // `{my_notes}` in an LLM phase after a `reflect` is legitimately supplied —
    // not R12 (summarize-only), not R11 (reflect runs earlier).
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [
        Phase(type: .reflect, prompt: "Note your thoughts"),
        Phase(type: .speakAll, prompt: "Given {my_notes}, speak")
      ])
    #expect(linter.lint(scenario).isEmpty)
  }

  @Test func summarizeWithKnownNonPerPersonaTokenPasses() {
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [Phase(type: .summarize, template: "Scores: {scoreboard}")])
    #expect(linter.lint(scenario).isEmpty)
  }
}

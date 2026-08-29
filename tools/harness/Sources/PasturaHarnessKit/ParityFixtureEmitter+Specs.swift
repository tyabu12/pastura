import Foundation
import PasturaCore

// The fixture roster lives in its own file so `ParityFixtureEmitter.swift`
// stays under SwiftLint's file / type-body caps as fixtures accumulate; the
// mechanism (run, normalize, encode) is unchanged by adding a spec here.
extension ParityFixtureEmitter {
  /// The fixtures this repo freezes, in emission order.
  ///
  /// Every scenario here is RNG-free on both engines — neither injects RNG
  /// today, so a fixture can only be frozen where no handler draws. That rules
  /// out the presets running `event_inject` or `assign random_one` until the
  /// S3b RNG seam lands; `target_score_race` is the only admitted one that
  /// exercises `conditional`.
  ///
  /// "Exercises `conditional`" means the **branch**, not merely the node: an
  /// earlier draft of the responder made every vote a self-vote, so every tally
  /// was empty, every score stayed 0, and `max_score >= 3` was false in all four
  /// evaluations — the phase ran and decided nothing. A fixture can look like a
  /// full run while its whole scoring half is frozen, so
  /// `everyFixtureExercisesVotingNotJustItsShape` asserts the non-degenerate
  /// outcome rather than leaving it to the responder's arithmetic.
  package static let specs: [FixtureSpec] = [
    FixtureSpec(
      name: "targetScoreRaceNominal",
      scenarioPath: "Pastura/Pastura/Resources/Presets/target_score_race.yaml",
      purpose: """
        Happy path. Every answer is well-formed and non-empty, so a green \
        comparison here means the two engines agree with an empty divergence \
        ledger — which is Stage 4's actual goal, not merely that the harness runs.
        """
    ),
    FixtureSpec(
      name: "targetScoreRaceDivergent",
      scenarioPath: "Pastura/Pastura/Resources/Presets/target_score_race.yaml",
      purpose: """
        Negative control. A ledger whose entries never fire ships unexercised, \
        so this fixture drives documented divergences on purpose and the parity \
        suite fails if one stops firing.

        **It drives a VALUE divergence only, by design rather than by loss.** \
        It used to drive one of each entry kind: calls 0-2 answer the first \
        agent's schema-declaring `speak_all` turn with present-but-empty \
        canonical fields across the whole retry window, which Swift returned as \
        an `agentOutput` while Kotlin's parser guard exhausted retries into a \
        `turnSkipped`. ADR-021 § Amendment 2026-08-06 resolved that — both \
        engines now skip — retiring `SCHEMA_GUARD_POSITION`. The empty-field \
        overrides are kept because they still exercise the retry window \
        identically on both sides.

        The structural arm was re-armed in `parityStructuralControl` instead, \
        because the surviving scriptable divergence costs Kotlin two extra \
        backend calls and `responses` is positional — the surplus has to land \
        on the run's LAST call, which here is a `vote` whose loss cascades \
        through the tally. So do not read a clean structural comparison here as \
        evidence the structural path is exercised; \
        `someFixtureDrivesBothEntryKinds` is what keeps that honest.

        The float-valued key below is this fixture's arm. Swift normalizes \
        `1.0` to "1" because `NSNumber.stringValue` drops the `.0`; Kotlin \
        preserves the literal as "1.0" — the VALUE divergence \
        `JSONResponseParser.kt` routes to Stage 4 to rule on.
        """,
      overrides: [
        0: #"{"statement": "", "inner_thought": ""}"#,
        1: #"{"statement": "", "inner_thought": ""}"#,
        2: #"{"statement": "", "inner_thought": ""}"#,
        3: #"{"statement": "s", "inner_thought": "t", "confidence": 1.0}"#
      ]
    ),
    FixtureSpec(
      name: "prisonersDilemmaNominal",
      scenarioPath: "Pastura/Pastura/Resources/Presets/prisoners_dilemma.yaml",
      purpose: """
        Happy path, and the first witness of three surfaces no other fixture \
        reaches: `choose` with `pairing: round_robin`, `whisper`, and \
        `score_calc` with `logic: pairwise_payoff`. The sibling nominal fixture \
        covers `speak_all` / `vote` / `conditional`, so a green comparison here \
        with an empty ledger widens Stage 4's agreement to the pairing and \
        payoff half of the Engine rather than deepening the half already met.

        **Why the responder's odometer schedule matters specifically here.** \
        5 agents round-robin to 5 pairings per round over 2 rounds, and \
        `ChooseHandler.executeRoundRobin` issues a pairing's two members as \
        consecutive backend calls — so a `k % n` answer schedule would give \
        the two members a fixed offset every time and only the two \
        off-diagonal payoff rows ([協力, 裏切り] and [裏切り, 協力]) would ever \
        fire. The \
        pair-indexed odometer walks all four `when:` rows instead, which is \
        what makes this fixture a real `pairwise_payoff` measurement rather \
        than a two-row one; `expectEveryPayoffRowFires` holds that Swift-side.
        """
    ),
    FixtureSpec(
      name: "boketeNominal",
      scenarioPath: "Pastura/Pastura/Resources/Presets/bokete.yaml",
      purpose: """
        Happy path, and the first witness of `assign` with `target: all` — the \
        round-shared assignment that reaches the transcript as a \
        `shared_assignment` event rather than the per-agent `assignment` word \
        wolf emits. It is RNG-free for the same reason the other nominal \
        fixtures are: the topic is picked by round index, not by draw, so two \
        rounds walk the two `topics:` entries deterministically.

        **It is also the first fixture whose scenario carries a non-empty \
        `extraData`.** `topics:` crosses the Swift-JSON -> Kotlin boundary \
        through two independently hand-written codecs — Swift's \
        `AnyCodableValue.encode(to:)` single-value container and Kotlin's \
        `JsonElement`-inspecting `AnyCodableValueSerializer` — which every \
        earlier fixture left unexercised by crossing an empty map. \
        `someGoldenScenarioCarriesAnArrayValuedExtraDataEntry` gates that \
        crossing separately, before the transcripts are compared at all.

        The `speak_all` / `vote` / `vote_tally` / `summarize` spine it runs is \
        already witnessed by `targetScoreRaceNominal`, so what this fixture \
        adds is the assignment head and the payload crossing, not a second \
        copy of the voting half.
        """
    ),
    FixtureSpec(
      name: "iiwakeBattleNominal",
      scenarioPath: "Pastura/Pastura/Resources/DemoPresets/iiwake_battle_v1.yaml",
      purpose: """
        Happy path, and the first witness of `speak_each` — sequential turns \
        where each agent sees the conversation so far, against the \
        simultaneous `speak_all` every other fixture runs. Paired with \
        `boketeNominal`, which shares the same \
        `assign(target: all)` / `vote` / `vote_tally` / `summarize` spine and \
        differs only in that one phase, so a divergence appearing here and not \
        there localizes to the speech handler rather than to the scenario.

        **Why a `DemoPresets/` scenario is admitted.** The parity fixtures \
        otherwise draw from `Resources/Presets/`, and reaching outside that \
        directory is a deliberate exception rather than an oversight: this is \
        shipped YAML (`BundledPresetResolver` resolves it, and \
        `check_demo_replay_drift.py` hashes its bytes), and it is the only \
        RNG-free bundled preset that runs `speak_each` at all. The alternative \
        was a hand-authored fixture under `tools/harness/Fixtures/`, which \
        would witness `speak_each` against a scenario no user ever runs.
        """
    ),
    FixtureSpec(
      name: "parityStructuralControl",
      scenarioPath: "tools/harness/Fixtures/parity_structural.yaml",
      purpose: """
        Structural negative control. The sibling divergent fixture drives a \
        VALUE divergence only; this one exists so the ledger's kind-coverage \
        guard has a `Structural` entry to hold, and so a divergence class and \
        its entries cannot be deleted together unnoticed — the way ADR-021 \
        § Amendment 2026-08-06 retired `SCHEMA_GUARD_POSITION` and silently \
        cost the control its only structural arm.

        Call 1 drives it. Swift's schema-guarded multi-object salvage (#907) \
        accepts the first object when every expected key is present and \
        non-empty, returning an `agentOutput` after ONE backend call. Kotlin's \
        `extractFirstJsonObject` returns object-like residue unchanged, so the \
        parse fails and the turn exhausts its retry budget into a `turnSkipped` \
        after THREE. Paired parser tests fed byte-identical input pin both \
        behaviours, so neither can drift silently.

        **Why its own scenario rather than an override on the sibling.** \
        `Fixture.responses` is positional, so Kotlin's two surplus calls \
        consume whatever answers follow; placed mid-run they shift every later \
        turn and the diff becomes noise about alignment rather than about the \
        engines. Here the divergent turn is the run's LAST, so the surplus \
        falls into the parity suite's padding. The cost is pinned instead of \
        hidden: the two engines issue different call counts, and that is \
        asserted rather than excused.

        Call 0 carries the float-valued key as well, so this fixture drives one \
        divergence of EACH entry kind by itself — kind coverage then holds \
        per-fixture rather than only across the set, for one extra override.
        """,
      overrides: [
        0: #"{"statement": "s", "inner_thought": "t", "confidence": 1.0}"#,
        1: #"{"statement": "hello", "inner_thought": "thinking"}{"stray": 1}"#
      ]
    )
  ]
}

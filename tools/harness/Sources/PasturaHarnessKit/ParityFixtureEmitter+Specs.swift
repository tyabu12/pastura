import Foundation
import PasturaCore

// The fixture roster lives in its own file so `ParityFixtureEmitter.swift`
// stays under SwiftLint's file / type-body caps as fixtures accumulate; the
// mechanism (run, normalize, encode) is unchanged by adding a spec here.
extension ParityFixtureEmitter {
  /// The one non-JSON answer a spec may use to drive a parse-failure retry.
  ///
  /// Named once so `everyOverrideAnswersTheSchemaItLandsOn` can exempt exactly
  /// this literal: a future spec typing a *different* non-JSON probe is forced
  /// through that test instead of being silently exempt.
  package static let unparseableProbe = "garbage"

  /// The fixtures this repo freezes, in emission order.
  ///
  /// A spec whose scenario draws from the `RandomSource` (`assign random_one`,
  /// `event_inject`) sets `seed:`, and one that draws nothing must not —
  /// `seededSpecsAreExactlyTheDrawingOnes` holds both directions, derived from
  /// the loaded scenario rather than from a name list. The seven unseeded specs
  /// are RNG-free by construction (S3a); `wordWolfNominal` and
  /// `lastFableNominal` are the seeded ones (S3b-2, #1618), and between them
  /// they witness every handler the unseeded roster could not reach.
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
        preserves the literal as "1.0" — the VALUE divergence ruled permanent \
        2026-08-29 (ADR-023 §15); it stays pinned here rather than fixed on \
        either side.
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
    ),
    FixtureSpec(
      name: "wordWolfNominal",
      scenarioPath: "Pastura/Pastura/Resources/Presets/word_wolf.yaml",
      purpose: """
        Happy path, and the first **seeded** fixture (ADR-023 S3b-2): the first \
        witness of three of the five handlers no unseeded fixture could reach — \
        `event_inject` (with a `probability:`), `narrate`, `eliminate` — plus \
        two variants of already-witnessed handlers, `assign` \
        with `target: random_one` and `score_calc` with `logic: wordwolf_judge`, \
        in one 21-call run. The other two, `reflect` and \
        `relationship_update`, are `lastFableNominal`'s: #1643 promoted the \
        scenario-refine v2 `word_wolf` preset, which drops the `reflect` \
        phase (5 calls, one per agent), so this fixture no longer runs it.

        **The seed is chosen for the draw sequence, and the sequence is the \
        contract.** `assignRandomOne` draws twice — `index(below: 1)` for the \
        topic (degenerate: `words:` has one entry, so the draw is consumed and \
        cannot be observed) and `index(below: 5)` for the wolf — then \
        `event_inject` rolls `unit() < 0.5` and, on a hit, `index(below: 3)` \
        for the announcement. Seed 6 puts the minority word on アオイ and makes \
        the roll a hit (0.056), so both the `current_event != ""` branch and \
        the second `speak_each`'s `{current_event}` are exercised; seeds 1-4 \
        all miss, which is what the first draft froze. A Kotlin replay that \
        consumes the stream in any other order lands a different wolf or a \
        miss, and the transcript names which.

        **Why two overrides.** The responder's vote rotation gives every agent \
        exactly one vote, so the tally is a five-way tie and `eliminate`, \
        `vote_winner` and the judge are all decided by `RankingOrder`'s name \
        tie-break rather than by the votes — the run would look like a full \
        game while measuring nothing but string ordering. Calls 17 (サクラ) and \
        20 (レン) vote アオイ instead, so the wolf takes 3 of 5 and the \
        `vote_winner == wolf_name` branch is taken on the votes' own account. \
        `everyOverrideAnswersTheSchemaItLandsOn` pins both indices to `vote` \
        calls.
        """,
      overrides: [
        17: #"{"vote": "アオイ", "reason": "reason 17"}"#,
        20: #"{"vote": "アオイ", "reason": "reason 20"}"#
      ],
      seed: 6
    ),
    FixtureSpec(
      name: "lastFableNominal",
      scenarioPath: "Pastura/Pastura/Resources/Presets/last_fable.yaml",
      purpose: """
        Happy path, seeded, and the first witness of `relationship_update` and \
        of `event_inject` with `no_repeat: true` — three rounds drawing from a \
        six-entry pool without replacement — plus a roster that shrinks by one \
        agent a round, which is what makes `eliminate` here a different \
        measurement from `wordWolfNominal`'s single round: every later phase \
        must skip the eliminated agent on both engines, and a vote cast *for* \
        one must be dropped from the tally while `relationship_update` still \
        reads it.

        Since #1643 dropped `reflect` from the `word_wolf` preset it is also \
        the roster's ONLY witness of that handler, so \
        `everyFixtureExercisesTheHandlersItDraws`' `reflect` arm now rests on \
        this fixture alone.

        **Draw sequence.** One `index(below: remaining.count)` per round, with \
        `remaining` shrinking 6 → 5 → 4; seed 1 yields 『オオカミ少年』, \
        『アリとキリギリス』, 『ウサギとカメ』.

        **Why seven overrides, all on votes.** `RecordingResponder` is handed \
        the full roster and cannot see the survivor set — it reads the schema \
        only — so from round 2 its rotation lands every surviving voter on \
        itself (hand-traced in review, then reproduced: round 2's tally was \
        `{}` and nobody was eliminated). Rounds 2 and 3 are therefore scripted \
        by hand. Round 1 is left to the rotation on purpose: its five-way tie \
        is the one place in the roster where `RankingOrder`'s name-descending \
        tie-break decides an elimination, so the Japanese-name ordering the two \
        engines implement independently (Swift on Unicode scalars, Kotlin on \
        UTF-16 code units — identical for these BMP names) is pinned by a \
        fixture rather than assumed. Round 2 (calls 23-26, survivors オオカミ \
        アリ カラス ウサギ) votes アリ, カラス, アリ, キツネ — a decisive アリ, \
        with ウサギ's vote for the eliminated キツネ as the dropped-vote witness \
        above. Round 3 (calls 33-35, survivors オオカミ カラス ウサギ) votes \
        カラス, ウサギ, カラス.
        """,
      overrides: [
        23: #"{"vote": "アリ", "reason": "reason 23"}"#,
        24: #"{"vote": "カラス", "reason": "reason 24"}"#,
        25: #"{"vote": "アリ", "reason": "reason 25"}"#,
        26: #"{"vote": "キツネ", "reason": "reason 26"}"#,
        33: #"{"vote": "カラス", "reason": "reason 33"}"#,
        34: #"{"vote": "ウサギ", "reason": "reason 34"}"#,
        35: #"{"vote": "カラス", "reason": "reason 35"}"#
      ],
      seed: 1
    ),
    FixtureSpec(
      name: "parityCancelConditional",
      scenarioPath: "tools/harness/Fixtures/parity_cancel.yaml",
      purpose: """
        Cancellation control (ADR-023 S4, #1622). The only fixture whose run \
        does NOT reach `simulation_completed`: the harness cancels it the \
        moment `phase_completed [1, 0]` — the conditional branch's first \
        sub-phase — is emitted, and what it freezes is the event tail both \
        engines produce from there.

        **What it witnesses.** Swift used to exit `ConditionalHandler`'s \
        sub-phase loop by RETURNING on cancellation, so the runner read the \
        branch as finished and emitted `phase_completed [1]` for work that had \
        been cut short — and on the pause path a second `error cancelled` on \
        top. #1622 made both paths throw, so the tail is now exactly what \
        Kotlin has always produced: `phase_completed [1, 0]` then \
        `error cancelled` as the LAST line, with no `phase_completed` for the \
        outer `[1]` and no `simulation_completed` at all. The branch's second \
        sub-phase — a template `summarize` at `[1, 1]` — never starts, which \
        is visible as an absent `phase_started` rather than only as a call \
        count.

        **Why its own scenario.** No bundled preset has a conditional branch \
        with two sub-phases: `target_score_race` and `word_wolf` each branch \
        into a single `summarize`, so the cancel would have had nowhere to \
        land between sub-phases and the fixture would have measured the \
        branch's exit rather than its interruption.

        **Why the trigger is an event position and not a call index** is \
        `FixtureSpec.cancelAfterPhaseCompleted`'s own doc: Kotlin observes \
        cancellation inside a backend call and Swift's responder does not, so \
        a call-indexed cut lands at different logical points on the two \
        engines and the diff would be about the harness.
        """,
      cancelAfterPhaseCompleted: [1, 0]
    ),
    FixtureSpec(
      name: "paritySuspendPreservesRetryBudget",
      scenarioPath: "tools/harness/Fixtures/parity_suspend.yaml",
      purpose: """
        Suspend control (ADR-023 §5.2 invariant 1, S5 #1625). A positive \
        control expected green with an empty ledger: suspend re-issues are \
        invisible in BOTH transcripts (no `SimulationEvent` marks them), so \
        `callCount` and the absence of a `turn_skipped` line are the only \
        observables that could catch the budget being charged.

        **Call order.** Index 0 is Ada's phase-0 turn. Index 1 is Bo's \
        phase-0 turn, attempt 1: suspended once, then answered "garbage" — \
        non-JSON, so both parsers fail identically and the turn retries. \
        Index 2 is attempt 2, suspended once, "garbage" again. Index 3 is \
        attempt 3, suspended once, then a derived valid answer accepted on \
        the LAST budgeted try (`LLMCaller.maxRetries == 2`, three attempts \
        total). Indices 4-5 are phase 1's two turns. If either engine had \
        charged a suspend to the retry budget, Bo's turn would exhaust it \
        one attempt early and `turn_skipped` would appear in place of the \
        accepted answer; `callCount` (9 = 6 answers + 3 suspends) would also \
        shift. Neither the yaml nor the spec authors that outcome, so it can \
        only be the seam's own behaviour.

        **Why not on a vote or choice call.** `RecordingResponder`'s \
        `voteCallCount` / `choiceCallCount` are phase-local, so a retry \
        window on a vote call shifts the rotation for every later vote in \
        the phase, and one on a choice call splits a pairing across two \
        schedule slots — the responder's choice-counter comment allows one \
        only on the run's last call. Two plain `speak_all` phases have \
        neither counter, so the schedule exercises only the retry seam.

        **What is deliberately untouched.** The Kotlin replay's structural \
        padding (`MAX_RETRIES + 1 == 3`, of which `parityStructuralControl` \
        consumes two) is a different mechanism from this fixture's suspend \
        cycles — a suspend re-issue is not a retry attempt, and this fixture \
        consumes none of that padding. Nor is the multi-object salvage \
        divergence in play: `"garbage"` fails both parsers the same way, so \
        there is nothing for the schema guard to salvage. And the Swift run's \
        `SuspendController` is idle — never `requestSuspend()`-ed — so \
        `awaitResume()` returns synchronously: this golden measures invariant \
        1 only; invariants 2 and 3 (one deferred per cycle, lost-wakeup \
        safety) are untested here and need a real suspend source.
        """,
      overrides: [1: unparseableProbe, 2: unparseableProbe],
      suspendBeforeResponse: [1: 1, 2: 1, 3: 1]
    )
  ]
}

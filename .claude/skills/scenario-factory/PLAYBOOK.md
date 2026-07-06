# Scenario-Design Playbook

Distilled, numbered design rules for authoring factory scenarios and refine
v2 candidates. Read by `/scenario-factory` Step 1 (generation gate) and
`/scenario-refine` Step 4 (v2 authoring) every cycle.

Discipline (this header is the contract):

- **Soft cap ~150 lines.** This file is read every night — it exists to
  SHRINK generation context, so entries stay concept-level (invariant + why +
  evidence pointer, per `.claude/rules/context-budget.md`), never incident
  prose. If an addition would blow the cap, compress or merge first.
- **Status per rule**: `[validated]` (reproduced or fix-confirmed on the
  harness), `[hypothesis]` (proposed / one weak datapoint), `[refuted]`
  (tried, did not work — prune to a one-line tombstone so it isn't retried).
- **Evidence dates** are provenance pointers into the operator-local factory
  journal (`data/factory/digest.md`, gitignored) — not required reading.
- **Additions** come from `data/factory/lessons-inbox.md` via a human
  `/orchestrate` PR (SKILL.md § Lessons promotion) — the nightly cycle never
  edits this file.

## Language & breakdown (Gemma 4 E2B)

1. **[validated]** Low-content speech (agreeable filler, pressured accusation)
   drifts into Korean; content-rich personas stay in Japanese. Give EVERY
   persona a concrete content hook and add an explicit `必ず日本語で` guard to
   drift-prone prompts (short relays, conformist casts). (07-03/07-05 failures;
   07-06 clean with both applied)
2. **[validated]** Cap statements at ≤2 sentences via the prompt — long
   grammar-constrained generations raise #253 sampler-crash exposure.
   (07-01 uncapped failed both attempts; 07-03/07-06 capped ran clean)
3. **[validated]** `choose` output = `action` + `inner_thought` ONLY (#760);
   keep option strings short and unambiguous (free-text wobble recurs), push
   reasoning into a preceding speak phase — structured choose decode is the
   suspected #253 trigger; fewer rounds shrink exposure. (06-21/22 repro + v2)
4. **[validated]** Stray trailing `」}` shapes appear ~1/30 outputs and
   self-recover via parse-retry — judging noise, not a design signal.

## Mechanics

5. **[validated]** Never gate a `conditional` on `vote_winner` with
   self-advocating personas: everyone self-votes, `exclude_self` empties the
   tally, the branch takes `else` forever and `{vote_winner}` leaks. Frame
   votes as endorsing ANOTHER's plan, or gate on something else. (07-04; 06-26)
6. **[validated]** A per-round branch must not test a CUMULATIVE score —
   `max_score >= N` goes true early and never flips. Use a `rounds: 1` tally,
   tie, or `active_count` condition. (06-28 failure → 07-01 confirmed recipe)
7. **[validated]** In `summarize` templates: `{scoreboard}` always resolves
   (safe); `{vote_winner}` / `{vote_results}` inside a conditional branch leak
   unrendered. (06-26 → confirmed fixed 06-28/07-01)
8. **[validated]** `event_inject` draws RANDOMLY each round — a scripted
   escalation arc or must-cover stimulus set needs round-indexed
   `assign source:<list>` instead. (06-28/06-30 failures; assign ordered on
   07-03/07-05/07-06)
9. **[validated]** `eliminate` uses the per-round vote tally (not cumulative
   `vote_tally`) and breaks ties deterministically — knockouts are safe to pair
   with cumulative scoring. (06-29, reconfirmed nightly)
10. **[validated]** `choose` does NOT write to the conversation log — sequence
    a speak deliberation BEFORE choose so reasoning (and any anchor/stimulus an
    experiment needs) is visible downstream. (06-25 Engine-verified;
    06-27/06-29 applied)
11. **[validated]** `scoring_free` has no convergence mechanism: deliberations
    restate positions, comedy loses differentiating pressure. Use it only when
    the phenomenon itself is the payoff; do not expect an arc. (06-26/06-27/07-04)
12. **[validated]** To hold a genuine multi-round split, force a HARD BINARY
    choice and give personas non-mappable top values — a safe middle option
    absorbs the pragmatists and collapses to consensus. (06-27 collapse;
    06-28/07-01/07-06 held splits)

## Persona design

13. **[validated]** Differentiate comedy personas by FORM (deadpan / operatic /
    groveling / …), not backstory — and prefer domains that are naturally
    form-diverse (apology styles, defeat speeches). Backstory-only casts
    converge to one register. (06-28 yusha failure → 06-29/07-01/07-03/07-06)
14. **[hypothesis]** A gimmick the model can't reliably produce dissolves into
    the shared register (and gets gang-eliminated first) — swap non-firing
    forms for ones E2B demonstrably lands; reinforce signature gags in the
    persona text. (07-01/06-30 failures; fix untested)
15. **[hypothesis]** Relay "build on the previous turn" instructions pull
    personas toward the prior speaker's register — protect contrast personas
    with "re-translate the previous content INTO your own style" phrasing.
    (06-30 failure; anti-echo variant partially worked 07-01)
16. **[validated]** Expect minor register breaks — 3rd-person self-reference,
    value flip-flops under pressure. Mitigate with single-axis, unambiguous
    value assignments per persona. (recurring, many nights)

## Interaction

17. **[validated]** `speak_each` yields name-referenced cross-talk;
    `speak_all` yields parallel monologues (cross-reference only in votes).
    Choose by whether interaction is the payoff. (06-25 A/B; consistent since)
18. **[validated]** Vote reasons parrot other speakers verbatim unless the
    prompt says "write your OWN reason, not a copy". (bug 06-24→07-03; nudge
    confirmed 07-06 — watch durability)
19. **[validated]** Acknowledgment ≠ persuasion: personas engage with others'
    arguments but almost never change their choice because of them. Don't
    stake a payoff on mid-run mind-changing. (07-03/07-06)

## Experiment design

20. **[hypothesis]** For a BEHAVIORAL bias split, the objective facts must make
    the rational action unambiguous so the immune control DEFECTS while the
    biased captives persist — otherwise everyone rationalizes the same action.
    (07-03 sunk-cost: introspection textbook, behavior uniform; fix untested)
21. **[validated]** Introspective payoff ≠ behavioral payoff: a bias can be
    textbook in `inner_thought` while choices stay uniform. Measure the channel
    the claim depends on. (07-03; 06-30)
22. **[validated]** Cumulative telephone-game decay fails with the full
    conversation log visible — speakers re-anchor to the base fact. Scope such
    designs as a PARALLEL bias-panel (works cleanly)… (07-06)
23. **[hypothesis]** …or retry true transmission decay with `log_window: 1`
    (#907) + `whisper`/`assign` seeding the fact privately — the Engine lever
    that did not exist when rule 22 was learned. Untested.
24. **[validated]** "Individuals show the bias, the deliberating group corrects
    it" is a legitimate, deeper observable — don't score group-level correction
    as a failed individual-bias demo. (07-05 bousai)
25. **[validated]** Force a personal REACTION to injected stimuli — otherwise
    speak phases verbatim-echo the stimulus text. (06-30)

## Comedy / format

26. **[validated]** Form-differentiated knockouts go one-note by R3–R4. Main
    lever: rotate a per-round お題 via `assign source:topics` (the "seriffu
    recipe"); keep such formats ≤4 rounds. (06-29 recipe; 3 later transfers)
27. **[validated]** Avoid constrained-wordplay formats (nazokake, homophone
    puns) — E2B produces the skeleton without the wordplay payload. (06-25)
28. **[validated]** Keep one comedy scenario per batch so the night retains a
    `(d) humor` datapoint (null categories don't score it). (operating
    convention since 06-27)

## Saturated premise families (dedup: do not regenerate as-is)

Id-level history lives in `digest-index.jsonl`; these FAMILIES are already
characterized — new instances need a new mechanic angle (e.g.
whisper/reflect/log_window), not a new topic skin:

- Form-differentiated knockout comedy (seriffu / yusha / yokai / shazai /
  haiboku) — format and its one-note limit fully mapped.
- Declare-then-secret-choose prisoners_dilemma variants (cartel / warikan /
  preset); free-rider public/private-gap dilemmas (kyoyu, kasei).
- Hard-binary ethics splits (saigo / kokuhatsu / manbiki / enjou / ai_teishi)
  — mechanic settled; only a genuinely fresh dilemma domain adds signal.
- Cognitive-bias panels with a numerate control (anchoring / framing /
  kakusho / sunk_cost / bousai) — open problem is rule 20, not new topics.
- Scoring-free social-psych observations (zenin / bystander / risky_shift /
  sokuho / kuuki) — same "inner_thought reveals mechanism, no arc" shape.
- Improv sequential_build relays (jidaigeki / uchujin / chinjiken);
  anthropomorphic-grievance venting (kaden_rousai, moto_akuyaku).
- Rumor distortion (dengon) — parallel panel works; chain decay = rules 22/23.

No validated rules exist yet for `whisper` / `reflect` / `log_window`-based
designs — first field results should land here via the lessons-inbox.

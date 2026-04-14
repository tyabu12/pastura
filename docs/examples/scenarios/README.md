# Example Scenarios

This directory holds example Pastura scenario YAML definitions that
are not bundled as presets but serve as reference material for scenario
design. They illustrate how various real-world experiments, thought
experiments, and games can be expressed with the declarative scenario engine.

## How to Use

Copy the YAML into the app via **Home → + → Import YAML**, or paste it into
the Visual Editor in YAML mode. You can also adapt the YAML as a starting
point for your own experiments.

## Adding New Examples

When adding a new example scenario here:

1. Prefer **ethically neutral** experiments (avoid Milgram, Stanford Prison
   Experiment, etc. — use adaptations or alternatives).
2. Keep inference count under 50 where possible for tester accessibility.
3. Use only the 3 built-in `score_calc` logics (`prisoners_dilemma`,
   `vote_tally`, `wordwolf_judge`) — custom logic is Phase 2 scope.
4. Include a brief header comment in the YAML describing what the scenario
   demonstrates and what's interesting to observe.

## Catalog

| File | What it demonstrates | Inference count |
|------|---------------------|-----------------|
| [`asch_conformity.yaml`](asch_conformity.yaml) | Social conformity — will the subject agent yield to group pressure when 4 confederates give the wrong answer? Each confederate has a distinct persuasion style (logical, intuitive, agreeable, confrontational). | ~15 |

## Observation Tips

- **Run the same scenario multiple times** — LLM output is non-deterministic,
  so individual runs don't generalize. Look for patterns across runs.
- **Vary the subject's persona description** — add traits like "confident"
  or "conforming" to see how persona shifts the outcome.
- **Check inner thoughts** — tap to reveal what the agent was "really"
  thinking. Often more revealing than the public statement.

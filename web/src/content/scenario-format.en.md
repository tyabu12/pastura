# Pastura scenario format reference

This page is the complete reference for the YAML format Pastura scenarios use.
It is written for both people and language models. If you are asking an LLM to
draft a scenario, you can point it at the raw Markdown version of this page at
`https://pastura.app/docs/scenario/format.md`.

A scenario is a single YAML file. Pastura runs it by having a local LLM play
each agent, round by round, following the phases you declare. Nothing in a
scenario is sent to a server.

## Top-level structure

```yaml
id: unique_snake_case_id      # required. Stable identifier, snake_case
language: en                  # required. Authoring language: `ja` or `en`
name: My Scenario             # required. Display title
description: One-line summary  # required
agents: 5                     # required. Number of agents, 2 to 10
rounds: 3                     # required. Number of rounds, 1 to 30
context: |                    # required. Shared briefing every agent sees
  You are contestants in a game...
personas:                     # required. One entry per agent (length == agents)
  - name: Alex
    description: A calm strategist who plans several moves ahead.
    secret: You already sold the family house.   # optional. Hidden from the others
  - name: Mia
    description: An optimist who trusts people by default.
phases:                       # required. The ordered list of what happens
  - type: speak_all
    prompt: What do you say to the group?
    output:
      statement: string
      inner_thought: string
```

Write every human-facing string (`name`, `description`, `context`, each
`prompt`, each `template`, and every persona `name` / `description` / `secret`)
in the language named by `language`. That value drives how the engine prompts
the model.

A persona may also carry an optional `secret`, its hidden agenda. The engine
injects it into that agent's own prompt only, so the other agents never learn
it and cannot react to it. The agent is told to keep it out of anything the
others can hear, while its `inner_thought` may name it freely. You (the viewer)
can reveal it from the persona sheet during a run, which is what makes the
dramatic irony readable. Use `secret` when you want a public face and a private
motive to differ. Keep the whole persona in `description` when you don't.

Optional top-level keys:

- `simulation_language` sets the language the agents speak when it differs from
  the authoring language. Omit it to speak in `language`.
- `log_window` sets how many recent conversation entries each prompt carries.
  It must be at least the agent count when a `speak_each` phase is present, or
  earlier speakers in the same round drop out of later prompts.

Do not add a top-level `min_engine_version` key. It is not part of the scenario
YAML schema, and a bare integer value fails to load. Compatibility is handled
by the gallery index, not by the scenario file.

## Phases

Phases run top to bottom, once per round. There are two families.

**LLM phases** run one model inference per agent (or one per round for
`narrate`). Each declares an `output` block naming the fields the model fills
in.

| Phase | What it does | Primary field | Private-thought field |
|-------|--------------|---------------|-----------------------|
| `speak_all` | Every agent addresses the group at once | `statement` | `inner_thought` |
| `speak_each` | Agents speak one at a time, each seeing the last | `statement` | `inner_thought` |
| `vote` | Each agent names another agent | `vote` | `reason` |
| `choose` | Each agent picks from declared `options` | `action` | `inner_thought` |
| `reflect` | Each agent privately updates a short note | `note` | (none) |
| `whisper` | Pairs of agents exchange a private line | `statement` | `inner_thought` |
| `narrate` | A commentator narrates the round highlight | (engine-fixed) | (none) |

**Code phases** run deterministically with no model call, so they declare no
`output` block.

| Phase | What it does |
|-------|--------------|
| `score_calc` | Applies a built-in scoring `logic` to update scores |
| `assign` | Distributes values from a `source` list to agents |
| `eliminate` | Removes the most-voted agent from later rounds |
| `summarize` | Emits a recap line from a `template` string |
| `conditional` | Runs one branch of sub-phases based on an `if` expression |
| `event_inject` | Injects a random event string into the run state |
| `relationship_update` | Updates an affinity matrix from vote and choose history |

### Output fields and canonical names

The `output` block names are not free-form. Each LLM phase has one canonical
primary field and, for most, one canonical private-thought field, shown in the
table above. Use those exact names. A scenario that saves with a different name
(for example `message` instead of `statement`) is rejected when you commit it in
the editor.

```yaml
- type: vote
  prompt: Who do you suspect, and why?
  output:
    vote: string      # canonical primary for `vote`
    reason: string    # canonical private-thought for `vote`
```

The private-thought field is display-only. Other agents never see it, so it is
where a model can reason honestly before it speaks.

Two rules on the names themselves:

- Field names must be ASCII letters, digits, and underscores, starting with a
  letter. A non-ASCII field name can crash on-device inference. Field *values*
  may be any language.
- `narrate` is special. Its output shape is fixed by the engine, so a `narrate`
  phase declares no `output` block at all.

## Scoring logics

A `score_calc` phase names one built-in `logic`:

| Logic | What it rewards |
|-------|-----------------|
| `prisoners_dilemma` | The cooperate / betray payoff matrix, per pairing |
| `vote_tally` | One point per vote received |
| `wordwolf_judge` | Whether the group voted out the odd-one-out |
| `event_reactive` | Agents whose last `choose` matched the injected event |
| `pairwise_payoff` | A payoff table you author in YAML, scored per pairing |

Each logic expects specific phases earlier in the round. See the pitfalls
section below.

## Phase field reference

Fields you can set on a phase, beyond `type`, `prompt`, and `output`:

- `options` (for `choose`): the list the action must come from. Without it, the
  action is unconstrained free text.
- `pairing` (for `choose` and some scoring): `round_robin` pairs every agent
  with every other, `individual` gives each agent an independent decision.
- `target` (for `assign`): `all` gives every agent the same value, `random_one`
  gives a single random agent the value (used for the odd-one-out in word-wolf
  style games).
- `source` (for `assign` and `event_inject`): the name of a top-level list key
  holding the values to distribute or inject. You add that key yourself (for
  example `words:` or `topics:`) alongside the required top-level keys, and it
  must be non-empty.
- `rounds` (for `speak_each` and `whisper`): how many sub-rounds of speaking
  happen within the phase.
- `logic` (for `score_calc`): one of the scoring logics above.
- `payoff` (for `score_calc` with `pairwise_payoff`): a list of rows, each
  `{ when: [action1, action2], points: [p1, p2] }`. A pairing is matched against
  `when` positionally and awards `points` to the two agents. A pairing matching
  no row scores nothing.
- `template` (for `summarize`): the recap string, which may contain `{...}`
  placeholders such as `{scoreboard}` or `{current_round}`.
- `if`, `then`, `else` (for `conditional`): a condition expression and the
  sub-phase lists for each branch.
- `probability`, `as`, `no_repeat` (for `event_inject`): the chance of firing,
  the variable name the event is stored under (default `current_event`), and
  whether to avoid repeating a previous event.
- `narrator` (for `narrate`): the persona that delivers the commentary.
- `mood` is an optional private-thought output field you can add to any LLM
  phase to let a model carry emotional momentum between rounds.
- `max_sentences` caps a spoken phase's length. It only affects LLM phases.

## Condition expressions

A `conditional` phase branches on an `if` expression. Expressions combine
comparisons with `&&`, `||`, and parentheses.

```yaml
- type: conditional
  if: current_round == total_rounds && max_score >= 10
  then:
    - type: summarize
      template: "Final round. {vote_winner} is ahead."
  else:
    - type: speak_all
      prompt: The game continues.
      output:
        statement: string
        inner_thought: string
```

Comparison operators are `==`, `!=`, `<`, `<=`, `>`, `>=`. Variables you can
reference include `current_round`, `total_rounds`, `max_score`, `min_score`,
`eliminated_count`, `active_count`, `vote_winner`, and `scores.<Name>` for a
named agent. Scoring logics can expose extra scenario-specific variables. For
example, `wordwolf_judge` sets `wolf_name` to the agent holding the minority
word, which the Word Wolf example below uses in its final `conditional`.

**Quote string values with double quotes.** `name == "Alex"` compares against
the text `Alex`. A single-quoted `'Alex'` is read as an undefined identifier, so
the comparison is always false and the branch silently never runs.

## Common pitfalls

These are silent no-ops. The scenario loads, but a phase does nothing useful
because a dependency is missing or misplaced. The in-app editor flags the
blocking ones, but it is easier to get them right the first time.

- `eliminate` needs a `vote` earlier in the same round. Without it, there is no
  tally to eliminate from.
- `prisoners_dilemma` needs a `round_robin` `choose` phase before it, which is
  what creates the pairings it scores.
- `pairwise_payoff` needs the same `round_robin` `choose` before it, plus a
  `payoff` table whose `when` rows cover the `choose` options.
- `wordwolf_judge` needs both an `assign` with `target: random_one` (to pick the
  odd-one-out) and a `vote` before it.
- `event_reactive` needs an `event_inject` before it, storing the event under a
  variable the scoring reads.
- `assign` needs a non-empty `source`. An empty list distributes nothing.
- In a condition, compare text with double quotes, and make sure a bare word on
  either side of `==` is a real variable, not a persona name you meant to quote.

## A complete example

The Word Wolf preset, with personas and prompt text trimmed for brevity:

```yaml
id: word_wolf_en
language: en
name: Word Wolf
description: Players discuss a topic word, but one holds a different word.
agents: 5
rounds: 1
context: |
  You are a contestant on the game show "Word Wolf".
  Everyone has a topic word, but one player's word differs.
  Never say the word itself. Describe concrete features that
  evoke it, then vote to expose the minority.
words:                          # custom top-level list, referenced by source
  - majority: apple
    minority: orange
mid_game_announcements:
  - "Host: Time is short. Narrow it down."
personas:
  - name: Avery
    description: A calm observer who leads with colour and shape.
  - name: Riley
    description: An outgoing talker who describes taste and texture.
  # ...three more personas...
phases:
  - type: assign                # give one player the minority word
    source: words
    target: random_one
  - type: speak_each
    prompt: Describe your topic without ever naming it.
    output:
      statement: string
      inner_thought: string
    rounds: 2
  - type: reflect
    prompt: Who seems suspicious? Update your private note.
    output:
      note: string
  - type: event_inject          # maybe interrupt with a show announcement
    source: mid_game_announcements
    probability: 0.5
  - type: conditional
    if: 'current_event != ""'
    then:
      - type: summarize
        template: "{current_event}"
  - type: narrate
    narrator: an enthusiastic play-by-play commentator
    prompt: Call out the most suspicious player and the decisive mismatch.
    max_sentences: 3
  - type: vote
    prompt: Vote for the minority whose clues are out of step.
    output:
      vote: string
      reason: string
  - type: eliminate
  - type: score_calc
    logic: wordwolf_judge
  - type: conditional           # branch on whether the group caught the wolf
    if: "vote_winner == wolf_name"
    then:
      - type: summarize
        template: "Wolf found. {wolf_name} was the minority. The majority wins."
    else:
      - type: summarize
        template: "Wolf escapes. The minority was {wolf_name}. The votes went elsewhere."
```

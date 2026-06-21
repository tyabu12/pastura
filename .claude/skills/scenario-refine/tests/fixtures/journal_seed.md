# Scenario Refine Audit Digest

Local audit journal seed for self-tests. The machine-readable `audit-data`
comment below records that `word_wolf` was evaluated on 2026-06-20 with the
default model, so rotation must rank it AFTER never-evaluated scenarios.

<!-- audit-digest:sections -->
## 2026-06-20

Model: gemma-4-E2B-it-Q4_K_M | Scenarios: 1 (ok 1 / failed 0 / config_error 0)

<!-- audit-data: {"date": "2026-06-20", "model": "gemma-4-E2B-it-Q4_K_M", "scenarios": {"word_wolf": {"coherence": 4, "interaction": 4, "breakdown_free": 5, "payoff": 3, "payoff_axis": "strategic_tension", "status": "ok"}}} -->

| id | name | channel | category | status | (a) | (b) | (c) | (d) payoff | Δtotal | comment |
|---|---|---|---|---|---|---|---|---|---|---|
| word_wolf | ワードウルフ | preset | game_theory | ok | 4 | 4 | 5 | strategic_tension 3 | – | baseline |

<!-- audit-digest:promotion -->
Promotion: channels documented in `.claude/skills/scenario-refine/SKILL.md` § Promotion.

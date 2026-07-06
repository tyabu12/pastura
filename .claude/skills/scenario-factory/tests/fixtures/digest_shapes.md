# Scenario Factory Digest (three historical table shapes)

Hand-written fixture exercising the `--rebuild-index` header-name-keyed
parser across the journal's three real shapes: 5-axis (current), 4-axis
(no `(e) development`), and pre-axis-column (no `axis` column at all).
One `name` cell carries an escaped `\|` to prove pipe round-tripping.

<!-- factory-digest:sections -->

## 2026-06-15

Model: gemma \| test | Scenarios: 1 (ok 1 / failed 0 / config_error 0)

| id | name | theme | axis | status | (a) coherence | (b) interaction | (c) breakdown-free | (d) humor | (e) development | comment |
|---|---|---|---|---|---|---|---|---|---|---|
| shape_a_ok | テスト \| 大喜利 | 大喜利 | elimination / creative | ok | 4 | 3 | 5 | 2 | 3 | ぱいぷ \| を含む |

## 2026-06-14

Model: gemma | Scenarios: 2 (ok 1 / failed 1 / config_error 0)

| id | name | theme | axis | status | (a) coherence | (b) interaction | (c) breakdown-free | (d) humor | comment |
|---|---|---|---|---|---|---|---|---|---|
| shape_b_ok | 四軸OK | テーマ | branching / roleplay | ok | 3 | 4 | 4 | 5 | good |
| shape_b_fail | 四軸失敗 | テーマ | – | failed | – | – | – | – | error: boom |

## 2026-06-13

Model: gemma | Scenarios: 1 (ok 1 / failed 0 / config_error 0)

| id | name | theme | status | (a) coherence | (b) interaction | (c) breakdown-free | (d) humor | comment |
|---|---|---|---|---|---|---|---|---|
| shape_c_ok | 旧形式 | 昔 | ok | 2 | 2 | 3 | 1 | legacy |

<!-- factory-digest:promotion -->
Promotion: channels documented in `.claude/skills/scenario-factory/SKILL.md` § Promotion.

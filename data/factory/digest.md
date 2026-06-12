# Scenario Factory Digest

Committed output of the `/scenario-factory` skill (ADR-013 Phase 2,
#521): one section per cycle date, newest first, written by
`.claude/skills/scenario-factory/scripts/append_digest.py` — not by
hand. Raw run logs and generated YAMLs stay local-only (gitignored
`data/factory/runs/` and `data/factory/scenarios/`).

Judge scores cover quality (coherence / interaction / breakdown-free /
humor) only — they are NOT a content-safety screen; safety is enforced
by the blocklist pre-commit gate at promotion time.

<!-- factory-digest:sections -->

## 2026-06-13

Model: gemma-4-E2B-it-Q4_K_M | Scenarios: 3 (ok 3 / failed 0 / config_error 0)

| id | name | theme | status | (a) coherence | (b) interaction | (c) breakdown-free | (d) humor | comment |
|---|---|---|---|---|---|---|---|---|
| factory_20260613_kinku_bokete | 禁句大喜利 | 制約付き大喜利（禁句ルール） | ok | 4 | 3 | 5 | 3 | 禁句はほぼ回避され制約が機能。当事者ヅラ子のみ一人称芸を放棄。ミニマリスト省吾「バッテリー切れか」が今夜のベスト |
| factory_20260613_iiwake_battle | 言い訳エスカレーション | 順番制エスカレーション大喜利（speak_each） | ok | 4 | 5 | 3 | 4 | speak_each の前話者参照が明確に機能（差別化発言）。ただし R1 で開き直りマコが自票で 4 点獲得、R2 でお題取り違え（「遅刻ではなく」）。昇格第一候補 |
| factory_20260613_shinya_tsuhan | 深夜の通販バトル | なりきりプレゼン大喜利（深夜通販） | ok | 2 | 3 | 2 | 3 | ペルソナ溶解が顕著（節約担当ヨシ江まで宇宙波動を語り全員霊感堂化）。R2 自票 2 件。「1〜2文」指示も無視され冗長。5 人ペルソナは芸風の言語的差別化が要強化 |

Notes: First factory cycle (E2E verification for #521). 3/3 runs ok, no #253 crash tonight. Engine finding: self-votes despite exclude_self were tallied 3 times across 2 scenarios (iiwake R1, tsuhan R2 ×2) — VoteHandler seems not to reject votes outside the candidates list; tracked in #524. One JSON-parse retry in tsuhan (auto-recovered).


<!-- factory-digest:promotion -->
Promotion: copy the winning YAML from `data/factory/scenarios/<date>/` to `Pastura/Pastura/Resources/Presets/` via an `/orchestrate` PR — landing under `Resources/` routes it through the blocklist pre-commit gate.

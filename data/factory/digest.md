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

Model: gemma-4-E2B-it-Q4_K_M | Scenarios: 6 (ok 5 / failed 1 / config_error 0)

| id | name | theme | status | (a) coherence | (b) interaction | (c) breakdown-free | (d) humor | comment |
|---|---|---|---|---|---|---|---|---|
| factory_20260613_kinku_bokete | 禁句大喜利 | 制約付き大喜利（禁句ルール） | ok | 4 | 3 | 5 | 3 | 禁句はほぼ回避され制約が機能。当事者ヅラ子のみ一人称芸を放棄。ミニマリスト省吾「バッテリー切れか」が今夜のベスト |
| factory_20260613_iiwake_battle | 言い訳エスカレーション | 順番制エスカレーション大喜利（speak_each） | ok | 4 | 5 | 3 | 4 | speak_each の前話者参照が明確に機能（差別化発言）。ただし R1 で開き直りマコが自票で 4 点獲得、R2 でお題取り違え（「遅刻ではなく」）。昇格第一候補 |
| factory_20260613_shinya_tsuhan | 深夜の通販バトル | なりきりプレゼン大喜利（深夜通販） | ok | 2 | 3 | 2 | 3 | ペルソナ溶解が顕著（節約担当ヨシ江まで宇宙波動を語り全員霊感堂化）。R2 自票 2 件。「1〜2文」指示も無視され冗長。5 人ペルソナは芸風の言語的差別化が要強化 |
| factory_20260613_shachiku_senryu | 社畜川柳バトル | 音数制約大喜利（五七五川柳） | ok | 3 | 3 | 4 | 3 | 文体の言語的差別化は 4 人とも維持（通販の反省を回収）。ただし五七五の音数はほぼ全句で違反、R2 は 2 句が二段構成に崩壊。ミレイが 2R 連続自票で首位（#524 再発 ×2）。マサムネ「在宅の陣地 畳の上で 睨み合う」が好句 |
| factory_20260613_maou_mensetsu | 魔王の転職面接 | 役割ミスマッチ面接（speak_each） | ok | 3 | 3 | 4 | 2 | 「一言〜二言」指示は完全遵守だが短文化で魔王語などの文体が消滅しコンセプト未発火。投票理由の大半が候補者発言の逐語コピー。自票ゼロ（exclude_self は今回正常）。おツユ「死者の静けさが安心材料でございます」が拾い物 |
| factory_20260613_suberi_survival | すべったら脱落 | 脱落式サバイバル大喜利（eliminate 初投入） | failed | – | – | – | – | R1 speak_all の 5 人目（静寂のジュン）推論中に #253 SIGABRT（LlamaCppService.safeSample）。eliminate フェーズ到達前で新メカニクス検証は持ち越し。直前 4 件のボケは正常生成 error: run_end line missing — process died mid-run (#253) |

Notes: Two cycles ran on 2026-06-13 (rows merged — append_digest.py replaces same-date sections). Cycle 1 (E2E verification for #521): 3/3 ok, no #253 crash. Engine finding: self-votes despite exclude_self were tallied 3 times across 2 scenarios (iiwake R1, tsuhan R2 ×2) — VoteHandler seems not to reject votes outside the candidates list; tracked in #524. One JSON-parse retry in tsuhan (auto-recovered). Cycle 2: first #253 crash in factory operation (suberi_survival, SIGABRT in LlamaCppService.safeSample mid-R1) — eliminate-phase mechanics remain unverified. #524 recurred ×2 (senryu: Mirei self-voted and won in both rounds) while mensetsu had zero self-votes. New finding: counting constraints (5-7-5) are not enforceable by prompt alone — nearly every line broke the meter.


<!-- factory-digest:promotion -->
Promotion: copy the winning YAML from `data/factory/scenarios/<date>/` to `Pastura/Pastura/Resources/Presets/` via an `/orchestrate` PR — landing under `Resources/` routes it through the blocklist pre-commit gate.

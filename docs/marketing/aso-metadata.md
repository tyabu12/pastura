# App Store metadata (ASO)

Git-managed snapshot of the live App Store Connect metadata, plus the ASO working
baseline for keyword/subtitle tuning. § Current = what is live now; proposed changes
land in § Proposal and are applied to ASC at release time.

- Tracking: #1073 (Growth C-1 — ja launch marketing execution)
- Umbrella: #1069 (Growth track)
- ASC field limits: subtitle ≤ 30 chars, keyword field ≤ 100 chars
  (comma-separated; avoid spaces after commas to save budget).

> Metadata-only edits (subtitle / keywords / description) can be submitted without a new
> binary but still pass through App Store review on the next version — verify current ASC
> behavior before assuming a change is review-free.

## Current — live on App Store Connect (snapshot 2026-07-23)

### Subtitle (App情報 › ローカリゼーション)

| Locale | Subtitle | Length |
|--------|----------|-------:|
| en | `Like stargazing, but for LLMs` | 29 / 30 |
| ja | `天体観測のように、LLM観測` | 14 / 30 |

### Keywords (バージョン別 › キーワード)

| Locale | Length |
|--------|-------:|
| en | 97 / 100 |
| ja | 86 / 100 |

**en**

```
AI agents,on-device,offline,multi-agent,roleplay,Gemma,Qwen,private AI,scenario,Word Wolf,observe
```

**ja**

```
AIエージェント,オンデバイス,オフライン,マルチエージェント,ロールプレイ,ローカルLLM,人狼,囚人のジレンマ,シナリオ,AI観測,サンドボックス,Gemma,Qwen
```

### Baseline observations (input for § Proposal)

- **en keywords 97/100** — nearly full; additions require swapping something out.
- **ja keywords 86/100** — ~14 chars headroom.
- **ja subtitle 14/30** — over half unused; subtitle carries high ASO weight → clearest
  near-term opportunity.
- **en/ja asymmetry** — en has `Word Wolf` / `observe`; ja has `人狼` (werewolf, *not*
  ワードウルフ=Word Wolf), `囚人のジレンマ`, `AI観測`, `サンドボックス`. Coverage differs by locale.

## Proposal (task A — pending)

_To be drafted by the #1073 ASO keyword pass. Present as a "current → proposed" diff per
field with rationale; do not edit § Current until a change is applied to ASC._

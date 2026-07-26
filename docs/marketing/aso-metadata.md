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

## Current — live on App Store Connect (snapshot 2026-07-27)

### Subtitle (App情報 › ローカリゼーション)

| Locale | Subtitle | Length |
|--------|----------|-------:|
| en | `Like stargazing, but for LLMs` | 29 / 30 |
| ja | `ローカルLLMでAIエージェントを観察` | 19 / 30 |

### Keywords (バージョン別 › キーワード)

| Locale | Length |
|--------|-------:|
| en | 100 / 100 |
| ja | 78 / 100 |

**en**

```
AI agents,on-device,offline,multi-agent,roleplay,Gemma,Qwen,private AI,scenario,Word Wolf,simulation
```

**ja**

```
オンデバイス,オフライン,マルチエージェント,ロールプレイ,人狼,ワードウルフ,囚人のジレンマ,シナリオ,シミュレーション,サンドボックス,パーティーゲーム
```

### Baseline observations (pre-1.1 state — superseded by the tables above; motivated the applied pass)

- **en keywords 97/100** — nearly full; additions require swapping something out.
- **ja keywords 86/100** — ~14 chars headroom.
- **ja subtitle 14/30** — over half unused; subtitle carries high ASO weight → clearest
  near-term opportunity.
- **en/ja asymmetry** — en has `Word Wolf` / `observe`; ja has `人狼` (werewolf, *not*
  ワードウルフ=Word Wolf), `囚人のジレンマ`, `AI観測`, `サンドボックス`. Coverage differs by locale.

## Proposal — ✅ APPLIED to ASC 2026-07-27, submitted with 1.1 (task A — #1073 ASO keyword pass, drafted 2026-07-23)

> This pass is **applied**: § Current above now reflects these values. The reasoning below is
> retained as the rationale for the current metadata (why each token was chosen / dropped). The
> "Baseline observations" subsection above describes the pre-change state that motivated it (its
> numbers are the old values, not § Current). `en` subtitle was intentionally left unchanged this
> pass. Remaining items are under § Next actions.

**Strategy** (per #1069 / #1073): the funnel's weakest stage is *discovery*. Graft onto three
existing search circles rather than evangelizing the "AI観測 / AIgazing" category —
(1) local-LLM enthusiasts, (2) werewolf / Word-Wolf party-game players, (3) "watching"-type
spectator entertainment. Priority: **ja** (first launch market, in review). **en is treated as
live too**, not merely the second-rocket: it is the ASC **primary** language and Apple indexes the
primary localization in every storefront (see mechanics below).

Wording here is a **proposal**; final wording + ASC application is the operator's call (human gate,
#1073). Char counts verified 2026-07-23. Do not edit § Current until a change is applied to ASC.

### Apple keyword mechanics (verified against authoritative sources)

- Keyword field: comma-separated, **no spaces**, 100 chars. App name + subtitle + keyword field +
  category are **cross-indexed** into one set — never repeat a word across them; Apple auto-combines
  components into phrases. **Singular only** (a plural counts as a duplicate). Avoid too-broad words
  ("AI" alone, "app") and filler. — [Apple, App Store search](https://developer.apple.com/app-store/search/)
- **Cross-localization**: the ASC primary language is **English**, and Apple indexes the primary
  localization in **all** storefronts; the Japan storefront indexes ja **+ English-US**.
  Phrase-combination is **within a single localization only** (a ja word won't fuse with an en word
  into a phrase). — [aso.dev cross-localization](https://aso.dev/metadata/cross-localization/),
  [MobileAction](https://www.mobileaction.co/blog/app-store-cross-localization/)
  - **Consequence used below**: the identical Latin tokens `Gemma` / `Qwen` in the en field already
    rank in Japan → keeping them in the ja field is redundant, so they are reclaimed for
    Japanese-native (kana/kanji) terms the en field cannot serve.

### ja (launch locale)

**Subtitle** — highest-weight search field; 16 chars were unused.

| | Value | Length |
|---|---|---:|
| Current | `天体観測のように、LLM観測` | 14 / 30 |
| **Proposed** | `ローカルLLMでAIエージェントを観察` | 19 / 30 |

The current line has near-zero search value (`LLM観測` is not a queried term; `天体観測` pulls
irrelevant stargazing traffic) and leans into the very category-evangelism the strategy
de-emphasizes. The proposal moves the two highest-value phrases — `ローカルLLM` (circle 1) and
`AIエージェント` (circle 1/3) — into the highest-weight field, readable as a plain value prop
("observe AI agents on a local LLM"). The poetic brand line is rehomed to the description's opening
line + a screenshot caption (neither is search-indexed → pure conversion surface).

**Keywords** — 86 / 100 → **78 / 100** (22 chars headroom).

| Action | Token(s) | Why |
|---|---|---|
| Remove | `ローカルLLM`, `AIエージェント` | promoted to the subtitle (higher weight) → now duplicates |
| Remove | `Gemma`, `Qwen` | redundant with the en field, which is indexed in Japan (reclaim ~11 chars) |
| Remove | `AI観測` | ~zero search volume, self-coined; evangelism residue (brand word → description) |
| Add | `ワードウルフ` | **circle 2** — literal name of a shipped scenario; serves the katakana query that en `Word Wolf` cannot. Zero relevance / review risk |
| Add | `シミュレーション` | **circle 3** — the app's literal nature; combines to "AIシミュレーション" within the ja field |
| Add | `パーティーゲーム` | **circle 2** breadth — `word_wolf` / `last_fable` are party games |
| Keep | `人狼` | genre-adjacent term that works in Japanese as a category word (Word Wolf is a 人狼-derived genre). **Intentional asymmetry** with en (see en note). Drop silently if App Review flags 5.2 |

```
オンデバイス,オフライン,マルチエージェント,ロールプレイ,人狼,ワードウルフ,囚人のジレンマ,シナリオ,シミュレーション,サンドボックス,パーティーゲーム
```

### en (primary language — indexed in every storefront incl. Japan; not merely "second rocket")

**Subtitle** — `Like stargazing, but for LLMs` (29 / 30). **Unchanged this pass** (signature brand
line). Note it has the same low-search-value problem as the ja subtitle *and* is indexed globally →
see Next actions.

**Keywords** — 97 / 100 → **100 / 100** (one swap).

| Action | Token | Why |
|---|---|---|
| Remove | `observe` | vague verb, negligible search intent |
| Add | `simulation` | **circle 3** — accurate; combines to "AI simulation" / "agent simulation" within the en field |

```
AI agents,on-device,offline,multi-agent,roleplay,Gemma,Qwen,private AI,scenario,Word Wolf,simulation
```

**Deferred (not this pass):** `werewolf` — rejected on **conversion** grounds (searcher wants to
play 人狼; no such scenario ships → disappointment → low rating), which is *why* en drops it while ja
keeps the genre word `人狼`. `social deduction` (accurate genre for `word_wolf` / `last_fable`) — 16
chars in a full field; needs the en-subtitle rework below to fund it.

### Next actions (out of scope for this pass — record for the next ASO pass)

- **en subtitle rework**: `Like stargazing, but for LLMs` → a search-first `On-device AI agent
  simulation`-class line (≤30). Frees `on-device` / `AI agent` from the en keyword field as
  duplicates → room for `social deduction` (circle 2, en). This is a bigger brand call than the ja
  subtitle (it is the English AIgazing signature) → a deliberate, separate decision.
- **Empirical check post-launch**: validate the `Gemma` / `Qwen` cross-localization reclaim against
  ASC search-term data (Japan storefront). If the app dropped out of "gemma" results in JP, restore
  both to the ja field — the change is reversible.
- **Rehome retired brand lines**: move `天体観測のように、LLM観測` / `Like stargazing…` to the
  description opener + a screenshot caption (conversion surfaces, not search-indexed).

# App Store listing — Japanese (`ja`)

> ASC input values for the `ja` localization. The ja copy is written to read
> naturally as Japanese (same policy as the LP's ja mirror), **not** as a
> back-translation of the EN. Character counts are Unicode code points
> (full-width chars count as 1 each, same as ASC).
>
> **Final copy review**: covered by the same Fable pre-submission pass as the EN
> file (2026-07-07); the required accuracy fix and term/notation-consistency
> fixes (「心の声」, 「エージェントたち」) are applied below. A later copy-polish pass
> (2026-07-07) refined the ja wording (tone tweaks + explicit 「LLM」 naming);
> the Description is 1,070 code points post-polish.

## App name / Subtitle

The store **Name** (`Pastura - Local LLMs simulator`) is kept in English across
both locales (confirmed value, `docs/release-setup.md` Part B2) — the English
brand identity plus the global-uniqueness constraint (`Pastura` alone is reserved).

The **Subtitle** is localized per locale (the Subtitle field is per-locale and
search-indexed in App Store Connect):

| Locale | Subtitle | Chars |
|---|---|---|
| en | `Like stargazing, but for LLMs` | 29 / 30 |
| ja | `天体観測のように、LLM観測` | 14 / 30 |

The ja subtitle reads naturally in Japanese, echoes the Description opener
(`AI観測。天体観測のように…`), and — since the Subtitle field is search-indexed — adds
ja keyword surface that an English subtitle would not.

## Promotional Text

```
AI エージェントが推論し、駆け引きし、時には嘘をつく。すべて iPhone の中で、完全オフライン。新しいシナリオやモデルも随時追加。アカウント登録は不要、データは端末の外に出ません。
```

**93 / 170 chars.** ✓

## Description

```
AI観測。天体観測のように、ローカル LLM を眺める。

Pastura は、端末の中で動く AI エージェントたちの閉じた牧場。あなたがシナリオを書くと、エージェントたちがそれを演じます。あなたは一歩下がって、彼らの発言、心の声、投票、スコアがリアルタイムに流れていく様子を、ただ眺めるだけ。

あなたは会話に参加できません。それが Pastura の設計です。人が入ると、エージェントはあなたに反応しはじめ、エージェントたち同士の素のやり取りは見られなくなってしまう。Pastura は LLM とチャットするアプリではなく、LLM エージェントが考える様子を眺めるアプリです。

すべては端末上で動きます。アカウント登録は不要。あなたのデータは一切、端末の外に出ません。機内モードでも動きます。

できること
・ワードウルフや囚人のジレンマなど、内蔵シナリオを再生
・ビジュアルエディターで独自シナリオを作成。YAML で細部まで制御も可能
・厳選された共有シナリオのギャラリーからのインポート
・ローカルLLMモデルを切り替えて、同じシナリオがどう変わるかを見る
・発言、心の声、投票、スコアがリアルタイムに届く
・実行結果を Markdown でエクスポートして、保存・貼り付け・共有

なぜローカル処理か
LLM モデルは他人のサーバーではなく、あなたの端末の中にあります。プライバシー、コスト、レイテンシが一度に片付く。推論がサーバーに触れることは一度もありません。月額は 0 円。テレメトリも分析もなし。あなたのシナリオも実行結果も、端末の外には出ません。

起動時にモデルを選ぶと Pastura はそれを一度だけダウンロードします（約 3 GB、Wi-Fi 推奨）。あとはずっとオフライン。ダウンロードを待つあいだは内蔵のデモ再生が流れ、モデルが揃う前から「観測」がどんなものかを確かめられます。

より大きな視野で
天体観測は、空の星の眺め方を教えてくれました。AI 観測は、AI エージェントの眺め方を教えてくれる。人類の作った AI を、立ち止まって眺めることは、あまりありません。Pastura はそのための、静かな窓。端末の中で動く、あなた一人のもの。それが彼らについて何かを語るのか、それとも私たち自身についてなのかは、観察するあなたへの宿題です。

動作には 6.5 GB 以上の RAM を搭載した端末が必要です（iPhone 15 Pro 以降）。無料でサブスクリプションもアプリ内課金もありません。
```

**1,070 / 4,000 chars.** ✓ — Pre-fold opener: 28 chars (`AI観測。天体観測のように、ローカル LLM を眺める。`). ja reads shorter than en by design (natural density, not padded).

## Keywords

> `AI観測` and `ローカルLLM` are ja search terms; the English Name and the ja
> Subtitle (`天体観測のように、LLM観測`) add complementary surface, not duplicating
> these exact keyword tokens.

```
AIエージェント,オンデバイス,オフライン,マルチエージェント,ロールプレイ,ローカルLLM,人狼,囚人のジレンマ,シナリオ,AI観測,サンドボックス,Gemma,Qwen
```

**86 / 100 chars.** ✓

## URLs

Support URL and Marketing URL are set **per App Store locale** — each version
localization has its own URL fields (confirmed in the ASC UI: the en locale
holds the root paths, the ja locale the `/ja/`-prefixed pages). The Astro site
serves both as static locale-prefixed routes; there is no Accept-Language
redirect. Privacy Policy URL is set in App Information (アプリ情報), not on the
version page. ja-locale values:

| Field | Value (ja locale) |
|---|---|
| Support URL | `https://pastura.app/ja/support/` |
| Marketing URL | `https://pastura.app/ja/` |
| Privacy Policy URL | `https://pastura.app/ja/legal/privacy-policy/` |

## Screenshot captions (JA)

> `思考` matches the in-app 「思考」 label; 「心の声」 matches the `INNER VOICE` →「心の声」tag.

| # | Screen | Caption |
|---|---|---|
| 1 | 観測トランスクリプト（発言＋心の声バブル） | 発言と、その裏にある心の声まで |
| 2 | ホーム — シナリオ一覧 | 実行できるシナリオが並ぶ牧場 |
| 3 | ビジュアルシナリオエディター | コード不要で、自分の世界を書く |
| 4 | 投票・スコア結果 | 投票、スコア、そして結末 |
| 5 | 過去の結果 | すべての実行を、あとから見返す |

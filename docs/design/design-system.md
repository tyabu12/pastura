# Pastura Design System

Pastura は、AIエージェントたちが「あなたの iPhone の中で静かに対話している」さまを覗き見るアプリです。このドキュメントは、Pastura のビジュアル・トーン・情報設計を凝縮した**再利用可能なデザインシステム**です。

用途：

1. **Claude Code への実装プロンプト** — Swift/SwiftUI・React・その他へ移植する際のソース
2. **Claude Design への継続プロンプト** — 他画面（オンボーディング、設定、会話履歴など）を今後デザインする際のコンテキスト

---

## 1. デザイン哲学（Voice）

Pastura は以下の原則に従います。この5つは画面を作る前に必ず自問してください。

| 原則 | 意味 | 具体的帰結 |
|------|------|-----------|
| **静謐（quietude）** | 鳴らない。光らない。強くない。 | 飽和色・ネオン・強いシャドウ禁止。アニメは長く緩く（>600ms, ease-out） |
| **観察（observation）** | ユーザーは「操作」ではなく「眺める」存在 | CTA は小さく、ボタンは控えめ。余白で「間」を作る |
| **牧草地（pastoral）** | 苔・麻・古紙・羊毛・犬の毛 | 彩度の低い自然色。純白・純黒は避ける |
| **技術の誠実さ** | LLMのダウンロードという技術的現実を隠さず詩に変える | `3.0 GB`・`残り約4分` を恥じず、むしろ主役として美しく見せる |
| **日本語優先** | 13pt 本文で漢字・ひらがな・カタカナが混ざっても読める密度 | 行間 1.65 以上、letter-spacing は 0〜0.02em |

**禁じ手**:
- ❌ 蛍光色・彩度 80% 超のアクセント
- ❌ `box-shadow: 0 20px 60px rgba(0,0,0,.5)` のような濃い浮遊感
- ❌ 絵文字（ブランド内で使わない。SF Symbols も抑制的に）
- ❌ グラデーション背景（画面内の光漏れ 1箇所のみ許容）
- ❌ 「完了！🎉」「素晴らしい！✨」のような祝祭的コピー
- ❌ スケルトンローダー（代わりにコンテンツ自体をゆっくり fade-in）

---

## 2. カラートークン

全色は **oklch / sRGB hex で指定**。ブランドカラーは「苔の緑」（moss）系1色に絞り、他は Warm Gray スケールで構成します。

### 2.1 背景 / Surfaces

| トークン | Hex | 用途 |
|---------|-----|------|
| `--page` | `#F3EFE7` | 外側（ワークベンチ・Safe Area 外） |
| `--screen-bg` | `#FCFAF4` | アプリ本体の背景（crisp な羊毛色） |
| `--bubble-bg` | `#FFFFFF` | 発言バブル |
| `--promo-bg` | `#FBFAF2` | プロモ/バナー |
| `--promo-border` | `#E4E7D2` | 同上のボーダー |

### 2.2 Ink（文字・輪郭）

| トークン | Hex | 用途 |
|---------|-----|------|
| `--ink` | `#2D2E26` | 本文（最濃。純黒ではない） |
| `--ink-2` | `#5A5A55` | サブテキスト・セクションラベル |
| `--muted` | `#8A8A83` | メタ情報・脚注 |
| `--rule` | `#E0DBCE` | 罫線 |

### 2.3 Moss Accent（苔アクセント）

Pastura 唯一のブランド色。用途別に4段階。

| トークン | Hex | 用途 |
|---------|-----|------|
| `--moss` | `#8A9A6C` | リーフアイコン・プロモ左ボーダー（3pt） |
| `--moss-dark` | `#6B7852` | DL進捗ドット点灯・アクセントリンク・ステータスラベル（Completed 等） |
| `--moss-ink` | `#3D4030` | 犬の輪郭・完了タイトル |
| `--moss-soft` | `#D4CBA8` | THINKING 左線・やさしい区切り |

### 2.4 Meta Contrast Presets（DL進捗表示）

日光下など**コントラスト要件が変わる環境**に備え、4段プリセットを定義。デフォルトは **L3**。

```css
[data-contrast="L1"]{ --meta-base:#8A8B76; --meta-strong:#5D6848; --meta-dot-on:#8A9A6C; }
[data-contrast="L2"]{ --meta-base:#6A6D5A; --meta-strong:#3D4530; --meta-dot-on:#7A8A5C; }
[data-contrast="L3"]{ --meta-base:#4A4E3D; --meta-strong:#2D2E26; --meta-dot-on:#6B7852; } /* default */
[data-contrast="L4"]{ --meta-base:#2D2E26; --meta-strong:#1A1B15; --meta-dot-on:#556340; }
```

### 2.5 キャラクターパレット（羊アバター）

| キャラ | 顔色 | 役割 |
|-------|------|------|
| Alice | `#F2E3C8` クリーム | やさしい第一声 |
| Bob | `#D9E2C6` セージ | 同意的・穏やか |
| Carol | `#EBD4D4` ピンク | 観察者 |
| Dave | `#D0D7DC` スレート | Wolf（狼）/ 中心人物 |

共通：耳 `#E8D9BC`, 耳内 `#D4C19E`, 鼻 `#3D4030`, 目 `#2D2E26`, ハイライト `rgba(255,255,255,.6)`

---

## 3. タイポグラフィ

### 3.1 ファミリー

| 用途 | ファミリー | フォールバック |
|------|-----------|---------------|
| 日本語本文 | **Noto Sans JP** (300/400/500/600) | system-ui, HiraKakuProN |
| モノスペース | **JetBrains Mono** | SF Mono, ui-monospace |

### 3.2 スケール（モバイル画面内）

| ラベル | サイズ | weight | line-height | letter-spacing | 用途 |
|-------|--------|--------|-------------|----------------|------|
| `title/phase` | 13pt | 600 | 1.3 | 0.02em | フェーズ見出し |
| `tag/phase` | 9.5pt | 600 | 1.2 | 0.22em, UPPER, mono | フェーズタグ |
| `body/bubble` | 13pt | 400 | 1.65 | 0 | 発言本文 |
| `body/promo` | 12pt | 400 | 1.65 | 0 | プロモ文 |
| `caption/name` | 10.5pt | 400 | 1.3 | 0.04em | アバター下の名前 |
| `thinking/body` | 10.5pt | 400 italic | 1.7 | 0.02em | 内なる思考 |
| `thinking/tag` | 8.5pt | 400 mono UPPER | 1.2 | 0.22em | REASON/THINKING ラベル |
| `meta/label` | 9pt | 600 mono | 1.2 | 0.06em | meta labels (DL / Vote Results / Round / sub-phase) |
| `meta/value` | 9pt | 400 mono | 1.2 | 0 | `35%`, `1.0 GB` |
| `meta/eta` | 10pt | 500 mono | 1.3 | 0 | 残り約4分 |
| `status/complete` | 16pt | 500 | 1.4 | 0.22em | 準備ができました |
| `status/hint` | 11pt | 400 mono | 1.2 | 0.1em | tap anywhere to begin |

### 3.3 日本語タイポの作法

- `text-wrap: pretty`（対応ブラウザ）で行末の孤立文字を抑える
- 読点「、」句点「。」で必ず改行候補が入るよう、max-width は 40ch 相当までに抑える
- 英字・数字が混ざる場合は半角、前後にスペース不要（`3.0 GB` はOKだが、日本語に続く場合「 GB」と半角スペース1つ）

---

## 4. スペーシング / レイアウト

### 4.1 スケール

4pt 基準で `4 / 8 / 12 / 14 / 20 / 32 / 48`。8の倍数に拘らず、14・20 のような中間値を積極的に使って「柔らかい」密度を出す。

### 4.2 角丸

| 用途 | 値 |
|------|---|
| iPhone 本体内側 | 31pt（デバイス追従） |
| 発言バブル | **上左 4pt, 他 14pt**（しっぽ付き） |
| プロモカード | 14pt |
| ボタン（投票） | 8pt |
| ドット | 50%（円） |

### 4.3 シャドウ

1要素あたり**最大2レイヤー**、彩度は苔系：

```css
box-shadow:
  0 1px 2px rgba(90,100,60,.04),
  0 12px 26px -12px rgba(90,100,60,.2);
```

---

## 5. コンポーネント定義

### 5.1 Phase Header（上部フェーズ帯）

```
[◆] WORD WOLF                            DEMO中
    発言ラウンド 1
```

- 左: 6pt 菱形 (leaf) + `tag/phase` + `title/phase` 縦並び
- 右: `DEMO中`（10pt mono, `--muted`）
- 背景: `screen-bg` を 78% 薄めた上に `backdrop-filter: blur(8px) saturate(1.05)`
- 下線: 1pt rgba(60,62,48,0.07)

### 5.2 Chat Bubble（発言）

```
[Avatar 48pt]  Alice
               [バブル: しっぽは上左]
               ▸ THINKING / ▾ タグ＋本文
```

- バブル間 spacing: 14pt
- アバター間隔: 10pt
- アバターサイズ: **48pt** (#171 で 42pt → 48pt にバンプ。~390pt 幅 iPhone で羊のシルエットが小さすぎる問題への対応。reference HTML と Swift `ChatBubbleLayout.avatarSize` を同時更新)
- フェードイン: 700ms ease-out, 180ms ずつディレイ

### 5.3 Vote Bubble（投票）

```
[Avatar]  Alice の投票
          [→ Dave]（outline ボタン風）
          REASON "散歩"って言葉、他の人も使ってない。お題が違うかも
```

- ボタンは `--moss` 1pt outline, text `--moss-dark`
- REASON は `thinking/tag` + `thinking/body` のセット

### 5.4 Promo Card

```
┌─────────────────────────────────┐
│ DL ●●●●●○○○ 35% · 1.0 GB / 3.0 GB │
│ 残り約4分                          │
│                                   │
│ [🐕]  少しだけお待ちください...    │
└─────────────────────────────────┘
 ↑ 左ボーダー 3pt moss
```

- 16:9 iPhone 画面で `bottom: 22pt, left/right: 14pt`
- meta は 2行構成（1行目: DL/ドット/pct/サイズ、2行目: ETA）
- body row は `HStack(spacing: 12)` で犬マーク 26pt + テキスト

### 5.5 DL Progress Dots

8個の 4pt 丸ドット。点灯数 = `round(pct/100 * 8)`。点灯色は `--moss-dark`、未点灯は `rgba(90,100,60,0.38)`。

### 5.6 Avatar（羊シルエット）

48pt 丸（§5.2 と同値。#171 で 42pt → 48pt にバンプ）。4色バリエーション。耳2枚 + 顔丸 + 鼻 + 目2つ + ハイライト1。詳細SVGは `./demo-replay-reference.html` の `SHEEP()` 参照。

### 5.7 Assistant Mark（犬 / コリー横顔）

26pt or 44pt（完了画面）。Pastura 全体を象徴するアシスタントマーク。白ベース、輪郭 `--moss-ink`、尾は `--moss` のカール。

---

## 6. モーション / アニメーション

**原則**: 速くしない、派手にしない、繰り返さない（パルスは例外）。

| ケース | Duration | Easing |
|--------|----------|--------|
| バブル登場 | 700ms | ease-out, stagger 180ms |
| DL ドット点灯 | 600ms | cubic-bezier(.4,0,.2,1) |
| ストリーム退場 | 1600ms | ease-out |
| 完了オーバーレイ登場 | 2400ms | ease-out, delay 200ms |
| マークパルス | 2400ms loop | ease-in-out, scale 1.0↔1.06 |
| タイトル fade-up | 1400ms | ease-out, delay 700ms |

ハプティクスは「完了時 1回、UIImpactFeedbackGenerator.light」のみ。

---

## 7. コピーライティング

### トーン

- 断定しない。「〜します」より「〜しています」「〜そうです」
- カタカナを多用しない。「ダウンロード」は許容、「ローディング」→「読み込み中」
- 数字は隠さず、美しく見せる。「少し時間がかかります」より「残り約4分」が良い
- 祝祭を避ける。「完了！」→「準備ができました」

### DL中プロモ文（3スロット）

> **Note**: 以下のコピー・切替タイミングはいずれも **draft**。`docs/specs/demo-replay-spec.md` §2 decision 13 に従い、final wording は実装 PR の copy pass で確定する。タイミングは独立タイマー（`docs/specs/demo-replay-ui.md` の PromoCard rotation セクション参照）で駆動され、**DL 進捗とは無関係**。

| スロット | 切替タイミング（暫定） | コピー（draft） |
|---------|----------------------|----------------|
| A | 0〜20 秒 | AIエージェントが、あなたのiPhoneの中で対話します |
| B | 20〜40 秒 | 少しだけお待ちください。その間、他のエージェントたちの様子をどうぞ |
| C | 40〜60 秒 | このアプリは広告もログインもなく、あなたの端末だけで静かに動きます |

（60 秒経過後は A に戻り、DL 完了まで無限循環。BG 復帰時は位置継続。interval `20s` は実装 PR で調整）

### 完了画面

- 主: `準備ができました`（draft）
- 副: `tap anywhere to begin`（英小文字・モノスペース、理由：「現実世界に戻る鍵穴」感）

> **Note**: 完了画面の「tap anywhere to begin」は **draft copy**。demo-replay-spec.md §2 decision 6 / §2 decision 8 に従い、実際の遷移は **auto のみ**（user tap 不要）。このテキストは視覚ヒントに留まるか、copy pass で削除・書き換えの対象（spec §2 decision 13）。

---

## 8. アクセシビリティ

- 本文の最小コントラスト比: 7:1（AAA）を目標に `--ink` と `--screen-bg` の組み合わせで達成
- メタ情報は L3 コントラストで 4.5:1 以上
- DL 進捗は `role="status" aria-live="polite"` / SwiftUI は `.accessibilityAddTraits(.updatesFrequently)`
- アバター・犬マークは `aria-hidden="true"` / `.accessibilityHidden(true)`（飾りだから）
- タップ領域は 44pt 未満の要素（THINKING トグル等）でも 44pt 確保。SwiftUI では `.padding(.vertical, N).contentShape(Rectangle()).onTapGesture{...}.padding(.vertical, -N)` の **negative-padding トリック**で、視覚上のサイズを変えずヒット判定だけ拡張する（`.contentShape(Rectangle())` 単独では view 自身の bounds までしか広がらない）
- Dynamic Type 非対応は割り切り。ただしトークン化して将来の対応に備える
- VoiceOver は画面全体で：フェーズ→発言順→プロモメタ→プロモ本文 の読み上げ順を維持

---

## 9. 他画面への展開ガイド

このシステムを他画面に使う際のチェックリスト：

- [ ] 背景は必ず `--screen-bg`（#FCFAF4）から始める
- [ ] アクセント色は `--moss` の1色のみ。2色目が欲しくなったら「構成を減らす」方を検討
- [ ] バブル・カード系は**角丸 14pt + 白背景 + 左ボーダー3pt moss** を基本形とする
- [ ] モノスペースはメタ情報・ラベル・数値のみ。本文には使わない
- [ ] アニメーションは 600ms 以上、ease-out を基準に
- [ ] 犬マーク（コリー）は「アシスタント」の記号、羊はユーザー側エージェントの記号として使い分ける
- [ ] コピーは「観察している」トーンを守る（祝祭・急かし・強調を避ける）

---

## 10. Claude Design / Claude Code 向けプロンプト雛形

このドキュメントと共に以下を投げるとよいです。

### Claude Design に別画面を依頼する場合

```
添付の design-system.md は Pastura というアプリのデザインシステムです。
このシステムに完全準拠して、以下の画面をデザインしてください：

[画面の目的]
[必要な機能]
[含めるべき情報]

制約：
- カラートークン・タイポスケール・アニメーション原則は design-system.md を逸脱しない
- デザイン哲学の5原則（静謐・観察・牧草地・技術の誠実さ・日本語優先）を守る
- 変化を加えたい場合は「なぜその原則を緩めるか」を明記
- モバイル 390×844（iPhone 15）基準で設計

Frame 2〜3案のバリエーションを出してください。
```

### Claude Code に実装を依頼する場合

```
添付の design-system.md（docs/design/）と対象画面の UI spec（docs/specs/<screen>-ui.md）、
および該当する design reference HTML を参照してください。
既存の SwiftUI プロジェクト（iOS 17+）に、このデザインを実装してください。

手順：
1. DesignTokens.swift / Theme.swift にカラー・フォント・スペーシングトークンを定義
   （design-system.md §2-§4 が canonical source）
2. 共通コンポーネント（Bubble, PromoCard, Avatar, AssistantMark）を切り出す
3. 画面固有の state は UI spec の Responsibility boundary に従って分担
   （VM が所有する挙動と host view のローカル state を混同しない）
4. アニメーションは UI spec のテーブル通りの Duration/Easing で

HTML は参照用で、移植対象ではありません。SwiftUI のイディオムで書き直してください。
犬・羊の SVG は Path で起こすか、最悪 SF Symbols で代用してください（ただし代用した場合は注釈）。
```

*DL-time demo replay 画面の具体例*:
`docs/design/demo-replay-reference.html` + `docs/specs/demo-replay-ui.md` +
`docs/specs/demo-replay-spec.md` + `docs/decisions/ADR-007.md` を参照。

---

*このドキュメントは Pastura v0.1 時点の仕様です。将来、ダークモード・複数モデル対応・会話履歴画面などが追加された際は、トークンを**減らす方向**で拡張してください（追加より削除を優先）。*

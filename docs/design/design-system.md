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
| `--whisper-bubble` | `#EBEEE1` | 密談（whisper）バブル — moss ティントの控えめな off-white で公開発言と区別（#908 PR2） |
| `--promo-bg` | `#FBFAF2` | プロモ/バナー |
| `--promo-border` | `#E4E7D2` | 同上のボーダー |

### 2.2 Ink（文字・輪郭）

| トークン | Hex | 用途 |
|---------|-----|------|
| `--ink` | `#2D2E26` | 本文（最濃。純黒ではない） |
| `--ink-2` | `#5A5A55` | サブテキスト・セクションラベル |
| `--muted` | `#8A8A83` | メタ情報・脚注 |
| `--rule` | `#E0DBCE` | 罫線 |
| `--ink-on-accent` | `#FFFFFF` | アクセント塗り（`moss` / `moss-dark`）の上に載る文字・グリフ |

`--ink-on-accent` は §2.3 が認める white-on-accent の前景。§1 の「純白の面を避ける」は**背景**の話なので抵触しない。適用範囲は下地で変わる:

- **テキストは `moss-dark` 上に限る**（≈4.7:1、AA 達成）。base `moss` 上は ≈3.03:1 で 4.5:1 に届かない。
- **グリフ・図形は `moss` 上も可**。WCAG 1.4.11 の非テキスト 3:1 が適用され ≈3.03:1 は充足する（`CheckBadge` のチェック、share タブのシンボル — 後者は `moss`→`moss-dark` グラデ上なので最悪値が明側の `moss`）。ただし余裕は約 1% しかないので、`moss` の色を動かす際はこの 2 用途を確認すること。

生の `Color.white` を各所に書かずトークンにしてあるのは、ダーク時のアクセント前景の判断が 1 箇所で済むようにするため。ダークでは `moss` が `night-moss`(#A8B888) になり白は ≈2.13:1 と 3:1 すら割る。これは**計算で確定済み**なので実機 QA（ADR-028 gate 4）では決められず、gate 1 のダーク値決定（`night-moss` を暗くするか、このトークンをペア化するか）で解く。**つまりこのトークンは「両外観で固定」ではなく、gate 1 の未解決 60 個の一つ**。Source: `PasturaPrimaryButtonStyle` / `SharedScenariosListView+CategoryChips`。

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

> **Source of Truth**: `docs/design/demo-replay-reference.html` の `sheepAvatar()` 関数が原点。本テーブルはその mirror で、Swift `Pastura/Views/DesignTokens.swift` の `PasturaPalette.avatar*` トークンが本テーブルを参照する。HTML 内の letters mode `.ava.<who>` セレクタの背景色は HTML-only ornament で iOS では未レンダー、scope 外。命名規約: 共有部位は `avatarPart`（例: `avatarEar`）、キャラ別部位は `avatarPartCharacter`（例: `avatarBodyAlice`）。enforcement 層: `Pastura/PasturaTests/Views/DesignTokensTests.swift`。

| キャラ | body | face | horn | 役割 |
|-------|------|------|------|------|
| Alice | `#F2E3C8` クリーム | `#C9A979` | `#B29364` | やさしい第一声 |
| Bob   | `#DDE4CC` セージ   | `#8A9A6C` | `#6F7F54` | 同意的・穏やか |
| Carol | `#EAD6D1` ピンク   | `#B8877C` | `#9C6E64` | 観察者 |
| Dave  | `#D9D7C9` スレート | `#6B6858` | `#4F4C3F` | Wolf（狼）/ 中心人物 |

共通：耳 `#E8D9BC`, 耳内 `#D4C19E`, 鼻 `#3D4030`, 目 `#2D2E26`, ハイライト `rgba(255,255,255,.6)`

### 2.6 Alert Family（4段階の温度）

通知・状態の温度感を 4 段階で表す。各レベルに base / `*Soft`（背景用）/ `*Ink`（文字用）の 3 ヴァリアント。Source: `Pastura/Views/DesignTokens+ExtendedPalette.swift` `§2.6 Alert Family`。

| Token | Hex | 用途 | 例 |
|-------|-----|------|-----|
| `info` | `#7B8FA8` | ニュートラル通知 | 「新しいデモが届きました」 |
| `success` | `#7A9270` | 完了・正の状態 | DL完了、保存成功 |
| `warning` | `#C7A566` | 注意・確認待ち | 「DLが一時停止されました」 |
| `danger` | `#B57870` | 取り消し・破壊的操作 | 「会話を削除しますか？」 |

補助バリエーション：

| | Soft (背景) | Ink (文字) |
|---|------------|-----------|
| info | `#E8EDF2` | `#4A5A6F` |
| success | `#E5ECDF` | `#4D5F44` |
| warning | `#F2EAD3` | `#6F5C2D` |
| danger | `#EDD9D4` | `#6F4540` |

**運用ルール（牧歌トーンの維持）：**

- **Cancel ボタンは赤くしない。** 文字 `inkSecondary` (`#5A5A55`)、背景透明、ボーダー `rule` (`#E0DBCE`) で中立に。ボーダー指定はカスタムスタイルやチップで枠線を描く場合に適用し、枠線を描かないプレーンな `Button("Cancel")` には不要。
  - **中立フィルの許容（アフォーダンス補強）**: タップ可能性が伝わりにくい面（例: `PromoCard` の DL中止フッター）では、中立を保ったまま**淡いフィル**を敷いてよい。塗りは `danger`（赤）ではなく低不透明度の中立トーン（`rule` @0.45 など）＋`rule` 上罫線＋`stop.fill` グリフ。「赤くしない」原則は維持したまま、透明背景ルールの例外として扱う。Source: `PromoCard.swift` `cancelLinkRow`。
- **破壊確認ダイアログのプライマリボタン**: `danger` 文字 / `dangerSoft` 背景 / 同色ボーダー（iOS の system destructive role が許す範囲で）。
- **トースト**: 1pt のアクセント左ボーダー + `*Soft` 背景 + 14pt 角丸（promo card と同じ造形）。

### 2.7 Interactive States（対話状態）

タップ可能要素のフィードバック。moss を 6/12/18% の alpha で重ねる方式で、下地のサーフェス色を問わない。Source: `§2.7 Interactive States`。

| Token | 値 | 用途 |
|-------|-----|------|
| `hover` | `rgba(138,154,108, 0.06)` | iPadOS pointer hover |
| `pressed` | `rgba(138,154,108, 0.12)` | タップ中 |
| `selected` | `rgba(138,154,108, 0.18)` | 選択維持 |
| `focusRing` | `#8A9A6C` | フォーカスリング (2pt outline / 2pt offset) |
| `disabledText` | `#B5B0A2` | 無効化テキスト |
| `disabledBackground` | `#ECE7DA` | 無効化サーフェス |

### 2.8 Link / Action（テキストリンク）

未使用予約。Pastura の現状画面にリンクは無いが、将来導入する際に "system blue" を発生させないために定義。Source: `§2.8 Link / Action`。

| Token | Hex | 用途 |
|-------|-----|------|
| `link` | `#5D7A4D` | デフォルトリンク（moss 寄りの深緑） |
| `linkVisited` | `#6F6753` | 訪問後（苔→土へ） |
| `linkHover` | `#4A6438` | hover 時 |

### 2.9 Dark Mode（夜の牧場）

**trait-based 配線済み（8 対）／値は未完。** `PasturaDynamicColor` が light/dark 対を
`UIColor(dynamicProvider:)` で解決し、下表の 8 対が `Color.*` エイリアス経由で実 UI に
届いている（[ADR-028](../decisions/ADR-028.md)）。ただし §2.1–§2.8 / §2.12 の残り **59**
トークンにはダーク対が無いため、アプリは `Info.plist` の `UIUserInterfaceStyle = Light`
で固定されたままで、実際にダークが描画されることはない。固定解除の条件は ADR-028
§ "Rollout"。Source: `§2.9 Dark Mode`。

**ダーク固定色が要る場合はこの 8 対のエイリアスを読まない。** `Color.ink` 等は「端末の
外観」を意味するようになったので、`ImageRenderer` 書き出しのように外観を固定したい
呼び出し側は `PasturaPalette.<token>.color` を直接読む（参照実装:
`HighlightShareCard`）。

| Token | Hex | 対応する day-mode token |
|-------|-----|------------------------|
| `nightBackground` | `#1B1D17` | `screenBackground` |
| `nightSurface` | `#232620` | ⚠️ **未決・未配線** — `bubbleBackground` は `nightBubble` が取っており、light 側に対が無い。ダークは背景/サーフェス/バブルの 3 段を要求するが light は 2 段しかないため、解消（light `surface` 新設 / `nightSurface` 削除 / 文脈対応）は視覚判断を伴う後続課題。ADR-028 § "The `nightSurface` double-mapping" |
| `nightBubble` | `#2C2F28` | `bubbleBackground` |
| `nightWhisperBubble` | `#2F3626` | `whisperBubble`（密談バブルのダーク対。#908 PR2） |
| `nightInk` | `#E8E5D8` | `ink` |
| `nightInkSecondary` | `#B0AC9C` | `inkSecondary` |
| `nightMuted` | `#7A7768` | `muted` |
| `nightRule` | `#353830` | `rule` |
| `nightMoss` | `#A8B888` | `moss` |

### 2.10 Time-of-Day（牧場の時間帯）

未使用予約。背景帯やヘッダのアンビエント表現用。`noon` と `night` は構造的トークン（`screenBackground` / `nightBackground`）と hex が重複するが、用途意味が違うので独立して定義する。Source: `§2.10 Time-of-Day`。

| Token | Hex | 雰囲気 |
|-------|-----|--------|
| `dawn` | `#F4E5CD` | 朝もやの黄み |
| `noon` | `#FCFAF4` | crisp 昼（既存 `screenBackground` と同 hex） |
| `dusk` | `#E5D4C2` | 夕の橙み |
| `night` | `#1B1D17` | 夜（既存 `nightBackground` と同 hex） |

### 2.11 Chart（最小4色）

未使用予約。グラフ可視化が必要になった場合の最小セット。既存トークンの再利用＝視覚言語が増えない方針。4 カテゴリを超える場合は palette を増やすのではなく可視化方式そのものを再考する。Source: `§2.11 Chart`。

| Token | Hex | 元 |
|-------|-----|-----|
| `chart1` | `#8A9A6C` | == `moss` |
| `chart2` | `#C7A566` | == `warning` |
| `chart3` | `#7B8FA8` | == `info` |
| `chart4` | `#B57870` | == `danger` |

### 2.12 Header Slots（GameHeader 専用）

`GameHeader`（§5.1, Demo / Sim 共通の上部 2 段ヘッダー）の slot 専用トークン。役割で命名しており、§2.4 の depth-tone preset (`metaBaseL1..L4`) や §2.2 の汎用 `rule` とは独立して進化させる。Hex が偶然重なる場合があるが、意味の取り違えを避けるため統合しない。

| Token | Hex | 用途 |
|-------|-----|-----|
| `headerRule` | `#C2C0AE` | Meta 行の中黒セパレータ `·`。汎用 `rule` (#E0DBCE) より暗く、行内タイポセパレータとして機能 |
| `headerMetaInk` | `#4A4E3D` | Meta 行のフェーズ名前景色（`metaBaseL3` と同 hex、role-anchored） |
| `headerMetaSubdued` | `#7B7D68` | Meta 行右寄せの推論 tok/s 値前景色（`metaBaseL1` と `metaBaseL2` の中間明度） |

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
| `thinking/tag` | 8.5pt | 400 mono UPPER | 1.2 | 0.22em | REASON/INNER VOICE ラベル |
| `meta/label` | 9pt | 600 mono | 1.2 | 0.06em | meta labels (DL / Vote Results / Round / sub-phase) |
| `meta/value` | 9pt | 400 mono | 1.2 | 0 | `35%`, `1.0 GB` |
| `meta/eta` | 10pt | 500 mono | 1.3 | 0 | 残り約4分 |
| `status/complete` | 16pt | 500 | 1.4 | 0.22em | 準備ができました |
| `status/hint` | 11pt | 400 mono | 1.2 | 0.1em | tap anywhere to begin |
| `title/scenario` | 16pt | 600 | 1.2 | 0.02em | GameHeader row 1 シナリオ名 (Demo / Sim 共通) |
| `meta/round` | 10pt | 600 mono | 1.2 | 0.06em, UPPER | GameHeader row 2 ROUND カウンタ |
| `meta/inline` | 10pt | 400 mono | 1.2 | 0.04em | GameHeader row 2 フェーズ名 / tok/s |
| `pill/status` | 9pt | 600 mono | 1.2 | 0.18em | GameHeader row 1 ステータスピル (Simulating / Demoing / Paused / Completed / ...) |

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
| Browse カード（`.insetGrouped`、詳細画面） | 14pt（continuous、§5.9） |
| 一覧セクション（`.grouped`、一覧画面） | なし（全幅バンド、§5.9 / #731） |
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
               ▸ INNER VOICE / ▾ タグ＋本文
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

48pt 丸（§5.2 と同値。#171 で 42pt → 48pt にバンプ）。4色バリエーション。耳2枚 + 顔丸 + 鼻 + 目2つ + ハイライト1。詳細SVGは `./demo-replay-reference.html` の `sheepAvatar()` 参照。

### 5.7 Assistant Mark（犬 / コリー横顔）

26pt or 44pt（完了画面）。Pastura 全体を象徴するアシスタントマーク。白ベース、輪郭 `--moss-ink`、尾は `--moss` のカール。

### 5.8 Toolbar buttons（iOS 26 Liquid Glass opt-out）

iOS 26 では `NavigationStack` 配下のシステム製 toolbar item（戻る chevron、`.confirmationAction` の Save、`.destructiveAction` の Delete など）が自動的に半透明 capsule "Liquid Glass" 効果でレンダリングされる。これは §1 の「静謐・観察・牧草地」に対し過剰に立体的で、Pastura のフラットな苔色トーンと衝突する。

このサブセクションでは、Liquid Glass を opt-out するための 2 つの再利用可能コンポーネントを定義する。Source: `Pastura/Pastura/Views/Components/PasturaBackButton.swift`。

#### 5.8.1 PasturaBackButton

root `NavigationStack` に push された全ビューで、システム back chevron を置き換える chevron-only ボタン。

| 仕様項目 | 値 / 出典 |
|---------|----------|
| アイコン | SF Symbol `chevron.backward`（RTL 対応版を選択） |
| 前景色 | `Color.ink` (#2D2E26、§2.2) |
| ボタンスタイル | `.buttonStyle(.plain)`（内側 chevron の content 用）。iOS 26 Liquid Glass capsule の抑制は ToolbarItem 側の `hidingPasturaSharedBackground()`（`.plain` 単体では capsule は消えない） |
| タップ動作 | `router.pop()`（`.claude/rules/navigation.md` 準拠） |
| アクセシビリティラベル | `String(localized: "Back")` → ja "戻る" |
| swipe-back gesture | `.preservesPasturaSwipeBackGesture()` View modifier 必須 |

**callsite テンプレート**:

```swift
.navigationBarBackButtonHidden(true)
.preservesPasturaSwipeBackGesture()
.toolbar {
  ToolbarItem(placement: .topBarLeading) { PasturaBackButton() }
  // ... 他の action items ...
}
```

**`.preservesPasturaSwipeBackGesture()` が必須な理由**: iOS 26 では `.navigationBarBackButtonHidden(true)` が `interactivePopGestureRecognizer` まで無効化する。view-level に `UIViewControllerRepresentable` の probe を mount し、host `UINavigationController` の gesture を再有効化（`viewControllers.count > 1` で gating）。詳細は `PasturaBackButton.swift` の doc-comment 参照。

**スコープ**: root NavigationStack に push されたビュー専用。sheet / fullScreenCover 内では `@Environment(\.dismiss)` を直接使うこと（`PasturaBackButton` は sheet を dismiss しない）。

**accessibility 既知の縮退**: システム back button は `"Back, button, <親ビュータイトル>"` を読み上げるが、PasturaBackButton は `"Back, button"` のみ（chevron-only 設計のため）。`.claude/rules/navigation.md` QA scenario 2 で明示的受容。

#### 5.8.2 PasturaToolbarButtonStyle

action item ボタン用の `ButtonStyle`。3 variant で Liquid Glass を opt-out しつつ、デザイン意図（Save / Delete / Share）を色に encode。

| Variant | 前景色 | 用途 | 例 |
|---------|--------|-----|-----|
| `.primary` | `Color.mossDark` (#6B7852, §2.3) | 確定・保存 | `ScenarioEditorView` の Save |
| `.destructive` | `Color.dangerInk` (#6F4540, §2.6) | 削除・破棄 | `ScenarioDetailView` の Delete |
| `.secondary` | `Color.ink` (#2D2E26, §2.2) | 補助アクション | `ResultDetailView` の Share/Film、`GalleryScenarioDetailView` の More menu |

**callsite テンプレート**:

```swift
ToolbarItem(placement: .primaryAction) {
  Button("Save") { ... }
    .buttonStyle(PasturaToolbarButtonStyle(variant: .primary))
}
```

押下時は `pressedOpacity` (0.6) で前景色を減光。capsule 背景・scale animation は付かない（§1 の「静的・観察される」voice を維持）。

**variant ↔ token mapping は `PasturaToolbarButtonStyleVariantTests` で pin** されており、不用意な token swap を CI で検知する。

#### 5.8.3 いつシステムを使い、いつカスタムを使うか

| シチュエーション | 選択 | 理由 |
|-----------------|------|------|
| root NavigationStack に push されたビューの toolbar | **カスタム** (`PasturaBackButton` + `PasturaToolbarButtonStyle`) | iOS 26 の Liquid Glass 衝突を回避 |
| Sheet / fullScreenCover 内の `NavigationStack` | システム標準 | sheet 内 NavigationStack は別 navigation context、現状 Liquid Glass の影響軽微（要観察） |
| `.confirmationDialog` / `.alert` のボタン | システム標準 | カスタム化 API なし（色は赤=`.destructive` か中立のみ）。**例外**: ボタンに意味的な配色（warning など）が要る確認だけ `.sheet` のカスタム確認ダイアログにする（§5.12） |

> **Note**: sheet 内 NavigationStack toolbar item の Liquid Glass 適用が visual problem になった場合、本サブセクションを更新して例外条件を明記すること。現時点では sheet 経路は scope 外。

### 5.9 Browse Card（`PasturaCard`）

ブラウズ系画面（Home / ScenarioDetail / Results / Shared Scenarios / Gallery / Settings）のカード。チャット/プロモのバブル（§5.2 / §5.4）とは別形式で、**影でなく罫線で面を定義**する。Source: `Pastura/Pastura/Views/Components/PasturaCard.swift`。

| 仕様項目 | 値 |
|---------|-----|
| 背景 | `bubbleBackground`（#FFFFFF） |
| 罫線 | `rule`（#E0DBCE）0.5pt ヘアライン。`.insetGrouped` は全周（`strokeBorder`）、`.grouped` は上下のみ |
| 角丸 | `.insetGrouped` 14pt（continuous） / `.grouped` なし（全幅バンド） |
| シャドウ | **なし**（§1「観察＝持ち上げない」。§4.3 の苔シャドウは Sim 画面で単一要素が浮く用途に限定） |
| 地（field） | `screenBackground`（#FCFAF4） |

`PasturaCardMetrics` がレイアウト定数（角丸 14 / ヘアライン 0.5 / チップ罫線 1 / 外側水平マージン 16 / カード間 18）を一元管理する。カード形式は `PasturaSectionStyle` で2種を選ぶ（命名は `UITableView.Style` / `ListStyle` に倣う）— `.insetGrouped`（角丸インセット枠・全周罫線、詳細画面の既定）と `.grouped`（左右マージン・角丸・側面罫線なしの全幅バンド＋上下ヘアライン、一覧画面）。全幅化のゼロ上書き（マージン / 角丸）は style 側に持たせ、`PasturaCardMetrics` の共有定数は正のまま保つ。複数行グループは1枚のカード内を `PasturaRowDivider`（`rule` ヘアライン、`.grouped` ではテキスト位置へ `leadingInset` で字下げ）で仕切る（iOS inset-grouped の構造を踏襲）。カードに「タップで push する行」を置く場合は `NavigationLink { 行 + 末尾 chevron } .buttonStyle(.plain)`（汎用行は `PasturaRowLabel` ＝ moss アイコン＋ink タイトル＋chevron＋全幅タップを利用）。

**ホスト選択**: ブラウズ系は**すべて** `ScrollView` + `PasturaCard` + `PasturaRowDivider` で統一する（#684）。一覧画面（Home / Shared Scenarios / Past Results / Settings）は `.grouped`（全幅バンド、#731）、詳細画面（ScenarioDetail / GalleryScenarioDetail）は `.insetGrouped`（角丸インセット）を使う — 「行のリスト＝全幅 / 内容のまとまり＝角丸」の線引き。一覧側で `.grouped` を採るのは、地のクリーム（#FCFAF4）と白カードの明度差が約2%しかなく、浮いた角丸枠が「箱が並ぶ」印象を与えていたため（#731）。Home も例外ではなく、シナリオ一覧は他画面と同一の `PasturaCard` グループカードで描く — `List` 上で同じ見た目を再現しようとすると角の描画や行間ヘアラインで破綻するため、機構ごと共通化した。一覧の見出し（セクションタイトル）と SharedScenarios のオフラインバナー / カテゴリチップは `.grouped` でも独立して画面端インセットを保つ（全幅化しない）。

- **Home のシナリオ削除** は `List` の `.onDelete` スワイプではなく**長押しコンテキストメニュー**（`.contextMenu` の destructive「削除」）＋ VoiceOver 用 `.accessibilityAction(named:)` で提供する。`List` を捨てたことでスワイプ削除は使えないが、Apple が List 外削除の代替として案内する方式（`swiftui-traps.md` 参照）。プリセット行は非削除なので contextMenu を付けない。
- **Editor（`.onMove`）** だけは並べ替えのため `Form` を維持し per-row 挙動を保つ。ドラッグ並べ替えを持つ画面が唯一の `List`/`Form` ホスト例外。
- **Past Results（観察履歴）の `PasturaSection` 見出しは日付バケット**（今日 / 今週 / 今月 / 過去は「M月 [YYYY年]」、P5）。同一ホスト上で各 run を時系列の独立行として描き、画面タイトル直下に総件数「N 回の記録」を中央寄せで添える（aggregate root のみ。push 詳細は単一セクション）。バケットの安定キーと表示ラベルの分離は `ResultsRowFormat`。

### 5.10 Primary Button（`PasturaPrimaryButtonStyle`）

ブラウズ系の主要 CTA（Gallery「Try this scenario」、Shared Scenarios の Retry 空/エラー状態）。Source: `Pastura/Pastura/Views/Components/PasturaPrimaryButtonStyle.swift`。

| 仕様項目 | 値 / 理由 |
|---------|----------|
| 塗り | `mossDark`（#6B7852）。白文字とのコントラスト ≈ 4.76:1（WCAG AA 達成）。base `moss`（#8A9A6C）の `.borderedProminent` は ≈ 3.0:1 で AA 未達のため不可 |
| 文字色 | 白（text-on-accent。§1「純白を避ける」は背景の話で、アクセント上の文字は対象外） |
| 角丸 | 12pt（14pt カードの内側で角が競合しないよう一段小さく） |
| 押下 | `pressedOpacity` 0.7 で減光。capsule 展開・scale アニメーションなし（§1 静的 voice） |

raw `.borderedProminent`（iOS 26 Liquid Glass capsule に opt-in する）は使わない。§5.8 の toolbar opt-out と同じ方針。fill↔token（`mossDark` / 白）は `PasturaPrimaryButtonStyleTests` で pin。

### 5.11 Navigation title display mode（large / inline）

各画面の `.navigationBarTitleDisplayMode` 規約。**タブ root（ボトムタブ4本の根）は常に `.inline`** — タブのタイトルは chrome なので静かに、縦スペースを割かない。タブ root 以外の push 画面は **タイトルが「主題の固有名」か「汎用ラベル」か** で判断 — 固有名は見出しとして読ませる価値があるので `.large`、汎用ラベルは chrome なので `.inline`。

| バケット | モード | 画面 |
|---------|-------|------|
| タブ root（4タブの根） | `.inline` | Home / Shared Scenarios / Past Results / Settings |
| 主題の固有名がタイトルの詳細 | `.large` | ScenarioDetail / GalleryScenarioDetail（シナリオ名） |
| エディタ / フォーム / 汎用ラベルの詳細 | `.inline` | ScenarioEditor / ResultDetail |

タブ root ルールは固有名/汎用ラベル軸を上書きする — Home のタイトル `"Pastura"` は固有名だが、タブ root なので `.inline`。4つのタブ root は各 View で明示的に `.inline` を指定する（`HomeView` / `SharedScenariosListView` / `ResultsView` / `SettingsView`）。`Shared Scenarios` / `Past Results` は push でも到達できる（③④で Home 経路が消えるまで）が、どちらも汎用ラベルなので push 版も `.inline` で一貫する。`.large` を明示指定しているのは固有名詳細の `ScenarioDetailView` と `GalleryScenarioDetailView`（どちらもシナリオ名が主題の固有名で、上の表どおり `.large`）。後者は明示しないと `.inline` の Search タブ root から `.inline` を継承してしまうため、明示が必須。SimulationView は GameHeader（§2.12）がタイトル行を所有する例外で、空タイトル + `.inline`。表示モードは toolbar の可視性 / back button / Liquid Glass opt-out（§5.8・navigation.md）とは直交。

### 5.12 Simulation control bar — 円形主操作ボタン & 確認シート

Sim 画面に限った2つの例外的コンポーネント。Source: `SimulationPlayButtonMetrics` / `SimulationLeaveSheet`（+`SimulationLeaveSheetTokens`）。両方の load-bearing token は `SimulationControlsTokenTests` で pin。

**再生/停止ボタン（円形主操作）**: フロストのコントロールバー（§4.3）上の主操作。`mossDark` 塗り 34pt 円＋白グリフ（14pt）。素のグリフ（ink）だとバー上で唯一の塗り要素が「黒い塊」として浮いて読めたため、明示的な主操作コントロールにした。**円自身に影は付けない** — バーが既に単一の浮遊要素（§1「観察＝持ち上げない」/ §4.3「Sim で単一要素のみ」）なので二重持ち上げを避ける。disabled は `disabledText` 塗り（disabled は §8 コントラスト対象外）。

**離脱確認シート（`SimulationLeaveSheet`）**: 実行中に戻る際の確認（keep-running 設定 OFF 時）。Pastura で唯一の独自確認ダイアログ — システム `.alert` の「全ボタン緑＝抑揚なし」を、`.sheet` で意味的な3段配色にする。主操作「一時停止して戻る」＝`PasturaPrimaryButtonStyle`（moss）、警戒「実行したまま戻る」＝§2.6 `warning`（琥珀、`warningSoft` 塗り＋`warningInk` 文字）、cancel「とどまる」＝中立（`inkSecondary`＋`rule`）。**警戒に `danger`（赤）を使わない** — 実行は継続・復帰可能で何も破壊しないため。赤は VoiceOver でも破壊操作として読み上げられ誤解を生む。`.confirmationDialog` は iOS 26 でポップオーバー誤アンカー（swiftui-traps）のため `.sheet`。ボタンは `lineLimit(nil)` で大きい Dynamic Type でも折り返す。

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

> **Note**: コピーは copy pass（`docs/specs/demo-replay-spec.md` §2 decision 13）で確定済み。`Localizable.xcstrings` に en ソース＋ja 翻訳として登録され、`PromoCard.slotCopy(_:)` が `String(localized:)` 経由で返す。**切替タイミング**は引き続き暫定で、独立タイマー（`docs/specs/demo-replay-ui.md` の PromoCard rotation セクション参照）で駆動され **DL 進捗とは無関係**。

| スロット | 切替タイミング（暫定） | en（ソース） | ja |
|---------|----------------------|-------------|-----|
| A | 0〜20 秒 | AI agents converse right inside your iPhone. | AIエージェントが、あなたのiPhoneの中で対話します |
| B | 20〜40 秒 | Just a moment. Meanwhile, watch how the other agents behave. | 少しだけお待ちください。その間、他のエージェントたちの様子をどうぞ |
| C | 40〜60 秒 | No ads, no sign-in. Pastura runs quietly on your device alone. | Pastura は広告もログインもなく、あなたの端末だけで静かに動きます |

（60 秒経過後は A に戻り、DL 完了まで無限循環。BG 復帰時は位置継続。interval `20s` は実装 PR で調整）

### 完了画面

- 主: `準備ができました`（draft）
- 副: `tap anywhere to begin`（英小文字・モノスペース、理由：「現実世界に戻る鍵穴」感）

> **Note**: 完了画面の「tap anywhere to begin」は **draft copy**。demo-replay-spec.md §2 decision 6 / §2 decision 8 に従い、実際の遷移は **auto のみ**（user tap 不要）。このテキストは視覚ヒントに留まるか、copy pass で削除・書き換えの対象（spec §2 decision 13）。

---

## 8. アクセシビリティ

- 本文の最小コントラスト比: 7:1（AAA）を目標に `--ink` と `--screen-bg` の組み合わせで達成
- **判読が要るメタ情報**（DL 進捗・ステータス等、確実に読ませる必要があるもの）は § 2.4 の L3 コントラストプリセット（`--meta-base` #4A4E3D ≈ 8:1）で 4.5:1 以上を確保する
- **`--muted`（#8A8A83）quietude 階層は意図的に sub-AA**（#FCFAF4 上で ≈ 3.3:1）。一覧キャプション（`provenance · N agents · N rounds`）・脚注・アンビエントなラベル（`DEMO中` など）に使う、§1 の「静謐・観察」を体現する控えめなティアで、上の 4.5:1 要件の対象外とする意図的な判断。これにより § 2.2（`--muted` をメタ情報・脚注に割り当て）と本節の整合を取る。判読が要る情報をこのティアに置かないこと（その場合は上の L3 プリセットへ）
- DL 進捗は `role="status" aria-live="polite"` / SwiftUI は `.accessibilityAddTraits(.updatesFrequently)`
- アバター・犬マークは `aria-hidden="true"` / `.accessibilityHidden(true)`（飾りだから）
- タップ領域は 44pt 未満の要素（THINKING トグル等）でも 44pt 確保。SwiftUI では `.padding(.vertical, N).contentShape(Rectangle()).onTapGesture{...}.padding(.vertical, -N)` の **negative-padding トリック**で、視覚上のサイズを変えずヒット判定だけ拡張する（`.contentShape(Rectangle())` 単独では view 自身の bounds までしか広がらない）
- Dynamic Type 非対応は割り切り。ただしトークン化して将来の対応に備える
- VoiceOver は画面全体で：フェーズ→発言順→プロモメタ→プロモ本文 の読み上げ順を維持

---

## 9. 他画面への展開ガイド

このシステムを他画面に使う際のチェックリスト：

- [ ] 背景は必ず `--screen-bg`（#FCFAF4）から始める。ブラウズ系（一覧・詳細・設定）では `screenBackground` を地（field）として敷き、その上にカードを置く（§5.9）。全面コンテンツ画面（Sim / DL）は `screenBackground` をそのまま本体背景に使う
- [ ] アクセント色は `--moss` の1色のみ。2色目が欲しくなったら「構成を減らす」方を検討
- [ ] **カード形式は2種を使い分ける**：チャット/プロモのバブルは**角丸 14pt + 白背景 + 左ボーダー3pt moss + 苔シャドウ**（§5.2 / §5.4）。ブラウズ系のカードは**白背景 + `rule` 0.5pt ヘアライン・影なし**（`PasturaCard`、§5.9）で、`PasturaSectionStyle` により一覧は `.grouped`（全幅・角丸なし・上下罫線のみ）、詳細は `.insetGrouped`（角丸14pt・全周罫線）を使い分ける。ブラウズ系は「観察＝持ち上げない」voice に沿って影でなく罫線で面を定義する
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

# DL-time Demo Replay — UI Spec

> **Status:** Draft (visual / behaviour spec; VM contract, playback
> state machine, and data flow live in companion docs — see below)
> **Date:** 2026-04-20

## Companion docs

- [`docs/specs/demo-replay-spec.md`](demo-replay-spec.md) — data format,
  `ReplayViewModel` architecture, playback state machine, content-filter
  policy.
- [`docs/decisions/ADR-007.md`](../decisions/ADR-007.md) — iOS lifecycle
  branching (scenePhase transitions, BG/FG pause/resume, download-complete
  hand-off, DL-failure, mobile-data confirmation flow).
- [`docs/design/design-system.md`](../design/design-system.md) — cross-
  screen design tokens (colour / typography / spacing / motion). Every
  token referenced in this doc is defined there.
- [`docs/design/demo-replay-reference.html`](../design/demo-replay-reference.html)
  — interactive visual prototype (4 storyboard frames side-by-side).
- [`docs/specs/demo-replay-mockup-prompt.md`](demo-replay-mockup-prompt.md)
  — Claude Design prompt used to generate the HTML reference; useful as a
  starting point for future per-screen visual exploration.

## Responsibility boundary

This UI spec owns **visual layout, animation timings, and non-state-
machine interactions** (e.g., THINKING toggle, SheepAvatar geometry).
Where prose here implies state-machine behaviour or lifecycle branching,
the companion docs are authoritative — they are cited inline at each
such point.

- **`demo-replay-spec.md` §4 is authoritative** for the `ReplayViewModel`
  contract, the playback state machine
  (`.idle` / `.playing` / `.paused` / `.transitioning`), content-filter
  policy, and the event stream shape.
- **ADR-007 §3 is authoritative** for iOS lifecycle branching
  (scenePhase, BG/FG pause/resume, DL-complete hand-off, DL-failure,
  mobile-data confirmation flow).

### Three independent progress-like concerns on the same screen

The DL-time screen surfaces three progress-like elements with different
drivers. Conflating them was the original source of ambiguity between an
earlier draft of this doc and `demo-replay-spec.md`; the separation below
is load-bearing.

| Element | Driven by | Notes |
|---------|-----------|-------|
| 8-dot DL progress indicator (PromoCard top row) | DL progress (`ModelManager.progress`) | Genuine progress bar; monotonic |
| Slot A/B/C copy rotation (PromoCard body) | Independent timer, **~20 s / slot, provisional** (infinite cycle `A → B → C → A → …`) | **Orthogonal to DL progress.** Pauses on background, resumes from the same slot position. Final interval tuned during implementation PR |
| Frame 4 completion overlay | DL-complete signal (`ModelManager.progress ≥ 1.0`) | Fires once; auto-transitions per spec §2 decision 8 — no user tap required (spec §2 decision 6 excludes user-triggered transitions) |

The replayed chat stream (bubbles, THINKING, voting) is **entirely
independent of DL progress**: demos play through at 2× speed
(spec §2 decision 5), loop to the next bundled demo at end-of-stream, and
keep cycling until the DL-complete signal fires (spec §4.9).

---

## Overview

Pastura（AIエージェント同士の会話を眺めるアプリ）の **AIモデルダウンロード中に表示されるデモ再生画面** の実装ハンドオフです。

ユーザーが初回起動後、ローカルLLMモデル（数GB）のダウンロード待機中に、**事前録画されたエージェント同士の会話デモ**をチャットUI風に再生することで、「この後こういう体験ができますよ」を静かに予感させる画面です。

---

## Design Reference

`docs/design/demo-replay-reference.html` は **デザインリファレンス** です。本番コードとしてそのまま使うものではなく、意図したルック・アニメーション・情報設計を示すプロトタイプです。

開発者のタスクは、**既存の Swift/SwiftUI プロジェクトのアーキテクチャとコンポーネントに合わせてこのデザインを再現すること** です。以下の形式を推奨します：

- **SwiftUI** （iOS 17+ 想定 — 最新の CLAUDE.md に従う）
- カラーは Asset Catalog に色トークンとして定義
- タイポグラフィは `Font` の extension として集約
- アバター・アシスタントマークは SwiftUI `Shape` / `Path` もしくは SF Symbols で代用可

HTML/CSS/JS をそのまま移植せず、**SwiftUI のイディオム**（`VStack`, `HStack`, `ZStack`, `overlay`, `.background`, `GeometryReader` など）で構築してください。

## Fidelity

**High-fidelity (hifi)**。カラー・余白・タイポグラフィ・角丸・アニメーションまで最終仕様です。ピクセル単位ではなく**論理ポイント単位**で再現してください（390×844 = iPhone 15 系の論理サイズ）。

---

## Screens / Views

本画面は **1 つのルートビュー (`ModelDownloadDemoView`)** が以下 3 つの独立した入力源を合成して表示します:

- `ReplayViewModel` が吐く `AgentOutputRow` イベント列（spec §4.2 / §4.7）— チャットストリーム本体
- DL 進捗（`ModelManager.progress`）— PromoCard の 8-dot インジケータと Frame 4 オーバーレイを駆動
- Slot A/B/C rotation 用の独立タイマー（〜20 秒 / slot、暫定値）— PromoCard 本文のコピー切替

以下の Frame 1-3 は **1 本の録画デモが再生されていく中の視覚的段階** を示すもので、**DL 進捗に連動した画面遷移ではありません**（spec §4.7 — レンダーは VM が吐くイベントに追従します）。Frame 4 のみ DL 完了シグナル（`ModelManager.progress ≥ 1.0`）で駆動され、spec §4.9 の `.transitioning` 状態に対応します。

### Frame 1 — デモ再生序盤（録画最初の発話）
- **状態**: Alice の第一声のみ表示、他のエージェントは未表示
- **PromoCard**: 起動時は Slot A 表示（独立タイマー駆動で 〜20 秒後に B へ、DL 進捗とは無関係）

### Frame 2 — デモ序盤の全員発話
- **状態**: Alice, Bob, Carol, Dave の 4 発言が順次フェードイン（各 180ms ディレイ）。Dave にのみ "THINKING"（内なる思考）を展開
- **PromoCard**: Slot A / B / C のいずれか（経過時間次第、DL 進捗とは無関係）

### Frame 3 — デモ中盤の投票フェーズ
- **状態**: フェーズラベルが「投票」に切替。3 人が Dave に投票。各投票バブルに `→ Dave` のハイライトと `REASON`（理由）を添付
- **PromoCard**: Slot A / B / C のいずれか（同上）

### Frame 4 — DL 完了・遷移
- **トリガー**: DL 完了シグナル（`ModelManager.progress ≥ 1.0`）。spec §4.9 `.transitioning` 状態に対応
- **状態**: 既存のチャットストリームが `opacity:.12 + blur(1px)` にフェードアウト（1.6s）。中央にアシスタントマーク（犬 / コリー）がパルスアニメーションで出現し、「準備ができました」のコピーが浮かぶ。2.4s で完全に切り替わる（auto-transition; spec §2 decision 8 — ユーザー操作不要）
- **PromoCard**: 非表示

---

## Detailed Layout Spec（SwiftUI換算）

### 全体構造

```
ZStack(alignment: .top) {
  Color("PasturaScreenBG")           // #fcfaf4
  VStack(spacing: 0) {
    PhaseHeader()                     // 上部フェーズ帯
    ChatStream()                      // スクロール可能な会話ログ
    Spacer()
  }
  PromoCard()                         // bottom: 22pt / leading: 14pt / trailing: 14pt
  DLCompleteOverlay()                 // Frame 4 で opacity 0→1
}
```

### PhaseHeader

- padding: `10pt vertical, 20pt horizontal`
- 左：6pt の菱形（`.rotationEffect(.degrees(45))`、色 `#8a9a6c`、opacity 0.7）
- 左テキスト上段: `WORD WOLF` — サイズ 9.5pt / モノスペース / `letterSpacing 0.22em` / 色 `#6f7359` / weight: semibold / UPPERCASE
- 左テキスト下段: フェーズ名（例「発言ラウンド 1」） — サイズ 13pt / 色 `#2d2e26` / weight: semibold
- 右: `DEMO中` — サイズ 10pt / モノスペース / 色 `#7b7d68`
- 背景: 画面背景を78%に薄めた色 + `.background(.ultraThinMaterial)` 近似（`saturate(1.05) blur(8px)`）
- 下線: 1pt / `rgba(60,62,48,0.07)`

### ChatStream（Frame 1/2/3）

- padding: `top 8pt, horizontal 20pt, bottom 16pt`
- バブル間の spacing: 14pt
- 各バブルは **横並び HStack** ：
  - アバター（42pt 丸、色はキャラごと、下記）
  - 縦 VStack：
    - 名前ラベル（10.5pt / `#7a7e68` / letterSpacing 0.04em）
    - 発言バブル（下記）
    - THINKING 折りたたみ or 展開

#### 発言バブル
- padding: `8pt vertical, 12pt horizontal`
- 背景: `#ffffff`
- ボーダー: 1pt / `rgba(90,90,70,0.07)`
- 角丸: **上左 4pt、他 14pt**（`UnevenRoundedRectangle` または `.clipShape(CustomShape())`）
- フォント: 13pt / 色 `#2d2e26` / line-height 1.65

#### THINKING（内なる思考）
- 折りたたみ時: `▸ THINKING` のみ（8.5pt / モノスペース / `#b1ac92` / letterSpacing 0.22em）
- 展開時: 左に1.5pt縦線（`#d4cba8`）、本文は 10.5pt / `#8a876f` / italic / line-height 1.7
- タップでトグル（実装推奨）

#### アバター
- 42pt 丸。「羊」シルエット（SVGで実装済み、詳細は HTML 参照）
- キャラごとの色違い（顔まわり）：
  - Alice: `#f2e3c8`（クリーム）
  - Bob: `#d9e2c6`（セージ）
  - Carol: `#ebd4d4`（ピンク）
  - Dave: `#d0d7dc`（スレート）
- SwiftUI 実装は `ZStack` で丸 + カスタム `Shape` による耳・顔輪郭でOK

### PromoCard（Frame 1/2/3）

- 位置: bottom 22pt, leading/trailing 14pt
- 背景: `#fbfaf2` / ボーダー 1pt `#e4e7d2` / **左ボーダー 3pt `#8a9a6c`**（アクセント）
- 角丸: 14pt
- シャドウ: `0 1 2 rgba(90,100,60,0.04), 0 12 26 rgba(90,100,60,0.2)`（複数レイヤー）

**構造（VStack, spacing: 0）**:

```
VStack(alignment: .leading, spacing: 0) {
  // promo-head
  PromoMeta()                     // padding: 8pt/14pt/7pt
  // promo-body-row
  HStack(alignment: .top, spacing: 12pt) {
    AssistantMarkDogSide()        // 26pt, 犬の横顔（SVG）
    Text(promoCopy)               // 12pt / 1.65 line-height / #2d2e26
  }.padding(.horizontal, 14).padding(.bottom, 13).padding(.top, 11)
}
```

#### PromoMeta（DL進捗表示）

- レイアウト: 縦 2行、アクセシビリティ `accessibilityElement(children: .combine)` + `.accessibilityAddTraits(.updatesFrequently)`
- **1行目** (HStack, spacing: 6pt)：
  - `DL` — 9pt / モノスペース / semibold / letterSpacing 0.06em / `#4a4e3d`
  - 8個のドット（4pt 丸、spacing 2.5pt）：塗り進捗は `round(pct/100*8)` 個
    - 未点灯: `rgba(90,100,60,0.38)`
    - 点灯: `#6b7852`
  - パーセント (例 `35%`) — 9pt / モノスペース / `#4a4e3d`
  - セパレータ `·` — 9pt / `#a6a48f` / margin 2pt
  - サイズ `1.0 GB / 3.0 GB` — 9pt / モノスペース / `#4a4e3d`
- **2行目**：
  - `残り約4分` — 10pt / モノスペース / weight: medium / `#2d2e26` / padding-leading 2pt
  - 1分未満: 「まもなく」 / pct >= 100: 非表示

**GBフォーマット**: 常に小数1桁固定、単位前にスペース：`0.2 GB / 3.0 GB`（総量は 3.0GB 固定、DL済み = pct/100 × 3）

**残り時間表記**:
```swift
func formatETA(_ minutes: Int) -> String {
    minutes <= 0 ? "まもなく" : "残り約\(minutes)分"
}
```

### AssistantMarkDogSide

- 26pt 四方のベクター。犬（コリー）の横顔
- ベースは白抜き（`#ffffff`）、輪郭・耳・目・鼻は `#3d4030`、尾の巻きやアクセントは `#8a9a6c`
- SVG は `../design/demo-replay-reference.html` 内の `DOG_SIDE` 定数を参照。SwiftUI へは `Path` 起こし、もしくは `Image(systemName:)` の代用に留めるなら `dog.fill` では表現力不足なので**カスタム SF Symbol または SwiftUI Path 実装を強く推奨**

### DLCompleteOverlay（Frame 4）

- フルスクリーン overlay
- 中央 VStack：
  - 44pt の犬マーク（2.4s ループで scale 1.0 ↔ 1.06 パルス）
  - `準備ができました` — 16pt / weight: medium / letterSpacing 0.22em / `#3d4030`
  - 8pt gap
  - `tap anywhere to begin` — 11pt / モノスペース / `#8a8b76` / letterSpacing 0.1em（**draft** — spec §2 decision 13 で final wording は copy pass 決定。spec §2 decision 6 に従い実際のタップ遷移は実装しない — auto-transition のみ、このテキストは視覚的ヒントに留まる / copy pass で削除される可能性あり）
- フェードイン: `animation(.easeOut(duration: 2.4).delay(0.2), value: isCompleted)`

---

## Interactions & Behavior

### VM ownership / host view split

このスクリーンのチャットストリーム、デモループ、BG/FG pause/resume は **`ReplayViewModel` が所有** します（spec §4.2 / §4.9 が権威）。UI 層の責務は VM が `@Observable` で露出する state を受け取り、`Views/Components/AgentOutputRow` に流し込むだけです。`ModelDownloadDemoView` 自身は DL 進捗（`ModelManager.progress` / `ModelManager.state`）を観察して、以下の **装飾クローム 3 点** を駆動します:

1. PromoCard 上部の 8-dot インジケータ（`progress` に追従）
2. Frame 4 完了オーバーレイ（`progress ≥ 1.0` でフェードイン、spec §4.9 の `.transitioning` 状態に対応）
3. PromoCard 本文の Slot A/B/C rotation（**DL 進捗とは独立のタイマー駆動**、下記）

チャット内容を DL 進捗で gate する処理は UI 側には置きません。再生順・ループ挙動は spec §4.9 の state machine が権威です。

### PromoCard のコピー rotation（Slot A/B/C）

独立タイマー駆動で `A → B → C → A → …` と循環します。DL 進捗とも `ReplayViewModel` とも独立（`ModelDownloadDemoView` が所有するローカル state）。

- **Interval**: 〜20 秒 / slot（**暫定値**。実装 PR で調整予定）
- **Cycle**: 無限循環（DL 完了時は Frame 4 オーバーレイが PromoCard をフェードアウトで覆うため、rotation 側から停止する必要は無い）
- **BG 復帰時の挙動**: 位置継続（経過時間を保持して再開。spec §4.9 chat stream の pause/resume と同じ考え方）
- **Wording**: 各 slot の日本語コピー draft は `docs/design/design-system.md` §7 参照。spec §2 decision 13 に従い final wording は実装 PR の copy pass で確定

### アニメーション仕様

| 要素 | Duration | Easing | Delay |
|------|----------|--------|-------|
| バブル fade-in | 700ms | ease-out | 0 / 180 / 360 / 540ms |
| DL ドット点灯遷移 | 600ms | cubic-bezier(.4,0,.2,1) | — |
| Slot A/B/C 切替 cross-fade | 400ms | ease-in-out | — |
| Frame 4 ストリームフェード | 1600ms | ease-out | 0 |
| Frame 4 完了オーバーレイ | 2400ms | ease-out | 200ms |
| Frame 4 マークパルス | 2400ms loop | ease-in-out | 400ms |
| 完了タイトル fade-up | 1400ms | ease-out | 700ms |
| 完了サブテキスト fade-up | 1400ms | ease-out | 1050ms |

### 操作

- **THINKING タップ**: 展開/折りたたみトグル（状態はビューローカル `@State` で保持）
- **DL 完了後の振る舞い**: spec §2 decision 8 に従い **自動遷移**（spec §2 decision 6 で user-triggered transition は MVP スコープ外）。Frame 4 のアニメーション（2.4s）完了後、host view が VM をアンマウント — 「tap anywhere to begin」等のユーザー操作に依存する遷移は **実装しない**
- **BG / FG 遷移時の挙動**: spec §4.9 の `.paused` / `.playing` 遷移と ADR-007 §3.3 ケース (a) が権威。UI 側は `@Environment(\.scenePhase)` を VM に forward するのみ

---

## State Management

State ownership is deliberately split across three independent concerns:

| Concern | Owner | Source |
|---------|-------|--------|
| Playback / chat stream / loop / BG-FG pause-resume | `ReplayViewModel` | spec §4.2 / §4.9 — authoritative |
| DL progress (drives 8-dot indicator, Frame 4 trigger, `downloadedGB` / `totalGB` / ETA display) | `ModelManager.progress` / `ModelManager.state` | Observed directly by `ModelDownloadDemoView` |
| Slot A/B/C rotation timer | `ModelDownloadDemoView` local `@State` | UI-local; see [PromoCard のコピー rotation](#promocard-のコピー-rotation-slot-abc) above |

Do **not** introduce a top-level state class that combines chat rendering with DL progress. An earlier draft of this doc described such a `ModelDownloadState { phase: DemoPhase }` with progress-gated chat reveal — that pattern contradicts spec §4.2 / §4.7 and is explicitly out of scope. Chat content is driven by the `ReplayViewModel` event stream, not by DL progress.

### Display-only helpers on the host view

The following computed values are safe to derive directly on the host view from `ModelManager` state (no separate state class needed):

```swift
// Illustrative — final shape decided at implementation PR.
// downloadedGB / totalGB / etaMinutes are pure display helpers on
// `ModelManager`-observed values; they do not constitute playback state.
func downloadedGB(from progress: Double, totalBytes: Int64) -> Double {
    Double(totalBytes) * progress / 1_000_000_000
}
func etaMinutes(from seconds: Int?) -> Int? {
    seconds.map { max(0, Int(($0 + 59) / 60)) }
}
```

---

## Design Tokens（Swift実装用）

> **Canonical source**: `docs/design/design-system.md` のカラートークン / タイポグラフィ / スペーシング / レイアウト セクション。以下の Swift スケッチは **そのミラー** であり、齟齬があれば design-system.md を優先（cross-screen 利用前提なので tokens 定義は design-system.md で一元管理）。

`Theme.swift` または `DesignTokens.swift` に集約推奨：

```swift
extension Color {
    // Backgrounds
    static let pasturaPage       = Color(hex: 0xF3EFE7)   // 親ページ（参考）
    static let pasturaScreenBG   = Color(hex: 0xFCFAF4)   // スクリーン本体（crisp）
    static let pasturaBubbleBG   = Color.white
    static let pasturaPromoBG    = Color(hex: 0xFBFAF2)
    static let pasturaPromoBorder = Color(hex: 0xE4E7D2)
    
    // Ink
    static let pasturaInk        = Color(hex: 0x2D2E26)   // 本文
    static let pasturaInk2       = Color(hex: 0x5A5A55)   // サブ
    static let pasturaMuted      = Color(hex: 0x8A8A83)
    
    // Accent（苔緑 / Moss）
    static let pasturaMoss       = Color(hex: 0x8A9A6C)   // リーフ / 左ボーダー
    static let pasturaMossDark   = Color(hex: 0x6B7852)   // ドット点灯（L3コントラスト）
    static let pasturaMossInk    = Color(hex: 0x3D4030)   // 犬輪郭・完了タイトル
    
    // Meta (L3 default)
    static let metaBase          = Color(hex: 0x4A4E3D)
    static let metaStrong        = Color(hex: 0x2D2E26)
    static let metaSep           = Color(hex: 0xA6A48F)
    static let metaDotOff        = Color(hex: 0x5A6428).opacity(0.38)
    static let metaDotOn         = Color(hex: 0x6B7852)
    
    // Avatars (sheep)
    static let sheepCream        = Color(hex: 0xF2E3C8)   // Alice
    static let sheepSage         = Color(hex: 0xD9E2C6)   // Bob
    static let sheepPink         = Color(hex: 0xEBD4D4)   // Carol
    static let sheepSlate        = Color(hex: 0xD0D7DC)   // Dave
}

extension Font {
    static let pasturaPhaseTag     = Font.system(size: 9.5, weight: .semibold, design: .monospaced)
    static let pasturaPhaseTitle   = Font.system(size: 13, weight: .semibold)
    static let pasturaBubbleBody   = Font.system(size: 13, weight: .regular)
    static let pasturaBubbleName   = Font.system(size: 10.5, weight: .regular)
    static let pasturaThinking     = Font.system(size: 10.5, weight: .regular).italic()
    static let pasturaThinkingTag  = Font.system(size: 8.5, weight: .regular, design: .monospaced)
    static let pasturaPromoText    = Font.system(size: 12, weight: .regular)
    static let pasturaMeta         = Font.system(size: 9, weight: .regular, design: .monospaced)
    static let pasturaMetaLabel    = Font.system(size: 9, weight: .semibold, design: .monospaced)
    static let pasturaMetaETA      = Font.system(size: 10, weight: .medium, design: .monospaced)
    static let pasturaCompleteTitle = Font.system(size: 16, weight: .medium)
    static let pasturaCompleteSub   = Font.system(size: 11, weight: .regular, design: .monospaced)
}

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 14
    static let xl: CGFloat = 20
}

enum Radius {
    static let bubble: CGFloat = 14     // 通常角
    static let bubbleTip: CGFloat = 4   // 発言バブル 上左
    static let promo: CGFloat = 14
    static let phoneInner: CGFloat = 31
}
```

### 推奨フォント

- **日本語**: `Noto Sans JP`（Google Fonts から Variable Font を埋め込み）。未埋め込みならシステムの `HiraKakuProN` で代替可
- **モノスペース**: `SF Mono` or `JetBrains Mono`

---

## Assets

本デザインで必要なアセット：

| アセット | 形式 | 備考 |
|---------|------|------|
| 犬（横顔） | Vector / SF Symbol | `../design/demo-replay-reference.html` の `DOG_SIDE` SVG を SwiftUI `Path` に変換 |
| 羊アバター（4色） | Vector | 同 HTML 内の `SHEEP()` 関数のSVG。色違いで4バリエーション |
| 葉（phase-l の菱形） | `RoundedRectangle` + rotation | SVG不要、SwiftUI で生成可 |

**ブランドカラーやロゴ**: Pastura のロゴは別途入手してください（本デザインでは未使用）。

---

## Related files

この spec は 3 層ドキュメントの一部です。正式な一覧はファイル冒頭の [Companion docs](#companion-docs) セクションを参照してください。従来の「1 つのバンドルに兄弟ファイルとして同梱」というフレーミングは本 split 以降適用されません（`docs/design/` と `docs/specs/` に分かれて配置）。

---

## Implementation Checklist

開発者向け：

- [ ] `DesignTokens.swift`（または `Theme.swift`）にカラー / フォント / スペーシングを定義。canonical tokens は `docs/design/design-system.md` §2-§4（カラートークン / タイポグラフィ / スペーシング / レイアウト）に従う — このファイルの上記 Swift スケッチはそのミラーであり、齟齬があれば design-system.md 優先
- [ ] `ModelDownloadDemoView` (host view) を実装: `ReplayViewModel` をホストし、`ModelManager.progress` を観察して 8-dot + Frame 4 を駆動、Slot rotation タイマーをローカル `@State` で所有、`@Environment(\.scenePhase)` を VM に forward（spec §4 / ADR-007 §3 に従う）
- [ ] `PhaseHeader`, `ChatBubble`, `ThinkingBlock`, `PromoCard`, `PromoMeta`, `AssistantMark`, `SheepAvatar` コンポーネントを分割実装
- [ ] `DOG_SIDE` SVG を SwiftUI `Path` に変換（犬の横顔）
- [ ] `SHEEP()` SVG を SwiftUI `Path` に変換（羊の顔、色パラメータ化）
- [ ] チャットバブルのフェードインアニメーション（各 180ms ずらし）
- [ ] DL ドット点灯トランジション（progress 変化時の 600ms ease）
- [ ] Slot A/B/C rotation: 〜20 秒 / slot の独立タイマー + 400ms cross-fade 切替。interval は実装時に調整
- [ ] Frame 4 の多段アニメーション（ストリームフェード + マークパルス + コピー段階表示）。自動遷移、ユーザー操作不要（spec §2 decision 8）
- [ ] アクセシビリティ: `PromoMeta` に `accessibilityLabel("ダウンロード \(pct)% \(downloaded) / \(total)、\(eta)")` + `.accessibilityAddTraits(.updatesFrequently)`
- [ ] THINKING 展開/折りたたみをタップで切替（状態はビューローカル）
- [ ] VoiceOver で読み上げ順を検証
- [ ] Dynamic Type 非対応（デザイン固定サイズ想定）。`.font(.pasturaBubbleBody)` など extension で統一しておくと、将来の Dynamic Type 対応が容易

---

## Notes for Reviewer

- **配色のコントラスト**: 本デザインは WCAG AA 余裕ありのレベル（L3）を採用済み。より高いコントラストが求められる場面（強い日光下など）のため、`[data-contrast="L4"]` の色を Asset Catalog に `"MetaBase-HighContrast"` 系として用意しておくと、将来の「増強コントラスト」対応がスムーズです
- **ローカライズ**: 現状 ja-JP 固定。en 対応時は「残り約4分」→「~4 min left」、「準備ができました」→「Ready」など、コピー全体の再設計が必要です（単純翻訳では冗長）
- **音声**: デモ再生は無音想定。効果音やハプティクスは未定義です
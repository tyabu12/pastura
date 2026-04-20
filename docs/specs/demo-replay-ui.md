# Handoff: Pastura DL中デモ再生画面

## Overview

Pastura（AIエージェント同士の会話を眺めるアプリ）の **AIモデルダウンロード中に表示されるデモ再生画面** の実装ハンドオフです。

ユーザーが初回起動後、ローカルLLMモデル（数GB）のダウンロード待機中に、**事前録画されたエージェント同士の会話デモ**をチャットUI風に再生することで、「この後こういう体験ができますよ」を静かに予感させる画面です。

---

## About the Design Files

このバンドルに含まれる `design_reference.html` は **デザインリファレンス** です。本番コードとしてそのまま使うものではなく、意図したルック・アニメーション・情報設計を示すプロトタイプです。

開発者のタスクは、**既存の Swift/SwiftUI プロジェクトのアーキテクチャとコンポーネントに合わせてこのデザインを再現すること** です。以下の形式を推奨します：

- **SwiftUI** （iOS 16+ 想定）
- カラーは Asset Catalog に色トークンとして定義
- タイポグラフィは `Font` の extension として集約
- アバター・アシスタントマークは SwiftUI `Shape` / `Path` もしくは SF Symbols で代用可

HTML/CSS/JS をそのまま移植せず、**SwiftUI のイディオム**（`VStack`, `HStack`, `ZStack`, `overlay`, `.background`, `GeometryReader` など）で構築してください。

## Fidelity

**High-fidelity (hifi)**。カラー・余白・タイポグラフィ・角丸・アニメーションまで最終仕様です。ピクセル単位ではなく**論理ポイント単位**で再現してください（390×844 = iPhone 15 系の論理サイズ）。

---

## Screens / Views

本画面は **単一の画面で4フレームの時系列を表現** します。実装時は1つのルートビュー（`ModelDownloadDemoView`）がDL進捗に応じて中身を遷移させる形になります。

### Frame 1 — DL開始直後（0〜10%）
- **状態**: Alice の第一声のみ表示、他のエージェントは未表示
- **プロモ**: `A` 文章を表示（「AIエージェントが、あなたのiPhoneの中で対話します」）

### Frame 2 — 全員発話完了（10〜50%）
- **状態**: Alice, Bob, Carol, Dave の4発言が順次フェードイン（各 180ms ディレイ）。Dave にのみ "THINKING"（内なる思考）を展開
- **プロモ**: `B` 文章（「少しだけお待ちください。その間、他のエージェントたちの様子をどうぞ」）

### Frame 3 — 投票フェーズ（50〜90%）
- **状態**: フェーズラベルが「投票」に切替。3人がDave に投票。各投票バブルに `→ Dave` のハイライトと `REASON`（理由）を添付
- **プロモ**: `C` 文章（「このアプリは広告もログインもなく、あなたの端末だけで静かに動きます」）

### Frame 4 — DL完了・遷移（100%）
- **状態**: 既存のチャットストリームが `opacity:.12 + blur(1px)` にフェードアウト（1.6s）。中央に種/アシスタントマークがパルスアニメーションで出現し、「準備ができました」のコピーが浮かぶ。2.4s で完全に切り替わる
- **プロモ**: 非表示（DL完了後はメタ情報不要）

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
- SVG は `design_reference.html` 内の `DOG_SIDE` 定数を参照。SwiftUI へは `Path` 起こし、もしくは `Image(systemName:)` の代用に留めるなら `dog.fill` では表現力不足なので**カスタム SF Symbol または SwiftUI Path 実装を強く推奨**

### DLCompleteOverlay（Frame 4）

- フルスクリーン overlay
- 中央 VStack：
  - 44pt の犬マーク（2.4s ループで scale 1.0 ↔ 1.06 パルス）
  - `準備ができました` — 16pt / weight: medium / letterSpacing 0.22em / `#3d4030`
  - 8pt gap
  - `tap anywhere to begin` — 11pt / モノスペース / `#8a8b76` / letterSpacing 0.1em
- フェードイン: `animation(.easeOut(duration: 2.4).delay(0.2), value: isCompleted)`

---

## Interactions & Behavior

### DL進捗バインディング

`ModelDownloadDemoView` は以下を観察します：

```swift
@Observable final class ModelDownloadState {
    var progress: Double        // 0.0 ... 1.0
    var totalBytes: Int64       // 3_000_000_000 (3GB)
    var etaSeconds: Int?        // nil = 計算中
    var phase: DemoPhase        // .round1, .voting, .complete
}
```

- **progress** が 0.5 を超えたら phase を `.voting` に遷移
- **progress** が 1.0 に達したら phase を `.complete` にし、Frame 4 オーバーレイをフェードイン
- **progress** の変化は `.animation(.easeInOut(duration: 0.6), value: progress)`（ドットの点灯遷移）

### フェーズ毎のチャット表示

```swift
switch state.phase {
case .round1: ChatStreamRound1(showAllBubbles: state.progress > 0.1)
case .voting: VotingStream()
case .complete: ChatStreamRound1(showAllBubbles: true).opacity(isRevealing ? 0.12 : 1)
}
```

### アニメーション仕様

| 要素 | Duration | Easing | Delay |
|------|----------|--------|-------|
| バブル fade-in | 700ms | ease-out | 0 / 180 / 360 / 540ms |
| DL ドット点灯遷移 | 600ms | cubic-bezier(.4,0,.2,1) | — |
| Frame 4 ストリームフェード | 1600ms | ease-out | 0 |
| Frame 4 完了オーバーレイ | 2400ms | ease-out | 200ms |
| Frame 4 マークパルス | 2400ms loop | ease-in-out | 400ms |
| 完了タイトル fade-up | 1400ms | ease-out | 700ms |
| 完了サブテキスト fade-up | 1400ms | ease-out | 1050ms |

### 操作

- **THINKINGタップ**: 展開/折りたたみトグル（状態はビューローカルで保持）
- **DL完了後のタップ**: 親の `onBegin()` クロージャを呼び出してデモ画面を閉じる
- **バックグラウンド復帰時**: DL進捗は最新の値に同期（Combine / `Observation` で自動）

---

## State Management

```swift
@Observable final class ModelDownloadState {
    enum Phase: Hashable { case round1, voting, complete }
    var progress: Double = 0
    var totalBytes: Int64 = 3_000_000_000
    var etaSeconds: Int?
    var phase: Phase = .round1
    
    var currentPromoSlot: PromoSlot {
        switch progress {
        case ..<0.2: .A
        case ..<0.5: .B
        case ..<1.0: .C
        default: .none
        }
    }
    
    var downloadedGB: Double { Double(totalBytes) * progress / 1_000_000_000 }
    var totalGB: Double { Double(totalBytes) / 1_000_000_000 }
    var etaMinutes: Int? { etaSeconds.map { max(0, Int(($0 + 59) / 60)) } }
}
```

---

## Design Tokens（Swift実装用）

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
| 犬（横顔） | Vector / SF Symbol | `design_reference.html` の `DOG_SIDE` SVG を SwiftUI `Path` に変換 |
| 羊アバター（4色） | Vector | 同 HTML 内の `SHEEP()` 関数のSVG。色違いで4バリエーション |
| 葉（phase-l の菱形） | `RoundedRectangle` + rotation | SVG不要、SwiftUI で生成可 |

**ブランドカラーやロゴ**: Pastura のロゴは別途入手してください（本デザインでは未使用）。

---

## Files

- `design_reference.html` — 完全なインタラクティブプロトタイプ。ブラウザで開くと全4フレームが並列表示される
- `DESIGN_SYSTEM.md` — デザインシステム（色・タイポ・トーン・再利用プロンプト）。他画面への展開・今後の Claude 向けプロンプトとしても使用可
- `README.md` — 本書

---

## Implementation Checklist

開発者向け：

- [ ] `DesignTokens.swift` に上記カラー/フォント/スペーシングを定義
- [ ] `ModelDownloadState`（Observable）を実装し、実際の `URLSession.downloadTask` から progress/etaSeconds を更新
- [ ] `PhaseHeader`, `ChatBubble`, `ThinkingBlock`, `PromoCard`, `PromoMeta`, `AssistantMark`, `SheepAvatar` コンポーネントを分割実装
- [ ] `DOG_SIDE` SVG を SwiftUI `Path` に変換（犬の横顔）
- [ ] `SHEEP()` SVG を SwiftUI `Path` に変換（羊の顔、色パラメータ化）
- [ ] チャットバブルのフェードインアニメーション（各180ms ずらし）
- [ ] DLドット点灯トランジション（progress変化時の 600ms ease）
- [ ] Frame 4 の多段アニメーション（ストリームフェード + マークパルス + コピー段階表示）
- [ ] アクセシビリティ: `PromoMeta` に `accessibilityLabel("ダウンロード \(pct)% \(downloaded) / \(total)、\(eta)")` + `.accessibilityAddTraits(.updatesFrequently)`
- [ ] THINKING 展開/折りたたみをタップで切替（状態はビューローカル）
- [ ] VoiceOver で読み上げ順を検証
- [ ] Dynamic Type 非対応（デザイン固定サイズ想定）。`.font(.pasturaBubbleBody)` など extension で統一しておくと、将来の Dynamic Type 対応が容易

---

## Notes for Reviewer

- **配色のコントラスト**: 本デザインは WCAG AA 余裕ありのレベル（L3）を採用済み。より高いコントラストが求められる場面（強い日光下など）のため、`[data-contrast="L4"]` の色を Asset Catalog に `"MetaBase-HighContrast"` 系として用意しておくと、将来の「増強コントラスト」対応がスムーズです
- **ローカライズ**: 現状 ja-JP 固定。en 対応時は「残り約4分」→「~4 min left」、「準備ができました」→「Ready」など、コピー全体の再設計が必要です（単純翻訳では冗長）
- **音声**: デモ再生は無音想定。効果音やハプティクスは未定義です
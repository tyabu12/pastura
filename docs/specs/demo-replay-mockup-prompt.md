# DL-time Demo Replay — Claude Design Mockup Prompt

> **Status:** Working draft (exploration, not a ship artefact)
> **Date:** 2026-04-20
> **Purpose:** Prompt to paste into [Claude Design](https://www.anthropic.com/news/claude-design-anthropic-labs)
> to generate HTML/CSS visual mockups of the DL-time demo replay screen. Used for
> UX exploration before SwiftUI implementation. Companion to
> `docs/specs/demo-replay-spec.md` and ADR-007.

## Scope

- **In scope:** Normal playback (spec §4.9 `.playing`) + DL-complete transition
  (`.transitioning`). Multi-variant visual exploration from a zero baseline.
- **Out of scope for this mockup:** DL failure retry, mobile-data warning modal,
  no-playable-demos fallback (spec §3.3 / §5.3). Those states stay on the spec
  but are not explored here to keep the prompt focused.

## Output expectations

- One self-contained HTML file rendering 4 storyboard frames top-to-bottom.
- 2–3 visual variants (different directions, not refinements of one).
- iPhone-sized container (390px width) per frame.
- Japanese copy throughout.
- CSS animations where feasible (progress bar fill, fade-ins, transition).

## Prompt body

```
# Pastura — DL中デモ再生画面のモックアップ

## プロダクトの背景

Pastura は「放牧（pasturage）」をモチーフにした iOS アプリ。ユーザーが
YAML で定義したシナリオに従い、複数の AI エージェントが iPhone 内で対話・
意思決定するのを「眺める（gaze）」シミュレータ。コンセプトは
"AIgazing simulator" — 牧草地で羊を眺めるように、AI エージェントたちが
勝手に相互作用する様子をのんびり観察する体験。

- オンデバイス LLM（約 3GB）で完全オフライン・無料・広告なし・プライベート
- ゲームではない。勝つためではなく観察するためのアプリ
- 放牧の静けさと、AI の予測不能な挙動のコントラストが味

## 今回作ってほしいもの

アプリ初回起動時、モデル（~3GB）をダウンロードする間、事前録画されたデモ
対話を再生して「このアプリで何が起きるのか」を先に体験させる画面。進捗バー
だけだと退屈で離脱されるため、Word Wolf のデモ対話をループ再生する。

## 画面の構成要素（すべて含める）

1. エージェント発話行 — 発言がチャットのように順次フェードイン。発言の下
   に「内なる思考（inner_thought）」がタップで展開できる形で付く想定
2. フェーズヘッダー — 現在のシナリオフェーズ（例：「発言ラウンド 1」「投票」）
3. DL 進捗バー + 残り時間推定 — 控えめに。主役ではなく添え物
4. プロモコピー（3 スロット — すべて working draft。Claude Design による別案
   提案も歓迎）:
   - A（導入）draft: 「AIエージェントが、あなたのiPhoneの中で対話します」
   - B（待機理由）draft: 「少しだけお待ちください。その間、他のエージェント
     たちの様子をどうぞ」
   - C（価値訴求）draft: 「広告なし・無料・完全にあなたのデバイス内で動作」
     ※ この draft は sales-leaning と自覚している。より穏やかで「放牧的」な
       トーンの別案を 2〜3 個提案してほしい（広告なし・無料・オンデバイスの
       3 要素は残す前提）

## 再生されるデモ対話（Word Wolf — 社会的推理ゲーム）

前提：4 人のエージェントのうち 3 人は同じお題（猫）を、1 人だけ違うお題
（犬）を持っている。発言で推理し、違う人（ウルフ）を投票で当てる。

フェーズ1: 発言ラウンド
- Alice: 「わたしのお題、毛がふわふわで撫でたくなる感じ」
  - inner_thought: 「みんな同じ単語だろうから抽象的に言っておこう」
- Bob: 「うちにもいるよ。鳴き声がかわいい」
  - inner_thought: 「ありがちな表現で様子を見る」
- Carol: 「一人で気ままに過ごすタイプかも」
  - inner_thought: 「みんな似た感じだな。違和感のある発言する人を見逃さないように」
- Dave（ウルフ）: 「散歩するのが楽しいよね」
  - inner_thought: 「犬の話をさりげなく紛れ込ませる作戦で行こう。"散歩"なら猫でも通じるはず」

フェーズ2: 投票
- Alice → Dave（「"散歩"って言葉、他の誰も使ってない。お題が違うのかも」）
- Bob → Dave
- Carol → Dave
- Dave → Alice

結果: Dave 脱落。お題は「猫」、Dave だけ「犬」だった。

## 出力形式（紙芝居式）

1 つの HTML ファイル内に、以下の 4 フレームを縦に並べて描画してほしい。
各フレームは iPhone サイズ（幅 390px）のコンテナで表示。各フレームの上に
「Frame N: 説明」の見出しを付けて状態遷移が追えるように。

- Frame 1: DL 開始直後、Alice の発言 1 件だけが表示された状態（進捗 5%）
- Frame 2: フェーズ1 の発言が全員揃い、Dave の inner_thought が展開済み
  （進捗 35%）
- Frame 3: 投票フェーズ、Dave に票が集まっている状態（進捗 70%）
- Frame 4: DL 完了直前〜直後の遷移アニメーション（デモ画面が fade-out しつつ、
  画面中央に「準備完了」のようなテキストが浮かび上がり始める瞬間。
  setup-complete 画面の全貌は描かず、余韻だけ。進捗 100%）

CSS アニメーション対応できるなら歓迎:
- 進捗バーが少しずつ埋まる
- エージェント発話が fade-in + slight slide-up
- Frame 4 の遷移は opacity + scale で滑らかに

対応できない場合は静的フレームのみで OK。

## ビジュアル参照語（ムードボード）

「放牧」「AIgazing」を視覚に翻訳するための比喩。全案共通のムードボードとして
解釈してほしい（3 案すべてがこれら全部を表現する必要はない、雰囲気の源泉）：

- 野鳥観察の hide（窓越しに生き物を静かに覗く距離感）
- プラネタリウム（ドームの下で見上げる、決定論的だが神秘的な動き）
- 草原のちょっと霧のある朝もや（静かに始まる朝、輪郭のやわらかさ）
- 羊飼いの日記帳（手書き・紙の質感・余白、観察者の記録）
- 朝の日本庭園で池の鯉を見つめる（静止と動きの拮抗、禅的観察）

あわせて、放牧全般の雰囲気（ゆったり・穏やか・観察的・傍観者視点・
予測不能な AI 挙動と静かな UI のコントラスト）を意識してほしい。フラット
デザインは OK だが、遊び心は欲しい（やりすぎない）。

## 3 案の diversity 方針（観察メタファーで振る）

3 案は意図的にトーンを振ってほしい。各案に「核となる観察メタファー」を設定し、
他 2 案と被らないように：

- **案 1: 「hide から外を見る」** — 野鳥観察 + 草原の朝もや。窓越しの距離感、
  自然観察の静けさ。ベージュ・苔緑・白のパレット想定
- **案 2: 「ドームの下で見上げる」** — プラネタリウム。没入・思弁的・深い静寂。
  ダークモード、紫〜藍、星のような点描想定
- **案 3: 「観察者の記録」** — 羊飼いの日記帳 + 日本庭園の鯉。手書き・紙・和。
  セピア〜温白・余白多め、日本庭園の空気感想定

メタファーに引っ張られすぎず、現代的な iPhone UI として成立する範囲で解釈
してほしい。案ごとに何を狙ったかを短く説明するコメントを HTML 冒頭に。

## レイアウト基礎

- 1 フレーム = 幅 390px × 高さ 844px（iPhone 14/15 基準）
- safe-area 目安: 上 47px / 下 34px を余白として確保
- ライト/ダークは案ごとに自由に選択。案冒頭のコメントでどちらを選んだかと
  理由を 1 行書いてほしい
- 日本語フォント: system 系 + `Noto Sans JP` などを fallback

## 評価観点

最終的に 1 案を選んで SwiftUI 実装に落とす想定。判断軸：

**閾値（全案が満たすべき前提、優劣ではなく最低ライン）**
- iPhone らしい手触り（safe-area・余白・タップ感が iOS ネイティブ）

**比較軸（優先順位）**
1. 放牧感（ゆったり・静か・観察的な雰囲気）
2. 対話の主体性（AI の発言が画面の主役、UI は傍観者に徹する）
3. 情報密度（ちょうどよい情報量。詰めすぎず、スカスカでもない）
4. プロモ訴求（Slot A/B/C の 3 情報が違和感なく伝わる）

各案の HTML 冒頭コメントで、この 4 軸に対して自分の案がどう位置取りしているか
を一言ずつ書いてほしい。

## 言語

UI 文言・エージェント発言ともすべて日本語。Phase 2 は日本語のみを想定。
```

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

§2.9 でダーク対を持つ（slice 4）。方向が2つに割れるので注意 —
`page` は light で本体背景より**暗い**（引っ込んだ面）ので dark でも
`nightBackground` より暗く**沈む**。`promoBackground` は**カード段**の面なので
`nightBubble` に追随して地より**浮く**（light で `screenBackground` とほぼ同値
なのは light 上端が圧縮されている副作用で、設計上の関係は `bubbleBackground`
との 1.047 の差）。`promoBorder` は倍率を保ったまま**向きが反転**する — light
ではカードより暗い線が、dark ではカードより明るい線になる（`rule` →
`nightRule` と同じ。暗い地では面より暗い境界線は背後の地に溶ける）。

### 2.2 Ink（文字・輪郭）

| トークン | Hex | 用途 |
|---------|-----|------|
| `--ink` | `#2D2E26` | 本文（最濃。純黒ではない） |
| `--ink-2` | `#5A5A55` | サブテキスト・セクションラベル |
| `--muted` | `#8A8A83` | メタ情報・脚注 |
| `--rule` | `#E0DBCE` | 罫線 |
| `--ink-on-accent` | `#FFFFFF` | アクセント塗り（`moss` / `moss-dark`）の上に載る文字・グリフ |
| `--ink-on-wash` | `#5A5A55` | 半透明のインク系ウォッシュに乗る中立文字（バッジ・チップ・ステータスピル）。§2.3 の `--moss-on-wash` のインク側の対応物。ダーク対は §2.9 の `nightInkOnWash`（#1408 で追加。下の「slice 4」には**含まれない**） |

**`--ink-on-wash` の light 値が `--ink-2` と同一なのは偶然ではなく設計。** 別名参照ではなく**値の複製**である。複製が買っているのは dark の独立性ではなく（dark 半分は `PasturaDynamicPalette` で独立に宣言されるので別名でも保たれる）、**逆向きの切り離し** — 将来 `--ink-2` を light 側で再調整したときにこのトークンが黙って追随しないこと。§2.12 の `headerMetaInk` が `metaBaseL3` と同 hex を別役割で複製しているのと同型。壊れていたのは dark だけだったため（4 箇所で 4.413〜4.773:1、うち 2 つは 4.501:1 で「バーちょうど」）light は据え置き、dark だけ `nightInkSecondary` → `nightInkOnWash` に持ち上げた。**したがって light 端末ではこの変更は一切見えない。** 適用先は「同じトークンを文字と半透明ウォッシュの両方に塗っている」4 箇所（*self-wash*）に限る — `PhaseEditorSheet.fieldPill` の thought、`ScenarioBadgeStyle.secondary`、`PhaseTypeLabel` の非 LLM、`ResultsView` の paused ピル。不透明な中立塗りは別問題で、§2.6 の Soft+Ink 対が担当する（#1407 と同じ形）。計測は `DesignTokensTests+InkOnWash` が正本。#1408。

**`--ink-2` のセクションラベル用途には既知の未適用がある。** 自前のセクションヘッダー `PasturaSection` はヘッダーを `--muted` で描いており、この表と一致しない。対象は設定 / 観察履歴 / さがす といったタブ配下に限らず、ScenarioDetail / GalleryScenarioDetail などの push 先も含む。掃引対象の正は**呼び出し形**の grep — `rg -l 'PasturaSection\(' Pastura/Pastura/Views/`。**件数はここに写さない**（`muted-application-audit` §6.3 が列挙を持つ。消費側の数は「決定が変わらないまま動く」在庫で、`adr-writing.md` §4 の写し禁止に当たる）。型名だけの grep は `PasturaSectionStyle` の言及も拾って広く出るので使わないこと。#1298 では `ScenarioEditorView` の Personas / Phases ヘッダーだけを表どおり `--ink-2` に揃えた — 隣に `--muted` のカウントが並び、明度がほぼ同じで色相だけ違う組み合わせになっていたため。`PasturaSection` 側はパレット掃引の担当として残す。**「表に寄せる」か「表を `PasturaSection` に合わせる」かは #1448 で決着した — コードを表に寄せる。** §2.2 が役割の規範的な記述であること、#1298 が既に先例を作っていること、監査で「表のほうが誤り」とする論拠が出なかったことによる（導出は `muted-application-audit` §6.3）。適用は #1485 — `PasturaSection` を通らない手書きヘッダーと、システム `secondaryLabel` のまま残っているヘッダーも同じ判断の対象で、3種類を1つに畳むのがその終着点（列挙は `muted-application-audit` §6.3）。**5画面**（手書きヘッダーを含めて6画面）にまたがる視覚変更なので ADR-028 gate 4/5 の実機 QA が要る — ファイル数と画面数を取り違えないこと。

`--ink-on-accent` は §2.3 が認めるアクセント上の前景（**light では白**、dark は `night-ink-on-accent`）。§1 の「純白の面を避ける」は**背景**の話なので抵触しない。適用範囲は下地で変わる:

- **テキストは `moss-dark` 上に限る**（≈4.7:1、AA 達成）。base `moss` 上は ≈3.03:1 で 4.5:1 に届かない。
- **グリフ・図形は `moss` 上も可**。WCAG 1.4.11 の非テキスト 3:1 が適用され ≈3.03:1 は充足する（`CheckBadge` のチェック、share タブのシンボル — 後者は `moss`→`moss-dark` グラデ上なので最悪値が明側の `moss`）。ただし余裕は約 1% しかないので、`moss` の色を動かす際はこの 2 用途を確認すること。

`CheckBadge` の `filled` 塗りを `moss-dark`（≈4.74:1、見た目のコストなし）に上げる案は #1298 で検討し**退けた**。上の分類が図形を base `moss` 上で明示的に認めている以上、その代表例である `CheckBadge` を余裕の薄さだけを理由に個別例外にすると、分類そのものが空文化する。約 1% の余裕は上の但し書きが引き受ける前提であり、gate 1 後のダークでは `night-ink-on-accent` on `night-moss` が 6.395:1 で余裕がある。

生の `Color.white` を各所に書かずトークンにしてあるのは、ダーク時のアクセント前景の判断が 1 箇所で済むようにするため — そして **slice 4 でその判断が付いた（ADR-028 gate 1、達成）**。

ダークでは `moss` が `night-moss`(#A8B888) になり、そこに白を置くと ≈2.13:1 で 3:1 すら割る。これは計算で確定していたので実機 QA では決められず、gate 1 の二択（`night-moss` を暗くするか、このトークンをペア化するか）だった。**ペア化を採った** — `night-moss` を暗くすると §2.7 の wash 4本（その RGB から作られている）、§2.4 のドット梯子（それを基準にしている）、§2.5 の body window（地に対する 8.00:1 を天井として読んでいる）の3スライスが無効になる。

ダーク値は `--night-ink-on-accent`(#2C2F28) で、**白ではない**（Material 3 が primary を tone 40→80 に上げるとき on-primary を tone 100→20 に反転させるのと同じ動き）。`night-moss-dark` 上で 7.117:1、`night-moss` 上で 6.395:1。**上の適用範囲はダークでは緩む** — テキストも図形も両方の下地で AA を満たす（ただし AAA を満たすのは `night-moss-dark` 上だけ）。したがってこのトークンは「両外観で固定」ではなく **ペア済み**。§2.9 の対応表を参照。Source: `PasturaPrimaryButtonStyle` / `SharedScenariosListView+CategoryChips`。

### 2.3 Moss Accent（苔アクセント）

Pastura 唯一のブランド色。用途別に4段階。

| トークン | Hex | 用途 |
|---------|-----|------|
| `--moss` | `#8A9A6C` | リーフアイコン・プロモ左ボーダー（3pt） |
| `--moss-dark` | `#6B7852` | DL進捗ドット点灯・ホーム更新バッジドット・アクセントリンク・**完了ステータスピルのウォッシュ**（ラベルではない — ラベルは下の `--moss-ink`、§8 の例外） |
| `--moss-ink` | `#3D4030` | 犬の輪郭・完了タイトル・**完了ステータスピルのラベル**（`ResultsView` の完了ピル、`GameHeaderStatus.completed`）。**ここに挙げた意味に限り**半透明の苔系ウォッシュ上でこの段を使ってよい（§8 の唯一の例外、条件はそちら）。ここに無い意味で乗せているサイトは routing 未正当化 — §8 末尾の ⚠️。**⚠️ このセルに役割を足すのは §8 の例外を広げる変更**であり、条件 (1) はこの列挙を読むので、doc の追記1行で例外が満たせてしまう。ADR-028 の amendment を伴う判断として扱い、通常の doc 整備と同列に置かないこと（下の `--moss-on-wash` の列挙は**用例**なので、あちらへの追記はこれに当たらない）。Swift 側の対は `PasturaPalette.mossInk` の doc コメント |
| `--moss-soft` | `#D4CBA8` | THINKING 左線・やさしい区切り／不透明塗りとして文字を載せる場合は前景に `--moss-ink` を組む（§2.6 と同じ Soft+Ink ペアリング。6.537:1） |

この 4 段とは別に、**役割トークン**が 1 つある。梯子の 5 段目ではない。

| トークン | Hex | 用途 |
|---------|-----|------|
| `--moss-on-wash` | `#535D40` | 半透明の苔系ウォッシュに乗るアクセント文字（バッジ・チップ・ステータスピル・カード面のアイブロウ・進捗読み出し）。ステータスピルは**実行中系のアームのみ**（完了アームは上の `--moss-ink`、§8 の例外）。**この列挙は網羅ではなく用例**である点が上の `--moss-ink` と違う — §8 の既定は「半透明の同族ウォッシュ上なら `*-on-wash`」と**地のファミリで**振り分けるので、ここに無い意味でも既定は満たす。逆に `--moss-ink` の列挙は §8 の例外の条件 (1) がそれを読むため、あちらは網羅として扱うこと。ダーク対は §2.9 の `nightMossOnWash`（#1327 で追加。下の「slice 4」には**含まれない**） |

段位置ではなく **4.5:1 という目標比から解いた値**である点が 4 段と違う（ADR-028
のアーム論、アーム3）。`--moss-dark` はこの仕事をどのウォッシュ濃度でもこなせない
— 純白に対してすら天井が 4.737:1 なので、目に見える濃さのウォッシュはすべて
バーを割る。出荷済みサイトの各ウォッシュ上で light 3.74〜4.07 にしかならない
`--moss-dark` が、このトークンなら 5.51〜6.00 になる（サイト数は
`mossWashSites` の size pin が正 — ここには書かない。各ウォッシュを
そのアピアランスの最悪地 — light は `screen-background` — に合成した値。テストが
assert する規約と同じ）。**下限側は「そのサイトが出荷していた比」ではなく
`--moss-dark` を置いたときの反実仮想**である点に注意 — #1459 以降、`--moss-dark`
を一度も読んでいない行（`HomePausedCard` の進捗ラベル。`--moss-ink` から直接
移設）が含まれるので、レンジを移行前の実測値として読むと誤る
（#1327）。適用範囲は**半透明**の苔系ウォッシュに限る — 不透明な `--moss-soft`
の上では 4.29 で届かない。そちらの地は §2.6 と同じ Soft+Ink ペアリングで解決済み
（前景に `--moss-ink`、6.537:1。#1407）。

§2.9 でダーク対を持つ（slice 4）。**4段の順序が反転する** — light は
輝度で ink < dark < moss < soft（ink が最暗）だが、dark は
soft < moss < dark < ink（ink が最明）。つまり `nightMossDark` は
`nightMoss` より**明るい**。`nightMoss` がアーム1（+11L）で置かれて地に対し
8.00:1 に座っているため、その上に乗る強調段は必然的に 8:1 を超える（light の
4.538 に対し dark は 8.902）。moss → mossDark の段差も 1.561 → 1.113 に縮む。
§2.4 で見つかった天井現象の §2.3 版で、`docs/decisions/ADR-028.md` の
slice 4 Amendment に導出がある。

**ホーム更新バッジドットが `--moss-dark` なのは light 側の測定による**（#1298）。base `moss` はドットの `screen-background` リングに対し 2.908:1 で WCAG 1.4.11 の非テキスト 3:1 に届かない。**測定が制約し、先例が選ぶ。** 測定は `moss`（2.908）と `moss-soft`（地に対し 1.559）を落とし、残るのは `--moss-dark`（4.538）と `--moss-ink`（10.190）の2段。そこから選んだのは DL進捗ドット — 同じ「点灯した小さな指標」という役割 — が既に `--moss-dark` を使っている先例による。dark 側は元々 7.999:1 で不足が無く、上の反転により 8.902:1 と**むしろ目立つ方向**に動く — slice 2 が DL ドットで取ったのと同じ「機能 > 知覚重みの同等性」のトレードとして受け入れている。実装は `HomeCompactRowLayout.updateBadgeDotFill`（`HomeCompactRowLayoutTests` が読むトークンを pin）。

### 2.4 Meta Contrast Presets（DL進捗表示）

日光下など**コントラスト要件が変わる環境**に備え、4段プリセットを定義。デフォルトは **L3**。

```css
[data-contrast="L1"]{ --meta-base:#8A8B76; --meta-strong:#5D6848; --meta-dot-on:#8A9A6C; }
[data-contrast="L2"]{ --meta-base:#6A6D5A; --meta-strong:#3D4530; --meta-dot-on:#7A8A5C; }
[data-contrast="L3"]{ --meta-base:#4A4E3D; --meta-strong:#2D2E26; --meta-dot-on:#6B7852; } /* default */
[data-contrast="L4"]{ --meta-base:#2D2E26; --meta-strong:#1A1B15; --meta-dot-on:#556340; }
```

ダーク対は §2.9 に 12 対そろっている（#1313）。**梯子の向きが反転する**ので、上の CSS を
そのまま暗くしたものにはならない — 詳細と比率は §2.9 の §2.4 対応表を見ること。
`tokens.css` 側のダーク値は `[data-contrast]` セレクタではなく `--night-meta-*-l1..l4` の
フラット宣言で持っている（プリセット切替は外観と直交する機構なので、ダーク変種を作ると
どのカードも使わない `[data-scheme][data-contrast]` の組み合わせが増えるだけ）。

### 2.5 キャラクターパレット（羊アバター）

> **Source of Truth（light 半分のみ）**: `docs/design/demo-replay-reference.html` の `sheepAvatar()` 関数が**ライト値の**原点。本テーブルはその mirror で、Swift `Pastura/Views/DesignTokens.swift` の `PasturaPalette.avatar*` トークンが本テーブルを参照する。**ダーク値の原点はそこには無い** — あのプロトタイプは light 専用なので、§2.9 が正本、`ds/colors-avatar-dark.html` がその mirror（#1319）。HTML 内の letters mode `.ava.<who>` セレクタの背景色は HTML-only ornament で iOS では未レンダー、scope 外。命名規約: 共有部位は `avatarPart`（例: `avatarEar`）、キャラ別部位は `avatarPartCharacter`（例: `avatarBodyAlice`）。Swift 側の値は `Pastura/PasturaTests/Views/DesignTokensTests.swift` が固定する。ただし**プロトタイプ→本表の一致を検証する経路は無い**（目視のみ）— HTML を parse するテストもスクリプトも存在しない。

| キャラ | body | face | horn | 役割 |
|-------|------|------|------|------|
| Alice | `#F2E3C8` クリーム | `#C9A979` | `#B29364` | やさしい第一声 |
| Bob   | `#DDE4CC` セージ   | `#8A9A6C` | `#6F7F54` | 同意的・穏やか |
| Carol | `#EAD6D1` ピンク   | `#B8877C` | `#9C6E64` | 観察者 |
| Dave  | `#D9D7C9` スレート | `#6B6858` | `#4F4C3F` | Wolf（狼）/ 中心人物 |

共通：耳 `#E8D9BC`, 耳内 `#D4C19E`, 鼻 `#3D4030`, 目 `#2D2E26`, ハイライト `rgba(255,255,255,.6)`

ダーク対は §2.9 に 17 対そろっている（#1319）。**「暗くする」変換は明度ではなく色相と絶対彩度（`2·S·min(L, 1−L)`、定義と根拠は §2.9）を守る** — 4 体の識別は色相が担っていて、body 同士のコントラストは light で 1.03〜1.14 しか無いため。詳細は §2.9 の §2.5 対応表。

⚠️ **耳・耳内・鼻はどの実装も描いていない。** `SheepAvatar.swift` の `Canvas` も SoT の `sheepAvatar()` も body / face / eye / horn だけを描く（Swift はさらに highlight を描くが SoT は描かない）。トークンとしては §2.5 の完全性のために残しているが、塗られてはいないので視覚検証の経路が無い。

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

"system blue" を発生させないために定義。**`link` は既に使われている** — Settings の
外部リンク行（`SettingsView.swift:317,336` の `.tint`、
`SettingsView+Feedback.swift:79,82`）と `ViewerPredictionSheet.swift:110` の計
5 箇所 3 ファイル。`linkVisited` / `linkHover` は消費者ゼロの予約のまま
（hover は iPadOS ポインタ専用）。3 つとも §2.9 でダーク対を持つ（slice 4）。
Source: `§2.8 Link / Action`。

ダーク値は3つともアーム3（目標コントラスト配置）で、それぞれ light の自比を
地に対して保つ（4.618 / 5.378 / 6.345 → 4.631 / 5.378 / 6.340）。light の
順序は直感に反していて `linkVisited`（5.378）が `link`（4.618）より
コントラストが高い — 緑ではなく彩度を落とした茶であり、「訪問済み」を担うのが
輝度ではなく色相だからで、比を保つとその奇妙さも保たれる。ADR-028 の #1282
Amendment が `link` に添えた「~7:1 の帯」は slice 1 の Ink-over-Soft の関係で
あってこれらの目標ではない（slice 2 がアーム3を「light の比を解く」に精緻化した）。

| Token | Hex | 用途 |
|-------|-----|------|
| `link` | `#5D7A4D` | デフォルトリンク（moss 寄りの深緑） |
| `linkVisited` | `#6F6753` | 訪問後（苔→土へ） |
| `linkHover` | `#4A6438` | hover 時 |

### 2.9 Dark Mode（夜の牧場）

**trait-based 配線済み（69 対）／値は完成。** `PasturaDynamicColor` が light/dark 対を
`UIColor(dynamicProvider:)` で解決し、下表の 69 対が `Color.*` エイリアス経由で実 UI に
届いている（[ADR-028](../decisions/ADR-028.md) の 8 対 + #1282 が設計した §2.6/§2.7 の
18 対 + #1313 が設計した §2.4 の 12 対と §2.12 の 2 対 + #1319 が設計した §2.5 の 17 対
+ slice 4 が設計した §2.1/§2.3/§2.8 の残り 9 対と §2.2 の `inkOnAccent`
+ gate 1 を閉じた**後**に増えた役割トークン 2 対 — `mossOnWash`（#1327）と
`inkOnWash`（#1408））。**後半 2 対はどの slice にも属さない** — 「ダーク値を負っていた
light トークン」ではなく、新たに存在する必要が生じた light トークンであり、§2.9 が
パレットの既定になった後なので生まれつきペアだった（ただし `mossOnWash` は light 自体が
壊れていたので新しい値が要り、`inkOnWash` の light 値は `--ink-2` の複製、と事情は異なる）。
したがって上の列挙は内訳ではなく由来の一覧。
**ダーク対を持たないトークンは `headerMetaSubdued` 1 つだけで、しかも未決ではなく解決済み**
— **両外観で固定**という記録によるもので、gate 1 は designed dark value と同格の充足条件
としてこれを認めている。したがって **gate 1 に答えを負ったトークンは 0**。
「未ペア 1」と「未解決 0」は別の数なので、片方を述べた記述をもう片方として読まないこと。

`Info.plist` の `UIUserInterfaceStyle = Light` は削除され、アプリは端末の外観設定に
従う。ADR-028 § "Rollout" の 5 条件は全て達成済み — gate 4（Home / ScenarioDetail /
Demo / Simulation / Results / Settings の実機ダーク QA。実際には Editor・
ModelPicker・DL 完了オーバーレイ・ナビバータイトルの外観追従も歩いた）と gate 5
（ダーク共有カード経路の実機確認）が、先に達成済みだった gate 1（値の完成）・
`nightSurface` の解消・生 SwiftUI 色のトークン化に続いて閉じた。ダークは実際に
実機で描画される。

**ただし 1 点は未確認のまま残っている** — ゲートを閉じた QA より後に入った
6 件の修正。この数は ADR-028 § "What is NOT confirmed" の列挙、
再走手順は `docs/qa/dark-mode-qa.md` の再走リストが正本。うち #1354 分は
2026-08-05 に実機で部分的に消化済み（未消化分は同 § の 3 ギャップを参照）。

§2.1 の `nightPage` を `ViewerPredictionSheet` に当てた見え方（このファイルが
持つ値であり、唯一プラットフォーム慣習に逆らって選んだもの）は実機で決着した。
**設計上の上下関係は描画時に反転する** — 暗幕は背後だけにかかりシートには
かからないため、`nightBackground` の 1.099 下にあるはずのシートが画面上では
背後の 1.031 上に来る。穴には見えず、ほぼ面一。ADR-028 § Amendment 2026-08-05 (#1336)。
Source: `§2.9 Dark Mode`。

**ダーク値の視覚リファレンス**: [`ds/colors-states-dark.html`](ds/colors-states-dark.html)
（§2.6/§2.7 の 18 対 + トースト・設定・DL 進捗のモック）、
[`ds/colors-meta-header-dark.html`](ds/colors-meta-header-dark.html)
（§2.4/§2.12 の 14 対 + 固定 1 + L1→L4 梯子の反転表示・DL 進捗メタ行・GameHeader のモック）、
[`ds/colors-avatar-dark.html`](ds/colors-avatar-dark.html)
（§2.5 の 17 対 + 4 体を両外観で並べた比較・会話行/Home 行/さがすタイル/共有カードのモック）、
[`ds/colors-remainder-dark.html`](ds/colors-remainder-dark.html)
（§2.1/§2.2/§2.3/§2.8 の 10 対 + プロモカードの DL 進捗・Settings 外部リンク行・
アクセント上の前景を最小文字サイズで並べたモック）。

**外観を固定した書き出しでは、まず外観を「注入」する。** `ImageRenderer` は ambient を
継承しないので、`.environment(\.colorScheme, …)` と明示パラメータの両方を渡す（参照実装:
`HighlightShareCard`）。**注入を省くと書き出しは端末がダークでも light に倒れる** — #1337
で計測。これが本当の失敗モードで、エイリアスを読むこと自体ではない。

その上で **この 69 対のエイリアスは読まず** `PasturaPalette.<token>.color` を直接読むのが
規約。理由は呼び出し側で選んだ外観が読んで分かること、および Apple 側の挙動に書き出しの
正しさを預けないこと。エイリアスを読んでも*要求した*外観では出る（注入は `Canvas` の
`GraphicsContext` にも届く — #1337）が、`light` と `dark` が同じ値に潰れて呼び出し側の
選択が効かなくなる。

`SheepAvatar` はスライス3 以前、§2.5 のエイリアスを **14 箇所**（17 から未描画の 3 つを
引いた数）で読んでいて、そのカードの中で描かれる。現在は 0 箇所で、塗りは
`SheepAvatarPalette` を通る。`HighlightCardPalette` が pin しているのは 6 トークンだけで
§2.5 は入っていないので、#1319 で `SheepAvatarPalette` を足し、カードから明示の外観を
渡すようにした。カードが描くコンポーネントも注入の対象には入っているので、**要件そのものは
書き出し側（注入するか）に付く** — 一段下に伝播する要件ではない。

| Token | Hex | 対応する day-mode token |
|-------|-----|------------------------|
| `nightBackground` | `#1B1D17` | `screenBackground` |
| `nightBubble` | `#2C2F28` | `bubbleBackground` |
| `nightWhisperBubble` | `#2F3626` | `whisperBubble`（密談バブルのダーク対。#908 PR2） |
| `nightInk` | `#E8E5D8` | `ink` |
| `nightInkSecondary` | `#B0AC9C` | `inkSecondary` |
| `nightMuted` | `#7A7768` | `muted` |
| `nightRule` | `#353830` | `rule` |
| `nightMoss` | `#A8B888` | `moss` |

§2.6 アラートファミリの対（#1282）。`*Soft` と `*Ink` は**役割が反転**する — light の
「淡い地 + 濃い字」が dark では「暗い地 + 淡い字」になるので、base に使った変換式は
当てない。各 Ink は変換ではなく**目標コントラストで配置**しており、自分の Soft 上で
7.7〜8.4:1。

| Token | Hex | 対応する day-mode token |
|-------|-----|------------------------|
| `nightInfo` | `#97ABC4` | `info`（夜地に対し 7.2:1） |
| `nightInfoSoft` | `#252D37` | `infoSoft` |
| `nightInfoInk` | `#B3C5DB` | `infoInk`（Soft 上 7.9:1） |
| `nightSuccess` | `#95B189` | `success`（7.2:1） |
| `nightSuccessSoft` | `#2A3725` | `successSoft`。`nightWhisperBubble` とほぼ同値（1.003）だが、light 側でも `successSoft` と `whisperBubble` は 1.026 でほぼ同値 — 既存関係の忠実な写像であり、**直さないこと** |
| `nightSuccessInk` | `#BFDBB3` | `successInk`（Soft 上 8.4:1） |
| `nightWarning` | `#D4B67E` | `warning`（8.7:1）。輝度を忠実に写した #DBBF8A（9.6:1）は採らない — light では warning が 4 色中**最も控えめ**（地に対し 2.23:1、他は 3.18〜3.42）なので、輝度順位を保存すると知覚重みの順位が反転する |
| `nightWarningSoft` | `#383124` | `warningSoft` |
| `nightWarningInk` | `#E0CEAE` | `warningInk`（Soft 上 8.3:1） |
| `nightDanger` | `#CE9790` | `danger`（6.9:1）。落ち着いたサーモン — 「赤は叫ばない」は両外観で保つ |
| `nightDangerSoft` | `#382624` | `dangerSoft` |
| `nightDangerInk` | `#E0B4AE` | `dangerInk`（Soft 上 7.7:1） |

§2.7 インタラクティブ状態の対（#1282）。moss 系の重ねは `nightMoss` に載せ替え、
alpha を約 1.33 倍にする（明るい moss を 6% で暗面に重ねてもほぼ判別できないため）。

| Token | Hex | 対応する day-mode token |
|-------|-----|------------------------|
| `nightHover` | `rgba(168, 184, 136, 0.08)` | `hover` |
| `nightPressed` | `rgba(168, 184, 136, 0.16)` | `pressed` |
| `nightSelected` | `rgba(168, 184, 136, 0.24)` | `selected` |
| `nightFocusRing` | `#A8B888` | `focusRing`。`nightMoss` と同 hex を別トークンとして持つ — light 側で `focusRing` が `moss` と同 hex を別に持つのと同じ理由 |
| `nightDisabledText` | `#605F54` | `disabledText`（無効地の上で 2.4:1 — light の 1.75:1 と同じく WCAG 1.4.3 の非活性除外に乗る意図的な sub-AA） |
| `nightDisabledBackground` | `#222420` | `disabledBackground`。`nightBubble` より**沈める**（1.151）— dark では「明るい＝浮く」が既に hover/selected の意味なので、無効面を持ち上げると衝突する |

§2.4 メタコントラストプリセットの対（#1313）。**L1→L4 の梯子はダークで向きが反転する** —
light では L が上がるほど暗くなって淡い地に対するコントラストが増すが、dark では同じ強調が
明るくなる方向。per-token の変換式では表せず、梯子ごと設計し直している（ADR-028 §
Amendment 2026-07-29（#1282 の方 — 同じ日付の見出しが 2 つある）が「機械変換不能」と名指しした唯一の項目）。比率は `nightBubble` に
対する値で、L1〜L3 は light の比率をそのまま写している。

**地は確定した（slice 4）。** 実描画面は `PromoCard` の `promoBackground` で、その
ダーク値 `nightPromoBackground`(#282C24) がこの梯子の実際の地。設計時は
`nightBubble` を暫定地に置き、**#2A2D26〜#2F3229 の帯**をアサートではなく*前提*として
いたが、導出値はその帯のわずか**下**に着地した（Y 0.0238 対 帯下端 0.0251）。
`DesignTokensTests+NightMeta` の
`nightMetaLadderStaysMonotonicAgainstTheCardSurface` は `promoBackground` の
pair registry 不在をアサートするトリップワイヤを持っていて、ペア化した瞬間に**発火した**。
発火が役目だったので**そのアサーションは削除済み**（テストを grep しても今は無い） —
地を実描画面の `nightPromoBackground` に差し替えて梯子を再測定したのが後継。
再検算の結果、梯子は帯外でも保つ — base は 3.33/5.08/8.16/10.77 から
**3.48/5.31/8.54/11.27** に上がり、単調性を維持し L3 は 8.54（約束の 4.5 以上）。
帯そのものを検査していなかったのは正しかった — 梯子は帯の両端どちらでも単調なので、
帯検査は常に通り、実際の地に対して一度も測らないまま終わっていた。

**下表の per-token 比は暫定地（`nightBubble`）に対する設計記録**で、意図的にそのまま
残している（「light の比をそのまま写している」が成り立つのはこの地に対してのみ）。実際の
地に対しては各段が上振れし、白の天井も 13.60 → 14.23 に動く。再検算が確立したのは
**単調性と L3 ≥ 4.5** であって、light 比の保持ではない。

| Token | Hex | 対応する day-mode token |
|-------|-----|------------------------|
| `nightMetaBaseL1` | `#7E7F6B` | `metaBaseL1`（3.33:1 / light 3.32:1） |
| `nightMetaStrongL1` | `#A0AC88` | `metaStrongL1`（5.67:1、light と同値） |
| `nightMetaDotOnL1` | `#A8B888` | `metaDotOnL1`。`nightMoss`・`nightFocusRing` と同 hex — light 側で `metaDotOnL1` が `moss`・`focusRing` と同 hex (#8A9A6C) である3者一致の忠実な写像。**統合しないこと** |
| `nightMetaBaseL2` | `#9DA08C` | `metaBaseL2`（5.08:1、light と同値） |
| `nightMetaStrongL2` | `#D5DBCB` | `metaStrongL2`（9.60:1 / light 9.59:1） |
| `nightMetaDotOnL2` | `#B7C49C` | `metaDotOnL2` |
| `nightMetaBaseL3` | `#C7CABC` | `metaBaseL3`（8.16:1 / light 8.19:1）。既定プリセットで、アプリに消費者がある唯一の段 |
| `nightMetaStrongL3` | `#E8E5D8` | `metaStrongL3`。**天井拘束** — light は 13.11:1 だが `nightBubble` の天井は純白で 13.60:1 なので余白ごと再現できない。light 値が `ink` (#2D2E26) なので答えは `nightInk`：天井に押し当てた値が既存ペアの答えと一致した |
| `nightMetaDotOnL3` | `#C3CEAE` | `metaDotOnL3` |
| `nightMetaBaseL4` | `#E8E5D8` | `metaBaseL4`。同じく天井拘束で `nightInk`。light 側でも `metaBaseL4 == ink` なので「L4 は本文と同じ強さ」という意味が外観反転を越えて残る |
| `nightMetaStrongL4` | `#F1F0E8` | `metaStrongL4`（11.89:1）。梯子の頂点で、`nightInk` より上に置く唯一のトークン。純白ではなく warm off-white — light が #1A1B15（純黒ではない near-black）を出荷している以上、非対称のほうが異常 |
| `nightMetaDotOnL4` | `#D5DDC6` | `metaDotOnL4` |

**ドットだけ守る不変量が違う。** base / strong は「地に対する比」を写しているが、点灯ドットの
仕事は地に対してではなく**消灯ドットに対して**読めること。消灯ドットは `moss@38%` で、`moss`
は既にペア済みなので dark では `nightMoss@38%`（合成後 #5B634C）に上がる。地基準で写すと
点灯/消灯の差が light 2.03:1 → dark 1.34:1 まで落ちてインジケータが機能を失うので、
`nightMoss` を起点に light の各段の明度差を反転させた梯子を採っている（消灯比 2.96 / 3.42 /
3.83 / 4.50、light の 2.03 / 2.50 / 3.17 / 4.33 をどの段でも下回らない）。
代償として dark のドットは同じ段のメタ文字より明るくなる（L1 で 6.40:1 対 3.33:1、light では
逆に 2.90 対 3.32 と控えめ）。機能を採って知覚重みの相対関係を捨てた、という選択。

§2.12 GameHeader スロットの対（#1313）。地は `nightBackground`（`GameHeader` は frosted な
`screenBackground` の上に乗り、そちらはペア済み）。**3 スロット中 2 つだけ**が対を持つ。

| Token | Hex | 対応する day-mode token |
|-------|-----|------------------------|
| `nightHeaderRule` | `#474535` | `headerRule`（1.76:1、light と同値）。`nightRule`（1.43:1）より**強い**まま — light で `headerRule` が汎用 `rule` より暗く、行内タイポセパレータとして機能するのと同じ関係 |
| `nightHeaderMetaInk` | `#B2B6A2` | `headerMetaInk`（8.18:1 / light 8.22:1）。light では `metaBaseL3` と同 hex だが、**ダークでは値が分かれる**（#B2B6A2 対 #C7CABC）— 乗る面が違うので同じ目標比を別の地で解くと別の答えになる。§2.12 の「§2.4 とは独立して進化させる」が実際に効いた形であり、直すべきドリフトではない |

§2.5 キャラクターパレットの対（#1319）。ADR-028 が「三アームのどれも当てはまらない」と
名指しした唯一の項目で、**第四の処方**を要した。4 体の body は**族としてまとめて**下げ、
各体は色相と**絶対彩度**（`2·S·min(L, 1−L)`、HSL 由来）を保つ。どの量かを明示するのは、HSL の `S` そのものは大きく落ち（Alice で 62→25、明度が下がれば同じ `S` がより濃い色を意味するため）、Lab クロマは逆に微増する（15.1→15.8）ので、量を言わないと検証できないから。face / horn はそのキャラ自身の light の body 比から従属して
決まる。だから羊は「暗くなる」だけで「別の色になる」ことはなく、18〜48pt で実際に羊を
読ませている内部構造（light では body は地に対して 1.21〜1.39 しか無く、輪郭では読めない）
がそのまま残る。

**地に対する比は結果であって目標ではない。** 設計したのは `nightBackground` に対する
**7.0〜8.0:1 の窓**で、下限は Dave の内部コントラスト（彼の eye÷face はパレット最薄の段で、
7:1 を割ると 1.8 を下回る）、上限はブランドアクセント `nightMoss`（8.00:1）を羊毛が
追い越さないこと。4 体は**この窓を端から端まで張っている** — Alice 7.99 は天井の 8.00 の
すぐ下、Dave 7.02 は床の 7.00 のすぐ上で、どちら向きにも余裕は無い。この窓は
`nightAvatarBodiesSitInsideTheDesignedWindow` がアサートしており、天井は 8.0 のリテラルでは
なく `nightMoss` 自身の比を読むので、アクセントを再調整すれば天井も一緒に動く。「地に対して 7.5:1 を狙った」と書くとアーム3（目標コントラスト配置）の
理屈になり、legibility の仕事を持たないトークンに対して次のスライスがそれを先例に引く。

**床が天井の鏡になる。** スライス2 は「dark の地は light に無い*天井*を持つ」を記録した。
ここでは*床*で同じことが起きる — light は near-white の地に対して 20:1 の下向きの余白が
あるので body の 5.95 倍暗い horn を置けるが、night の地はそれ自体が床。よって
**eye÷face だけは保存できず圧縮する**（Dave 2.45 → 1.93）。4 体とも、目を純黒にしてすら
届く上限の 86% に着地している。

**3 つの hex 一致はいずれも切った**（スライス2 では 2 つとも忠実に引き継いだので向きが逆）。

| Token | Hex | 対応する day-mode token |
|-------|-----|------------------------|
| `nightAvatarBodyAlice` | `#BFB095` | `avatarBodyAlice`（地に対し 7.99:1） |
| `nightAvatarBodyBob` | `#ABB29A` | `avatarBodyBob`（7.75:1） |
| `nightAvatarBodyCarol` | `#BAA6A0` | `avatarBodyCarol`（7.33:1） |
| `nightAvatarBodyDave` | `#A9A798` | `avatarBodyDave`（7.02:1）。4 体で最も彩度が低いのは light 同様、それが Dave の識別 |
| `nightAvatarFaceAlice` | `#9F7F4F` | `avatarFaceAlice`（body 比 1.75、light は 1.76） |
| `nightAvatarFaceBob` | `#637446` | `avatarFaceBob`（body 比 2.32、light と同値）。light 値は `moss` と同 hex だが**継承しない** — `nightMoss` は Bob の dark body より明るく、顔が体に対し 1.03:1 になって消える |
| `nightAvatarFaceCarol` | `#936156` | `avatarFaceCarol`（body 比 2.22、light は 2.21） |
| `nightAvatarFaceDave` | `#4A4737` | `avatarFaceDave`（body 比 3.86、light は 3.87）。4 体で最も強い内部コントラストで、それが狼の徴 |
| `nightAvatarHornAlice` | `#8A6B3D` | `avatarHornAlice`（body 比 2.32、light は 2.29 — 8 つの中で最も乖離が大きく 1.32%） |
| `nightAvatarHornBob` | `#4D5C31` | `avatarHornBob`（body 比 3.31、light は 3.32） |
| `nightAvatarHornCarol` | `#794B41` | `avatarHornCarol`（body 比 3.13、light は 3.11） |
| `nightAvatarHornDave` | `#2C291C` | `avatarHornDave`（body 比 6.02、light は 5.95）。地に対しては 1.17:1 とほぼ見分けが付かないが、角は毛の**上に**描かれ地に触れないので問題にならない。light の角も同じ理由で反対の極（淡い地に対し 8.25:1）にある |
| `nightAvatarEar` | `#B8A88B` | `avatarEar`。**未描画**（下記） |
| `nightAvatarEarInner` | `#A79471` | `avatarEarInner`。**未描画** |
| `nightAvatarNose` | `#2A2D1D` | `avatarNose`。**未描画**。目に対する light の比（1.29:1 → 1.28:1）で配置している — 顔の族に乗せると目より暗くなり線画の順序が反転した。light 値は `mossInk` と同 hex だが**継承しない**（`mossInk` はスライス3 の時点で未ペアで、未決の値への前方依存になるため。slice 4 でペア済み） |
| `nightAvatarEye` | `#16170F` | `avatarEye` — 両外観で羊の**最暗点**。light 値は `ink` と同 hex だが継承すると**目が白くなる**。#2D2E26 のまま固定するのも不可で、`nightAvatarHornDave` のほうが暗いため狼の角が瞳より暗くなる。よってペア化し、§2.5 自身の near-black の床（パレット全体の最暗値は slice 4 の `night-page` #11130F）（**HSL L** = 7.5%、light 最暗の `metaStrongL4` の HSL L = 9.4% のすぐ下）に置いた。§2.9 の他の数値は WCAG コントラスト比なので、ここだけ量が違うことに注意。純黒を採らないのは `nightMetaStrongL4` が純白を採らないのと同じ理由 |
| `nightAvatarHighlight` | `rgba(255,255,255,0.40)` | `avatarHighlight`。**alpha を下げる**（0.60 → 0.40）。§2.7 の wash が約 1.33 倍に上げたのと逆向きだが、矛盾ではない — wash は暗い面に載せる**淡い色**なので alpha が要る。こちらは面の上に置く**光の反射**で、面が暗くなった分だけ同じ alpha が*強い*段差になる。仕事が逆なので向きも逆 |
| `nightPage` | `#11130F` | `page`（引っ込んだ面なので dark でも地より**沈む**。パレット最暗値。ただし唯一の消費先であるシート上では暗幕により画面上は反転する — ADR-028 § Amendment 2026-08-05 (#1336)） |
| `nightPromoBackground` | `#282C24` | `promoBackground`（カード段。§2.4 梯子の実際の描画地） |
| `nightPromoBorder` | `#35392F` | `promoBorder`（倍率保持・**向き反転**。`rule`→`nightRule` と同じ） |
| `nightInkOnAccent` | `#2C2F28` | `inkOnAccent`（白ではない。`nightBubble` と同値だがそれは AAA 配置の**結果**） |
| `nightInkOnWash` | `#BAB7A9` | `inkOnWash`（アーム3。4 種の self-wash 上で 4.991〜5.397。`nightInkSecondary` では 4.413〜4.773 で、うち 2 つは 4.501 と「バーちょうど」だった）。**#1327 とは向きが逆** — 壊れていたのは dark。`nightInk` なら 7.955〜8.602 で通るので不可能性の証明は無く、退けた根拠は**役割**（§8） |
| `nightMossDark` | `#B3C197` | `mossDark`（**`nightMoss` より明るい** — 強調段の向きが反転） |
| `nightMossInk` | `#C6CBB1` | `mossInk`（アーム3、地に対し 10.19 保持） |
| `nightMossSoft` | `#384029` | `mossSoft`（向き反転。色相は moss 族へ寄せた） |
| `nightMossOnWash` | `#BDC6A4` | `mossOnWash`（アーム3。7 種のウォッシュ上で 4.70〜6.03、最薄はカテゴリチップ） |
| `nightLink` | `#699054` | `link` |
| `nightLinkVisited` | `#9B9075` | `linkVisited` |
| `nightLinkHover` | `#7FAA62` | `linkHover` |

**耳・耳内・鼻はどの実装も描かない。** §2.5 の完全性のためにペア化してあるが、
`SheepAvatar.swift` の `Canvas` も SoT の `sheepAvatar()` も body / face / eye / horn しか
描かない。値はスウォッチ上でしか検証できず、実画面での検証経路は存在しない。

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
| `headerMetaSubdued` | `#7B7D68` | Meta 行右寄せの推論 tok/s 値前景色（`metaBaseL1` と `metaBaseL2` の中間明度）。**両外観で固定** — 下記参照 |

`headerRule` と `headerMetaInk` は §2.9 にダーク対がある（#1313）。

**`headerMetaSubdued` はダーク対を持たない — 両外観で固定。** L≈45% の中間調は明地でも
暗地でもほぼ同じコントラストになるため、自地に対する比を忠実に写した解（light 4.04:1）が
light 値そのものになる：実測 #7B7D68 は `nightBackground` 上で **4.03:1**。これは指標の
退化ではなく答えで、ADR-028 § Rollout gate 1 は「両外観で固定という記録」を designed dark
value と同格の充足条件として明示している。

当初案は上表の括弧書き（「`metaBaseL1` と `metaBaseL2` の中間明度」）を不変量として写し
#8E907B (5.20:1) を置いたが、**あれは light 値の導出メモであってこのセクションが課す拘束では
ない** — §2.12 自身が「§2.4 とは独立して進化させる」と宣言している。実際それを写すと、この
セクションが本当に述べている役割（セパレータに埋もれない二次情報 ＝ ink との階層）が壊れる:
`headerMetaInk ÷ headerMetaSubdued` は light 2.032×、固定なら dark 2.031× で保存されるのに、
#8E907B では 1.573× まで潰れる。この不変量は
`DesignTokensTests+NightPalette.headerMetaSubduedReadsTheSameOnBothGrounds` が保持している。

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

1要素あたり**最大2レイヤー**、色味は near-black `#0B0C0A`（`--scrim` と同値）。
**正本は `PasturaShadows`**（Swift）で、`check_design_tokens_css.py` が
Swift → `tokens.css` の向きで照合する。以下はその写し:

```css
box-shadow:
  0 1px 2px rgba(11,12,10,.03),
  0 12px 26px -12px rgba(11,12,10,.13);
```

**この色味はこの節の全ファミリに共通で、理由は色ではなく向き。**
`a·C + (1−a)·ground` は `C` が `ground` より明るい限り `ground` を下回れないので、
かつての苔系 `rgba(90,100,60)` はダークの地 `nightBackground`（#1B1D17）の上で
影ではなく**発光**になっていた。「両モードで固定」では足りず、**覆いうるすべての地
より暗い**ことが要件。同じ結論に先に到達したのが full-bleed の `--scrim`（ADR-028）で、
値を共有しているのは「オクルーダ用の near-black をパレットに複数持たない」ため。

**彩度が苔系にならないのは避けられない**: tint は #1B1D17 の各チャネルを下回る必要が
あり、G ≤ 28 / B ≥ 0 なので **G−B は理論上限でも 28**。一方、色相を担うのは tint なので、
アルファを据え置いたまま苔系の色味を出すには tint の G−B が苔系そのものの値 **40** 要る
— これが最も緩い読み方で、それでも 28 に届かない。実際にはアルファも解き直しており、
変更前の合成の色味を保つには **51**（`.tight`）〜**58**（`.soft`）が要る。
ライト側の影がニュートラルになるのは選択ではなく帰結。
そのぶん**明度は保存**する — アルファはライト合成のレッドチャネルを保つよう解き直す
（この2レイヤーは .04 → **.03** / .2 → **.13**、#1378）。§4.3.1 のオクルーダ族は
自分のアルファ（0.22 → 0.10 等）で同じ計算をしており、その 94 / 14.8 という数字は
そちらの族のもの（ADR-028 § Amendment 2026-08-05 (#1373)）。

ダークでの沈み込みは α 0.03 で ~0.5 sRGB 段、0.10 で ~1.6 段、0.13 で ~2.1 段、
0.36 で ~5.8 段（地の相対輝度 0.0117 に対して下の余地が少ない）。ダークの浮き上がりは
主に「面が地より明るい」＋ヘアラインが担う。

#### 4.3.1 オクルージョンシャドウ（per-site ジオメトリ）

**地（app ground）の上に直接浮く要素**のうち、上の2レイヤーレシピではなく
**サイト固有のジオメトリ**を要するもの。色味は §4.3 と同じ `#0B0C0A` で、
**違うのはジオメトリだけ**。正本は `PasturaOccluderShadows`（Swift）、照合は同じ。

```css
/* card (ModelPicker のモデル一覧カード) */ box-shadow: 0 12px 14px rgba(11,12,10,.10);
/* cta  (ModelPicker の固定ダウンロードボタン) */ box-shadow: 0  6px  8px rgba(11,12,10,.36);
/* pill (InFlightSimulationIndicator) */ box-shadow: 0  2px  8px rgba(11,12,10,.10);
```

**拘束する地は `nightBackground` #1B1D17 だけ**。#1354 以降どの画面もこれを持ち、
これより暗い `nightPage` #11130F はこのファミリのどのメンバーからも到達不能
（唯一の消費者 `ViewerPredictionSheet` は `SimulationView` から presented され、
その間ピルは `isSimulationOnTop` で抑止される）。`#0B0C0A` が #11130F をも下回るのは
余裕であって要件ではない。§4.3 側も拘束する地は同じ #1B1D17 — 4消費者のうち
`ResultsView` のタイムラインカードと `GalleryCatalogRow` は `bubbleBackground` の
カードだが、radius 2 / y 1 の影はカードの**外**に落ちるので、合成先は自分の面ではなく
画面の地。#1B1D17 以外に乗るのは `GalleryCatalogRow` 内のアートタイルのバッジ
1件だけで（地はタイルの moss wash (56,61,50)、外周は `nightBubble` #2C2F28）、
同じ tint がどちらも下回るので追加の制約にはならない。なお2レイヤー両方を積むのは
`PromoCard` のみで、他の3消費者は `.tight` 単独。

---

## 5. コンポーネント定義

### 5.1 Phase Header（上部フェーズ帯）

```
[◆] WORD WOLF                            DEMO中
    発言ラウンド 1
```

- 左: 6pt 菱形 (leaf) + `tag/phase` + `title/phase` 縦並び
- 右: `DEMO中`（10pt mono, `--muted`）— **`GameHeader` 以前のモック値。実装の根拠に読まないこと**。出荷しているのは `GameHeaderStatus` のステータスピルで、トークンは §2.3／§8、寸法は §3 の `pill/status`（9pt mono）が正（#1455）
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

48pt 丸（§5.2 と同値。#171 で 42pt → 48pt にバンプ）。4色バリエーション。実際に描かれるのは **毛玉5円 + 顔楕円 + 目2つ + 角2本**（Swift はさらにハイライト1点。SoT の `sheepAvatar()` は描かない）。§2.5 に耳・鼻のトークンはあるが**どちらの実装も描いていない** — 仕様が先行して実装が角の羊になった名残。詳細SVGは `./demo-replay-reference.html` の `sheepAvatar()` 参照。

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
| 塗り | `mossDark`（#6B7852）。`inkOnAccent` とのコントラスト ≈ 4.74:1（light、WCAG AA 達成）／ ≈7.12:1（dark、AAA）。`.borderedProminent` は継承された `.tint(Color.moss)` から塗るので ≈ 3.03:1（light）／≈2.13:1（dark） で AA 未達のため不可 |
| 文字色 | `inkOnAccent`（**light では白**、dark は #2C2F28 の near-ground tone。§1「純白を避ける」は背景の話で、アクセント上の文字は対象外） |
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

**再生/停止ボタン（円形主操作）**: フロストのコントロールバー（§4.3）上の主操作。`mossDark` 塗り 34pt 円＋白グリフ（14pt）。素のグリフ（ink）だとバー上で唯一の塗り要素が「黒い塊」として浮いて読めたため、明示的な主操作コントロールにした。**円自身に影は付けない** — バーが既に単一の浮遊要素（§1「観察＝持ち上げない」/ §4.3「Sim で単一要素のみ」）なので二重持ち上げを避ける。disabled は `disabledText` 塗り（コントラスト対象外の根拠は §2.9 の `nightDisabledText` 行が記録する WCAG 1.4.3 非活性除外。§8 は disabled に言及していない）。

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
- **`--muted`（#8A8A83）quietude 階層は意図的に sub-AA**（#FCFAF4 上で ≈ 3.3:1）。一覧キャプション（`provenance · N agents · N rounds`）・脚注・アンビエントなラベル（`DEMO中` など）に使う、§1 の「静謐・観察」を体現する控えめなティアで、上の 4.5:1 要件の対象外とする意図的な判断。これにより § 2.2（`--muted` をメタ情報・脚注に割り当て）と本節の整合を取る。判読が要る情報をこのティアに置かないこと
- ⚠️ **上の免除は「測った地」にしか及ばない。** ≈ 3.3:1 は `screen-bg` 上の値で、`muted` は出荷している12の地（両外観 6 ずつ）で **2.136〜4.152** に散る。最悪は `--moss-soft` 上の 2.136、ダークで最もバーに近いのが `night-page` 上の 4.152（バーの 8% 下）。**ページ地で正当にアンビエントなラベルが、色付きの塗りの上では大きく下回っていても「§8 公認」に見える** — 地を変えたら測り直すこと。12組は `DesignTokensTests+MutedAsContent` が pin しており、残りサイトのアプリ全体掃引は #1448
- ⚠️ **不透明な12の地でも足りない — 半透明ウォッシュ上に「測っていない地」がもう一段ある。** `muted` テキストが実際に載るウォッシュは3種類（自分自身のウォッシュ、苔系ウォッシュ、`ReportSheet` チップの `rule@0.45`）で、いずれも上の12組のどれとも一致しない。シート地は Pastura トークンではないので、地を1つ決め打ちせず**全12地に対して量化**している。**「新しい最悪」ではなく「§8 が測っていない地」** — どれも `--moss-soft` 上の 2.136 を下回らないので12組の幅がトークンを依然として囲む。この順序そのものを `compositedGroundsStayAboveTheOpaqueWorstCase` が pin する。⚠️ **「未測定」は「違反」ではない。** U は「§8 を根拠に引用できない」という意味であって、repoint の要否は上のバレット3の役割判定（一覧キャプション・脚注・アンビエントか）で決める。役割がアンビエントなら、測り直した比が sub-AA でもバレット3のまま**据え置く** — `ResultsView` の `.pending` ピルと `ActiveModelChip` がその実例で、意図的に quiet なまま残してある。ここを「未測定だから上げる」と読むと、§1 の「静謐・観察」を体現するために意図的に置いた階層を機械的に潰すことになり、出荷後に戻すのは難しい。**比を合成で出すときは fixture の `composite` / `contrastRatio` を使うこと**（チャンネルを 0–255 に量子化する自作スクリプトはずれる）。**サイトごとの比はここに写さない** — 正本は fixture が実行時に計算し、その転記が `muted-application-audit` §3.2（導出は ADR-028 § Amendment 2026-08-15）
- **「この画面で他に書いていない」は必要条件でしかない。** 掃引の初回トリアージはこれを十分条件として使い、出荷 88 サイト中 41 を must-read に分類した — §8 が公認例として自分で挙げている `HomeCompactScenarioRow` のキャプション（`provenance · N agents · N rounds`）まで含めて。判定は「その `muted` テキストが次の5つのいずれかを**単独で**述べているか」で行う: **(A1)** 使えない状態とその理由、**(A2)** 進むために要る指示、**(A3)** ユーザーが行動の対象にする数値・識別子、**(A4)** 劣化・失敗の結末（ADR-021 D5）、**(A5)** その画面が存在する理由である一次出力。逆に**公認**なのは一覧キャプション・タイムスタンプ・その一覧自身の件数・セクション見出し・区切り（`vs` `·`）・順序が既に付いた列の順位・一過性の進捗ナレーション・脚注・ブランドの eyebrow・開示アフォーダンスのラベル（開示される中身ではなく）。両方向の対照とサイトごとの裁定は `docs/design/muted-application-audit.md` §2 / §5
- **`--muted` の母集団には常設の追跡がある。** `MutedSweepLedgerTests` が `Color.muted` の**ファイル別出現数**を台帳 §5 の写しとして pin し、**除去だけでなく追加でも落ちる**。`Color.muted` という**綴り**が母集団の定義なので、エイリアスを経由しない読み（固定外観の書き出しが要求する `PasturaPalette.muted` 直読み）は別 arm で押さえる — 台帳 §1.1。⚠️ **これを「もう misapplication は無い」と読まないこと** — 上の moss 系バレットと同じ注意がここにも要る。gate が見るのは**母集団**（綴りの出現数）だけで、§5 の S/M 裁定が正しいことも、未着手のバッチが残っていないことも保証しない（残件は台帳 §5 Tally と §7 の表が持つ）。緑は「集合が台帳のスナップショットと一致している」以上を意味しない
- **置き換えるトークンは「地を所有するファミリ」が供給する。** §8 が縛るのは**比**であって特定のトークンではない。不透明な `--moss-soft` 上なら §2.3/§2.6 の Soft+Ink ペアリングで `--moss-ink`、中立なカード面なら `--ink-2`（`PasturaApp` の DB 移行失敗文が先例）、**半透明のウォッシュ上なら §2.2/§2.3 の `*-on-wash` 役割トークン** — 苔系は `--moss-on-wash`、インク系は `--ink-on-wash`。この 3 つ目の地を落とすと、半透明のインク系ウォッシュを追ってきた読者が `--ink-2` に着地する — つまり dark で 4.413〜4.773 を出した当のトークンで、#1408 はまさにそれを直した（導出は ADR-028 § Amendment 2026-08-13（#1408））。**§2.4 の L3 プリセットの段を借りないこと** — 値が合っても §2.4 は DL 進捗の役割を持つ梯子で、借りると2つのファミリが結合する（ADR-028 § "Three narrower rejections"）。同じ #4A4E3D が別の役割で要るとき、このリポジトリは `--header-meta-ink` を**別トークンとして起こした**（§2.12）。L3 が正解なのは §2.4 自身のメタ面。導出は ADR-028 § Amendment 2026-08-13（#1427）
- **例外は1つだけ。しかも「役割が文書化されていれば既定を上書きしてよい」ではない。** 上の既定（半透明ウォッシュ → `*-on-wash`）を外れてファミリの **Ink 段**を使ってよいのは、次の4つを**すべて**満たす場合に限る: **(1)** §2.2/§2.3 がその Ink 段に**その意味そのもの**の役割を割り当てている、**(2)** 同じファミリのウォッシュ上でその段を描いている出荷済みのピルが既にある — **ただしこの例外を経由して着地したサイトは先例に数えない**（さもないと最初の1件が以後すべての (2) を自動的に満たし、条件がラチェットで緩む）、**(3)** その要素が**行の主役を上回らない**（階層が反転しない）、**(4)** 借りる Ink 段が、過去の amendment でコントラスト不足を理由に退けられたトークン**ではない**。今日これを満たすのは**完了**だけで、答えは `--moss-ink` — (1) は §2.3 の「完了タイトル」、(2) は `ResultsView` の完了ピル、(3) はヘッダのタイトルが完了ピルを上回ること（light 13.147 対 8.604、dark 10.769 対 6.047）、(4) は `--moss-ink` がどの amendment でも失敗トークンでないこと。`GameHeaderStatus.completed` がこの経路
- ⚠️ **インク系はこの例外を取らない。上のバレットの `--ink-2` に関する記述はそのまま有効。** インク系の Ink 段は `--ink`（`--ink-2` ではない — あれは #1408 で dark 4.413〜4.773 を出した当の失敗トークンで、置き換え先の候補ですらない = 条件 (4) で落ちる）。その `--ink` は (1) を満たさない（§2.2 は本文の段としか結び付けていない）し、(3) でも落ちる — バーはクリアするのに #1408 が**役割**を理由に退けたのがまさにこれで、`nightInkWouldAlsoClearTheBarAndIsRejectedOnRoleNotContrast` がその算術を pin している。**「文書化された役割＋出荷先例」だけで既定を上書きしてよい、と一般化しないこと** — (1)(2) だけなら通ってしまう組み合わせがある。導出は ADR-028 § Amendment 2026-08-14（#1455）
- ⚠️ **「§8 の例外が認めるサイト」と「同じ形をしたサイト」は別集合。** 半透明の同族ウォッシュ上に Ink 段が乗っているサイトは、上の4条件を満たさなくても存在しうる — 満たさないなら**コントラストではなく routing の問題**で、比がバーを越えていても正当化されていない。実例だった `HomePausedCard` の進捗ラベル（`--moss-ink` on `--moss` 0.16→0.07。「Round X / Y」は §2.3 がこのトークンに与えたどの役割でもなかった）は #1459 で `--moss-on-wash` へ repoint 済み。**#1459 時点の掃引では他に出なかったが、これを「もう無い」と読まないこと** — 掃引は `DesignTokensTests+MossInkAsWashLabel` の doc が持つ `rg 'Color\.moss(Dark)?\.opacity\('` を起点にした手作業で、新しいサイトを検出する gate は無く、`--muted` における #1448 のような常設の追跡も置いていない
  - **比を下げてよいのは §8 の既定が指すトークンへ戻すときに限る。** #1459 は 8.807→5.782（light）/ 5.927→5.550（dark）と、**バーを越えていた比を意図的に下げた**。根拠は routing（既定のトークンへ戻した）であって階層判断そのものではない — **「階層のために比を下げてよい」と一般化しないこと**。fixture の下限は 4.5 だけなので、余裕を残した引き下げはテストに一切映らない。コントラストの修理ではないので、この形を「AA 落ちを直す」話としても読まないこと
  - **`DesignTokensTests+MossInkAsWashLabel` は例外の許可リストではない。** membership の正本はあの fixture で、ここの名前は今日の写しにすぎない。**行ごとに**見ること: `"ResultsView.completed"` は条件 (2) の先例**そのもの**なので (2) を自分で満たすとは言えない。`"GameHeader.statusPill"`（= `GameHeaderStatus.completed`）は4条件を満たすが、carve-out により**次のサイトの (2) にはなれない**。集合として「行があれば4条件を満たす」と要約しないこと。同じ形が再び現れたら、比ではなく §2.2/§2.3 の役割から判定に入る。**ここの写しは `scripts/check-mossink-wash-membership.py` が set-equality で pin している**（pre-commit サブゲート / CI `shell-tests`）。fixture に行を足してここを更新しない場合も、逆にここが fixture の持たない名前を挙げる場合も落ちる。ただし**緑は名前の集合が一致していること以上を言わない** — 名前だけ足せば緑になるので、上の「行ごとに」はゲートが肩代わりしない。アプリ側の新しいサイトを検出するものでもない（一つ上のバレットの記述はそのまま有効）
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

# Pastura シナリオ形式リファレンス

このページは Pastura シナリオが使う YAML 形式の完全なリファレンスです。
人間と言語モデルの両方が読むことを想定しています。LLM にシナリオの下書きを
依頼する場合は、このページの Markdown 生データを
`https://pastura.app/docs/scenario/format.md` で参照させることができます。

シナリオは 1 つの YAML ファイルです。Pastura はローカル LLM に各エージェントを
演じさせ、宣言したフェーズに従ってラウンドごとに実行します。シナリオの内容が
サーバーに送信されることはありません。

## トップレベル構造

```yaml
id: unique_snake_case_id      # required. Stable identifier, snake_case
language: en                  # required. Authoring language: `ja` or `en`
name: My Scenario             # required. Display title
description: One-line summary  # required
agents: 5                     # required. Number of agents, 2 to 10
rounds: 3                     # required. Number of rounds, 1 to 30
context: |                    # required. Shared briefing every agent sees
  You are contestants in a game...
personas:                     # required. One entry per agent (length == agents)
  - name: Alex
    description: A calm strategist who plans several moves ahead.
  - name: Mia
    description: An optimist who trusts people by default.
phases:                       # required. The ordered list of what happens
  - type: speak_all
    prompt: What do you say to the group?
    output:
      statement: string
      inner_thought: string
```

人間向けの文字列（`name`、`description`、`context`、各 `prompt`、各
`template`、各ペルソナの `name` / `description`）はすべて `language` で
指定した言語で書いてください。この値がエンジンのプロンプト生成方法を決めます。

任意のトップレベルキー:

- `simulation_language` は、記述言語と異なる言語でエージェントに発話させたい
  場合に設定します。省略すると `language` と同じ言語で話します。
- `log_window` は、各プロンプトに含める直近の会話エントリ数を設定します。
  `speak_each` フェーズがある場合は少なくともエージェント数以上にしてください。
  それより小さいと、同じラウンド内で先に発話したエージェントの発言が後続の
  プロンプトから欠落します。

トップレベルに `min_engine_version` キーを追加しないでください。これは
シナリオ YAML スキーマの一部ではなく、単純な整数値を指定するとロードに
失敗します。互換性の管理はシナリオファイルではなくギャラリーのインデックスが
担当します。

## フェーズ

フェーズはラウンドごとに上から下へ実行されます。フェーズには 2 系統あります。

**LLM フェーズ** はエージェントごとに 1 回モデル推論を実行します（`narrate`
のみラウンドごとに 1 回）。それぞれモデルが埋めるフィールドを指定する
`output` ブロックを宣言します。

| フェーズ | 動作内容 | 主フィールド | 内心フィールド |
|-------|--------------|---------------|-----------------------|
| `speak_all` | 全エージェントが同時にグループへ発言する | `statement` | `inner_thought` |
| `speak_each` | エージェントが 1 人ずつ順番に発言し、直前の発言を見て話す | `statement` | `inner_thought` |
| `vote` | 各エージェントが他のエージェントを 1 人指名する | `vote` | `reason` |
| `choose` | 各エージェントが宣言済みの `options` から選ぶ | `action` | `inner_thought` |
| `reflect` | 各エージェントが短いメモを内密に更新する | `note` | （なし） |
| `whisper` | エージェントのペアが内密に 1 行だけやり取りする | `statement` | `inner_thought` |
| `narrate` | 進行役がそのラウンドのハイライトを語る | （エンジン固定） | （なし） |

**コードフェーズ** はモデル呼び出しなしで決定的に実行されるため、`output`
ブロックを宣言しません。

| フェーズ | 動作内容 |
|-------|--------------|
| `score_calc` | 組み込みのスコアリング `logic` を適用してスコアを更新する |
| `assign` | `source` リストの値をエージェントに配分する |
| `eliminate` | 最多得票のエージェントを以降のラウンドから除外する |
| `summarize` | `template` 文字列から要約行を出力する |
| `conditional` | `if` 式の結果に応じてサブフェーズの片方の分岐を実行する |
| `event_inject` | ランダムなイベント文字列を実行状態に注入する |
| `relationship_update` | vote と choose の履歴から親密度マトリクスを更新する |

### 出力フィールドと正式名称

`output` ブロックの名前は自由記述ではありません。各 LLM フェーズには
上の表に示した正式な主フィールドが 1 つあり、多くの場合は正式な内心フィールドも
1 つあります。必ずこの正確な名前を使ってください。異なる名前で保存された
シナリオ（例えば `statement` の代わりに `message` を使うなど）は、エディタで
コミットする際に拒否されます。

```yaml
- type: vote
  prompt: Who do you suspect, and why?
  output:
    vote: string      # canonical primary for `vote`
    reason: string    # canonical private-thought for `vote`
```

内心フィールドは表示専用です。他のエージェントには見えないため、モデルが
発言する前に正直に思考できる場所になっています。

名前そのものに関する 2 つのルール:

- フィールド名は ASCII の英字・数字・アンダースコアのみで構成し、先頭は英字に
  してください。非 ASCII のフィールド名はオンデバイス推論をクラッシュさせる
  ことがあります。フィールドの値は任意の言語で構いません。
- `narrate` は特殊です。出力形状はエンジンによって固定されているため、
  `narrate` フェーズは `output` ブロックを一切宣言しません。

## スコアリングロジック

`score_calc` フェーズは組み込みの `logic` を 1 つ指定します。

| ロジック | 何を評価するか |
|-------|-----------------|
| `prisoners_dilemma` | ペアリングごとの協力／裏切りの報酬マトリクス |
| `vote_tally` | 得票 1 票につき 1 ポイント |
| `wordwolf_judge` | グループが少数派（正解）を追放できたかどうか |
| `event_reactive` | 直前の `choose` が注入されたイベントと一致したエージェント |

各ロジックは同じラウンドの前段に特定のフェーズがあることを前提としています。
詳しくは下記の落とし穴セクションを参照してください。

## フェーズフィールドリファレンス

`type`、`prompt`、`output` 以外にフェーズへ設定できるフィールド:

- `options`（`choose` 用）: アクションが選ばなければならない選択肢のリスト。
  指定しない場合、アクションは制約のない自由記述になります。
- `pairing`（`choose` と一部のスコアリング用）: `round_robin` は全エージェント
  同士を総当たりでペアリングし、`individual` は各エージェントが独立して
  判断します。
- `target`（`assign` 用）: `all` は全エージェントに同じ値を与え、
  `random_one` はランダムに選んだ 1 人のエージェントだけに値を与えます
  （ワードウルフ形式のゲームで少数派を決めるのに使います）。
- `source`（`assign` 用）: 配分する値のリスト。空にはできません。
- `rounds`（`speak_each` と `whisper` 用）: フェーズ内で何回の発話サブラウンドを
  行うか。
- `logic`（`score_calc` 用）: 上記のスコアリングロジックのいずれか。
- `template`（`summarize` 用）: 要約文字列。`{scoreboard}` や
  `{current_round}` のような `{...}` プレースホルダーを含められます。
- `if`、`then`、`else`（`conditional` 用）: 条件式と、各分岐のサブフェーズ
  リスト。
- `probability`、`as`、`no_repeat`（`event_inject` 用）: 発火する確率、
  イベントを格納する変数名（デフォルトは `current_event`）、そして直前の
  イベントの再発を避けるかどうか。
- `narrator`（`narrate` 用）: 進行役として語るペルソナ。
- `mood` は任意の内心出力フィールドで、どの LLM フェーズにも追加でき、
  モデルがラウンドをまたいで感情の余韻を持ち越せるようにします。
- `max_sentences` は発話フェーズの長さに上限をかけます。LLM フェーズにのみ
  影響します。

## 条件式

`conditional` フェーズは `if` 式で分岐します。式は `&&`、`||`、括弧を
使って比較を組み合わせられます。

```yaml
- type: conditional
  if: current_round == total_rounds && max_score >= 10
  then:
    - type: summarize
      template: "Final round. {vote_winner} is ahead."
  else:
    - type: speak_all
      prompt: The game continues.
      output:
        statement: string
        inner_thought: string
```

比較演算子は `==`、`!=`、`<`、`<=`、`>`、`>=` です。参照できる変数には
`current_round`、`total_rounds`、`max_score`、`min_score`、
`eliminated_count`、`active_count`、`vote_winner`、特定のエージェントを
指す `scores.<Name>` があります。

**文字列値はダブルクォートで囲んでください。** `name == "Alex"` は
テキスト `Alex` と比較します。シングルクォートの `'Alex'` は未定義の
識別子として読まれるため、比較は常に false になり、その分岐は無言のまま
一度も実行されません。

## よくある落とし穴

以下はいずれも無言の無効化です。シナリオ自体はロードできますが、依存関係が
欠けているか順序が違うために、そのフェーズが実質的に何もしなくなります。
アプリ内エディタはブロッキングになるものを警告してくれますが、最初から
正しく書いておくほうが簡単です。

- `eliminate` は同じラウンド内でそれより前に `vote` が必要です。ないと、
  除外の対象を集計する票数がありません。
- `prisoners_dilemma` はその前に `round_robin` の `choose` フェーズが必要です。
  これがスコアリング対象のペアリングを作ります。
- `wordwolf_judge` は `target: random_one` を指定した `assign`（少数派を
  選ぶため）と、その前の `vote` の両方が必要です。
- `event_reactive` はその前に `event_inject` が必要で、スコアリングが読む
  変数にイベントを格納しておく必要があります。
- `assign` は空でない `source` が必要です。空のリストは何も配分しません。
- 条件式ではテキストをダブルクォートで比較し、`==` の両辺の裸の単語が
  クォートし忘れたペルソナ名ではなく、実在する変数であることを確認して
  ください。

## 完全な例

Prisoner's Dilemma プリセットです。プロンプト文は簡潔さのために省略して
あります。

```yaml
id: prisoners_dilemma_en
language: en
name: Prisoner's Dilemma
description: Five contestants weigh cooperation against betrayal.
agents: 5
rounds: 3
context: |
  You are a contestant on the game show "Prisoner's Dilemma".
  Against each opponent you choose to cooperate or betray.
  Both cooperate scores 3 each. Betraying alone scores 5.
personas:
  - name: Alex
    description: A calm strategist who computes the optimal move.
  - name: Mia
    description: An optimist who trusts people even after being burned.
  # ...three more personas...
phases:
  - type: speak_all
    prompt: Address the group before the round.
    output:
      statement: string
      inner_thought: string
  - type: choose
    prompt: For each opponent, cooperate or betray.
    options:
      - cooperate
      - betray
    pairing: round_robin
    output:
      action: string
      inner_thought: string
  - type: score_calc
    logic: prisoners_dilemma
  - type: summarize
    template: "Round {current_round}: {scoreboard}"
```

#!/usr/bin/env python3
"""
Among Them — シナリオ検証プロトタイプ
=====================================
3つのプリセットシナリオを簡易実行して「面白いか？」を確認するスクリプト。

使い方:
  # Ollama（おすすめ。事前に ollama run gemma4:e2b で起動しておく）
  python among_them_prototype.py -b ollama -s prisoners

  # Claude API
  export ANTHROPIC_API_KEY="your-key"
  python among_them_prototype.py -b claude -s bokete

  # LiteRT-LM（pip install litert-lm-api）
  python among_them_prototype.py -b litert -s wordwolf

  # 全シナリオ一気に
  python among_them_prototype.py -b ollama -s all
"""

import argparse
import json
import os
import random
import re
import sys
import time
from dataclasses import dataclass, field
from typing import Any, Callable

try:
    import yaml
except ImportError:
    yaml = None  # YAMLシナリオ使用時のみ必要

# ---------------------------------------------------------------------------
# LLM Backend（--backend で切り替え）
# ---------------------------------------------------------------------------

# グローバルに保持。main() で設定される
_call_llm_fn: Callable[[str, str], str] | None = None
_backend_name: str = ""
_debug_mode: bool = False


def call_llm(system_prompt: str, user_prompt: str) -> str:
    """現在のバックエンドでLLMを呼び出す。"""
    assert _call_llm_fn is not None, "バックエンドが初期化されていません"
    result = _call_llm_fn(system_prompt, user_prompt)
    if _debug_mode:
        print(f"    [DEBUG raw] {result[:200]}{'...' if len(result) > 200 else ''}")
    return result


def call_llm_with_retry(system_prompt: str, user_prompt: str, max_retries: int = 2) -> dict:
    """LLMを呼び出し、JSONパースに失敗 or 空フィールドがあればリトライ。"""
    for attempt in range(max_retries + 1):
        raw = call_llm(system_prompt, user_prompt)
        parsed = parse_json_response(raw)

        # raw_text が返ってきた = JSONパース失敗
        if "raw_text" in parsed:
            if attempt < max_retries:
                if _debug_mode:
                    print(f"    [DEBUG] JSONパース失敗、リトライ ({attempt + 1}/{max_retries})")
                continue
            else:
                return parsed

        # 主要フィールドが空「...」かチェック
        has_empty = any(
            v == "..." or v == "" or v is None
            for v in parsed.values()
            if isinstance(v, str)
        )
        if has_empty and attempt < max_retries:
            if _debug_mode:
                print(f"    [DEBUG] 空フィールド検出、リトライ ({attempt + 1}/{max_retries})")
            continue

        return parsed

    return parsed


# --- Claude API -----------------------------------------------------------

def _call_claude(system_prompt: str, user_prompt: str) -> str:
    try:
        import anthropic
    except ImportError:
        print("❌ pip install anthropic してください")
        sys.exit(1)

    client = anthropic.Anthropic()
    response = client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=1000,
        system=system_prompt,
        messages=[{"role": "user", "content": user_prompt}],
    )
    return response.content[0].text


# --- Ollama (OpenAI互換API) -----------------------------------------------

def _make_ollama_caller(model: str, base_url: str) -> Callable[[str, str], str]:
    """Ollamaバックエンドのクロージャを返す。"""
    try:
        from openai import OpenAI
    except ImportError:
        print("❌ pip install openai してください")
        sys.exit(1)

    client = OpenAI(base_url=base_url, api_key="unused")

    def _call(system_prompt: str, user_prompt: str) -> str:
        response = client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            temperature=0.8,
            max_tokens=1000,
        )
        return response.choices[0].message.content or ""

    return _call


# --- LiteRT-LM Python API -------------------------------------------------

def _make_litert_caller(model_path: str) -> Callable[[str, str], str]:
    """LiteRT-LM Python バインディングを使うバックエンド。"""
    try:
        import litert_lm
    except ImportError:
        print("❌ pip install litert-lm-api してください")
        print("   モデルファイルは Hugging Face から取得:")
        print("   https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm")
        sys.exit(1)

    # LiteRT-LM の API はまだ変動する可能性があるため、
    # ここではベストエフォートで初期化。動かない場合は CLI 経由の
    # サブプロセス呼び出しにフォールバックする設計。
    engine = None
    try:
        engine = litert_lm.Engine(model_path)
        print(f"  ✅ LiteRT-LM エンジン初期化完了: {model_path}")
    except Exception as e:
        print(f"  ⚠️  LiteRT-LM Python API の初期化に失敗: {e}")
        print(f"  → CLI サブプロセスモードにフォールバックします")

    def _call_api(system_prompt: str, user_prompt: str) -> str:
        prompt = f"<|turn>system\n{system_prompt}<turn|>\n<|turn>user\n{user_prompt}<turn|>\n<|turn>model\n"
        response = engine.generate(prompt, max_tokens=500)
        return response

    def _call_cli(system_prompt: str, user_prompt: str) -> str:
        import subprocess
        import tempfile

        full_prompt = f"[System]\n{system_prompt}\n\n[User]\n{user_prompt}"
        with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False) as f:
            f.write(full_prompt)
            prompt_file = f.name

        try:
            result = subprocess.run(
                [
                    "litert-lm", "run",
                    "--from-huggingface-repo=litert-community/gemma-4-E2B-it-litert-lm",
                    "gemma-4-E2B-it.litertlm",
                    f"--prompt_file={prompt_file}",
                    "--max_tokens=500",
                ],
                capture_output=True, text=True, timeout=120,
            )
            return result.stdout.strip()
        except FileNotFoundError:
            print("❌ litert-lm CLI が見つかりません。")
            print("   uv tool install litert-lm でインストールしてください")
            sys.exit(1)
        finally:
            os.unlink(prompt_file)

    return _call_api if engine else _call_cli


# --- バックエンド初期化 -----------------------------------------------------

def init_backend(backend: str, model: str | None = None, ollama_url: str = "http://localhost:11434/v1") -> None:
    """バックエンドを初期化してグローバルにセット。"""
    global _call_llm_fn, _backend_name

    if backend == "claude":
        if not os.environ.get("ANTHROPIC_API_KEY"):
            print("❌ ANTHROPIC_API_KEY を設定してください")
            print("   export ANTHROPIC_API_KEY='your-key'")
            sys.exit(1)
        _call_llm_fn = _call_claude
        _backend_name = "Claude API (claude-sonnet-4-20250514)"

    elif backend == "ollama":
        ollama_model = model or "gemma4:e2b"
        _call_llm_fn = _make_ollama_caller(ollama_model, ollama_url)
        _backend_name = f"Ollama ({ollama_model} @ {ollama_url})"

    elif backend == "litert":
        model_path = model or "gemma-4-E2B-it.litertlm"
        _call_llm_fn = _make_litert_caller(model_path)
        _backend_name = f"LiteRT-LM ({model_path})"

    else:
        print(f"❌ 未知のバックエンド: {backend}")
        sys.exit(1)

    print(f"\n🤖 バックエンド: {_backend_name}")


# --- JSON パース -----------------------------------------------------------

def parse_json_response(text: str) -> dict:
    """LLMの応答からJSONを抽出。コードブロックやthinkingタグに対応。"""
    text = text.strip()

    # Gemma 4 の thinking タグを除去
    text = re.sub(r"<\|channel>thought\n.*?<channel\|>", "", text, flags=re.DOTALL)

    # コードブロックの除去
    if "```" in text:
        # ```json ... ``` の中身を抽出
        m = re.search(r"```(?:json)?\s*\n?(.*?)\n?```", text, re.DOTALL)
        if m:
            text = m.group(1)

    # テキスト中の最初の { ... } を抽出（前後にゴミがある場合）
    text = text.strip()
    if not text.startswith("{"):
        m = re.search(r"\{.*\}", text, re.DOTALL)
        if m:
            text = m.group(0)

    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return {"raw_text": text}


# ===========================================================================
# シナリオ 1: 囚人のジレンマ
# ===========================================================================

PRISONERS_PERSONAS = [
    {"name": "アキラ", "persona": "冷静な戦略家。常にデータと過去の行動パターンから最適解を計算する。感情に流されない。口調は丁寧で論理的。例:「データ上、協力の期待値が高い」"},
    {"name": "ミサキ", "persona": "お人好しの楽観主義者。基本的に人を信じる。裏切られても「次こそは」と思うタイプ。口調は明るく前向き。例:「みんなで協力すればきっとうまくいく！」"},
    {"name": "リュウジ", "persona": "攻撃的な現実主義者。出し抜けるなら出し抜く。ただし報復されるのは嫌い。口調は粗くて挑発的。例:「甘いこと言ってると痛い目見るぜ」"},
    {"name": "ハルカ", "persona": "社交的な外交官タイプ。同盟を組みたがる。宣言で他者を誘導するのが得意。口調は柔らかく説得力がある。例:「ここは手を組みませんか？」"},
    {"name": "ケンタ", "persona": "気まぐれなトリックスター。予測不能な行動で場を引っかき回す。退屈が嫌い。口調は軽くてふざけている。例:「さーて、今回はどうしよっかなー？」"},
]

PRISONERS_SYSTEM = """あなたはゲーム番組「囚人のジレンマ」の出場者です。キャラクターになりきって演じてください。

## ゲームルール
- 対戦相手と「協力(cooperate)」か「裏切り(betray)」を選ぶ
- 両方協力=各3点 / 自分だけ裏切り=5点（相手は0点） / 両方裏切り=各1点
- 対戦前に全員に向けて宣言できる（嘘やハッタリもOK）

## あなたのキャラクター
名前: {name}
性格: {persona}

## 回答ルール（厳守）
- 必ず日本語で回答すること
- 全フィールドに必ず文章を書くこと（空欄「...」は禁止）
- declarationは1文の日本語の宣言
- inner_thoughtは1文で本心を簡潔に書く
- JSONは必ず1行で書くこと（改行を入れない）
- JSON以外のテキストやコードブロック(```)は書かないこと

## 回答例
入力: 対戦相手はミサキ。過去にミサキは全員に協力している。
出力:
{{"declaration": "ミサキさん、信じ合いましょう！", "action": "betray", "inner_thought": "ミサキはお人好しだから裏切れば5点もらえる。"}}

入力: 対戦相手はリュウジ。前回リュウジに裏切られた。
出力:
{{"declaration": "リュウジ、今回は協力しようぜ。", "action": "betray", "inner_thought": "前回の報復だ、こっちも裏切る。"}}

## 戦略のヒント
- 宣言で「協力する」と言いながらactionでbetrayするのは有効な戦略です（ブラフ）
- 毎回cooperateするだけでは勝てません。時には裏切りも必要です
- あなたの性格に合った判断をしてください"""

def run_prisoners_dilemma(rounds: int = 5):
    agents = PRISONERS_PERSONAS
    scores = {a["name"]: 0 for a in agents}
    history: list[dict] = []

    print("\n" + "=" * 60)
    print("  囚人のジレンマ — 総当たりリーグ戦")
    print("=" * 60)

    for round_num in range(1, rounds + 1):
        print(f"\n--- ラウンド {round_num} ---")

        # 総当たりのペアを作る（簡易版: 隣接ペア）
        pairs = [(agents[i], agents[(i + 1) % len(agents)]) for i in range(len(agents))]

        for a1, a2 in pairs:
            # スコアボードと履歴の要約
            history_summary = ""
            for h in history[-10:]:  # 直近10件
                history_summary += f"  R{h['round']}: {h['p1']}({h['a1']}) vs {h['p2']}({h['a2']})\n"

            context = f"""現在のスコア: {json.dumps(scores, ensure_ascii=False)}

過去の対戦:
{history_summary if history_summary else '  まだなし'}

今回の対戦相手: {a2['name']}"""

            # Agent 1 の行動
            sys1 = PRISONERS_SYSTEM.format(name=a1["name"], persona=a1["persona"])
            r1 = call_llm_with_retry(sys1, context)

            # Agent 2 の行動（相手名だけ変える）
            context2 = context.replace(f"今回の対戦相手: {a2['name']}", f"今回の対戦相手: {a1['name']}")
            sys2 = PRISONERS_SYSTEM.format(name=a2["name"], persona=a2["persona"])
            r2 = call_llm_with_retry(sys2, context2)

            # 得点計算
            act1 = r1.get("action", "cooperate")
            act2 = r2.get("action", "cooperate")
            if act1 == "cooperate" and act2 == "cooperate":
                scores[a1["name"]] += 3; scores[a2["name"]] += 3
            elif act1 == "cooperate" and act2 == "betray":
                scores[a1["name"]] += 0; scores[a2["name"]] += 5
            elif act1 == "betray" and act2 == "cooperate":
                scores[a1["name"]] += 5; scores[a2["name"]] += 0
            else:
                scores[a1["name"]] += 1; scores[a2["name"]] += 1

            history.append({
                "round": round_num,
                "p1": a1["name"], "a1": act1,
                "p2": a2["name"], "a2": act2,
            })

            # 表示
            print(f"\n  {a1['name']} vs {a2['name']}")
            print(f"    {a1['name']}: 「{r1.get('declaration', '...')}」 → {act1}")
            print(f"      (本心: {r1.get('inner_thought', '...')})")
            print(f"    {a2['name']}: 「{r2.get('declaration', '...')}」 → {act2}")
            print(f"      (本心: {r2.get('inner_thought', '...')})")

    print(f"\n{'=' * 60}")
    print("  最終スコア")
    print("=" * 60)
    for name, score in sorted(scores.items(), key=lambda x: -x[1]):
        print(f"  {name}: {score}点")


# ===========================================================================
# シナリオ 2: ボケて（テキスト大喜利）
# ===========================================================================

BOKETE_PERSONAS = [
    {"name": "ツッコミ太郎", "style": "ストレートな一言ツッコミ系。短くて鋭い。例:「お前が言うな」「それ逆だろ」のような切れ味のある一言。"},
    {"name": "シュール子", "style": "シュールで意味不明な方向に飛躍する。脈絡がないほど良い。例:「3年後にこれの意味がわかる」「宇宙の裏側ではこれが普通」"},
    {"name": "あるある先生", "style": "日常の「あるある」に落とし込む。共感を狙う。例:「月曜の朝、みんなこうなってる」「上司がいない日の職場」"},
    {"name": "ブラック山田", "style": "少し毒のあるブラックユーモア。皮肉が効いている。例:「給料日前日の財布の中身」「転職サイトの閲覧履歴」"},
    {"name": "天然ボケ美", "style": "本気で的外れなことを言う天然ボケ。計算ではなく素で面白い。例:「え、これ火曜日ですか？」「あ、おいしそう」"},
]

BOKETE_TOPICS = [
    "スーツを着た猫が真剣な顔で会議室のホワイトボードの前に立っている写真",
    "おばあちゃんがスケボーで坂道を爆走している写真",
    "コンビニの店員が棚の上で寝ている写真",
    "犬が運転席に座ってハンドルを握っている写真",
    "赤ちゃんがノートパソコンでプレゼンしている写真",
]

BOKETE_SYSTEM_BOKE = """あなたはお笑い大喜利バトル番組の出場者です。キャラクターになりきってボケてください。

## あなたのキャラクター
名前: {name}
お笑いスタイル: {style}

## ルール
写真の説明文が与えられます。その写真に一言ボケをつけてください。

## 回答ルール（厳守）
- 必ず日本語で回答すること
- bokeは必ず面白いセリフを書くこと（空欄禁止）
- inner_thoughtは狙いを短く1文で
- JSONは必ず1行で書くこと（改行を入れない）
- JSON以外のテキストやコードブロック(```)は書かないこと

## 回答例
入力: お題: 犬が運転席に座ってハンドルを握っている写真
出力:
{{"boke": "免許見せてみろ", "inner_thought": "短く鋭いツッコミで攻める"}}
{{"boke": "この後ETCのゲートを時速200kmで通過した", "inner_thought": "ありえない展開で飛躍"}}
{{"boke": "助手席の人間のほうが道わかってない", "inner_thought": "運転あるあるに落とす"}}"""

BOKETE_SYSTEM_VOTE = """あなたはお笑い大喜利バトル番組の出場者で、今は審査員として投票します。

## あなたのキャラクター
名前: {name}
お笑いスタイル: {style}

## ルール
他の参加者のボケを見て、自分以外で一番面白いと思うものに投票してください。

## 回答ルール（厳守）
- voteには必ず参加者の名前を正確に書くこと
- reasonは1文で簡潔に（空欄禁止）
- JSONは必ず1行で書くこと（改行を入れない）
- JSON以外のテキストやコードブロック(```)は書かないこと

## 回答例
{{"vote": "シュール子", "reason": "予想外すぎて笑った"}}"""


def run_bokete(rounds: int = 3):
    agents = BOKETE_PERSONAS
    scores = {a["name"]: 0 for a in agents}

    print("\n" + "=" * 60)
    print("  ボケて — AI大喜利バトル")
    print("=" * 60)

    for round_num in range(1, min(rounds + 1, len(BOKETE_TOPICS) + 1)):
        topic = BOKETE_TOPICS[round_num - 1]
        print(f"\n--- ラウンド {round_num} ---")
        print(f"  お題: {topic}")

        # ボケフェーズ
        bokes: dict[str, dict] = {}
        for agent in agents:
            sys_prompt = BOKETE_SYSTEM_BOKE.format(name=agent["name"], style=agent["style"])
            result = call_llm_with_retry(sys_prompt, f"お題: {topic}")
            bokes[agent["name"]] = result
            print(f"\n  {agent['name']}: 「{result.get('boke', '...')}」")
            print(f"    (狙い: {result.get('inner_thought', '...')})")

        # 投票フェーズ
        print(f"\n  --- 投票 ---")
        boke_list = "\n".join([f"  {name}: 「{b.get('boke', '...')}」" for name, b in bokes.items()])

        votes: dict[str, int] = {a["name"]: 0 for a in agents}
        for agent in agents:
            sys_prompt = BOKETE_SYSTEM_VOTE.format(name=agent["name"], style=agent["style"])
            other_bokes = "\n".join([
                f"  {name}: 「{b.get('boke', '...')}」"
                for name, b in bokes.items() if name != agent["name"]
            ])
            result = call_llm_with_retry(
                sys_prompt,
                f"お題: {topic}\n\n他の参加者のボケ:\n{other_bokes}"
            )
            voted_for = result.get("vote", "")
            if voted_for in votes:
                votes[voted_for] += 1
            print(f"  {agent['name']} → {voted_for} ({result.get('reason', '...')})")

        # スコア加算
        for name, v in votes.items():
            scores[name] += v

    print(f"\n{'=' * 60}")
    print("  最終スコア")
    print("=" * 60)
    for name, score in sorted(scores.items(), key=lambda x: -x[1]):
        print(f"  {name}: {score}票")


# ===========================================================================
# シナリオ 3: ワードウルフ
# ===========================================================================

WORDWOLF_PERSONAS = [
    {"name": "ユウキ", "persona": "慎重派。自分からは情報を出さず、他人の発言を観察する。口調は落ち着いている。例:「そうですね、確かにそういう面もありますね」"},
    {"name": "サクラ", "persona": "積極的に話すタイプ。具体的なエピソードを交えて話す。口調は明るい。例:「私この前それやったんだけど、すっごく楽しかった！」"},
    {"name": "タクミ", "persona": "分析的。他の人の発言の矛盾を見つけようとする。口調は知的。例:「ちょっと待って、それってさっきの話と矛盾してない？」"},
    {"name": "アオイ", "persona": "のんびり屋。あまり深く考えず素直に話す。口調はゆったり。例:「えー、なんか好きだなー、あったかい感じがして」"},
    {"name": "レン", "persona": "駆け引き上手。わざと曖昧な発言をして様子を見る。口調はクール。例:「まあ、人それぞれだよね」"},
]

WORDWOLF_TOPICS = [
    {"majority": "りんご", "minority": "みかん"},
    {"majority": "温泉", "minority": "プール"},
    {"majority": "ラーメン", "minority": "うどん"},
]

WORDWOLF_SYSTEM = """あなたはゲーム番組「ワードウルフ」の出場者です。キャラクターになりきって会話してください。

## ゲームルール
- 全員にお題が1つ配られている
- ほとんどの人は同じお題だが、1人だけ違うお題を持っている
- 自分が多数派か少数派かは分からない
- お題について会話する（お題の単語そのものは絶対に言ってはいけない）
- 最後に投票で少数派を当てる

## あなたのキャラクター
名前: {name}
性格: {persona}
あなたのお題: 「{word}」

## 回答ルール（厳守）
- 必ず日本語で回答すること
- statementは必ず1〜2文の発言を書くこと（空欄禁止）
- お題の単語そのものは絶対に言わないこと
- inner_thoughtは1文で簡潔に
- JSONは必ず1行で書くこと（改行を入れない）
- JSON以外のテキストやコードブロック(```)は書かないこと

## 回答例（お題が「りんご」の場合）
{{"statement": "秋になると特に美味しくなるよね、赤くてツヤツヤしてるやつが好き。", "inner_thought": "色と季節の話でみんなの反応を見たい。"}}
{{"statement": "皮をむくのが面倒だけど、その分おいしいよね。", "inner_thought": "皮の話をして反応を観察。"}}"""

WORDWOLF_VOTE_SYSTEM = """あなたはゲーム番組「ワードウルフ」の出場者です。会話を振り返り、少数派を見つけてください。

## あなたのキャラクター
名前: {name}
あなたのお題: 「{word}」

## 回答ルール（厳守）
- voteには必ず参加者の名前を正確に書くこと
- reasonは1文で簡潔に（空欄禁止）
- JSONは必ず1行で書くこと（改行を入れない）
- JSON以外のテキストやコードブロック(```)は書かないこと

## 回答例
{{"vote": "アオイ", "reason": "みんなが色の話をしているときに形の話をしていた"}}"""


def run_wordwolf(rounds: int = 1):
    agents = WORDWOLF_PERSONAS

    print("\n" + "=" * 60)
    print("  ワードウルフ")
    print("=" * 60)

    for game_num in range(1, min(rounds + 1, len(WORDWOLF_TOPICS) + 1)):
        topic = WORDWOLF_TOPICS[game_num - 1]

        # ランダムに1人を少数派に
        minority_idx = random.randint(0, len(agents) - 1)
        words = {}
        for i, agent in enumerate(agents):
            words[agent["name"]] = topic["minority"] if i == minority_idx else topic["majority"]

        print(f"\n--- ゲーム {game_num} ---")
        print(f"  多数派のお題: {topic['majority']} / 少数派のお題: {topic['minority']}")
        print(f"  少数派: {agents[minority_idx]['name']}（プレイヤーには非公開）")

        # 会話ラウンド（3ラウンド）
        conversation_log = ""
        for conv_round in range(1, 4):
            print(f"\n  -- 会話ラウンド {conv_round} --")
            for agent in agents:
                sys_prompt = WORDWOLF_SYSTEM.format(
                    name=agent["name"],
                    persona=agent["persona"],
                    word=words[agent["name"]],
                )
                user_prompt = f"これまでの会話:\n{conversation_log if conversation_log else '（まだなし）'}\n\nあなたの番です。お題について話してください。"
                result = call_llm_with_retry(sys_prompt, user_prompt)

                statement = result.get("statement", "...")
                conversation_log += f"  {agent['name']}: {statement}\n"
                print(f"  {agent['name']}: {statement}")
                print(f"    (本心: {result.get('inner_thought', '...')})")

        # 投票フェーズ
        print(f"\n  -- 投票 --")
        vote_counts: dict[str, int] = {a["name"]: 0 for a in agents}
        for agent in agents:
            sys_prompt = WORDWOLF_VOTE_SYSTEM.format(
                name=agent["name"],
                word=words[agent["name"]],
            )
            result = call_llm_with_retry(sys_prompt, f"会話ログ:\n{conversation_log}")
            voted_for = result.get("vote", "")
            if voted_for in vote_counts:
                vote_counts[voted_for] += 1
            print(f"  {agent['name']} → {voted_for} ({result.get('reason', '...')})")

        # 結果
        most_voted = max(vote_counts, key=vote_counts.get)
        minority_name = agents[minority_idx]["name"]
        success = most_voted == minority_name
        print(f"\n  最多得票: {most_voted} ({vote_counts[most_voted]}票)")
        print(f"  実際の少数派: {minority_name}")
        print(f"  結果: {'多数派の勝ち！少数派を見破った！' if success else '少数派の勝ち！逃げ切った！'}")


# ===========================================================================
# YAML シナリオエンジン
# ===========================================================================

def load_yaml_scenario(file_path: str) -> dict:
    """YAMLシナリオファイルを読み込み、バリデーションして返す。"""
    if yaml is None:
        print("❌ pip install pyyaml してください")
        sys.exit(1)

    with open(file_path, "r", encoding="utf-8") as f:
        raw = f.read()

    # コードブロック除去（LLM生成YAMLへの対応）
    if "```" in raw:
        lines = raw.split("\n")
        lines = [l for l in lines if not l.strip().startswith("```")]
        raw = "\n".join(lines)

    try:
        data = yaml.safe_load(raw)
    except yaml.YAMLError as e:
        print(f"❌ YAMLパースエラー: {e}")
        sys.exit(1)

    # 必須フィールドチェック
    required = ["id", "name", "agents", "rounds", "context", "personas", "phases"]
    missing = [f for f in required if f not in data]
    if missing:
        print(f"❌ 必須フィールドが不足: {missing}")
        sys.exit(1)

    if len(data["personas"]) != data["agents"]:
        print(f"⚠️  agents={data['agents']} だが personas が {len(data['personas'])} 人（personas数を採用）")

    # フェーズタイプチェック
    valid_types = {"speak_all", "speak_each", "vote", "choose", "score_calc", "assign", "eliminate", "summarize"}
    for i, phase in enumerate(data["phases"]):
        if phase.get("type") not in valid_types:
            print(f"❌ phases[{i}] の type が不正: {phase.get('type')}")
            sys.exit(1)

    print(f"✅ シナリオ読み込み完了: {data['name']}")
    print(f"   エージェント数: {len(data['personas'])}")
    print(f"   フェーズ構成: {' → '.join(p['type'] for p in data['phases'])}")
    return data


def _build_system_prompt(scenario: dict, persona: dict, phase: dict) -> str:
    """エージェント用のシステムプロンプトを構築する。"""
    output_fields = phase.get("output", {})
    output_spec = ", ".join([f'"{k}": "{v}"' for k, v in output_fields.items()])

    # choose の場合、options を明示
    options_line = ""
    if phase["type"] == "choose" and "options" in phase:
        opts = ", ".join(phase["options"])
        options_line = f"\n- actionフィールドは必ず次のいずれかを書くこと: {opts}"

    # vote フェーズの場合、候補者名リストを明示
    vote_line = ""
    if phase["type"] == "vote":
        exclude_self = phase.get("exclude_self", True)
        candidates = [p["name"] for p in scenario["personas"] if p["name"] != persona["name"]] if exclude_self else [p["name"] for p in scenario["personas"]]
        vote_line = f"\n- voteフィールドは必ず次の名前のいずれかを正確に書くこと: {', '.join(candidates)}"

    return f"""あなたはシミュレーションの参加者です。キャラクターになりきってください。

## シナリオ
{scenario['context']}

## あなたのキャラクター
名前: {persona['name']}
{persona.get('description', '')}

## 回答ルール（厳守）
- 必ず日本語で回答すること
- 全フィールドに必ず文章を書くこと（空欄「...」は禁止）
- JSONは必ず1行で書くこと（改行を入れない）
- JSON以外のテキストやコードブロック(```)は書かないこと{options_line}{vote_line}

## 出力フォーマット（JSON）
{{{output_spec}}}"""


def _expand_prompt(template: str, variables: dict) -> str:
    """プロンプトテンプレート内の {変数名} を展開する。"""
    result = template
    for key, value in variables.items():
        result = result.replace(f"{{{key}}}", str(value))
    return result


def _run_phase_speak_all(scenario: dict, phase: dict, state: dict) -> None:
    """speak_all: 全員が同時に1つの発言を生成。"""
    print(f"\n  [{phase['type']}]")
    prompt_template = phase.get("prompt", "あなたの意見を述べてください。")

    for persona in scenario["personas"]:
        name = persona["name"]
        if state["eliminated"].get(name):
            continue
        sys_prompt = _build_system_prompt(scenario, persona, phase)
        variables = {**state["variables"], "scoreboard": json.dumps(state["scores"], ensure_ascii=False)}
        user_prompt = _expand_prompt(prompt_template, variables)
        result = call_llm_with_retry(sys_prompt, user_prompt)

        # 表示
        main_field = _get_main_field(phase)
        print(f"  {name}: 「{result.get(main_field, '...')}」")
        if "inner_thought" in result:
            print(f"    (本心: {result['inner_thought']})")

        # ログ蓄積
        state["conversation_log"] += f"  {name}: {result.get(main_field, '...')}\n"
        state["last_outputs"][name] = result


def _run_phase_speak_each(scenario: dict, phase: dict, state: dict) -> None:
    """speak_each: 1人ずつ順番に発言（会話の蓄積あり）。"""
    sub_rounds = phase.get("rounds", 1)
    prompt_template = phase.get("prompt", "これまでの会話: {conversation_log}\nあなたの番です。")

    for sub_round in range(1, sub_rounds + 1):
        print(f"\n  [{phase['type']}] ラウンド {sub_round}/{sub_rounds}")
        for persona in scenario["personas"]:
            name = persona["name"]
            if state["eliminated"].get(name):
                continue
            sys_prompt = _build_system_prompt(scenario, persona, phase)
            variables = {
                **state["variables"],
                "conversation_log": state["conversation_log"] if state["conversation_log"] else "（まだなし）",
                "scoreboard": json.dumps(state["scores"], ensure_ascii=False),
            }
            user_prompt = _expand_prompt(prompt_template, variables)
            result = call_llm_with_retry(sys_prompt, user_prompt)

            main_field = _get_main_field(phase)
            statement = result.get(main_field, "...")
            print(f"  {name}: {statement}")
            if "inner_thought" in result:
                print(f"    (本心: {result['inner_thought']})")

            state["conversation_log"] += f"  {name}: {statement}\n"
            state["last_outputs"][name] = result


def _run_phase_vote(scenario: dict, phase: dict, state: dict) -> None:
    """vote: 全員が誰か1人に投票。"""
    print(f"\n  [{phase['type']}] 投票")
    prompt_template = phase.get("prompt", "最も怪しいと思う人に投票してください。")
    exclude_self = phase.get("exclude_self", True)

    vote_counts: dict[str, int] = {}
    for persona in scenario["personas"]:
        name = persona["name"]
        if state["eliminated"].get(name):
            continue
        vote_counts[name] = 0

    for persona in scenario["personas"]:
        name = persona["name"]
        if state["eliminated"].get(name):
            continue

        candidates = [n for n in vote_counts if (n != name if exclude_self else True)]
        sys_prompt = _build_system_prompt(scenario, persona, phase)
        variables = {
            **state["variables"],
            "conversation_log": state["conversation_log"],
            "candidates": ", ".join(candidates),
            "scoreboard": json.dumps(state["scores"], ensure_ascii=False),
        }
        user_prompt = _expand_prompt(prompt_template, variables)
        result = call_llm_with_retry(sys_prompt, user_prompt)

        voted_for = result.get("vote", "")
        if voted_for in vote_counts:
            vote_counts[voted_for] += 1
        else:
            # agent名以外の投票（例: 有責/無責）も動的に集計
            vote_counts[voted_for] = vote_counts.get(voted_for, 0) + 1
        print(f"  {name} → {voted_for} ({result.get('reason', '...')})")

    state["vote_counts"] = vote_counts
    state["variables"]["vote_result"] = json.dumps(vote_counts, ensure_ascii=False)

    # 投票結果のサマリー表示
    if vote_counts:
        print(f"\n  投票結果:")
        for target, count in sorted(vote_counts.items(), key=lambda x: -x[1]):
            print(f"    {target}: {count}票")


def _run_phase_choose(scenario: dict, phase: dict, state: dict) -> None:
    """choose: 選択肢から1つ選ぶ。"""
    print(f"\n  [{phase['type']}] 選択")
    prompt_template = phase.get("prompt", "選択してください。")
    options = phase.get("options", [])
    pairing = phase.get("pairing")

    if pairing == "round_robin":
        # 総当たりペアリング
        active = [p for p in scenario["personas"] if not state["eliminated"].get(p["name"])]
        pairs = [(active[i], active[(i + 1) % len(active)]) for i in range(len(active))]

        for a1, a2 in pairs:
            choices = {}
            for agent, opponent in [(a1, a2), (a2, a1)]:
                sys_prompt = _build_system_prompt(scenario, agent, phase)
                variables = {
                    **state["variables"],
                    "opponent_name": opponent["name"],
                    "scoreboard": json.dumps(state["scores"], ensure_ascii=False),
                    "conversation_log": state["conversation_log"],
                }
                user_prompt = _expand_prompt(prompt_template, variables)
                result = call_llm_with_retry(sys_prompt, user_prompt)
                action = result.get("action", options[0] if options else "?")
                # オプション外の値をフォールバック
                if options and action not in options:
                    action = options[0]
                choices[agent["name"]] = action
                state["last_outputs"][agent["name"]] = result

            print(f"  {a1['name']}({choices[a1['name']]}) vs {a2['name']}({choices[a2['name']]})")
            state["pairings"].append({
                "p1": a1["name"], "a1": choices[a1["name"]],
                "p2": a2["name"], "a2": choices[a2["name"]],
            })
    else:
        # 全員が個別に選択
        for persona in scenario["personas"]:
            name = persona["name"]
            if state["eliminated"].get(name):
                continue
            sys_prompt = _build_system_prompt(scenario, persona, phase)
            variables = {
                **state["variables"],
                "scoreboard": json.dumps(state["scores"], ensure_ascii=False),
                "conversation_log": state["conversation_log"],
            }
            user_prompt = _expand_prompt(prompt_template, variables)
            result = call_llm_with_retry(sys_prompt, user_prompt)
            action = result.get("action", options[0] if options else "?")
            if options and action not in options:
                action = options[0]
            print(f"  {name} → {action}")
            if "inner_thought" in result:
                print(f"    (本心: {result['inner_thought']})")
            state["last_outputs"][name] = result


def _run_phase_score_calc(scenario: dict, phase: dict, state: dict) -> None:
    """score_calc: 組み込みロジックでスコア計算。"""
    logic = phase.get("logic", "vote_tally")
    print(f"\n  [{phase['type']}] {logic}")

    if logic == "prisoners_dilemma":
        for pairing in state["pairings"]:
            a1, act1 = pairing["p1"], pairing["a1"]
            a2, act2 = pairing["p2"], pairing["a2"]
            if act1 == "cooperate" and act2 == "cooperate":
                state["scores"][a1] += 3; state["scores"][a2] += 3
            elif act1 == "cooperate" and act2 == "betray":
                state["scores"][a1] += 0; state["scores"][a2] += 5
            elif act1 == "betray" and act2 == "cooperate":
                state["scores"][a1] += 5; state["scores"][a2] += 0
            else:
                state["scores"][a1] += 1; state["scores"][a2] += 1
            print(f"  {a1}({act1}) vs {a2}({act2}) → {state['scores'][a1]}, {state['scores'][a2]}")
        state["pairings"] = []

    elif logic == "vote_tally":
        vote_counts = state.get("vote_counts", {})
        for name, count in vote_counts.items():
            if name in state["scores"]:
                state["scores"][name] += count
        ranked = sorted(vote_counts.items(), key=lambda x: -x[1])
        for name, count in ranked:
            cumulative = state["scores"].get(name, "?")
            print(f"  {name}: {count}票 (累計: {cumulative})")

    elif logic == "wordwolf_judge":
        vote_counts = state.get("vote_counts", {})
        if vote_counts:
            most_voted = max(vote_counts, key=vote_counts.get)
            wolf = state["variables"].get("wolf_name", "?")
            success = most_voted == wolf
            print(f"  最多得票: {most_voted} ({vote_counts[most_voted]}票)")
            print(f"  実際のウルフ: {wolf}")
            print(f"  結果: {'多数派の勝ち！' if success else 'ウルフの勝ち！'}")

    else:
        print(f"  ⚠️  未知のロジック: {logic}（スキップ）")


def _run_phase_assign(scenario: dict, phase: dict, state: dict) -> None:
    """assign: エージェントに情報を配布。"""
    source_key = phase.get("source", "")
    target = phase.get("target", "all")
    source_data = scenario.get(source_key, [])

    print(f"\n  [{phase['type']}] 情報配布 ({source_key})")

    if target == "random_one":
        # ワードウルフ型: 1人だけ別の情報を持つ
        active = [p for p in scenario["personas"] if not state["eliminated"].get(p["name"])]
        if isinstance(source_data, list) and len(source_data) > 0:
            topic = random.choice(source_data)
            wolf_idx = random.randint(0, len(active) - 1)
            for i, persona in enumerate(active):
                if i == wolf_idx:
                    state["variables"][f"assigned_{persona['name']}"] = topic.get("minority", str(topic))
                    state["variables"]["wolf_name"] = persona["name"]
                    print(f"  {persona['name']}: 【少数派】")
                else:
                    state["variables"][f"assigned_{persona['name']}"] = topic.get("majority", str(topic))
                    print(f"  {persona['name']}: 多数派")
        else:
            print(f"  ⚠️  source '{source_key}' が見つからないか空です")
    else:
        # 全員に同じ情報を配布
        if isinstance(source_data, list):
            round_idx = state.get("current_round", 1) - 1
            item = source_data[round_idx % len(source_data)] if source_data else ""
            for persona in scenario["personas"]:
                state["variables"][f"assigned_{persona['name']}"] = str(item)
            state["variables"]["assigned_topic"] = str(item)
            print(f"  配布: {item}")
        else:
            state["variables"]["assigned_topic"] = str(source_data)
            print(f"  配布: {source_data}")


def _run_phase_eliminate(scenario: dict, phase: dict, state: dict) -> None:
    """eliminate: 最多得票者を脱落。"""
    mode = phase.get("mode", "most_voted")
    print(f"\n  [{phase['type']}] 脱落判定")

    if mode == "most_voted":
        vote_counts = state.get("vote_counts", {})
        if vote_counts:
            most_voted = max(vote_counts, key=vote_counts.get)
            state["eliminated"][most_voted] = True
            print(f"  💀 {most_voted} が脱落！ ({vote_counts[most_voted]}票)")
        else:
            print(f"  ⚠️  投票結果がありません")


def _run_phase_summarize(scenario: dict, phase: dict, state: dict) -> None:
    """summarize: ラウンド結果を要約表示。"""
    template = phase.get("template", "ラウンド {current_round} 完了")
    print(f"\n  [{phase['type']}]")

    # pairings があればペアごとにテンプレート展開
    if state["pairings"] and "{agent1}" in template:
        for p in state["pairings"]:
            variables = {
                "agent1": p["p1"], "action1": p["a1"],
                "agent2": p["p2"], "action2": p["a2"],
                "score1": str(state["scores"].get(p["p1"], 0)),
                "score2": str(state["scores"].get(p["p2"], 0)),
            }
            print(f"  {_expand_prompt(template, variables)}")
    else:
        variables = {**state["variables"], "current_round": str(state.get("current_round", "?"))}
        print(f"  {_expand_prompt(template, variables)}")


def _get_main_field(phase: dict) -> str:
    """フェーズの主要出力フィールド名を推定する。"""
    output = phase.get("output", {})
    # statement, declaration, boke など発言系のフィールドを探す
    for candidate in ["statement", "declaration", "boke", "speech", "response", "answer"]:
        if candidate in output:
            return candidate
    # 最初のフィールドを使う
    if output:
        return next(iter(output))
    return "statement"


# フェーズタイプ→ハンドラのマッピング
_PHASE_HANDLERS = {
    "speak_all": _run_phase_speak_all,
    "speak_each": _run_phase_speak_each,
    "vote": _run_phase_vote,
    "choose": _run_phase_choose,
    "score_calc": _run_phase_score_calc,
    "assign": _run_phase_assign,
    "eliminate": _run_phase_eliminate,
    "summarize": _run_phase_summarize,
}


def run_yaml_scenario(file_path: str, rounds_override: int | None = None) -> None:
    """YAMLシナリオファイルを読み込んで実行する。"""
    scenario = load_yaml_scenario(file_path)
    rounds = rounds_override if rounds_override is not None else scenario["rounds"]

    # 状態初期化
    state = {
        "scores": {p["name"]: 0 for p in scenario["personas"]},
        "eliminated": {p["name"]: False for p in scenario["personas"]},
        "conversation_log": "",
        "last_outputs": {},
        "vote_counts": {},
        "pairings": [],
        "variables": {},
        "current_round": 0,
    }

    print(f"\n{'=' * 60}")
    print(f"  {scenario['name']}")
    desc = scenario.get("description", "")
    if desc:
        print(f"  {desc}")
    print(f"{'=' * 60}")

    for round_num in range(1, rounds + 1):
        state["current_round"] = round_num
        state["variables"]["current_round"] = str(round_num)
        # ラウンドごとに会話ログと一時状態をリセット（累積させるシナリオは speak_each の rounds で対応）
        state["conversation_log"] = ""
        state["pairings"] = []

        active_count = sum(1 for v in state["eliminated"].values() if not v)
        if active_count < 2:
            print(f"\n  残り{active_count}人のため終了")
            break

        print(f"\n--- ラウンド {round_num}/{rounds} ---")

        for phase in scenario["phases"]:
            handler = _PHASE_HANDLERS.get(phase["type"])
            if handler:
                handler(scenario, phase, state)
            else:
                print(f"\n  ⚠️  未対応フェーズ: {phase['type']}")

    # 最終結果
    print(f"\n{'=' * 60}")
    print("  最終結果")
    print(f"{'=' * 60}")
    for name, score in sorted(state["scores"].items(), key=lambda x: -x[1]):
        status = " 💀" if state["eliminated"].get(name) else ""
        print(f"  {name}: {score}点{status}")


# ===========================================================================
# メイン
# ===========================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Among Them シナリオ検証プロトタイプ",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用例:
  # Ollama で囚人のジレンマを3ラウンド（おすすめ）
  python among_them_prototype.py -b ollama -s prisoners -r 3

  # Ollama で全シナリオ（gemma4:e4b を使う場合）
  python among_them_prototype.py -b ollama -m gemma4:e4b -s all

  # YAMLシナリオを読み込んで実行
  python among_them_prototype.py -b ollama -s yaml --file scenario.yaml

  # Claude API でボケてを検証
  export ANTHROPIC_API_KEY="your-key"
  python among_them_prototype.py -b claude -s bokete

  # LiteRT-LM CLI 経由
  python among_them_prototype.py -b litert -s wordwolf
""",
    )
    parser.add_argument(
        "--backend", "-b",
        choices=["ollama", "claude", "litert"],
        default="ollama",
        help="LLMバックエンド (default: ollama)",
    )
    parser.add_argument(
        "--model", "-m",
        default=None,
        help="モデル名/パス (default: ollama→gemma4:e2b, litert→gemma-4-E2B-it.litertlm)",
    )
    parser.add_argument(
        "--ollama-url",
        default="http://localhost:11434/v1",
        help="Ollama API URL (default: http://localhost:11434/v1)",
    )
    parser.add_argument(
        "--scenario", "-s",
        choices=["prisoners", "bokete", "wordwolf", "yaml", "all"],
        default="all",
        help="実行するシナリオ (default: all). yaml を指定した場合 --file も必要",
    )
    parser.add_argument("--rounds", "-r", type=int, default=None, help="ラウンド数 (default: シナリオ定義に従う、プリセットは3)")
    parser.add_argument("--file", "-f", default=None, help="YAMLシナリオファイルのパス (--scenario yaml 時に使用)")
    parser.add_argument("--debug", "-d", action="store_true", help="LLMの生出力を表示する")
    args = parser.parse_args()

    # YAML シナリオの引数チェック（バックエンド初期化前に行う）
    if args.scenario == "yaml" and not args.file:
        print("❌ --scenario yaml には --file オプションが必要です")
        print("   例: python among_them_prototype.py -s yaml --file scenario.yaml")
        sys.exit(1)

    # バックエンド初期化
    init_backend(args.backend, model=args.model, ollama_url=args.ollama_url)

    # デバッグモード
    global _debug_mode
    _debug_mode = args.debug
    if _debug_mode:
        print("🔍 デバッグモード: LLMの生出力を表示します\n")

    scenarios = {
        "prisoners": ("囚人のジレンマ", run_prisoners_dilemma),
        "bokete": ("ボケて", run_bokete),
        "wordwolf": ("ワードウルフ", run_wordwolf),
    }

    default_rounds = args.rounds if args.rounds is not None else 3
    start_time = time.time()

    if args.scenario == "yaml":
        if not args.file:
            print("❌ --scenario yaml には --file オプションが必要です")
            print("   例: python among_them_prototype.py -s yaml --file scenario.yaml")
            sys.exit(1)
        run_yaml_scenario(args.file, rounds_override=args.rounds)
    elif args.scenario == "all":
        for key, (name, func) in scenarios.items():
            func(rounds=default_rounds)
    else:
        name, func = scenarios[args.scenario]
        func(rounds=default_rounds)

    elapsed = time.time() - start_time

    print(f"\n\n{'=' * 60}")
    print(f"  検証完了！（所要時間: {elapsed:.1f}秒）")
    print(f"  バックエンド: {_backend_name}")
    print(f"  {'─' * 56}")
    print(f"  次のステップ:")
    print(f"  1. 会話ログを読んで「面白いか？」を主観評価")
    print(f"  2. バックエンドを変えて品質比較")
    print(f"     -b claude で高品質、-b ollama -m gemma4:e2b でローカル")
    print(f"  3. プロンプトを調整してイテレーション")
    print(f"{'=' * 60}")


if __name__ == "__main__":
    main()

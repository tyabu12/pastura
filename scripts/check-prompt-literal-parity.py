#!/usr/bin/env python3
"""Hold the Swift <-> Kotlin `pickLanguage` prompt literals in sync (#1295).

ADR-023 keeps the Kotlin `commonMain` engine as a **parallel implementation** of
the shipped Swift one through the migration. Both carry the model-facing ja/en
prompt text, both route it through a `pickLanguage(language, ja:, en:)` helper,
and until this gate nothing checked the pair agreed. They already had: the en
`appendSecretSection` guidance diverged on `main` and survived because it is
small. A behaviour comparison between the two engines is worthless if they are
running different prompts, which is the one thing the parallel port exists to
make comparable.

What this measures: **`pickLanguage` literal-pair parity**, not prompt parity.
See § "What this cannot see" below before trusting it for anything wider.

Membership is Swift-driven
--------------------------
Swift is the shipped source of truth and is where the drift originates, so the
scan starts there: every tracked `.swift` under `Pastura/Pastura/{Engine,LLM}/**`
(the ADR-023 ledger's own scope) that contains a `pickLanguage` CALL. Each is
resolved to a Kotlin counterpart by basename under `shared/engine/src/commonMain`,
stripping a `+Extension` suffix -- which is what pairs `PromptBuilder.swift` +
`PromptBuilder+PrivateSections.swift` + `PromptBuilder+Injection.swift` with the
single `PromptBuilder.kt`.

The Kotlin-driven alternative was rejected: conditioning membership on "the
Kotlin file has literals" means a port that loses its literals drops out of the
scan with ZERO output -- the same silent-miss the hand-written manifest was
rejected for. Swift-driven makes that case fail loudly (every Swift literal
reports as swift-only). It also avoids hard-erroring on the five `commonMain`
files that legitimately have no same-basename Swift original (SimulationException,
RunHandle, SuspensionRelay, LLMBackend, SimulationEngine).

A Swift file with no Kotlin counterpart needs an explicit `unported` allowlist
row. A reverse sweep then catches a Kotlin file carrying literals that the
Swift-driven pass never reached.

Normalization erases interpolation
----------------------------------
The two sides use genuinely different mechanisms -- Swift `String(format:)` with
`%@` / `%lld`, Swift `\\(expr)`, Kotlin `$ident` / `${expr}` -- so comparing
variable names is not possible. All of them collapse to one sentinel, which is
why Swift `"%@ には好感を持っている。"` and Kotlin `"$other には好感を持っている。"`
compare equal. Consequence, stated so nobody over-trusts a green run: this gate
CANNOT detect two sides interpolating a *different value* into a matching
skeleton.

What this cannot see
--------------------
- **Section assembly and separators.** The `\\n` vs `\\n\\n` join in
  `appendSecretSection` (#1295) lives outside every literal.
- **Which value is interpolated** (above).
- **Any prompt-visible literal not routed through `pickLanguage`.** Live
  examples that currently agree, and would therefore drift unnoticed:
  `sentenceNoun` (`"sentence"` / `"sentences"`, interpolated straight into the en
  rules block) and the conversation-log line format (`"  <name>: <content>"`).

Tracked-only scope (NOT a worktree walk), per `.claude/rules/ci-workflows.md`
§ "Gate scripts": a gate asserting a repository invariant reads `git ls-files`,
never `os.walk`, or it goes green on a clean CI checkout and red on a developer
machine holding build output.

Usage:
    check-prompt-literal-parity.py [--check]   # gate the real tree
    check-prompt-literal-parity.py --self-test # validate the checker itself
    check-prompt-literal-parity.py --dump      # print every extracted pair
"""
from __future__ import annotations

import hashlib
import pathlib
import re
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
ALLOWLIST = REPO / "shared" / "prompt-literal-parity-allowlist.tsv"
SWIFT_SCOPE_DIRS = ["Pastura/Pastura/Engine", "Pastura/Pastura/LLM"]
KOTLIN_SCOPE_DIR = "shared/engine/src/commonMain"

# Every interpolation / format placeholder collapses to this, so the two sides'
# different substitution mechanisms compare equal. U+0001 cannot occur in source.
SENTINEL = "\x01"

# Floor guard: the tree holds 13 Swift files with pickLanguage calls. Set close
# to that, not comfortably below it — the `<dir>/**/*.swift` pathspec bug in
# `_tracked` dropped the four files sitting directly in `Engine/` and still left
# 9, so a slack floor would have waved it through (mirrors
# check-adr023-port-coverage.py's MIN_TRACKED_FILES).
MIN_SWIFT_CALLSITE_FILES = 11

# The helper's own declaration in LanguageDispatch.{swift,kt}, whose `ja: String`
# args are types, not literals. Excluding it is load-bearing: the literal parser
# hard-fails on a non-literal argument (deliberately -- a silent skip would hide
# a real call). Anchored at the name and allowing only a generic-parameter list
# between: a looser "`func` appears earlier on this line" test also swallows a
# one-line `func f() -> String { pickLanguage(...) }`, silently dropping a real
# call site from the gate.
_DECL_RE = re.compile(r"\b(?:fun|func)\b\s*(?:<[^>]*>\s*)?$")

_IDENT_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
# printf specifiers, incl. the positional `%1$@` form xcstringstool-adjacent code
# uses. `%%` is handled first so a literal percent survives.
_PRINTF_RE = re.compile(
    r"%(?:\d+\$)?[-+ #0]*[0-9]*(?:\.[0-9]+)?(?:hh|h|ll|l|L|z|j|t|q)?[@diouxXeEfFgGcsSpa]"
)


class ExtractError(Exception):
    """A `pickLanguage` call this parser refuses to guess at."""


# --------------------------------------------------------------------------
# Source scanning
# --------------------------------------------------------------------------


def _read_string_literal(src: str, i: int, kotlin: bool) -> tuple[str, int]:
    """Read the literal starting at `src[i]` (a `"`). Returns (content, end).

    `content` is the RAW source between the delimiters -- escapes are left as
    written (`\\n` stays two characters). Both languages spell the common escapes
    identically, so comparing at this level is consistent; it also keeps a Kotlin
    raw string (which does not process escapes) comparable to its Swift twin.
    """
    if src.startswith('"""', i):
        end = src.find('"""', i + 3)
        if end == -1:
            raise ExtractError("unterminated multi-line string literal")
        return _dedent(src[i + 3 : end], src, end, kotlin), end + 3

    j = i + 1
    out = []
    while j < len(src):
        c = src[j]
        if c == "\\":
            out.append(src[j : j + 2])
            j += 2
            continue
        if c == '"':
            return "".join(out), j + 1
        if c == "\n":
            raise ExtractError("newline inside a single-line string literal")
        out.append(c)
        j += 1
    raise ExtractError("unterminated string literal")


def _dedent(body: str, src: str, close_idx: int, kotlin: bool) -> str:
    """Apply the language's own multi-line dedent rule to a `\"\"\"` body."""
    lines = body.split("\n")
    # Both languages drop the newline right after the opening delimiter and the
    # one right before the closing delimiter.
    if lines and lines[0].strip() == "":
        lines = lines[1:]
    if lines and lines[-1].strip() == "":
        lines = lines[:-1]
    if not lines:
        return ""
    if kotlin:
        # trimIndent(): strip the minimum indent across non-blank lines.
        indents = [len(ln) - len(ln.lstrip()) for ln in lines if ln.strip()]
        strip = min(indents) if indents else 0
    else:
        # Swift: strip the indentation of the CLOSING delimiter's line.
        line_start = src.rfind("\n", 0, close_idx) + 1
        closing = src[line_start:close_idx]
        strip = len(closing) if closing.strip() == "" else 0
    return "\n".join(ln[strip:] if ln.strip() else "" for ln in lines)


def _skip_trivia(src: str, i: int) -> int:
    """Advance past whitespace and comments."""
    while i < len(src):
        if src[i].isspace():
            i += 1
        elif src.startswith("//", i):
            nl = src.find("\n", i)
            i = len(src) if nl == -1 else nl + 1
        elif src.startswith("/*", i):
            end = src.find("*/", i + 2)
            i = len(src) if end == -1 else end + 2
        else:
            return i
    return i


def _read_concatenated(src: str, i: int, kotlin: bool) -> str:
    """Read one or more `+`-joined string literals starting at `src[i]`.

    Kotlin wraps long literals as `"..." +\\n    "..."`; joining before comparison
    is what lets a wrapped Kotlin literal match its unwrapped Swift twin.
    """
    i = _skip_trivia(src, i)
    if i >= len(src) or src[i] != '"':
        raise ExtractError("argument is not a string literal")
    parts = []
    while True:
        content, i = _read_string_literal(src, i, kotlin)
        parts.append(content)
        j = _skip_trivia(src, i)
        if j < len(src) and src[j] == "+":
            k = _skip_trivia(src, j + 1)
            if k < len(src) and src[k] == '"':
                i = k
                continue
        return "".join(parts)


def extract_pairs(text: str, kotlin: bool) -> list[tuple[str, str]]:
    """Every (ja, en) literal pair passed to a `pickLanguage` CALL in `text`.

    Normalized (see module docstring). Raises `ExtractError` on a call this
    parser cannot read -- loudly, rather than skipping it.
    """
    pairs: list[tuple[str, str]] = []
    for m in re.finditer(r"\bpickLanguage\b", text):
        line_start = text.rfind("\n", 0, m.start()) + 1
        if _DECL_RE.search(text[line_start : m.start()]):
            continue  # the helper's own declaration, not a call
        i = _skip_trivia(text, m.end())
        if i >= len(text) or text[i] != "(":
            continue
        args = _scan_call_args(text, i, kotlin)
        if "ja" not in args or "en" not in args:
            raise ExtractError(f"pickLanguage call at offset {m.start()} lacks ja/en")
        pairs.append((normalize(args["ja"], kotlin), normalize(args["en"], kotlin)))
    return pairs


def _scan_call_args(text: str, open_idx: int, kotlin: bool) -> dict[str, str]:
    """Map `ja`/`en` argument labels to their raw literal text, depth-1 only."""
    sep = "=" if kotlin else ":"
    args: dict[str, str] = {}
    depth = 0
    i = open_idx
    while i < len(text):
        c = text[i]
        if c == '"':
            _, i = _read_string_literal(text, i, kotlin)
            continue
        if c in "([{":
            depth += 1
            i += 1
            continue
        if c in ")]}":
            depth -= 1
            if depth == 0:
                return args
            i += 1
            continue
        if depth == 1 and (c == "j" or c == "e"):
            im = _IDENT_RE.match(text, i)
            if im and im.group(0) in ("ja", "en"):
                after = _skip_trivia(text, im.end())
                if after < len(text) and text[after] == sep:
                    args[im.group(0)] = _read_concatenated(text, after + 1, kotlin)
                    i = im.end()
                    continue
            i = im.end() if im else i + 1
            continue
        if c.isalpha() or c == "_":
            im = _IDENT_RE.match(text, i)
            i = im.end() if im else i + 1
            continue
        i += 1
    raise ExtractError("unterminated pickLanguage call")


def normalize(literal: str, kotlin: bool) -> str:
    """Collapse every interpolation / format placeholder to a single sentinel."""
    out = []
    i = 0
    while i < len(literal):
        c = literal[i]
        if not kotlin and c == "\\" and literal.startswith("\\(", i):
            i = _skip_balanced(literal, i + 1, "(", ")")
            out.append(SENTINEL)
            continue
        if c == "\\":
            out.append(literal[i : i + 2])
            i += 2
            continue
        if kotlin and c == "$":
            if literal.startswith("${", i):
                i = _skip_balanced(literal, i + 1, "{", "}")
                out.append(SENTINEL)
                continue
            im = _IDENT_RE.match(literal, i + 1)
            if im:
                out.append(SENTINEL)
                i = im.end()
                continue
        out.append(c)
        i += 1
    text = "".join(out)
    # `%%` is a literal percent -- protect it before collapsing real specifiers.
    text = text.replace("%%", "\x02")
    text = _PRINTF_RE.sub(SENTINEL, text)
    return text.replace("\x02", "%%")


def _skip_balanced(s: str, i: int, opener: str, closer: str) -> int:
    """Index just past the `closer` matching the `opener` at `s[i]`."""
    depth = 0
    while i < len(s):
        if s[i] == opener:
            depth += 1
        elif s[i] == closer:
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise ExtractError("unbalanced interpolation")


# --------------------------------------------------------------------------
# Pairing + comparison
# --------------------------------------------------------------------------


def stem_of(path: str) -> str:
    """`Engine/Phases/ChooseHandler.swift` -> `ChooseHandler`; `A+B.swift` -> `A`."""
    name = path.rsplit("/", 1)[-1]
    name = name.rsplit(".", 1)[0]
    return name.split("+", 1)[0]


def digest(pair: tuple[str, str]) -> str:
    """Allowlist key. Covers BOTH sides, so editing either forces re-approval."""
    raw = (pair[0] + "\x00" + pair[1]).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()[:12]


def excerpt(pair: tuple[str, str], width: int = 48) -> str:
    """A readable, TSV-safe prefix of the ja literal for the allowlist row."""
    s = pair[0].replace("\\", "\\\\").replace("\t", "\\t").replace("\n", "\\n")
    s = s.replace(SENTINEL, "<>")
    return s[:width] if len(s) <= width else s[: width - 1] + "…"


def parse_allowlist(text: str) -> tuple[set[tuple[str, str, str]], set[str], list[str]]:
    """-> (deliberate divergences, unported stems, format errors).

    Row: `<side>\\t<stem>\\t<digest>\\t<excerpt>\\t<reason>` where side is
    `swift-only`, `kotlin-only`, or `unported` (digest/excerpt `-`).
    """
    divergences: set[tuple[str, str, str]] = set()
    unported: set[str] = set()
    errors: list[str] = []
    for lineno, raw in enumerate(text.splitlines(), start=1):
        line = raw.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        cols = line.split("\t")
        if cols[0] == "side":
            continue  # header
        if len(cols) != 5:
            errors.append(f"allowlist line {lineno}: expected 5 tab-separated columns, got {len(cols)}")
            continue
        side, stem, dig, _exc, reason = cols
        if not reason.strip():
            errors.append(f"allowlist line {lineno}: empty reason column")
            continue
        if side == "unported":
            unported.add(stem)
        elif side in ("swift-only", "kotlin-only"):
            divergences.add((side, stem, dig))
        else:
            errors.append(f"allowlist line {lineno}: unknown side {side!r}")
    return divergences, unported, errors


def evaluate(
    swift_sources: dict[str, str],
    kotlin_sources: dict[str, str],
    allowlist_text: str,
) -> list[str]:
    """Return the list of problems; empty means the invariant holds."""
    divergences, unported, problems = parse_allowlist(allowlist_text)
    problems = list(problems)

    def collect(sources: dict[str, str], kotlin: bool) -> dict[str, list[tuple[str, str]]]:
        by_stem: dict[str, list[tuple[str, str]]] = {}
        for path, text in sorted(sources.items()):
            try:
                pairs = extract_pairs(text, kotlin)
            except ExtractError as exc:
                problems.append(f"{path}: cannot extract pickLanguage literals — {exc}")
                continue
            if pairs:
                by_stem.setdefault(stem_of(path), []).extend(pairs)
        return by_stem

    swift_by_stem = collect(swift_sources, kotlin=False)
    kotlin_by_stem = collect(kotlin_sources, kotlin=True)
    kotlin_paths = {stem_of(p): p for p in kotlin_sources}

    for stem in sorted(swift_by_stem):
        if stem not in kotlin_paths:
            if stem not in unported:
                problems.append(
                    f"{stem}: has pickLanguage literals but no Kotlin counterpart under "
                    f"{KOTLIN_SCOPE_DIR}/. If that is a deliberate deferral, add:\n"
                    f"    unported\t{stem}\t-\t-\t<why it is not ported yet>"
                )
            continue
        problems.extend(_compare(stem, swift_by_stem[stem], kotlin_by_stem.get(stem, []), divergences))

    for stem in sorted(kotlin_by_stem):
        if stem not in swift_by_stem:
            problems.append(
                f"{stem}: Kotlin has pickLanguage literals but no Swift file under "
                f"{' / '.join(SWIFT_SCOPE_DIRS)} does — the pair is unanchored."
            )

    # A stale `unported` row would silently exempt a stem that HAS been ported.
    for stem in sorted(unported):
        if stem in kotlin_paths:
            problems.append(
                f"{stem}: allowlisted as `unported` but a Kotlin counterpart now exists "
                f"({kotlin_paths[stem]}) — drop the row and let the comparison run."
            )
        elif stem not in swift_by_stem:
            problems.append(f"{stem}: dangling `unported` allowlist row — no such Swift file with literals.")

    used = {(side, stem, dig) for side, stem, dig in divergences}
    for side, stem, dig in sorted(used - _live_divergences(swift_by_stem, kotlin_by_stem)):
        problems.append(
            f"{stem}: allowlist row `{side}` {dig} no longer matches any divergence — "
            "the literal was changed or reconciled; drop the row."
        )
    return problems


def _live_divergences(
    swift_by_stem: dict[str, list[tuple[str, str]]],
    kotlin_by_stem: dict[str, list[tuple[str, str]]],
) -> set[tuple[str, str, str]]:
    live: set[tuple[str, str, str]] = set()
    for stem in set(swift_by_stem) | set(kotlin_by_stem):
        s, k = _diff(swift_by_stem.get(stem, []), kotlin_by_stem.get(stem, []))
        live.update(("swift-only", stem, digest(p)) for p in s)
        live.update(("kotlin-only", stem, digest(p)) for p in k)
    return live


def _diff(
    swift: list[tuple[str, str]], kotlin: list[tuple[str, str]]
) -> tuple[list[tuple[str, str]], list[tuple[str, str]]]:
    """Multiset difference both ways. Order is NOT compared — the Swift side is
    split across sibling files while Kotlin is one file, so source order is not
    alignable."""
    remaining = list(kotlin)
    swift_only = []
    for pair in swift:
        if pair in remaining:
            remaining.remove(pair)
        else:
            swift_only.append(pair)
    return swift_only, remaining


def _compare(
    stem: str,
    swift: list[tuple[str, str]],
    kotlin: list[tuple[str, str]],
    allowed: set[tuple[str, str, str]],
) -> list[str]:
    swift_only, kotlin_only = _diff(swift, kotlin)
    problems = []
    for side, pairs in (("swift-only", swift_only), ("kotlin-only", kotlin_only)):
        for pair in pairs:
            dig = digest(pair)
            if (side, stem, dig) in allowed:
                continue
            problems.append(
                f"{stem}: {side} pickLanguage literal (no counterpart on the other side)\n"
                f"    ja: {excerpt(pair, 120)}\n"
                f"    en: {excerpt((pair[1], ''), 120)}\n"
                f"  Reconcile both sides, or — if the divergence is deliberate — add:\n"
                f"    {side}\t{stem}\t{dig}\t{excerpt(pair)}\t<why>"
            )
    return problems


# --------------------------------------------------------------------------
# Modes
# --------------------------------------------------------------------------


def _tracked(dirs: list[str], suffix: str) -> dict[str, str]:
    """Tracked files under `dirs` with the given suffix.

    Pathspecs are DIRECTORIES, filtered by suffix here — not a `<dir>/**/*.swift`
    glob. Git pathspec `*` matches `/`, so that glob requires a path component
    between the directory and the file and silently drops everything sitting
    directly in it (`Engine/PromptBuilder.swift` — i.e. the file this gate exists
    for). Written as a glob first; caught only because the reverse sweep called
    the Kotlin side unanchored.
    """
    args = ["git", "-C", str(REPO), "ls-files", "-z", "--"] + dirs
    out = subprocess.run(args, capture_output=True, text=True, check=True).stdout
    sources = {}
    for path in out.split("\0"):
        if path.endswith(suffix):
            sources[path] = (REPO / path).read_text(encoding="utf-8")
    return sources


def _load_real() -> tuple[dict[str, str], dict[str, str], str]:
    swift = _tracked(SWIFT_SCOPE_DIRS, ".swift")
    kotlin = _tracked([KOTLIN_SCOPE_DIR], ".kt")
    return swift, kotlin, ALLOWLIST.read_text(encoding="utf-8")


def check() -> int:
    swift, kotlin, allowlist_text = _load_real()
    with_calls = [p for p, t in swift.items() if re.search(r"\bpickLanguage\s*\(", t)]
    if len(with_calls) < MIN_SWIFT_CALLSITE_FILES:
        print(
            f"prompt-literal parity: only {len(with_calls)} Swift files with pickLanguage "
            f"calls (expected >= {MIN_SWIFT_CALLSITE_FILES}) — enumeration drifted, refusing "
            "to pass.",
            file=sys.stderr,
        )
        return 1
    problems = evaluate(swift, kotlin, allowlist_text)
    if problems:
        print("prompt-literal parity: FAILED\n", file=sys.stderr)
        for p in problems:
            print(f"  - {p}\n", file=sys.stderr)
        print(
            "The Swift and Kotlin engines must render the same prompt text (ADR-023);\n"
            f"deliberate exceptions live in {ALLOWLIST.relative_to(REPO)}.",
            file=sys.stderr,
        )
        return 1
    swift_pairs = sum(len(extract_pairs(t, False)) for t in swift.values())
    kotlin_pairs = sum(len(extract_pairs(t, True)) for t in kotlin.values())
    print(
        f"prompt-literal parity: clean — {swift_pairs} Swift / {kotlin_pairs} Kotlin "
        f"pickLanguage pairs across {len(with_calls)} Swift files."
    )
    return 0


def dump() -> int:
    """Print every extracted pair, so the extractor can be hand-verified once.

    A green `--check` on a broken extractor is indistinguishable from a green
    `--check` on a correct one; this is how you tell them apart.
    """
    swift, kotlin, _ = _load_real()
    for label, sources, is_kotlin in (("SWIFT", swift, False), ("KOTLIN", kotlin, True)):
        print(f"===== {label} =====")
        for path in sorted(sources):
            pairs = extract_pairs(sources[path], is_kotlin)
            if not pairs:
                continue
            print(f"--- {path}  (stem={stem_of(path)}, {len(pairs)} pairs)")
            for pair in pairs:
                print(f"  [{digest(pair)}] ja={pair[0]!r}")
                print(f"  {' ' * 14}en={pair[1]!r}")
    return 0


# --------------------------------------------------------------------------
# Self-test
# --------------------------------------------------------------------------

# Fixtures are copied from the real tree, not invented: the ja rules block puts
# bare `{で始まり}` prose three lines below a real `${maxSentences}` template (a
# brace-anchored normalizer would eat the prose), and the en block embeds both a
# double quote and a triple backtick inside a `"""` body.
_SWIFT_RULES = '''
func f() {
  var rules = pickLanguage(
    language,
    ja: """
      ## 回答ルール（厳守）
      - 発言は\\(maxSentences)文以内で簡潔に書くこと
      - 全フィールドに必ず文章を書くこと（空欄「...」は禁止）
      - JSON以外のテキストやコードブロック(```)は書かないこと
      - {で始まり}で終わる単一オブジェクトのみ出力すること
      """,
    en: """
      ## Response Rules (strict)
      - Keep your statement concise: at most \\(maxSentences) \\(sentenceNoun).
      - Every field must contain a sentence (no empty "..." values).
      - Do not include any text or code fences (```) outside the JSON.
      - Output exactly one object starting with { and ending with }.
      """)
}
'''

_KOTLIN_RULES = '''
fun f() {
    var rules = pickLanguage(
        language,
        ja = """
            ## 回答ルール（厳守）
            - 発言は${maxSentences}文以内で簡潔に書くこと
            - 全フィールドに必ず文章を書くこと（空欄「...」は禁止）
            - JSON以外のテキストやコードブロック(```)は書かないこと
            - {で始まり}で終わる単一オブジェクトのみ出力すること
        """.trimIndent(),
        en = """
            ## Response Rules (strict)
            - Keep your statement concise: at most $maxSentences $sentenceNoun.
            - Every field must contain a sentence (no empty "..." values).
            - Do not include any text or code fences (```) outside the JSON.
            - Output exactly one object starting with { and ending with }.
        """.trimIndent(),
    )
}
'''

# `String(format:)` on one side vs interpolation on the other — the shape
# RelationshipVerbalizer / WordwolfJudgeLogic really use. Plus the empty literal.
_SWIFT_VERB = '''
func g() -> String {
  _ = pickLanguage(language, ja: "", en: " ")
  return String(format: pickLanguage(
    language, ja: "%@ には好感を持っている。", en: "You feel warmly toward %@."), other)
}
'''

_KOTLIN_VERB = '''
fun g(): String {
    pickLanguage(language, ja = "", en = " ")
    return pickLanguage(
        language,
        ja = "$other には好感を" +
            "持っている。",
        en = "You feel warmly " +
            "toward $other.",
    )
}
'''

_DECL_SWIFT = 'nonisolated func pickLanguage(_ l: String, ja: String, en: String) -> String { l }\n'
_DECL_KOTLIN = 'internal fun pickLanguage(language: String, ja: String, en: String): String = language\n'
_ONE_LINE_FUNC = 'func r(_ l: String) -> String { pickLanguage(l, ja: "はい", en: "Yes") }\n'

_HEADER = "side\tstem\tdigest\texcerpt\treason\n"


def self_test() -> int:
    failures: list[str] = []

    def expect(label: str, problems: list[str], want_ok: bool) -> None:
        ok = not problems
        if ok != want_ok:
            failures.append(
                f"{label}: expected {'no problems' if want_ok else 'a failure'}, got {problems!r}"
            )

    sw = {"Pastura/Pastura/Engine/PromptBuilder.swift": _SWIFT_RULES}
    kt = {"shared/engine/src/commonMain/kotlin/com/pastura/engine/PromptBuilder.kt": _KOTLIN_RULES}

    # 1. Positive: multi-line dedent (Swift closing-delimiter vs Kotlin trimIndent),
    #    braced-vs-bare templates, bare {} prose, embedded quote, triple backticks.
    expect("multiline rules block agrees", evaluate(sw, kt, _HEADER), True)

    # Negative control for the fixture itself: if the normalizer were eating the
    # bare `{...}` prose, these two would still match. Assert the prose survives.
    ja_norm = extract_pairs(_SWIFT_RULES, False)[0][0]
    if "{で始まり}で終わる" not in ja_norm:
        failures.append("normalizer destroyed bare `{}` prose adjacent to a template")
    if ja_norm.count(SENTINEL) != 1:
        failures.append(f"expected exactly 1 erased template in the ja block, got {ja_norm.count(SENTINEL)}")
    en_norm = extract_pairs(_SWIFT_RULES, False)[0][1]
    if '(no empty "..." values)' not in en_norm or "```" not in en_norm:
        failures.append("normalizer lost an embedded quote or code fence")

    # 2. Positive: printf-vs-interpolation equivalence, `+`-concatenation, empty literal.
    expect(
        "printf vs interpolation + concatenation agree",
        evaluate(
            {"Pastura/Pastura/Engine/RelationshipVerbalizer.swift": _SWIFT_VERB},
            {"shared/engine/src/commonMain/kotlin/com/pastura/engine/RelationshipVerbalizer.kt": _KOTLIN_VERB},
            _HEADER,
        ),
        True,
    )

    # 3. Negative control — en diverges by one word.
    expect(
        "en divergence is caught",
        evaluate(sw, {k: v.replace("concise", "brief") for k, v in kt.items()}, _HEADER),
        False,
    )

    # 4. Negative control — ja diverges by one character.
    expect(
        "ja divergence is caught",
        evaluate(sw, {k: v.replace("簡潔に", "手短に") for k, v in kt.items()}, _HEADER),
        False,
    )

    # 5. The silent-miss the Kotlin-driven design would have passed: the Kotlin
    #    counterpart exists but has lost its literals.
    expect(
        "Kotlin counterpart present but empty is caught",
        evaluate(sw, {k: "fun f() {}\n" for k in kt}, _HEADER),
        False,
    )

    # 6. Swift file with no Kotlin counterpart at all — needs an `unported` row.
    expect("unported Swift file without a row fails", evaluate(sw, {}, _HEADER), False)
    expect(
        "unported Swift file with a row passes",
        evaluate(sw, {}, _HEADER + "unported\tPromptBuilder\t-\t-\tStage-3 deferral\n"),
        True,
    )
    expect(
        "stale unported row is caught once the port lands",
        evaluate(sw, kt, _HEADER + "unported\tPromptBuilder\t-\t-\tStage-3 deferral\n"),
        False,
    )

    # 7. Kotlin literals with no Swift anchor.
    expect("unanchored Kotlin file is caught", evaluate({}, kt, _HEADER), False)

    # 8. Allowlist honours a deliberate divergence, and goes stale when it heals.
    swift_extra = dict(sw)
    swift_extra["Pastura/Pastura/Engine/PromptBuilder+Extra.swift"] = (
        'func h() { _ = pickLanguage(l, ja: "\\n- 追加ルール", en: "\\n- Extra rule") }\n'
    )
    extra_pair = ("\\n- 追加ルール", "\\n- Extra rule")
    row = f"swift-only\tPromptBuilder\t{digest(extra_pair)}\t{excerpt(extra_pair)}\tdeliberate\n"
    expect("sibling-file literal without a row fails", evaluate(swift_extra, kt, _HEADER), False)
    expect("allowlisted divergence passes", evaluate(swift_extra, kt, _HEADER + row), True)
    expect("stale allowlist row is caught", evaluate(sw, kt, _HEADER + row), False)

    # 9. The declaration is not mistaken for a call (its `ja: String` is a type)…
    if extract_pairs(_DECL_SWIFT, False) or extract_pairs(_DECL_KOTLIN, True):
        failures.append("pickLanguage declaration was parsed as a call")
    # …and the exclusion does not overreach. A "`func` earlier on this line"
    # test drops this real call site silently; that is how it was written first.
    if len(extract_pairs(_ONE_LINE_FUNC, False)) != 1:
        failures.append("a call on the same line as `func` was dropped as a declaration")

    # 10. A malformed allowlist row is reported, not silently ignored.
    expect("short allowlist row is reported", evaluate(sw, kt, _HEADER + "swift-only\tX\n"), False)
    expect("unknown side is reported", evaluate(sw, kt, _HEADER + "both\tX\tabc\t-\twhy\n"), False)
    expect("empty reason is reported", evaluate(sw, kt, _HEADER + "unported\tX\t-\t-\t\n"), False)

    if failures:
        print("prompt-literal parity self-test: FAILED", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1
    print("prompt-literal parity self-test: passed (2 positive + 12 controls).")
    return 0


def main(argv: list[str]) -> int:
    mode = argv[1] if len(argv) > 1 else "--check"
    if mode == "--self-test":
        return self_test()
    if mode == "--dump":
        return dump()
    if mode == "--check":
        return check()
    print(f"usage: {argv[0]} [--check|--self-test|--dump]", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))

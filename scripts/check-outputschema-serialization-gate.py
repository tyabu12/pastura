#!/usr/bin/env python3
"""Fail the build if production code JSON-serializes an `OutputSchema`.

ADR-023 §12 condition 1 leaves the Swift↔Kotlin `OutputSchema` JSON tag-form
difference standing in production and reconciles it only in a parity test
(`SwiftGoldenParityTests`). That is safe **only because no production code in
either language JSON-encodes or JSON-decodes an `OutputSchema` value** — it
crosses the §5.2 K/N boundary as a typed object, scenario input arrives as YAML,
and ADR-023 D2 keeps persistence in Swift/GRDB. The moment a production
serialization site appears, the two languages disagree on the wire shape and the
test-side-only reconciliation becomes a silent bug.

This gate keeps that premise executable rather than prose. Three stacked
detectors run over comment-stripped, tracked-only production source; any hit
fails:

- **D1 — file co-occurrence**: a file that names `OutputSchema` AND calls a
  *native* serializer entry point. The token set is `JSONEncoder`/`JSONDecoder`
  (Swift) and `encodeTo…(`/`decodeFrom…(` (Kotlin) — deliberately NOT
  `JSONSerialization` / hand-built `JsonObject`: those cannot serialize a struct
  without a bespoke `[String:Any]` / `JsonObject` adapter whose shape the author
  writes explicitly, which is not the language-native wire shape the parity test
  governs (that is exactly what `OllamaService` does with the `schema` it reads).
- **D2 — line argument heuristic**: a serializer-call line that also mentions a
  `schema` identifier, catching the type-inferred encode (`encode(backend.schema)`)
  in a file that never spells `OutputSchema`, and the second line of a straddled
  `val j = Json` / `j.encodeToString(schema)`.
- **D3 — containment tripwire**: a non-defining file that puts `OutputSchema`
  next to a `@Serializable` / `Codable` conformance — i.e. a wrapper type gaining
  an `OutputSchema` field, which would serialize it via the wrapper with no
  `OutputSchema` token at any call site (the live `ScenarioCodec` shape:
  `Json.encodeToString(scenario)` never names the type it embeds).

Known bounds, stated rather than papered over:

- A cross-file flow whose calling file neither names `OutputSchema` nor uses a
  `schema`-ish identifier (`let x = backend.constraints; try JSONEncoder().encode(x)`)
  evades all three detectors. Closing it needs type resolution, disproportionate
  here.
- A rename of the type to `OutputSchemaV2` escapes `\\bOutputSchema\\b` — the parse
  guard fails loudly on the resulting zero counts rather than passing empty.
- The scan is **tracked-only** (`git ls-files`), so a brand-new production file
  that is not yet staged is invisible. This is intentional and safe: the
  pre-commit sub-gate runs against the staged index and CI against the committed
  tree, so a real serialization site is always tracked by the time either gate
  sees it. To reproduce the negative control by hand, `git add -N` the probe file
  first, or `git ls-files` will not surface it.

Usage:
    check-outputschema-serialization-gate.py [--check]   # gate the real tree
    check-outputschema-serialization-gate.py --self-test # validate the gate
"""
from __future__ import annotations

import pathlib
import re
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent

# Tracked-only scope globs (git ls-files pathspecs). Swift test roots
# (PasturaTests / PasturaUITests) are siblings of Pastura/Pastura, so excluded
# by the glob; Kotlin *Main excludes commonTest/jvmTest/nativeTest source sets.
SWIFT_GLOBS = ["Pastura/Pastura/**/*.swift"]
KOTLIN_GLOBS = ["shared/*/src/*Main/**/*.kt"]

# The two defining files must be in scope, or the gate is scanning the wrong
# tree (a moved source root, a broken glob) and must fail rather than pass empty.
SWIFT_DEFINING = "Pastura/Pastura/Models/OutputSchema.swift"
KOTLIN_DEFINING = "shared/models/src/commonMain/kotlin/com/pastura/models/OutputSchema.kt"

TYPE_RE = re.compile(r"\bOutputSchema\b")

# D1 native-serializer entry points. Swift: the two whole-value coders. Kotlin:
# any kotlinx `encodeTo…(` / `decodeFrom…(` (String, JsonElement, ByteArray, …).
SWIFT_SERIALIZER_RE = re.compile(r"\bJSONEncoder\b|\bJSONDecoder\b")
KOTLIN_SERIALIZER_RE = re.compile(r"\b(?:encodeTo|decodeFrom)[A-Za-z]+\s*\(")

# D2: a serializer call on a line that also names a `schema` identifier.
SCHEMA_ID_RE = re.compile(r"schema", re.IGNORECASE)

# D3 conformance tokens. Swift `\bCodable\b` does not match `AnyCodableValue`
# (no word boundary at `yC`), verified against ScenarioLoader.swift.
SWIFT_CONFORMANCE_RE = re.compile(r"\bCodable\b|\bEncodable\b|\bDecodable\b")
KOTLIN_CONFORMANCE_RE = re.compile(r"@Serializable")

# Declaration pattern → a file is the type's own definition, self-carved from D3
# by shape rather than by path (a path list rots; a declaration match cannot).
DEFINING_DECL_RE = re.compile(
    r"\b(?:struct|enum|(?:data\s+)?class)\s+OutputSchema\b"
)


def strip_comments(text: str) -> str:
    """Blank out // and /* */ (nesting) comments; keep string contents intact.

    String literals are preserved and scanned as code (over-flag direction — a
    token inside a literal merely co-occurs, it never suppresses a real hit). The
    only job here is to NOT read `//` inside `"https://…"` as a comment start,
    which would blank the real code after it and cause a MISS — the expensive
    error. Handles single/triple-quoted strings, `//`, and nested `/* */` for
    both languages.
    """
    out: list[str] = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        two = text[i : i + 2]
        three = text[i : i + 3]
        if three == '"""':
            out.append(three)
            i += 3
            while i < n and text[i : i + 3] != '"""':
                out.append(text[i])
                i += 1
            if i < n:
                out.append('"""')
                i += 3
            continue
        if c == '"':
            out.append(c)
            i += 1
            while i < n and text[i] != '"':
                if text[i] == "\\" and i + 1 < n:
                    out.append(text[i])
                    out.append(text[i + 1])
                    i += 2
                    continue
                out.append(text[i])
                i += 1
            if i < n:
                out.append('"')
                i += 1
            continue
        if two == "//":
            while i < n and text[i] != "\n":
                out.append(" ")
                i += 1
            continue
        if two == "/*":
            depth = 1
            out.append("  ")
            i += 2
            while i < n and depth > 0:
                if text[i : i + 2] == "/*":
                    depth += 1
                    out.append("  ")
                    i += 2
                elif text[i : i + 2] == "*/":
                    depth -= 1
                    out.append("  ")
                    i += 2
                else:
                    out.append("\n" if text[i] == "\n" else " ")
                    i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def lang_of(path: str) -> str:
    return "swift" if path.endswith(".swift") else "kotlin"


def detect_d1(stripped: str, lang: str) -> bool:
    if not TYPE_RE.search(stripped):
        return False
    ser = SWIFT_SERIALIZER_RE if lang == "swift" else KOTLIN_SERIALIZER_RE
    return bool(ser.search(stripped))


def detect_d2(stripped: str, lang: str) -> list[str]:
    ser = SWIFT_SERIALIZER_RE if lang == "swift" else KOTLIN_SERIALIZER_RE
    hits: list[str] = []
    for line in stripped.splitlines():
        if ser.search(line) and SCHEMA_ID_RE.search(line):
            hits.append(line.strip())
    return hits


def detect_d3(stripped: str, lang: str) -> bool:
    if not TYPE_RE.search(stripped):
        return False
    if DEFINING_DECL_RE.search(stripped):
        return False  # the type's own definition is not a containment channel
    conf = SWIFT_CONFORMANCE_RE if lang == "swift" else KOTLIN_CONFORMANCE_RE
    return bool(conf.search(stripped))


def scan(files: list[tuple[str, str]]) -> list[str]:
    """files: (path, raw_text). Returns a finding string per (detector, file)."""
    findings: list[str] = []
    for path, raw in files:
        lang = lang_of(path)
        stripped = strip_comments(raw)
        if detect_d1(stripped, lang):
            findings.append(f"D1 {path}: names OutputSchema and calls a native serializer")
        for line in detect_d2(stripped, lang):
            findings.append(f"D2 {path}: serializer call on a schema line — `{line}`")
        if detect_d3(stripped, lang):
            findings.append(f"D3 {path}: OutputSchema next to a serialization conformance")
    return findings


def _git_files(globs: list[str]) -> list[str]:
    out = subprocess.run(
        ["git", "-C", str(REPO), "ls-files", "--", *globs],
        capture_output=True, text=True, check=True,
    ).stdout
    return [p for p in out.splitlines() if p]


def _read(paths: list[str]) -> list[tuple[str, str]]:
    return [(p, (REPO / p).read_text(encoding="utf-8")) for p in paths]


def check() -> int:
    swift = _git_files(SWIFT_GLOBS)
    kotlin = _git_files(KOTLIN_GLOBS)
    files = _read(swift + kotlin)

    # Parse guard: refuse to pass empty if the scan scope collapsed.
    swift_named = sum(1 for p, t in files if lang_of(p) == "swift" and TYPE_RE.search(t))
    kotlin_named = sum(1 for p, t in files if lang_of(p) == "kotlin" and TYPE_RE.search(t))
    scanned = {p for p, _ in files}
    if swift_named < 10 or kotlin_named < 3:
        print(
            f"serialization gate: only {swift_named} Swift / {kotlin_named} Kotlin files "
            "name OutputSchema — scan scope collapsed (moved root, broken glob, or a "
            "type rename). Refusing to pass silently.",
            file=sys.stderr,
        )
        return 1
    for defining in (SWIFT_DEFINING, KOTLIN_DEFINING):
        if defining not in scanned:
            print(
                f"serialization gate: defining file {defining} not in scan scope — "
                "the glob no longer reaches it. Refusing to pass silently.",
                file=sys.stderr,
            )
            return 1

    findings = scan(files)
    if findings:
        print(
            "serialization gate: production code appears to JSON-serialize an "
            "OutputSchema. ADR-023 §12 condition 1 rests on this never happening — "
            "the Swift↔Kotlin tag form is reconciled test-side only. If this is a "
            "real crossing, revisit that ruling (not this gate); if a false positive, "
            "the token set is the thing to refine.\n",
            file=sys.stderr,
        )
        for f in findings:
            print(f"  {f}", file=sys.stderr)
        return 1

    print(
        f"serialization gate: clean — {swift_named} Swift + {kotlin_named} Kotlin files "
        "name OutputSchema, none serialize it."
    )
    return 0


def self_test() -> int:
    """Per-detector controls: each detector must fire on its own target and stay
    silent on the negative controls, so a dead detector cannot pass by riding
    another's hit. Fixtures carry synthetic paths through the real scan()."""
    KM = "shared/models/src/commonMain/kotlin/com/pastura/models/"
    KT = "shared/models/src/commonTest/kotlin/com/pastura/models/"
    SW = "Pastura/Pastura/LLM/"

    def one(path: str, text: str, want_substr: str | None) -> str | None:
        findings = scan([(path, text)])
        if want_substr is None:
            return None if not findings else f"expected clean, got {findings}"
        return None if any(want_substr in f for f in findings) else \
            f"expected a {want_substr} finding, got {findings}"

    # (label, path, content, expected finding prefix or None-for-clean, must-NOT-contain)
    cases: list[tuple[str, str, str, str | None, list[str]]] = [
        ("N1 kotlin encode",
         KM + "Fixture.kt",
         "fun f(schema: OutputSchema): String = Json.encodeToString(schema)",
         "D1", []),
        ("N2 swift encode",
         SW + "Fixture.swift",
         "func send(schema: OutputSchema) {\n  let d = try JSONEncoder().encode(schema)\n}",
         "D1", []),
        ("N3 inferred encode, no type token",
         SW + "Fixture.swift",
         "func send(backend: Backend) {\n  let d = try JSONEncoder().encode(backend.schema)\n}",
         "D2", ["D1"]),  # D1 must NOT fire — file never names OutputSchema
        ("N4 straddled encode",
         KM + "Fixture.kt",
         "fun f(s: OutputSchema): String {\n  val j = Json\n  return j.encodeToString(outputSchema)\n}",
         "D1", []),
        ("N5 containment channel",
         KM + "Fixture.kt",
         "@Serializable\ndata class Wrapped(val schema: OutputSchema)",
         "D3", []),
        ("C1 comments only",
         KM + "Fixture.kt",
         "// OutputSchema.Field example, Json.encodeToString(x)\n/* @Serializable OutputSchema */\nval x = 1",
         None, []),
        ("C2 // inside a string literal",
         SW + "Fixture.swift",
         'func f(schema: OutputSchema) {\n  let u = "https://x"\n  let d = try JSONEncoder().encode(schema)\n}',
         "D1", []),
        ("C4 defining file shape",
         KM + "OutputSchema.kt",
         "@Serializable\npublic data class OutputSchema(val fields: List<Field>)",
         None, []),
    ]

    errors: list[str] = []
    for label, path, text, want, must_not in cases:
        err = one(path, text, want)
        if err:
            errors.append(f"{label}: {err}")
        for bad in must_not:
            if any(bad in f for f in scan([(path, text)])):
                errors.append(f"{label}: unexpected {bad} finding")

    # C2 specifically: the encode line must survive comment-stripping (the //
    # inside "https://x" must not blank the real code after it).
    c2 = strip_comments('let u = "https://x"\nlet d = try JSONEncoder().encode(schema)')
    if "JSONEncoder" not in c2:
        errors.append("C2 strip: JSONEncoder blanked by a // inside a string literal")

    # C3: N1's content at a test path is out of scope for the real globs. The
    # scan() itself is scope-agnostic (it trusts its caller), so this asserts the
    # glob, not scan — verify the test roots are excluded by _git_files scope.
    tracked = set(_git_files(SWIFT_GLOBS) + _git_files(KOTLIN_GLOBS))
    leaked = [p for p in tracked if "/commonTest/" in p or "/jvmTest/" in p
              or p.startswith("Pastura/PasturaTests/") or p.startswith("Pastura/PasturaUITests/")]
    if leaked:
        errors.append(f"C3 scope: test paths leaked into scan scope: {leaked[:3]}")

    # P0: the real tree must be clean under scan (defensive — check() also runs it).
    real = _read(_git_files(SWIFT_GLOBS) + _git_files(KOTLIN_GLOBS))
    p0 = scan(real)
    if p0:
        errors.append(f"P0 real tree not clean: {p0}")

    if errors:
        for e in errors:
            print(f"self-test: {e}", file=sys.stderr)
        return 1
    print(f"self-test: passed ({len(cases)} detector controls + strip/scope/baseline).")
    return 0


def main(argv: list[str]) -> int:
    mode = argv[1] if len(argv) > 1 else "--check"
    if mode == "--self-test":
        return self_test()
    if mode in ("--check", ""):
        return check()
    print(f"usage: {argv[0]} [--check|--self-test]", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))

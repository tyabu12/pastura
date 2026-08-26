#!/usr/bin/env python3
"""Append one factory-cycle section to the local digest, (date, run_id)-idempotently.

This is the ROOT of a four-script fork family sharing this marker /
same-key-idempotency / bootstrap / flock core: forked by
`.claude/skills/scenario-refine/scripts/append_audit.py`,
`.claude/skills/model-eval/scripts/append_eval.py` and
`.claude/skills/queue-consumer/scripts/append_digest.py`. A real fix to that
shared core is swept across all four.

usage: append_digest.py --results <results.json> --digest <digest.md>
         (results.json must carry `run_id` — the section key is (date, run_id))
       append_digest.py --digest <digest.md> --rebuild-index

Alongside the digest an append also writes a machine-readable sidecar index
`digest-index.jsonl` (one JSON object per scenario, `comment` excluded — it is
the bulk of digest size). The index lets the nightly generation step dedup
against FULL history without reading the ~39k-token digest. It is a REBUILDABLE
cache; digest.md stays the source of truth — `--rebuild-index` regenerates it
from the digest's markdown tables.

The digest is a LOCAL log (gitignored — not committed). If the target
file is absent (clean clone / first run), it is bootstrapped from a
scaffold; the canonical promotion docs live in the skill's SKILL.md
§ Promotion, with only a one-line `Promotion:` pointer kept in the file.

The digest must contain both marker comments:

  <!-- factory-digest:sections -->    new sections inserted directly below
                                      (newest first)
  <!-- factory-digest:promotion -->   promotion pointer footer; never modified

If a section for the same (date, run_id) already exists between the markers
it is REPLACED (so re-running a partially-failed cycle is safe) and a warning
goes to stderr. Two cycles sharing a date but not a run_id keep SEPARATE
sections — before #1542 the key was the date alone and the second run of a
day silently wiped the first run's judging record. A legacy date-only
`## <date>` heading never matches the replace pattern, so pre-#1542 sections
in an existing local digest survive untouched.

Digest + sidecar writes are serialized by an exclusive flock on
`<digest>.lock`: sibling runs sharing a main checkout would otherwise
interleave a read-modify-write and lose a whole section regardless of key.

Missing markers are a hard error — never blind-append.

Results JSON schema (composed by the /scenario-factory session):

{
  "date": "YYYY-MM-DD",
  "run_id": "01:23:45",   // REQUIRED. Recommended value: the cycle's HH:MM:SS
                          // start time — the heading already carries the date,
                          // so unlike queue-consumer's full "YYYY-MM-DD HH:MM"
                          // only the clock part is needed to disambiguate.
                          // Never auto-derived from the clock: a generated
                          // default would give a re-run of a partially-failed
                          // cycle a NEW key and duplicate its section instead
                          // of replacing it.
  "model": "gemma-4-E2B-it-Q4_K_M",
  "notes": "optional free text",
  "scenarios": [
    {
      "id": "factory_20260613_example",
      "name": "...", "theme": "...",
      "axis": "branching / roleplay",   // optional: the under-represented
                                        // gallery axis this scenario targeted
                                        // (SKILL.md Step 1.5); omitted → em-dash
      "yaml": "data/factory/scenarios/2026-06-13/....yaml",
      "run_log": "data/factory/runs/2026-06-13/....jsonl",
      "status": "ok|failed|config_error",
      "attempts": 1, "duration_sec": 123.4,
      "scores": {"coherence": 4, "interaction": 3, "breakdown_free": 5,
                 "humor": 2, "development": 3},   // null when not ok
      "comment": "one-line judge comment",
      "error": null
    }
  ]
}

`development` = cross-round development/surprise, universal across categories; null allowed for single-round scenarios (renders as `–`, same as the existing null-humor handling).
"""

import argparse
import contextlib
import fcntl
import json
import os
import re
import sys
from datetime import datetime

SECTIONS_MARKER = "<!-- factory-digest:sections -->"
# run_id shape: short, filesystem/markdown-safe, and heading-legible. The
# clock-shaped subset is additionally range-checked (see validate_run_id).
RUN_ID_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9:_-]{0,15}")
CLOCK_RE = re.compile(r"\d{2}:\d{2}(:\d{2})?")
PROMOTION_MARKER = "<!-- factory-digest:promotion -->"
RUBRIC_KEYS = ["coherence", "interaction", "breakdown_free", "humor", "development"]
# Bootstrap scaffold for a fresh local log (the digest is gitignored, so a
# clean clone / first run has nothing to append to). Carries BOTH markers
# and a `Promotion:`-prefixed pointer line so the dual-marker validator and
# the SKILL.md § Promotion cross-reference both stay intact.
SCAFFOLD = f"""# Scenario Factory Digest

Local log of `/scenario-factory` cycles, newest first. Gitignored — a
local journal, not committed. Promoting a winning scenario (bundled
preset or shared-scenario gallery) goes through an /orchestrate PR; see
the skill's SKILL.md § Promotion.

{SECTIONS_MARKER}

{PROMOTION_MARKER}
Promotion: channels documented in `.claude/skills/scenario-factory/SKILL.md` § Promotion.
"""


def validate_run_id(run_id):
    """Return an error string, or None when `run_id` is usable as a section key.

    A clock-shaped value is range-checked so a typo like `99:99` is rejected at
    append time rather than becoming a permanent, unreachable section key."""
    if not isinstance(run_id, str) or not RUN_ID_RE.fullmatch(run_id):
        return (f"results.run_id must match {RUN_ID_RE.pattern} "
                f"(recommended: the cycle's HH:MM:SS start time), "
                f"got: {run_id!r}")
    if CLOCK_RE.fullmatch(run_id):
        fmt = "%H:%M:%S" if run_id.count(":") == 2 else "%H:%M"
        try:
            datetime.strptime(run_id, fmt)
        except ValueError:
            return f"results.run_id looks like a clock time but is not one: {run_id!r}"
    return None


@contextlib.contextmanager
def digest_lock(digest_path):
    """Exclusive flock on `<digest>.lock` around the whole read-modify-write.

    The (date, run_id) key stops two same-day runs from OVERWRITING each other's
    section, but not from interleaving: both read the same body, both write, and
    the loser's section vanishes. The lock file is separate from the digest so
    the truncating write below can never drop it, and it covers the sidecar too
    — a sibling must never observe digest and index half-updated."""
    lock_path = digest_path + ".lock"
    os.makedirs(os.path.dirname(lock_path) or ".", exist_ok=True)
    fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o644)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)


def cell(value):
    """Escape a markdown table cell; em-dash for absent values."""
    if value is None or value == "":
        return "–"
    return str(value).replace("|", "\\|").replace("\n", " ")


def render_section(results):
    scenarios = results.get("scenarios", [])
    counts = {"ok": 0, "failed": 0, "config_error": 0}
    for s in scenarios:
        counts[s.get("status", "failed")] = counts.get(s.get("status", "failed"), 0) + 1

    lines = [
        f"## {results['date']} — {results['run_id']}",
        "",
        f"Model: {results.get('model', '?')} | Scenarios: {len(scenarios)} "
        f"(ok {counts['ok']} / failed {counts['failed']} / "
        f"config_error {counts['config_error']})",
        "",
        "| id | name | theme | axis | status | (a) coherence | (b) interaction "
        "| (c) breakdown-free | (d) humor | (e) development | comment |",
        "|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    for s in scenarios:
        scores = s.get("scores") or {}
        comment = s.get("comment") or ""
        if s.get("status") != "ok" and s.get("error"):
            comment = f"{comment} error: {s['error']}".strip()
        row = [
            cell(s.get("id")), cell(s.get("name")), cell(s.get("theme")),
            cell(s.get("axis")), cell(s.get("status")),
        ]
        row += [cell(scores.get(k)) for k in RUBRIC_KEYS]
        row.append(cell(comment))
        lines.append("| " + " | ".join(row) + " |")
    if results.get("notes"):
        lines += ["", f"Notes: {results['notes']}"]
    lines.append("")
    return "\n".join(lines)


# --- Sidecar index (digest-index.jsonl) -------------------------------------
# Index field set: comment is deliberately EXCLUDED (bulk of digest size). The
# index is a rebuildable cache; digest.md is the source of truth.
INDEX_FILENAME = "digest-index.jsonl"

# Rubric header cells render as "(a) coherence" etc. — map the label back to the
# scores dict key (note the header uses a hyphen: "breakdown-free").
RUBRIC_HEADER_TO_KEY = {
    "coherence": "coherence",
    "interaction": "interaction",
    "breakdown-free": "breakdown_free",
    "breakdown_free": "breakdown_free",
    "humor": "humor",
    "development": "development",
}
RUBRIC_HEADER_RE = re.compile(r"^\([a-z]\)\s+(.+)$")


def index_path_for(digest_path):
    """Sidecar index lives in the same directory as the digest, fixed name — so
    tests pointing --digest at a tmp file get a tmp index too."""
    return os.path.join(os.path.dirname(digest_path) or ".", INDEX_FILENAME)


def build_index_lines(date, run_id, scenarios):
    """One index object per scenario. `comment` omitted by design; `axis` /
    `scores` are absent-safe (null when the scenario has none)."""
    lines = []
    for s in scenarios:
        scores = s.get("scores")
        if isinstance(scores, dict):
            # Fill any RUBRIC_KEYS missing from the results dict with None
            # (present-but-null keys are left as-is) — keeps this incremental
            # path provably identical to --rebuild-index, which always
            # materializes every table column from the header.
            scores = {**scores, **{k: scores.get(k) for k in RUBRIC_KEYS if k not in scores}}
        lines.append({
            "date": date,
            "run_id": run_id,
            "id": s.get("id"),
            "name": s.get("name"),
            "theme": s.get("theme"),
            "axis": s.get("axis"),
            "status": s.get("status"),
            "scores": scores,
        })
    return lines


def write_index_incremental(digest_path, results):
    """Update the sidecar from the IN-MEMORY results (not by re-parsing the
    digest just written). (date, run_id)-idempotent: drop existing lines with
    BOTH the same date and the same run_id, mirroring the digest's section
    replace. A pre-#1542 line has no `run_id` key, so it reads as None and can
    never collide with a real run_id — the same survival property the digest's
    legacy date-only headings have. Bootstraps the file if absent. Fail-open:
    any write failure is a single non-fatal stderr warning — the append (digest
    is already persisted) must never fail on the cache.

    Caller must hold digest_lock()."""
    index_path = index_path_for(digest_path)
    date = results["date"]
    run_id = results["run_id"]
    new_lines = build_index_lines(date, run_id, results.get("scenarios", []))
    try:
        kept = []
        if os.path.exists(index_path):
            with open(index_path, encoding="utf-8") as f:
                for raw in f:
                    raw = raw.strip()
                    if not raw:
                        continue
                    obj = json.loads(raw)
                    if obj.get("date") == date and obj.get("run_id") == run_id:
                        continue  # replaced below
                    kept.append(obj)
        with open(index_path, "w", encoding="utf-8") as f:
            for obj in kept + new_lines:
                f.write(json.dumps(obj, ensure_ascii=False) + "\n")
    except (OSError, ValueError) as e:
        # ValueError covers a corrupt existing line (json.JSONDecodeError).
        print(f"warning: could not update sidecar index {index_path}: {e}; "
              f"regenerate it with --rebuild-index", file=sys.stderr)


def split_row_cells(line):
    """Split a markdown table row on UNESCAPED pipes, drop the leading/trailing
    empties from the outer pipes, then unescape `\\|` → `|` (the appender's
    cell() escapes pipes)."""
    parts = re.split(r"(?<!\\)\|", line)
    if parts and parts[0].strip() == "":
        parts = parts[1:]
    if parts and parts[-1].strip() == "":
        parts = parts[:-1]
    return [p.strip().replace("\\|", "|") for p in parts]


def _rebuild_fail(date, header, msg):
    """Rebuild is a manual/recovery operation — unlike the nightly append it
    MUST NOT fail-open into a silently partial index. Hard-fail loudly and
    write nothing."""
    print(f"rebuild-index: unrecognized table shape in section {date}: {msg}",
          file=sys.stderr)
    print(f"  header: {header}", file=sys.stderr)
    sys.exit(2)


def rebuild_index(digest_path):
    """Regenerate the ENTIRE sidecar by parsing the digest's markdown tables.
    Header-name-keyed column mapping (not fixed indices) so all three historical
    shapes parse — pre-axis-column, 4-axis, 5-axis. Writes nothing on any
    unrecognized shape.

    Read-and-rewrite runs under digest_lock(): a nightly append racing a manual
    rebuild would otherwise rebuild from a half-written digest."""
    if not os.path.exists(digest_path):
        print(f"rebuild-index: digest not found: {digest_path}", file=sys.stderr)
        return 1
    with digest_lock(digest_path):
        return _rebuild_index_locked(digest_path)


def _rebuild_index_locked(digest_path):
    with open(digest_path, encoding="utf-8") as f:
        digest = f.read()
    for marker in (SECTIONS_MARKER, PROMOTION_MARKER):
        if digest.count(marker) != 1:
            print(f"rebuild-index: digest must contain exactly one '{marker}'",
                  file=sys.stderr)
            return 1
    body = digest.partition(SECTIONS_MARKER)[2].partition(PROMOTION_MARKER)[0]

    all_lines = []
    section_count = 0
    # Sections are `## YYYY-MM-DD — <run_id>` blocks between the two markers.
    # The date-only form is the pre-#1542 heading: still parsed, with a null
    # run_id that can never collide with a real one.
    for chunk in re.split(r"(?m)^## ", body):
        heading, _, rest = chunk.partition("\n")
        m = re.fullmatch(r"(\d{4}-\d{2}-\d{2})(?: — (.+))?", heading.strip())
        if not m:
            continue  # preamble / non-section text
        date, run_id = m.group(1), m.group(2)
        # A suffix is held to the same shape the append path enforces, so a
        # hand-edited heading (`## <date> — rerun after the OOM`) cannot enter
        # the index as a run_id. Rebuild is a recovery operation: it hard-fails
        # rather than fail-open into a silently wrong index.
        if run_id is not None and validate_run_id(run_id):
            _rebuild_fail(date, heading.strip(),
                          f"heading suffix is not a valid run_id: {run_id!r}")
        section_count += 1

        table_lines = [l for l in rest.split("\n") if l.lstrip().startswith("|")]
        if not table_lines:
            continue
        header_line = table_lines[0]
        colnames = split_row_cells(header_line)
        # Map rubric columns for THIS table; a rubric-shaped but unknown column
        # is an unrecognized shape.
        rubric_cols = {}
        for cn in colnames:
            m = RUBRIC_HEADER_RE.match(cn)
            if m:
                key = RUBRIC_HEADER_TO_KEY.get(m.group(1).strip())
                if key is None:
                    _rebuild_fail(date, header_line,
                                  f"unknown rubric column {cn!r}")
                rubric_cols[cn] = key

        for dl in table_lines[1:]:
            cells = split_row_cells(dl)
            if cells and all(re.fullmatch(r":?-+:?", c) for c in cells):
                continue  # separator row (|---|---|)
            if len(cells) != len(colnames):
                _rebuild_fail(date, header_line,
                              f"row has {len(cells)} cells, header has "
                              f"{len(colnames)}")
            row = dict(zip(colnames, cells))

            def field(name):
                v = row.get(name)
                return None if v in (None, "", "–") else v

            status = field("status")
            scores = None
            if status == "ok":
                scores = {}
                for cn, key in rubric_cols.items():
                    cv = row.get(cn)
                    if cv in (None, "", "–"):
                        scores[key] = None
                    else:
                        try:
                            scores[key] = int(cv)
                        except ValueError:
                            _rebuild_fail(date, header_line,
                                          f"non-integer rubric cell {cv!r} "
                                          f"in column {cn!r}")
            all_lines.append({
                "date": date,
                "run_id": run_id,   # None for a legacy date-only heading
                "id": field("id"),
                "name": field("name"),
                "theme": field("theme"),
                "axis": field("axis"),  # None when the table has no axis column
                "status": status,
                "scores": scores,
            })

    # Full parse succeeded — only now write (so a hard-fail leaves no partial).
    index_path = index_path_for(digest_path)
    with open(index_path, "w", encoding="utf-8") as f:
        for obj in all_lines:
            f.write(json.dumps(obj, ensure_ascii=False) + "\n")
    print(f"rebuilt index {index_path}: {section_count} section(s), "
          f"{len(all_lines)} scenario line(s)")
    return 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--results")
    parser.add_argument("--digest", required=True)
    parser.add_argument("--rebuild-index", action="store_true",
                        help="regenerate digest-index.jsonl from the digest "
                             "(ignores --results)")
    args = parser.parse_args()

    if args.rebuild_index:
        return rebuild_index(args.digest)

    if not args.results:
        print("--results is required unless --rebuild-index is given",
              file=sys.stderr)
        return 2

    with open(args.results, encoding="utf-8") as f:
        results = json.load(f)
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", results.get("date", "")):
        print(f"results.date must be YYYY-MM-DD, got: {results.get('date')!r}",
              file=sys.stderr)
        return 1
    run_id_err = validate_run_id(results.get("run_id"))
    if run_id_err:
        # The digest is the only durable record of a night's judging, so an
        # unattended run that trips this must be recoverable by hand — name the
        # file the operator has to edit and what to do to it.
        print(f"append_digest: {run_id_err}", file=sys.stderr)
        print(f"  add a `run_id` to {args.results} and re-run the append",
              file=sys.stderr)
        return 1

    with digest_lock(args.digest):
        return _append_locked(args, results)


def _append_locked(args, results):
    if not os.path.exists(args.digest):
        # Local-log model: the digest is gitignored, so a clean clone or
        # the very first run has no file. Bootstrap the scaffold.
        os.makedirs(os.path.dirname(args.digest) or ".", exist_ok=True)
        with open(args.digest, "w", encoding="utf-8") as f:
            f.write(SCAFFOLD)

    with open(args.digest, encoding="utf-8") as f:
        digest = f.read()
    for marker in (SECTIONS_MARKER, PROMOTION_MARKER):
        if digest.count(marker) != 1:
            print(f"digest must contain exactly one '{marker}'", file=sys.stderr)
            return 1
    if digest.index(SECTIONS_MARKER) > digest.index(PROMOTION_MARKER):
        print("sections marker must precede promotion marker", file=sys.stderr)
        return 1

    head, _, tail = digest.partition(SECTIONS_MARKER)
    body, _, footer = tail.partition(PROMOTION_MARKER)

    # (date, run_id) idempotency: drop an existing section with the SAME key
    # (everything from its `## <date> — <run_id>` heading up to the next `## `
    # heading or body end). A legacy date-only `## <date>` heading cannot match
    # this pattern, which is what keeps pre-#1542 sections alive.
    pattern = re.compile(
        rf"^## {re.escape(results['date'])} — {re.escape(results['run_id'])}\n"
        r".*?(?=^## |\Z)",
        re.DOTALL | re.MULTILINE)
    body, replaced = pattern.subn("", body)
    if replaced:
        print(f"warning: replaced existing section for {results['date']} "
              f"— {results['run_id']}", file=sys.stderr)

    section = render_section(results)
    body = "\n\n" + section + "\n" + body.strip("\n") + ("\n\n" if body.strip("\n") else "\n")

    with open(args.digest, "w", encoding="utf-8") as f:
        f.write(head + SECTIONS_MARKER + body + PROMOTION_MARKER + footer)

    # Digest (source of truth) is now persisted; update the sidecar cache from
    # the in-memory results. Never fails the append (see write_index_incremental).
    write_index_incremental(args.digest, results)

    action = "replaced" if replaced else "appended"
    print(f"{action} section {results['date']} — {results['run_id']} "
          f"({len(results.get('scenarios', []))} scenario(s)) in {args.digest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

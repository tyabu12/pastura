#!/usr/bin/env python3
"""Validate `docs/gallery/highlights/<id>.json` against ADR-029.

Two consumers, one implementation:

  1. `scripts/check-gallery-entry.sh` runs this as a CLI (`--gallery-json` /
     `--gallery-dir` / `--blocklist` / `--model-registry`, all required — this
     module derives no paths of its own). That is the **enforcement point**
     (ADR-029 Decision 2): a hand-edited highlight never runs the extractor,
     so every rule must be re-derivable here, ungated, in CI.
  2. `scripts/gallery_highlight_extract.py` imports `check_content` as a
     fail-fast convenience before it writes anything.

Hashing is **raw-byte** (`hashlib.sha256` over bytes read in binary mode),
matching `shasum -a 256` and the existing gallery trust chain
(`check-gallery-entry.sh`, `URLSessionGalleryService`). It is deliberately
NOT `scripts/jsonl_to_demo_replay.py`'s `sha256_hex`, which hashes UTF-8
*text* for the demo-replay drift check — different trust root (ADR-029
Decision 1).

Prerequisite: **PyYAML** (`python3 -m pip install 'pyyaml>=6,<7'`), needed to
re-derive the shape a `yaml_hook.kind: persona` fragment promises. CI installs
it in the same job that runs the gate. If it is missing, a `persona` hook fails
with a named message rather than passing unverified — a gate that skips a check
when a dependency is absent is worse than one that is loud about it.

Exit code: 0 when every highlight passes, 1 otherwise. Each failure is one
line on stdout prefixed `highlight: <check> — …` so the bash gate can
aggregate them and a reader can grep a specific class.
"""
import argparse
import collections
import hashlib
import json
import math
import os
import re
import sys
import unicodedata

try:
    import yaml
except ImportError:  # reported as a failure below, never silently skipped
    yaml = None

SCHEMA_VERSION = 1
EXCERPT_MAX = 8

# ADR-029 Decision 1 — the `yaml_hook.kind` allowlist. `persona` promises the
# fragment parses as persona mappings, which licenses the app's
# editor-vocabulary rendition; `raw` claims no structure and is drawn as a YAML
# block, which is what both surfaces did before the discriminator existed
# (§ Amendment 2026-08-08).
YAML_HOOK_KINDS = frozenset({"persona", "raw"})

# A `kind: persona` fragment's mappings may name only these. `secret:` is
# rejected by name: a hidden agenda is a spoiler wherever it appears, and
# Decision 2's secret branch is designed-untested.
PERSONA_FRAGMENT_KEYS = frozenset({"name", "description"})

# ADR-029 Decision 3 — the full PhaseType catalog at last sync with
# `Pastura/Pastura/Models/PhaseType.swift` (raw values). A transcript phase
# outside this set means a new phase type landed (ADR-022 extension
# contract) and its visibility/outcome classification is unassigned.
PHASE_TYPES = frozenset({
    "speak_all", "speak_each", "vote", "choose", "reflect", "whisper",
    "score_calc", "assign", "eliminate", "summarize", "conditional",
    "event_inject", "relationship_update", "narrate",
})

# A persona's public, in-fiction utterance — the only excerpt-eligible output.
ELIGIBLE_PHASES = frozenset({"speak_all", "speak_each"})

# Outcome disclosures. An utterance is ineligible if any of these precedes it
# in the same round's phase list (ADR-029 Decision 3, position rule part 1).
OUTCOME_PHASES = frozenset({"vote", "eliminate", "score_calc", "choose", "summarize"})

# Field-level allowlist: speak phases also emit `inner_thought`.
SOURCE_FIELDS = frozenset({"statement"})

# Model ids that have left `ModelRegistry.catalog` but remain valid as
# `source.model`. A highlight is a pinned snapshot — a statement about the run
# that produced it — and the registry's supersede convention *removes* the old
# entry (`ModelRegistry.swift` § "Model-update (supersede) convention"), so a
# catalog-only check would turn every shipped highlight red on an unrelated
# model-swap PR, with only "re-run the harness" or "delete the excerpt" as
# remedies. Empty today: a swap PR still reddens until its author moves the id
# here — what the list buys is a failure that names its own remedy.
RETIRED_MODEL_IDS = frozenset()

# `id:` / `displayName:` inside a `ModelDescriptor(...)` literal. Anchored at
# line start so `shortDisplayName:` cannot be read as `displayName:`, and
# requiring a quoted value so `lookup(id: ModelID)` and
# `defaultInitialModelID = gemma4E2B.id` are not mistaken for entries.
_REGISTRY_ID = re.compile(r'^\s*id:\s*"([^"]+)"')
_REGISTRY_DISPLAY_NAME = re.compile(r'^\s*displayName:\s*"([^"]+)"')


# --- Hashing + text normalization ------------------------------------------


def sha256_file(path):
    """Raw-byte SHA-256, `shasum -a 256`-equivalent (ADR-029 Decision 1)."""
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def normalize(text):
    """Case- and diacritic-insensitive form for blocklist matching.

    NFD-decompose, drop combining marks, casefold — the same match semantics
    the demo-replay audit procedure pins (ADR-005 §5.2).
    """
    decomposed = unicodedata.normalize("NFD", text)
    stripped = "".join(c for c in decomposed if not unicodedata.combining(c))
    return stripped.casefold()


def load_blocklist(path):
    """-> [(normalized_term, contentCategory, index)] from ContentBlocklist.json."""
    with open(path, encoding="utf-8") as f:
        doc = json.load(f)
    out = []
    for i, entry in enumerate(doc.get("patterns") or []):
        term = normalize((entry or {}).get("term") or "")
        # Filter on the NORMALIZED form: a term of only combining marks
        # normalizes to "" and would substring-match everything.
        if term:
            out.append((term, (entry or {}).get("contentCategory", "?"), i))
    return out


# --- Content checks (shared with the extractor) -----------------------------


def _audited_strings(doc):
    """Every published string, paired with a locator for the failure message."""
    out = []
    for i, ex in enumerate(doc.get("excerpt") or []):
        if isinstance(ex, dict) and isinstance(ex.get("text"), str):
            out.append((f"excerpt[{i}].text", ex["text"]))
    hook = doc.get("yaml_hook")
    if isinstance(hook, dict):
        for key in ("fragment", "caption"):
            if isinstance(hook.get(key), str):
                out.append((f"yaml_hook.{key}", hook[key]))
    if isinstance(doc.get("teaser"), str):
        out.append(("teaser", doc["teaser"]))
    return out


def check_blocklist(doc, blocklist, where):
    """Blocklist audit. Reports the term's *index and category*, never the term."""
    failures = []
    for locator, text in _audited_strings(doc):
        haystack = normalize(text)
        for term, category, index in blocklist:
            if term in haystack:
                failures.append(
                    f"highlight: blocklist — {where} {locator} matches "
                    f"ContentBlocklist patterns[{index}] (category={category}). "
                    "Re-curate the excerpt; the term itself is withheld here.")
    return failures


def _check_schema(doc, where):
    failures = []
    sv = doc.get("schema_version")
    if not isinstance(sv, int) or isinstance(sv, bool) or sv != SCHEMA_VERSION:
        failures.append(
            f"highlight: schema — {where} schema_version must be {SCHEMA_VERSION}, "
            f"got {sv!r}")
    ref = doc.get("scenario_ref")
    if not isinstance(ref, dict) or not isinstance(ref.get("id"), str) \
            or not isinstance(ref.get("yaml_sha256"), str):
        failures.append(
            f"highlight: schema — {where} scenario_ref must be "
            "{id: str, yaml_sha256: str}")
    src = doc.get("source")
    if not isinstance(src, dict) or not all(
            isinstance(src.get(k), str) for k in ("model", "run_id", "generated_at")):
        failures.append(
            f"highlight: schema — {where} source must be "
            "{model: str, run_id: str, generated_at: str}")
    hook = doc.get("yaml_hook")
    if not isinstance(hook, dict) or not isinstance(hook.get("fragment"), str) \
            or not isinstance(hook.get("caption"), str) \
            or not isinstance(hook.get("kind"), str):
        failures.append(
            f"highlight: schema — {where} yaml_hook must be "
            "{kind: str, fragment: str, caption: str}")
    elif hook["kind"] not in YAML_HOOK_KINDS:
        failures.append(
            f"highlight: yaml_hook kind — {where} yaml_hook.kind={hook['kind']!r} is "
            f"not in the allowlist {sorted(YAML_HOOK_KINDS)}. Adding a value means "
            "designing its reading side first (ADR-029 revisit trigger); until then "
            "`raw` publishes the fragment as a YAML block")
    if not isinstance(doc.get("teaser"), str) or not doc.get("teaser").strip():
        failures.append(f"highlight: schema — {where} teaser must be a non-empty string")
    if not isinstance(doc.get("window_override"), bool):
        failures.append(f"highlight: schema — {where} window_override must be a boolean")
    if doc.get("content_filter_applied") is not True:
        failures.append(
            f"highlight: content_filter_applied — {where} must be exactly true "
            "(the publish-time blocklist audit attestation, ADR-029 Decision 2)")
    return failures


def _check_excerpt_shape(doc, where):
    failures = []
    excerpt = doc.get("excerpt")
    if not isinstance(excerpt, list) or not excerpt:
        return [f"highlight: schema — {where} excerpt must be a non-empty array"]
    if len(excerpt) > EXCERPT_MAX:
        failures.append(
            f"highlight: excerpt cap — {where} has {len(excerpt)} entries, "
            f"cap is {EXCERPT_MAX} (ADR-029 Decision 1)")
    for i, ex in enumerate(excerpt):
        loc = f"{where} excerpt[{i}]"
        if not isinstance(ex, dict):
            failures.append(f"highlight: schema — {loc} must be an object")
            continue
        if not isinstance(ex.get("agent"), str) or not ex["agent"]:
            failures.append(f"highlight: schema — {loc}.agent must be a non-empty string")
        if not isinstance(ex.get("text"), str) or not ex["text"].strip():
            failures.append(f"highlight: schema — {loc}.text must be a non-empty string")
        if not isinstance(ex.get("round"), int) or isinstance(ex.get("round"), bool) \
                or ex["round"] < 1:
            failures.append(f"highlight: schema — {loc}.round must be an integer >= 1")
        if not isinstance(ex.get("phase_index"), int) \
                or isinstance(ex.get("phase_index"), bool) or ex["phase_index"] < 0:
            failures.append(f"highlight: schema — {loc}.phase_index must be an integer >= 0")
        if not isinstance(ex.get("persona_index"), int) \
                or isinstance(ex.get("persona_index"), bool) or ex["persona_index"] < 0:
            failures.append(
                f"highlight: schema — {loc}.persona_index must be an integer >= 0 "
                "(the speaker's index in the scenario's `personas:` list, which is "
                "what resolves their avatar colour slot; ADR-029 Decision 1)")
        phase = ex.get("phase")
        if phase not in PHASE_TYPES:
            failures.append(
                f"highlight: unknown phase — {loc}.phase={phase!r} is outside the "
                "PhaseType catalog (a new phase type landed — classify it in "
                "ADR-029 Decision 3 first)")
        elif phase not in ELIGIBLE_PHASES:
            failures.append(
                f"highlight: phase not excerpt-eligible — {loc}.phase={phase!r}; only "
                f"{sorted(ELIGIBLE_PHASES)} output may be excerpted (ADR-029 Decision 3)")
        if ex.get("source_field") not in SOURCE_FIELDS:
            failures.append(
                f"highlight: source_field — {loc}.source_field="
                f"{ex.get('source_field')!r} is not in the allowlist "
                f"{sorted(SOURCE_FIELDS)} (ADR-029 Decision 3)")
    return failures


def _persona_entries(parsed):
    """-> the entry list for either accepted persona-fragment shape, else None.

    ADR-029 Decision 1 pins two: a bare block sequence of mappings (what both
    shipped hooks use — PyYAML parses one at any indent without dedenting) or a
    `personas:`-keyed mapping holding one.
    """
    if isinstance(parsed, list):
        return parsed
    if isinstance(parsed, dict) and set(parsed) == {"personas"} \
            and isinstance(parsed["personas"], list):
        return parsed["personas"]
    return None


def _top_level_shape(parsed):
    """A short description of what the fragment parsed to, for the failure text.

    Without it, a `personas:` fragment carrying a sibling key reads as "not a
    persona list" — untrue on its face, since it does have `personas:`. Naming
    the keys tells the curator which one to drop.
    """
    if isinstance(parsed, dict):
        return "a mapping with keys " + str(sorted(map(str, parsed)))
    if isinstance(parsed, list):
        return f"a {len(parsed)}-item sequence"
    return f"{type(parsed).__name__}"


def _secret_keys_in(parsed):
    """True if any mapping anywhere under `parsed` has a `secret` key.

    Recursive and shape-agnostic, so it sees forms a line scan cannot: a flow
    mapping (`- {name: a, secret: s}`), a quoted key (`"secret": s`), and a
    `personas: [...]` flow sequence are all ordinary YAML a curator may write.
    """
    if isinstance(parsed, dict):
        if any(str(key) == "secret" for key in parsed):
            return True
        return any(_secret_keys_in(value) for value in parsed.values())
    if isinstance(parsed, list):
        return any(_secret_keys_in(item) for item in parsed)
    return False


def _secret_failures(locations, where):
    """One failure line per place a `secret` key was found."""
    return [
        f"highlight: yaml_hook secret — {where} yaml_hook.fragment declares `secret:` "
        f"at {location}. A hidden agenda is a spoiler wherever it appears, and "
        "ADR-029 Decision 2's secret branch is designed-untested — the extractor "
        "refuses such scenarios, and this is the gate's copy that a hand-edited hook "
        "cannot bypass, in any kind"
        for location in locations]


def _check_yaml_hook_secret(doc, where):
    """No published fragment may declare `secret:`, whatever its kind.

    Keyed on the **spoiler**, not on the discriminator. The rule reads "a
    hidden agenda is a spoiler wherever it appears" (ADR-029 Decision 3's
    `assign` rule, applied to the hook), and `kind: raw` is where a curator is
    most likely to paste an unreviewed block — it is published verbatim on both
    surfaces, so a `raw` leak is strictly worse than a `persona` one.

    **Two detectors, and both are load-bearing.** A parse walk sees the key
    wherever YAML puts it, including forms with nothing at line start; a line
    scan covers what the parse cannot reach — `raw` licenses no shape, so a
    fragment that fails to parse gets no walk at all, and that is exactly when
    a curator is most likely to be pasting something unreviewed. Keeping only
    the line scan silently narrows the check for every flow-style fragment;
    keeping only the walk drops every unparseable one. The line scan is also
    deliberately conservative — it fires on `secret:` inside a quoted scalar,
    a false positive a curator resolves by rewording, which is the cheaper
    error of the two.

    **The two do not add up to full coverage**, and the gap is their
    *intersection*: a fragment that both fails to parse and hides `secret`
    off line-start — `- {name: [a, secret: s}`, or a multi-document stream
    (`safe_load` refuses those) whose secret sits inside a flow mapping. Both
    are `raw`-only, since `kind: persona`'s shape check rejects them outright,
    and neither is a plausible curator paste. Stated rather than papered over:
    an earlier revision of this docstring implied the two arms were a covering
    union, which they are not.

    This is the gate's only `secret:` check on the hook. The extractor's
    hard-fail (`declares_secret`) reads the *scenario YAML*, so nothing had
    ever re-derived the rule for the hook's own text, and a hand-edited hook
    never runs the extractor at all (Decision 2's standing argument).
    """
    hook = doc.get("yaml_hook")
    if not isinstance(hook, dict) or not isinstance(hook.get("fragment"), str):
        return []
    fragment = hook["fragment"]

    locations = [
        f"line {i + 1}"
        for i, line in enumerate(fragment.splitlines())
        if re.match(r"^\s*(-\s+)?secret\s*:", line)
    ]
    if yaml is None:
        # The walk cannot run, so only the weaker arm is live. Named rather
        # than silent, for the reason this module's docstring already gives
        # about PyYAML: a gate that quietly drops a check is worse than one
        # that is loud about it.
        #
        # The line-scan hits are reported **alongside** it rather than
        # discarded. Returning only the install notice would fail the gate
        # either way, but it would tell a curator holding a real, line-start
        # `secret:` to install a package instead of naming their spoiler —
        # right verdict, useless message.
        return _secret_failures(locations, where) + [
            f"highlight: yaml_hook secret — {where} PyYAML is not importable, so the "
            "fragment could not be walked and flow-style or quoted `secret` keys "
            "would pass unverified. Install it (python3 -m pip install "
            "'pyyaml>=6,<7')"]
    if not locations:
        try:
            if _secret_keys_in(yaml.safe_load(fragment)):
                locations.append("a mapping key (flow style or quoted)")
        except yaml.YAMLError:
            pass  # Unparseable: the line scan above is the only reachable arm.
        except RecursionError:
            # **Fails closed, deliberately.** `RecursionError` is not a
            # `YAMLError`, and it has *two* sources: PyYAML's own parser
            # recurses (~500 levels of nesting raises it out of `safe_load`),
            # and `_secret_keys_in` recurses too, so a self-referential alias
            # (`a: &x\n  b: [*x, …]`) parses fine and then blows the stack in
            # the walk. Swallowing it would turn a loud traceback into a silent
            # pass on a fragment nothing verified — the one outcome worse than
            # crashing.
            return [
                f"highlight: yaml_hook secret — {where} yaml_hook.fragment is too "
                "deeply nested or self-referential to verify (recursion limit hit "
                "while parsing or walking it), so `secret:` could not be ruled out. "
                "Flatten the fragment"]

    return _secret_failures(locations, where)


def _check_yaml_hook_fragment(doc, where):
    """`kind: persona` promises a shape — re-derive it (ADR-029 Decision 1).

    Two reasons this lives in the gate rather than only in the extractor. A
    hand-edited hook never runs the extractor, which is Decision 2's standing
    argument; and the app renders a `persona` fragment in the visual editor's
    vocabulary, so a shape it cannot parse must fail at supply time instead of
    degrading in a client the repo cannot update (§ Amendment 2026-08-08).

    `secret:` is **not** checked here — it is kind-independent, so it lives in
    ``_check_yaml_hook_secret``. Keying it on `persona` would have left the
    verbatim-published `raw` kind unguarded.
    """
    hook = doc.get("yaml_hook")
    if not isinstance(hook, dict) or hook.get("kind") != "persona":
        return []
    fragment = hook.get("fragment")
    if not isinstance(fragment, str):
        return []  # already reported by _check_schema
    if yaml is None:
        return [
            f"highlight: yaml_hook fragment — {where} kind=persona, but PyYAML is not "
            "importable so the fragment's shape cannot be verified. Install it "
            "(python3 -m pip install 'pyyaml>=6,<7'); this check fails closed rather "
            "than passing unverified"]
    try:
        parsed = yaml.safe_load(fragment)
    except (yaml.YAMLError, RecursionError) as exc:
        # `RecursionError` is not a `YAMLError`, and PyYAML's parser recurses —
        # ~500 levels of nesting raises it here. Reported as unparseable (which
        # it effectively is) rather than escaping as a traceback.
        return [
            f"highlight: yaml_hook fragment — {where} kind=persona but the fragment is "
            f"not parseable YAML: {type(exc).__name__}: {exc}"]

    entries = _persona_entries(parsed)
    if not entries:
        return [
            f"highlight: yaml_hook fragment — {where} kind=persona but the fragment is "
            "not a non-empty persona list (expected a block sequence of mappings, or a "
            "`personas:` key holding one; parsed top level was "
            f"{_top_level_shape(parsed)}). Use kind=raw to publish it as YAML instead"]

    failures = []
    for i, item in enumerate(entries):
        loc = f"{where} yaml_hook.fragment[{i}]"
        if not isinstance(item, dict):
            failures.append(f"highlight: yaml_hook fragment — {loc} must be a mapping")
            continue
        # `secret` is reported once, kind-independently, by
        # `_check_yaml_hook_secret`; excluded here so it is not named twice.
        # `map(str, …)` because YAML keys need not be strings — `1: c` alongside
        # `mood: x` makes a bare `sorted()` raise TypeError, which would abort
        # the run with a traceback instead of the one-failure-per-line contract
        # this module's docstring promises.
        rest = sorted(map(str, set(item) - PERSONA_FRAGMENT_KEYS - {"secret"}))
        if rest:
            failures.append(
                f"highlight: yaml_hook fragment — {loc} has key(s) {rest} outside the "
                f"allowlist {sorted(PERSONA_FRAGMENT_KEYS)}")
        for key in sorted(PERSONA_FRAGMENT_KEYS):
            value = item.get(key)
            if not isinstance(value, str) or not value.strip():
                failures.append(
                    f"highlight: yaml_hook fragment — {loc}.{key} must be a non-empty "
                    "string (the app draws both fields)")
    return failures


def _check_position(doc, entry, where, phase_tree):
    """Decision 3's two-part position rule, against the index entry.

    Also the home of the `conditional`-scenario refusal: the rule is stated in
    terms of `phase_index`, so the scenario class whose `phase_index` cannot be
    derived is refused where that index is read, not at an unrelated callsite.
    Being here means the extractor inherits it too — `check_content` dispatches
    this function for both callers, so the two cannot disagree about which
    highlights are publishable.
    """
    failures = []
    phases = entry.get("phases")
    rounds = entry.get("rounds")
    if not isinstance(phases, list) or not phases:
        return [f"highlight: schema — {where} gallery.json entry has no `phases` list "
                "to check the within-round bound against"]
    # Refused as a class, deliberately wider than the broken cases — the failure
    # message says so. `phases` is the FULLY-FLATTENED depth-first list (the
    # `conditional`, then its then-branch, then its else-branch) while a
    # transcript's `phase_path` indexes the TOP-LEVEL list, so the outcome-phase
    # prefix `phases[:idx]` spans branches that never ran together in one round.
    # Telling a sound pick from a skewed one needs the branch structure this
    # function does not have, which is #1473's work.
    #
    # Picks at or inside the conditional fail loudly today only because no
    # shipped scenario continues past its conditional; one that did could match
    # `phases[idx]` by coincidence and evaluate that prefix over the wrong range,
    # silently. Returning early keeps such speculation out of the report, and
    # drops the round-window arms too — derivable, but worth nothing on a
    # highlight that cannot ship.
    #
    # Either source alone triggers the refusal: a drifted index could otherwise
    # disable the guard (nothing on a highlight PR's path re-derives `phases` —
    # see `flatten_phase_tree`), while keying on the YAML alone would
    # miss an index claiming a conditional the YAML no longer has. Disagreement
    # between them is itself a reason not to publish.
    nodes, _reason = phase_tree
    # Tri-state, as before: `None` = the tree could not be derived, so the
    # scenario's own answer is unknown and only the index's claim is left.
    yaml_has_conditional = (
        None if nodes is None else any(n.type == "conditional" for n in nodes))
    if "conditional" in phases or yaml_has_conditional:
        source = ("the entry's `phases` list" if "conditional" in phases
                  else "the sibling scenario YAML's `phases:`")
        return [f"highlight: conditional scenario — {where} {source} contains "
                "`conditional`, whose branch sub-phases are flattened into the "
                "index's list. `phase_index` is not branch-aware, so neither the "
                "index nor the within-round bound can be derived correctly (#1473). "
                "Highlights are refused for this scenario class until that lands — "
                "including a pick before the conditional, which is sound but not "
                "distinguishable here."]
    if not isinstance(rounds, int) or isinstance(rounds, bool) or rounds < 1:
        return [f"highlight: schema — {where} gallery.json entry has no usable "
                "`rounds` value to compute the round window"]
    window = math.ceil(rounds / 2)
    override = doc.get("window_override") is True
    for i, ex in enumerate(doc.get("excerpt") or []):
        if not isinstance(ex, dict):
            continue
        loc = f"{where} excerpt[{i}]"
        idx = ex.get("phase_index")
        if isinstance(idx, int) and not isinstance(idx, bool) and 0 <= idx < len(phases):
            if phases[idx] != ex.get("phase"):
                failures.append(
                    f"highlight: phase_index mismatch — {loc}.phase_index={idx} names "
                    f"phases[{idx}]={phases[idx]!r} but phase={ex.get('phase')!r}")
            preceding = [p for p in phases[:idx] if p in OUTCOME_PHASES]
            if preceding:
                failures.append(
                    f"highlight: within-round bound — {loc}.phase_index={idx} is "
                    f"preceded in the round by outcome-class phase(s) {preceding}; "
                    "dialogue reacting to an in-round outcome leaks it "
                    "(ADR-029 Decision 3)")
        elif isinstance(idx, int) and not isinstance(idx, bool):
            failures.append(
                f"highlight: phase_index mismatch — {loc}.phase_index={idx} is outside "
                f"the entry's phases list (len={len(phases)})")
        rnd = ex.get("round")
        if isinstance(rnd, int) and not isinstance(rnd, bool):
            if rnd > rounds:
                failures.append(
                    f"highlight: round window — {loc}.round={rnd} exceeds the "
                    f"scenario's rounds={rounds}")
            elif rnd > window and not override:
                failures.append(
                    f"highlight: round window — {loc}.round={rnd} is outside the "
                    f"default window 1..{window} (rounds={rounds}); pass "
                    "--window-override at extraction to record window_override: true")
    return failures


def registry_model_ids(registry_swift):
    """-> ({id, …}, {displayName: id, …}) from `ModelRegistry.swift`, or None.

    `None` means the catalog could not be read — missing file, or a parse that
    found no entries. Both are reported as one named failure by the caller
    rather than degrading into "every model id is unknown", and an empty parse
    is a failure precisely because this repo auto-formats Swift on edit: a
    reformat that broke the pattern would otherwise silently disarm the check.

    This parses **every line-anchored `id: "…"` in the file**, a superset of
    `ModelRegistry.catalog`: a descriptor withheld from the catalog array would
    widen the allowlist by one. Tolerated — the check exists to catch display
    names and typos, not to police unshipped descriptors.
    """
    ids, display_to_id = set(), {}
    try:
        with open(registry_swift, encoding="utf-8") as f:
            current = None
            for line in f:
                match = _REGISTRY_ID.match(line)
                if match:
                    current = match.group(1)
                    ids.add(current)
                    continue
                match = _REGISTRY_DISPLAY_NAME.match(line)
                if match and current is not None:
                    display_to_id[match.group(1)] = current
    except (OSError, UnicodeDecodeError):
        return None
    if not ids:
        return None
    return ids, display_to_id


def _check_source_model(doc, allowed_model_ids, where):
    """`source.model` must name a model a reader could actually have run.

    The string is published verbatim in user-facing prose on the landing pages
    (「実際に端末で動かした結果…（<model>）」 and its English sibling), so one
    model appearing under two names across neighbouring pages is a visible
    defect. The authority is `ModelRegistry.catalog`, not the harness's
    `ModelProfile.all`, which also carries eval candidates with no app entry.

    Consequence to accept rather than discover: a transcript from a harness-only
    profile cannot produce a publishable highlight at all, and `--model` offers
    no way around it. The landing page calls this "a real on-device run", which
    it would not be for a model the reader cannot install.
    """
    source = doc.get("source")
    if not isinstance(source, dict) or not isinstance(source.get("model"), str):
        return []  # shape already reported by _check_schema
    model = source["model"]
    if model in allowed_model_ids:
        return []
    return [
        f"highlight: source.model — {where} source.model={model!r} is not a known "
        f"model id. Expected one of {sorted(allowed_model_ids)}. The harness writes "
        "`ModelProfile.name` (a display name) into the transcript's `run_start`, so "
        "an extraction that did not resolve it lands here; a superseded model's id "
        "belongs in RETIRED_MODEL_IDS in this file."]


def scenario_persona_names(scenario):
    """-> the scenario's persona names in declaration order, or None.

    `None` means the list could not be read *at all* — unparseable YAML, no
    `personas:` key, or an entry without a string `name`. Kept distinct from an
    empty list so the caller reports "cannot verify" instead of "every index is
    wrong": the two need different fixes.
    """
    if not isinstance(scenario, dict):
        return None
    personas = scenario.get("personas")
    if not isinstance(personas, list) or not personas:
        return None
    names = []
    for persona in personas:
        if not isinstance(persona, dict) or not isinstance(persona.get("name"), str):
            return None
        names.append(persona["name"])
    return names


PhaseNode = collections.namedtuple("PhaseNode", "type top branch inner")
"""One entry of the flattened phase list.

`top` is the index into the scenario's TOP-LEVEL `phases:`. `branch` is
`None` for a top-level phase, else `"then"` / `"else"`; `inner` is the
position within that branch (`None` at top level). Together they carry the
tree structure the flat list drops — which is what makes a `conditional`
scenario's `phase_index` resolvable in both directions (#1473).
"""


def flatten_phase_tree(scenario):
    """-> ([PhaseNode], None) in `gallery.json` `phases` order, or (None, reason).

    Three implementations of this depth-first order exist and must agree:
    `add-gallery-entry.sh`'s inline `flat()` (which WRITES the denormalized
    `gallery.json` `phases`), `GallerySeedYAMLTests.flattenPhaseKinds` (Swift),
    and this one. The Swift copy runs in the iOS suite, which
    `precommit-gate-classify.sh` skips for a `docs/`-only changeset — the shape
    every highlight batch has — so it is not a gate on this path. Hence
    `_check_phase_tree` below: it re-derives the list here and compares, making
    this the first gate-side drift check on that field for flat entries too.

    The reason string travels back so the failure text can name the actual
    cause, as `_read_persona_names` does: on a machine without PyYAML the fix
    is an install, and a message blaming the scenario would send the curator to
    the wrong file.

    Rejects two shapes the engine also rejects, so a fixture the loader would
    refuse cannot reach the position rule:

    - a `conditional` with neither branch populated (`ScenarioValidator`'s
      `validateConditionalPhase`: at least one of `then:` / `else:` must be
      non-empty);
    - a `conditional` nested inside a branch (the depth-1 rule, enforced twice
      upstream — `ScenarioValidator` blocks `depth > 0`, and
      `ConditionalHandler.subHandlers` deliberately omits `.conditional`).
      That upstream guarantee is what bounds a transcript `phase_path` to
      length 2, which the extractor's resolver relies on.
    """
    if not isinstance(scenario, dict):
        return None, "the sibling scenario YAML is not a mapping"
    phases = scenario.get("phases")
    if not isinstance(phases, list) or not phases:
        return None, ("the sibling scenario YAML has no non-empty `phases:` "
                      "list, so its phase tree cannot be derived")
    nodes = []
    for top, phase in enumerate(phases):
        if not isinstance(phase, dict) or not isinstance(phase.get("type"), str):
            return None, (f"the sibling scenario YAML's `phases:`[{top}] is not a "
                          "mapping carrying a string `type`")
        nodes.append(PhaseNode(phase["type"], top, None, None))
        if phase["type"] != "conditional":
            continue
        populated = 0
        for branch in ("then", "else"):
            sub = phase.get(branch)
            if sub is None:
                continue
            if not isinstance(sub, list):
                return None, (f"the sibling scenario YAML's `phases:`[{top}].{branch} "
                              "is not a list")
            populated += len(sub)
            for inner, child in enumerate(sub):
                if not isinstance(child, dict) or not isinstance(child.get("type"), str):
                    return None, (f"the sibling scenario YAML's `phases:`[{top}]."
                                  f"{branch}[{inner}] is not a mapping carrying a "
                                  "string `type`")
                if child["type"] == "conditional":
                    return None, (f"the sibling scenario YAML nests a `conditional` at "
                                  f"`phases:`[{top}].{branch}[{inner}], which the "
                                  "engine's depth-1 rule refuses (ScenarioValidator "
                                  "blocks depth > 0; ConditionalHandler registers no "
                                  "sub-handler for it)")
                nodes.append(PhaseNode(child["type"], top, branch, inner))
        if populated == 0:
            return None, (f"the sibling scenario YAML's `conditional` at "
                          f"`phases:`[{top}] populates neither `then:` nor `else:`, "
                          "which the engine refuses (ScenarioValidator requires at "
                          "least one non-empty branch)")
    return nodes, None


def _check_phase_tree(entry, phase_tree, where):
    """`gallery.json`'s denormalized `phases` must equal the YAML-derived tree.

    Nothing else on a highlight PR's path re-derives that field (see
    `flatten_phase_tree`), and every check stated in terms of `phase_index`
    reads it — so a drifted list would silently move what the position rule
    measures against. Failing here rather than inside `_check_position` keeps
    the drift reported as drift, not as a mismatched excerpt.
    """
    nodes, reason = phase_tree
    phases = entry.get("phases")
    if nodes is None:
        return [f"highlight: phase tree — {where} cannot be re-derived because "
                f"{reason}, so `phases` is unverified and every `phase_index` "
                "check reads an unchecked list"]
    derived = [n.type for n in nodes]
    if not isinstance(phases, list) or derived != phases:
        return [f"highlight: phase tree — {where} gallery.json `phases` is "
                f"{phases!r} but the sibling scenario YAML flattens to {derived!r}. "
                "Regenerate the entry (scripts/add-gallery-entry.sh --update); the "
                "denormalized list is what every `phase_index` check reads."]
    return []


def _check_persona_index(doc, personas, where):
    """Cross-reference `excerpt[].persona_index` against the sibling YAML.

    The app resolves a speaker's avatar colour as
    `SheepAvatar.Character.allCases[i % 4]`, where `i` is that speaker's index
    in the scenario's `personas:` list (`SimulationView.personaItem(for:)`).
    `i` was previously derived from excerpt order, which matched the run only
    when the excerpt was a prefix of `personas:`; carrying the real index makes
    the correspondence hold for any excerpt, which is why this is a
    cross-reference against the YAML and NOT a constraint on which lines may be
    excerpted.

    `personas` is the `(names, reason)` pair from ``_read_persona_names`` — a
    pair so an unreadable YAML reports *why* it could not be verified, rather
    than one message that blames the YAML for a missing PyYAML.
    """
    persona_names, reason = personas
    if persona_names is None:
        return [
            f"highlight: persona_index — {where} cannot be verified: {reason}"]
    failures = []
    for i, ex in enumerate(doc.get("excerpt") or []):
        if not isinstance(ex, dict):
            continue
        loc = f"{where} excerpt[{i}]"
        idx = ex.get("persona_index")
        if not isinstance(idx, int) or isinstance(idx, bool) or idx < 0:
            # NOT a guard — `_check_excerpt_shape` already fails all of these
            # (measured: removing this line leaves the suite green). It only
            # avoids double-reporting. Do not describe it as catching anything.
            continue
        agent = ex.get("agent")
        if idx >= len(persona_names):
            failures.append(
                f"highlight: persona_index — {loc}.persona_index={idx} is outside the "
                f"scenario's `personas:` list (len={len(persona_names)})")
        elif persona_names[idx] != agent:
            failures.append(
                f"highlight: persona_index — {loc}.persona_index={idx} names "
                f"{persona_names[idx]!r} in the scenario's `personas:` list but "
                f"agent={agent!r}")
        elif idx >= 0 and persona_names.index(agent) != idx:
            # Name-match alone is too weak when a scenario declares the same
            # name twice: either index would satisfy it, while the app resolves
            # the slot with `firstIndex(of:)` and so uses the first. Requiring
            # the first keeps the excerpt's colours equal to the run's.
            failures.append(
                f"highlight: persona_index — {loc}.persona_index={idx} is a later "
                f"duplicate of agent={agent!r}, first declared at "
                f"{persona_names.index(agent)}; the app resolves the slot from the "
                "first match, so only that index reproduces the run's colours")
    return failures


def check_content(doc, entry, blocklist, where, personas, allowed_model_ids,
                  phase_tree):
    """Every rule derivable from the highlight doc + its index entry.

    Shared by the extractor (fail-fast) and the gate (enforcement). Excludes
    the file-level checks (pairing, file hashes) the extractor cannot run.

    **This dispatch list is mirrored in prose, and nothing checks the mirror.**
    Adding a check here — or to ``validate_repo`` — means sweeping ADR-029
    Decision 2 ("re-derives, per highlight: …") in the same PR: it claims to be
    a *complete* list of what the gate re-derives, split across this function
    (content-level) and ``validate_repo`` (file-level), and
    `docs/gallery/README.md` gate 1 points at it rather than restating it. The extractor's own § "Hard-fails" is a partial sibling
    and needs updating only when the check has an extraction-time counterpart.
    Sweeping the mirror can *narrow* it: spelling out a category that was vague
    once excluded a member the vagueness had covered. Widen, do not enumerate.

    `personas` is ``_read_persona_names``'s `(names, reason)` pair;
    `allowed_model_ids` is ``registry_model_ids`` ∪ ``RETIRED_MODEL_IDS``;
    `phase_tree` is ``flatten_phase_tree``'s `(nodes, reason)` pair over the
    sibling YAML (`nodes is None` = unreadable). All three are required rather
    than defaulted, so a caller cannot skip a check by omission — the gate is
    the only place any of these failures would surface.
    """
    failures = _check_schema(doc, where)
    failures += _check_excerpt_shape(doc, where)
    failures += _check_persona_index(doc, personas, where)
    failures += _check_source_model(doc, allowed_model_ids, where)
    failures += _check_yaml_hook_secret(doc, where)
    failures += _check_yaml_hook_fragment(doc, where)
    failures += _check_phase_tree(entry, phase_tree, where)
    failures += _check_position(doc, entry, where, phase_tree)
    failures += check_blocklist(doc, blocklist, where)
    return failures


# --- Repository-level gate --------------------------------------------------


def _entry_index(gallery_json):
    with open(gallery_json, encoding="utf-8") as f:
        return json.load(f).get("scenarios") or []


def _read_scenario(yaml_path):
    """-> the parsed sibling scenario YAML, or None if it cannot be read.

    Separate from `_read_persona_names`, which parses the same file again: that
    one returns names, while ``flatten_phase_tree`` wants the document itself
    and derives the whole phase tree from it. Same catch set, so the two agree
    on what "unreadable" means.
    """
    if yaml is None:
        return None
    try:
        with open(yaml_path, encoding="utf-8") as f:
            return yaml.safe_load(f)
    except (OSError, UnicodeDecodeError, yaml.YAMLError, RecursionError):
        return None


def _read_persona_names(yaml_path):
    """-> (names, None) on success, or (None, reason) naming what went wrong.

    The reason travels back so the failure text can name the actual cause: on a
    machine without PyYAML the fix is an install, and a message blaming the YAML
    would send the curator to the wrong file. `RecursionError` is caught
    alongside `YAMLError` for the reason the sibling checks here document — it
    is not a `YAMLError`, so deep nesting escapes as a traceback otherwise.
    """
    if yaml is None:
        return None, ("PyYAML is not installed, so the sibling scenario YAML "
                      "cannot be parsed (python3 -m pip install 'pyyaml>=6,<7')")
    try:
        with open(yaml_path, encoding="utf-8") as f:
            parsed = yaml.safe_load(f)
    except (OSError, UnicodeDecodeError) as exc:
        return None, f"the sibling scenario YAML could not be read ({exc})"
    except (yaml.YAMLError, RecursionError) as exc:
        return None, f"the sibling scenario YAML does not parse ({type(exc).__name__})"
    names = scenario_persona_names(parsed)
    if names is None:
        return None, ("the sibling scenario YAML has no `personas:` list of "
                      "mappings each carrying a string `name`")
    return names, None


def validate_repo(gallery_json, gallery_dir, blocklist_path, registry_swift):
    """-> list of failure strings across the whole gallery."""
    failures = []
    entries = _entry_index(gallery_json)
    highlights_dir = os.path.join(gallery_dir, "highlights")

    on_disk = set()
    if os.path.isdir(highlights_dir):
        for name in sorted(os.listdir(highlights_dir)):
            if name.endswith(".json"):
                on_disk.add(os.path.join(highlights_dir, name))

    paired_entries = []
    for entry in entries:
        has_url = "highlight_url" in entry
        has_sha = "highlight_sha256" in entry
        if has_url != has_sha:
            failures.append(
                f"highlight: pairing — id={entry.get('id')} declares "
                f"{'highlight_url' if has_url else 'highlight_sha256'} without its "
                "partner; both-or-neither (ADR-029 Decision 4)")
            continue
        if not has_url:
            continue
        # `has()` is true for an explicit JSON null too — a hand-edited index
        # (exactly what this script polices) must fail with a named entry,
        # not a TypeError traceback from os.path.basename(None).
        if not isinstance(entry.get("highlight_url"), str) \
                or not isinstance(entry.get("highlight_sha256"), str) \
                or not isinstance(entry.get("yaml_url"), str):
            failures.append(
                f"highlight: schema — id={entry.get('id')} highlight_url / "
                "highlight_sha256 / yaml_url must all be strings")
            continue
        paired_entries.append(entry)

    if not paired_entries and not on_disk:
        return failures

    if not os.path.isfile(blocklist_path):
        failures.append(
            "highlight: blocklist — ContentBlocklist.json not found at "
            f"{blocklist_path}; the publish-time audit cannot run")
        return failures
    blocklist = load_blocklist(blocklist_path)

    registry = registry_model_ids(registry_swift)
    if registry is None:
        failures.append(
            "highlight: model registry — could not read any ModelDescriptor id from "
            f"{registry_swift}; source.model cannot be checked against the catalog")
        return failures
    allowed_model_ids = registry[0] | RETIRED_MODEL_IDS

    referenced = set()
    for entry in paired_entries:
        entry_id = entry.get("id")
        path = os.path.join(highlights_dir, os.path.basename(entry["highlight_url"]))
        referenced.add(path)
        where = f"[{os.path.relpath(path, os.path.dirname(gallery_dir))}]"
        if not os.path.isfile(path):
            failures.append(
                f"highlight: missing file — id={entry_id} declares highlight_url="
                f"{entry['highlight_url']} but {path} does not exist")
            continue
        actual = sha256_file(path)
        if actual != entry.get("highlight_sha256"):
            failures.append(
                f"highlight: highlight_sha256 mismatch — id={entry_id} "
                f"gallery.json={entry.get('highlight_sha256')} but actual={actual} "
                f"({path})")
        try:
            with open(path, encoding="utf-8") as f:
                doc = json.load(f)
        except (ValueError, UnicodeDecodeError) as exc:
            failures.append(f"highlight: schema — {where} is not valid JSON: {exc}")
            continue
        if not isinstance(doc, dict):
            failures.append(f"highlight: schema — {where} must be a JSON object")
            continue

        stem = os.path.basename(path)[: -len(".json")]
        if stem != entry_id:
            failures.append(
                f"highlight: schema — {where} filename stem {stem!r} != gallery.json "
                f"id {entry_id!r}")
        ref = doc.get("scenario_ref")
        if isinstance(ref, dict) and ref.get("id") != entry_id:
            failures.append(
                f"highlight: schema — {where} scenario_ref.id={ref.get('id')!r} != "
                f"gallery.json id {entry_id!r}")

        yaml_path = os.path.join(gallery_dir, os.path.basename(entry.get("yaml_url", "")))
        personas = (None, f"the sibling scenario YAML {yaml_path} is missing")
        # Bound here, like `personas`, so the missing-YAML path below does not
        # leave it unbound. A `None` node list = cannot verify; that path already
        # fails the highlight on the persona check, so it never ships unverified.
        phase_tree = (None, f"the sibling scenario YAML {yaml_path} is missing")
        if not os.path.isfile(yaml_path):
            failures.append(
                f"highlight: yaml_sha256 mismatch — id={entry_id} sibling YAML "
                f"{yaml_path} is missing, so the pin cannot be verified")
        else:
            yaml_sha = sha256_file(yaml_path)
            ref_sha = ref.get("yaml_sha256") if isinstance(ref, dict) else None
            if ref_sha != entry.get("yaml_sha256") or ref_sha != yaml_sha:
                failures.append(
                    f"highlight: yaml_sha256 mismatch — id={entry_id} highlight pins "
                    f"{ref_sha}, gallery.json has {entry.get('yaml_sha256')}, actual "
                    f"YAML bytes hash to {yaml_sha}. Regenerate or delete the highlight "
                    "(ADR-029 Decision 1: highlights are pinned snapshots)")
            personas = _read_persona_names(yaml_path)
            phase_tree = flatten_phase_tree(_read_scenario(yaml_path))

        failures += check_content(
            doc, entry, blocklist, where,
            personas=personas, allowed_model_ids=allowed_model_ids,
            phase_tree=phase_tree)

    for path in sorted(on_disk - referenced):
        rel = os.path.relpath(path, os.path.dirname(gallery_dir))
        failures.append(
            f"highlight: orphan — {rel} is not referenced by a gallery.json entry "
            "carrying both highlight_url and highlight_sha256 (the id may be absent "
            "from the index, or present without the fields)")

    return failures


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--gallery-json", required=True)
    ap.add_argument("--gallery-dir", required=True)
    ap.add_argument("--blocklist", required=True)
    # Required like its siblings: this module derives no paths of its own, so the
    # gate stays the single place that knows the repo layout.
    ap.add_argument("--model-registry", required=True)
    a = ap.parse_args()

    failures = validate_repo(
        a.gallery_json, a.gallery_dir, a.blocklist, a.model_registry)
    for line in failures:
        print(line)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

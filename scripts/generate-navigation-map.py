#!/usr/bin/env python3
"""Generate docs/design/navigation-map.md from the navigation source.

Two artifacts, two sources of truth, so the committed map never drifts:

- **Mermaid screen graph** — derived from the ``Route`` enum +
  ``NavigationLink`` / ``router.push`` / ``pushIfOnTop`` callsites (the
  per-tab-stack push-edge graph).
- **Screenshot-tour table** — derived from ``ScreenshotTourTests.swift`` by
  parsing its ``capture(app, name:, anchorId:)`` calls in order. The test is
  the single source for what the tour actually captures, including
  tab-reached screens (e.g. Settings) that are NOT ``Route`` graph nodes.
  Before this split the table was Route-derived, so converting a pushed
  screen to a bottom tab silently dropped its tour row even though the test
  still captured it (#622).

Mermaid graph details:

- **Nodes**: ``Route`` enum cases parsed from ``Pastura/Pastura/App/Router.swift``
  plus the synthetic tab-stack roots in ``SYNTHETIC_ROOTS`` — ``home``
  (HomeView) and ``sharedScenarios`` (SharedScenariosListView, the Browse
  tab root since ADR-016 D4). These own a tab's NavigationStack but are not
  Route cases.
- **Edges**: callsites of ``NavigationLink(value: Route.X ...)``,
  ``router.push(.X)`` (forward-looking — zero callsites today), and
  ``router.pushIfOnTop(... next: .X ...)`` scanned across ``Views/`` and
  ``App/``. Matching is whole-file with ``\\s``-tolerant regexes because
  swift-format freely breaks these calls across lines (see
  ``.claude/rules/ci-workflows.md`` — token presence over single-line grep);
  comments are stripped first so doc-comment examples never become edges.
- **Helper indirection**: ``NavigationLink(value: someHelper())`` carries no
  Route token. Known helpers are attributed via ``MANUAL_EDGES``; unknown
  helpers fail ``--check`` with "manual edge attribution required" rather
  than silently dropping an edge.

Tour table details:

- Each ``capture(...)`` call is one row (screenshot name + wait anchor).
  "Reached via" is classified from the navigation taps in the interval since
  the previous capture: a ``tabBars.buttons[...].tap()`` → ``tab``, any other
  (non-back) ``buttons[...].tap()`` → ``push``, none → ``root`` (launch).
  Back-button (``pasturaBackButton``) taps are pops, not forward navigation,
  so they are ignored. Comments are stripped first (per
  ``.claude/rules/ci-workflows.md``) so the doc-comment example
  ``capture(...)`` never parses, and the ``func capture(_ app:, name: String,
  ...)`` declaration never matches (no string literal after ``name:``).
- Table rows are driven entirely by the test: a captured screen with no Route
  node (Settings) still appears, and a Route node with no capture
  (``simulation``) correctly does not.

Sheets / fullScreenCover are intentionally absent: each ``AppRouter``
manages its tab's NavigationStack only (``.claude/rules/navigation.md``);
sheet-owned flows are out of scope for this map.

Modes:
  (default)     rewrite docs/design/navigation-map.md
  --check       regenerate in memory and diff against the committed file;
                nonzero exit on drift (CI: navigation-map-drift job)
  --self-test   run embedded regression fixtures; nonzero exit on failure

Screenshot names refer to the *gitignored* outputs of ``scripts/ui-tour.sh``
by name only (never by link) — see ``docs/design/screenshots/README.md`` for
regeneration.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
ROUTER_FILE = REPO_ROOT / "Pastura/Pastura/App/Router.swift"
TOUR_FILE = REPO_ROOT / "Pastura/PasturaUITests/ScreenshotTourTests.swift"
SCAN_DIRS = (
    REPO_ROOT / "Pastura/Pastura/Views",
    REPO_ROOT / "Pastura/Pastura/App",
)
OUTPUT_FILE = REPO_ROOT / "docs/design/navigation-map.md"

# Definition / infra files: Router.swift declares the enum (node source, not
# an edge source); AppRouter.swift carries the real pushIfOnTop SIGNATURE
# (comment-stripping alone would not remove it); RouteHint.swift quotes
# Route/case examples in doc comments. None of them navigates.
EDGE_SOURCE_EXCLUDE = {"Router.swift", "AppRouter.swift", "RouteHint.swift"}

# Callsite file -> screen node. A file that matches a nav token but is not
# listed here fails --check, forcing a conscious attribution update instead
# of a silently mis-attributed (or dropped) edge.
FILE_TO_SCREEN = {
    "Pastura/Pastura/Views/Home/HomeView.swift": "home",
    "Pastura/Pastura/Views/ScenarioDetail/ScenarioDetailView.swift": "scenarioDetail",
    "Pastura/Pastura/Views/ScenarioDetail/ScenarioDetailView+Sections.swift": "scenarioDetail",
    "Pastura/Pastura/Views/Results/ResultsView.swift": "results",
    "Pastura/Pastura/Views/Community/SharedScenarios/SharedScenariosListView.swift": "sharedScenarios",
    "Pastura/Pastura/Views/Community/SharedScenarios/GalleryScenarioDetailView.swift": "galleryScenarioDetail",
}

# (source screen, target route case, label) for edges the scanner cannot
# see because the Route value is built by a helper function.
MANUAL_EDGES = [
    ("home", "editor", "via newScenarioRoute()"),
]
# Helper identifiers covered by MANUAL_EDGES. NavigationLink(value: <id>())
# with an identifier outside this set is an error.
KNOWN_HELPERS = {"newScenarioRoute"}

# Synthetic stack-root nodes — own a tab's NavigationStack root but are not
# Route cases. `home` = Home tab (HomeView). `sharedScenarios` = Browse tab
# (SharedScenariosListView): ADR-016 D4 deleted its Route case, but it still
# pushes Route.galleryScenarioDetail onto its own tab stack, so it remains an
# edge SOURCE and must be a known node. (Settings is also a tab root but
# pushes no Route, so it needs no node here — it surfaces only in the tour
# table.) Rendered with the rounded stadium shape to mark them as roots.
SYNTHETIC_ROOTS = ("home", "sharedScenarios")

# Display label per Mermaid node. Anchors and screenshot names are NOT here
# anymore — they live solely in ScreenshotTourTests (the tour table's source
# of truth), removing the double-management this script used to carry (#622).
NODE_LABELS = {
    "home": "Home",
    "scenarioDetail": "Scenario Detail",
    "editor": "Scenario Editor",
    "simulation": "Simulation",
    "results": "Past Results",
    "resultDetail": "Result Detail",
    "sharedScenarios": "Shared Scenarios",
    "galleryScenarioDetail": "Gallery Scenario Detail",
}

HEADER = """\
<!-- Generated by scripts/generate-navigation-map.py — DO NOT edit by hand.
     Regenerate: python3 scripts/generate-navigation-map.py
     Drift guard: python3 scripts/generate-navigation-map.py --check (CI: navigation-map-drift) -->
"""

# --- parsing -----------------------------------------------------------------

BLOCK_COMMENT_RE = re.compile(r"/\*.*?\*/", re.S)
LINE_COMMENT_RE = re.compile(r"//[^\n]*")
ROUTE_CASE_RE = re.compile(r"^\s*case\s+(\w+)", re.M)
# \s matches newlines: swift-format may break after "NavigationLink(" and
# after "value:" (both shapes exist on main today).
LINK_ROUTE_RE = re.compile(r"NavigationLink\(\s*value:\s*Route\.(\w+)")
LINK_HELPER_RE = re.compile(r"NavigationLink\(\s*value:\s*(?!Route\.)(\w+)\(")
PUSH_RE = re.compile(r"router\.push\(\s*(?:Route)?\.(\w+)")
# Non-greedy across the expected: argument (which contains nested parens).
# The tempered span refuses to cross into a following pushIfOnTop( call, so
# a hypothetical future next:-less overload can't bridge two calls and
# mis-attribute the second call's target.
PUSH_IF_ON_TOP_RE = re.compile(r"pushIfOnTop\((?:(?!pushIfOnTop\().)*?next:\s*\.(\w+)", re.S)

# A tour stop: capture(app, name: "NN-x", anchorId: "y"). \s tolerates the
# multi-line wraps swift-format produces (the 01-home stop spans 3 lines with
# a trailing `timeout:` arg). Requires a string literal after `name:` /
# `anchorId:`, so the `func capture(_ app:, name: String, anchorId: String)`
# declaration (no literal) never matches. re.S so `\s` crosses newlines.
CAPTURE_RE = re.compile(
    r'capture\(\s*\w+\s*,\s*name:\s*"([^"]+)"\s*,\s*anchorId:\s*"([^"]+)"', re.S
)
# A button tap. Group 1 present => tab-bar switch; group 2 is the identifier
# (so back-button pops can be filtered). `.exists` and other non-`.tap()`
# accessors deliberately do NOT match — only forward taps count.
TAP_RE = re.compile(r'(tabBars\.)?buttons\[\s*"([^"]*)"\s*\]\s*\.tap\(\)')

BACK_BUTTON_ID = "pasturaBackButton"


def strip_comments(swift: str) -> str:
    """Remove block and line comments. Line-based ``//`` stripping can eat
    string-literal tails (e.g. ``"stub://..."``) — safe here because removal
    can only ever *hide* tokens inside strings, never invent nav tokens."""
    return LINE_COMMENT_RE.sub("", BLOCK_COMMENT_RE.sub("", swift))


def parse_route_cases(router_source: str) -> list[str]:
    """Route case names in declaration order. Router.swift is dedicated to
    the Route enum, so every top-level ``case`` line is a route."""
    return ROUTE_CASE_RE.findall(strip_comments(router_source))


def classify_reached_via(segment: str) -> str:
    """How the next captured screen was reached, from the taps in the interval
    since the previous capture. A tab-bar switch wins over a push; back-button
    pops are ignored (not forward navigation); no tap => launch root.

    Forward navigation must be expressed INLINE (``tabBars.buttons[...].tap()``
    / ``buttons[...].tap()``) to be seen — a tap hidden behind a helper call
    (like ``goBack(app)``) is invisible here, so a future forward-nav helper
    would mis-classify its interval as ``root``."""
    has_tab = False
    has_push = False
    for tap in TAP_RE.finditer(segment):
        if tap.group(1):  # tabBars. prefix
            has_tab = True
        elif tap.group(2) != BACK_BUTTON_ID:
            has_push = True
    if has_tab:
        return "tab"
    if has_push:
        return "push"
    return "root"


def parse_tour_stops(test_source: str) -> list[tuple[str, str, str]]:
    """Tour stops (screenshot name, wait anchor, reached-via) in capture order.

    The test is the single source of truth for what the tour captures.
    Comments are stripped first so the doc-comment ``capture(...)`` example
    never parses; the ``func capture`` declaration is excluded by the regex
    requiring a string literal after ``name:``."""
    stripped = strip_comments(test_source)
    stops: list[tuple[str, str, str]] = []
    prev_end = 0
    for cap in CAPTURE_RE.finditer(stripped):
        reached = classify_reached_via(stripped[prev_end : cap.start()])
        stops.append((cap.group(1), cap.group(2), reached))
        prev_end = cap.end()
    return stops


def scan_file_edges(rel_path: str, swift: str) -> tuple[list[tuple[str, str, str]], list[str]]:
    """Return (edges, errors) for one file. Edge = (source, target, label)."""
    stripped = strip_comments(swift)
    targets = LINK_ROUTE_RE.findall(stripped)
    targets += PUSH_RE.findall(stripped)
    targets += PUSH_IF_ON_TOP_RE.findall(stripped)
    helpers = [h for h in LINK_HELPER_RE.findall(stripped) if h not in KNOWN_HELPERS]

    errors = []
    if not targets and not helpers:
        return [], errors

    source = FILE_TO_SCREEN.get(rel_path)
    if source is None:
        errors.append(
            f"{rel_path}: navigation callsite found but file is not in "
            "FILE_TO_SCREEN — add an attribution entry in "
            "scripts/generate-navigation-map.py"
        )
        return [], errors
    for helper in helpers:
        errors.append(
            f"{rel_path}: NavigationLink(value: {helper}(...)) — manual edge "
            "attribution required: add the helper to KNOWN_HELPERS and its "
            "edge to MANUAL_EDGES in scripts/generate-navigation-map.py"
        )
    return [(source, target, "") for target in targets], errors


def collect_edges() -> tuple[list[tuple[str, str, str]], list[str]]:
    edges: list[tuple[str, str, str]] = []
    errors: list[str] = []
    for scan_dir in SCAN_DIRS:
        for path in sorted(scan_dir.rglob("*.swift")):
            if path.name in EDGE_SOURCE_EXCLUDE:
                continue
            rel = path.relative_to(REPO_ROOT).as_posix()
            file_edges, file_errors = scan_file_edges(rel, path.read_text(encoding="utf-8"))
            edges.extend(file_edges)
            errors.extend(file_errors)
    edges.extend(MANUAL_EDGES)
    return edges, errors


# --- emission ----------------------------------------------------------------


def emit_markdown(
    route_cases: list[str],
    edges: list[tuple[str, str, str]],
    tour_stops: list[tuple[str, str, str]],
) -> str:
    nodes = list(SYNTHETIC_ROOTS) + route_cases

    lines = [HEADER]
    lines.append("# Navigation Map — per-tab NavigationStacks\n")
    lines.append(
        "Screen graph of the four per-tab stacks, generated from `Route` enum\n"
        "cases and `NavigationLink` / `router.push` / `pushIfOnTop` callsites.\n"
        "Sheets and fullScreenCover flows are out of scope (each `AppRouter`\n"
        "manages its tab's stack only — see `.claude/rules/navigation.md`).\n"
        "`home` (`HomeView`) and `sharedScenarios` (`SharedScenariosListView`,\n"
        "the Browse tab root) are tab-stack roots, not `Route` cases.\n"
    )
    lines.append("```mermaid")
    lines.append("flowchart TD")
    for node in nodes:
        label = NODE_LABELS.get(node, node)
        shape = f"([{label}])" if node in SYNTHETIC_ROOTS else f'["{label}"]'
        lines.append(f"  {node}{shape}")
    seen = set()
    for source, target, label in sorted(edges):
        if (source, target, label) in seen:
            continue
        seen.add((source, target, label))
        arrow = f' -->|"{label}"| ' if label else " --> "
        lines.append(f"  {source}{arrow}{target}")
    lines.append("```\n")

    lines.append("## Screenshot tour\n")
    lines.append(
        "The `ScreenshotTourTests` UI test\n"
        "(`Pastura/PasturaUITests/ScreenshotTourTests.swift`) is the single\n"
        "source of truth for what the tour captures, in order — including\n"
        "tab-reached screens (e.g. Settings) that are not `Route` graph nodes\n"
        "above. `scripts/ui-tour.sh` runs it and extracts the PNGs into\n"
        "`docs/design/screenshots/` (gitignored — regenerate to view;\n"
        "`docs/design/screenshots/README.md`). Anchors are the per-screen wait\n"
        "identifiers; *Reached via* is the launch root, a tab switch, or a\n"
        "tab-stack push.\n"
    )
    lines.append("| # | Screenshot | Tour anchor | Reached via |")
    lines.append("|---|------------|-------------|-------------|")
    for index, (name, anchor, reached) in enumerate(tour_stops, start=1):
        lines.append(f"| {index} | `{name}.png` | `{anchor}` | {reached} |")
    lines.append("")
    return "\n".join(lines)


def generate() -> tuple[str, list[str]]:
    route_cases = parse_route_cases(ROUTER_FILE.read_text(encoding="utf-8"))
    edges, errors = collect_edges()
    tour_stops = parse_tour_stops(TOUR_FILE.read_text(encoding="utf-8"))
    known = set(SYNTHETIC_ROOTS) | set(route_cases)
    for source, target, _ in edges:
        if target not in known:
            errors.append(f"edge target '.{target}' is not a Route case — scanner or Route drift")
        if source not in known:
            errors.append(f"edge source '{source}' is not a known node")
    # Independent of the tour: every Mermaid node needs a display label. This
    # is NOT a Route<->stop correspondence — `simulation` is a labelled node
    # with no tour stop, and that is fine.
    missing_labels = [n for n in known if n not in NODE_LABELS]
    if missing_labels:
        errors.append(
            f"NODE_LABELS missing entries for: {', '.join(sorted(missing_labels))} — "
            "add label rows in scripts/generate-navigation-map.py"
        )
    # Independent of the graph: a non-empty tour catches a stale capture regex
    # (a silently-emptied table would otherwise pass --check once committed).
    if not tour_stops:
        errors.append(
            f"no tour stops parsed from {TOUR_FILE.relative_to(REPO_ROOT)} — "
            "the capture(...) regex in scripts/generate-navigation-map.py may be stale"
        )
    return emit_markdown(route_cases, edges, tour_stops), errors


# --- self-test ---------------------------------------------------------------


def self_test() -> int:
    failures = []
    total = 0

    def check(name: str, condition: bool):
        nonlocal total
        total += 1
        if not condition:
            failures.append(name)

    # --- edge scanning (Mermaid graph source) --------------------------------

    # Doc-comment tokens must never become edges or nodes.
    commented = "/// Example: `router.push(.settings)` no-ops here.\n// case foo\n"
    check("comment: zero edges", scan_file_edges("Pastura/Pastura/Views/Home/HomeView.swift", commented)[0] == [])
    check("comment: zero nodes", parse_route_cases("/// enum Route { case scenarioDetail(id: String) }\n") == [])

    # Exact production wrap from GalleryScenarioDetailView (next: and the
    # case on separate physical lines, nested parens in expected:).
    push_wrap = (
        "router.pushIfOnTop(\n"
        "  expected: .galleryScenarioDetail(scenario: scenario),\n"
        "  next: .scenarioDetail(\n"
        "    scenarioId: scenarioId,\n"
        "    initialName: .init(name)))\n"
    )
    edges, errs = scan_file_edges(
        "Pastura/Pastura/Views/Community/SharedScenarios/GalleryScenarioDetailView.swift", push_wrap
    )
    check("pushIfOnTop wrap: one scenarioDetail edge", edges == [("galleryScenarioDetail", "scenarioDetail", "")] and not errs)

    # Exact production wrap from ScenarioDetailView (line break after
    # "NavigationLink(" AND after "value:"-adjacent Route call).
    link_wrap = (
        "NavigationLink(\n"
        "  value: Route.simulation(\n"
        "    scenarioId: scenarioId,\n"
        "    initialName: .init(scenario.name)\n"
        "  )\n"
        ") { Label(\"Run\", systemImage: \"play.fill\") }\n"
    )
    edges, errs = scan_file_edges("Pastura/Pastura/Views/ScenarioDetail/ScenarioDetailView.swift", link_wrap)
    check("NavigationLink wrap: one simulation edge", edges == [("scenarioDetail", "simulation", "")] and not errs)

    # Unknown helper must error, never silently drop.
    helper = "NavigationLink(value: mysteryRoute()) { Text(\"x\") }\n"
    edges, errs = scan_file_edges("Pastura/Pastura/Views/Home/HomeView.swift", helper)
    check("unknown helper: error", edges == [] and len(errs) == 1 and "manual edge attribution" in errs[0])

    # Known helper produces no scanner edge (covered by MANUAL_EDGES instead).
    known_helper = "NavigationLink(value: newScenarioRoute()) { Text(\"x\") }\n"
    edges, errs = scan_file_edges("Pastura/Pastura/Views/Home/HomeView.swift", known_helper)
    check("known helper: no edge, no error", edges == [] and errs == [])

    # Un-attributed file with a real edge must error.
    edges, errs = scan_file_edges("Pastura/Pastura/Views/Settings/SettingsView.swift", "NavigationLink(value: Route.editor()) {}\n")
    check("unknown file: attribution error", edges == [] and len(errs) == 1 and "FILE_TO_SCREEN" in errs[0])

    # --- tour-table parsing (Screenshot tour source) ------------------------

    # Multi-line capture with a trailing `timeout:` (exact 01-home shape).
    # Doubles as the re.S guard: without re.S the newlines block the match,
    # parse returns [], and this assertion fails.
    multiline = (
        "capture(\n"
        '  app, name: "01-home",\n'
        '  anchorId: "home.scenarioListCell.ui_test_home_seed", timeout: 10)\n'
    )
    check(
        "tour: multi-line capture w/ timeout (re.S guard)",
        parse_tour_stops(multiline) == [("01-home", "home.scenarioListCell.ui_test_home_seed", "root")],
    )

    # Single-line capture.
    check(
        "tour: single-line capture",
        parse_tour_stops('capture(app, name: "02-scenario-detail", anchorId: "scenarioDetail.list")\n')
        == [("02-scenario-detail", "scenarioDetail.list", "root")],
    )

    # The verbatim doc-comment example (L14-15 of the test) must NOT parse —
    # strip_comments removes the `///` lines before the regex runs.
    doc_comment = (
        '/// `capture(app, name: "NN-screen-name", anchorId: "<identifier>")` with an\n'
        "/// identifier that only exists once the screen's content has loaded.\n"
    )
    check("tour: doc-comment example ignored", parse_tour_stops(doc_comment) == [])

    # The `func capture` declaration has `name: String` (no string literal) —
    # must not be parsed as a stop.
    helper_sig = (
        "private func capture(\n"
        "  _ app: XCUIApplication, name: String, anchorId: String,\n"
        "  timeout: TimeInterval = 5\n"
        ") {\n"
    )
    check("tour: helper signature not parsed", parse_tour_stops(helper_sig) == [])

    # reached-via: root -> push -> tab, with an inline back-button tap that
    # must be IGNORED (exercises the `!= pasturaBackButton` branch the goBack
    # helper otherwise hides behind a function call).
    seq = (
        'capture(app, name: "01-a", anchorId: "a")\n'
        'app.buttons["x"].tap()\n'
        'capture(app, name: "02-b", anchorId: "b")\n'
        'app.buttons["pasturaBackButton"].tap()\n'
        'app.tabBars.buttons["Browse"].tap()\n'
        'capture(app, name: "03-c", anchorId: "c")\n'
    )
    check(
        "tour: reached-via root/push/tab, inline back ignored",
        parse_tour_stops(seq)
        == [("01-a", "a", "root"), ("02-b", "b", "push"), ("03-c", "c", "tab")],
    )

    # An interval whose only tap is the back button => root, NOT push (proves
    # the back filter is load-bearing: drop the guard and this becomes push).
    back_only = (
        'capture(app, name: "01-a", anchorId: "a")\n'
        'app.buttons["pasturaBackButton"].tap()\n'
        'capture(app, name: "02-b", anchorId: "b")\n'
    )
    check(
        "tour: inline back-only interval -> root",
        parse_tour_stops(back_only) == [("01-a", "a", "root"), ("02-b", "b", "root")],
    )

    # A `.exists` reference (not `.tap()`) must not count as a push — mirrors
    # the test's `XCTAssertFalse(app.buttons["pasturaBackButton"].exists, ...)`.
    exists_only = (
        'capture(app, name: "01-a", anchorId: "a")\n'
        'XCTAssertFalse(app.buttons["pasturaBackButton"].exists, "no back")\n'
        'capture(app, name: "02-b", anchorId: "b")\n'
    )
    check(
        "tour: .exists (non-tap) not a push",
        parse_tour_stops(exists_only) == [("01-a", "a", "root"), ("02-b", "b", "root")],
    )

    # No captures => no stops (the input that trips generate()'s zero-stops error).
    check("tour: no captures -> no stops", parse_tour_stops("func body() { app.launch() }\n") == [])

    # --- emission ------------------------------------------------------------

    # SYNTHETIC_ROOTS regression (ADR-016 D4): a tab root whose Route case was
    # deleted but which still owns an outgoing edge (sharedScenarios ->
    # galleryScenarioDetail) must render as a rounded, sourceless root. Also
    # confirms the table is now tour-derived (a row keyed by screenshot name,
    # not node) and the old node-table columns are gone.
    md = emit_markdown(
        ["galleryScenarioDetail"],
        [("sharedScenarios", "galleryScenarioDetail", "")],
        [("04-shared-scenarios", "sharedScenarios.galleryCell.ui_test_canary", "tab")],
    )
    check(
        "emit: synthetic root rendered as rounded tab root",
        "sharedScenarios([Shared Scenarios])" in md
        and 'galleryScenarioDetail["Gallery Scenario Detail"]' in md,
    )
    check(
        "emit: tour table from stops, old node-table columns gone",
        "| 1 | `04-shared-scenarios.png` | `sharedScenarios.galleryCell.ui_test_canary` | tab |" in md
        and "Pushed from" not in md
        and "(stack root)" not in md,  # old table cell `— (stack root)`; prose "tab-stack roots" is fine
    )

    for name in failures:
        print(f"SELF-TEST FAIL: {name}", file=sys.stderr)
    print(f"self-test: {total - len(failures)}/{total} passed")
    return 1 if failures else 0


# --- main --------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="diff regenerated output against the committed file")
    parser.add_argument("--self-test", action="store_true", help="run embedded regression fixtures")
    args = parser.parse_args()

    if args.self_test:
        return self_test()

    content, errors = generate()
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    if args.check:
        committed = OUTPUT_FILE.read_text(encoding="utf-8") if OUTPUT_FILE.exists() else ""
        if committed != content:
            print(
                "ERROR: docs/design/navigation-map.md is stale — regenerate with\n"
                "  python3 scripts/generate-navigation-map.py",
                file=sys.stderr,
            )
            import difflib

            sys.stderr.writelines(
                difflib.unified_diff(
                    committed.splitlines(keepends=True),
                    content.splitlines(keepends=True),
                    fromfile="committed",
                    tofile="regenerated",
                )
            )
            return 1
        print("navigation-map: up to date")
        return 0

    OUTPUT_FILE.write_text(content, encoding="utf-8")
    print(f"wrote {OUTPUT_FILE.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

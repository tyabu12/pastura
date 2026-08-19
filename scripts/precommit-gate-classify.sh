#!/usr/bin/env bash
#
# scripts/precommit-gate-classify.sh — classify the staged changeset for
# the pre-commit gate (#625).
#
# Reads newline-separated staged paths on stdin (as produced by
# `git diff --cached --name-only`) and emits, on a single stdout line,
# the set of expensive gates the changeset warrants:
#
#   lint   — at least one staged path can affect SwiftLint output
#            (`*.swift`, or `.swiftlint.yml` itself: a tightened rule can
#            newly flag unchanged code). `swiftlint lint` scans the whole
#            tree, so a changeset with no such path cannot introduce a new
#            violation and the lint step is safely skippable.
#   build  — at least one staged path is NOT provably build-irrelevant.
#
# Tokens are space-separated; either may be absent. An empty changeset
# emits nothing (both gates skippable).
#
# Design — CONSERVATIVE by inversion (#625). The script does NOT try to
# enumerate every build-relevant file type: forgetting one would be a
# *false skip* — a broken build landing, which the issue calls the worst
# case. Instead it skips the build ONLY when EVERY staged path matches a
# small denylist of provably build-irrelevant locations (web/, docs/,
# .github/, .claude/, markdown, repo-meta dotfiles). Any unrecognized
# path forces the build.
#
# bash 3.2 portable — ships to dev macOS machines via the pre-commit
# hook (`#!/usr/bin/env bash`). NO mapfile/readarray, declare -A,
# ${var^^}, or <<< here-strings. The CI `shell-tests` job runs on ubuntu
# (bash 5+) and does NOT catch a 3.2 regression — keep this 3.2-clean by
# hand. Tested by scripts/tests/precommit-gate-classify-test.sh.

set -euo pipefail

# Drop blank lines so an empty changeset (a lone trailing newline) does
# not read as a single empty, non-safe path. `|| true` absorbs grep's
# exit-1 on all-blank input under `set -e`.
staged="$(grep -v '^[[:space:]]*$' || true)"

tokens=""

# Both classifications below capture the match instead of testing a `grep -q`
# pipeline's status, and the difference is load-bearing rather than stylistic.
# `grep -q` exits at its first hit; the still-writing `printf` takes SIGPIPE and
# returns 141; `pipefail` (set above) promotes that to the pipeline's status.
# So on a changeset whose name list outruns the pipe buffer, with a matching
# path near the front, BOTH tokens silently dropped: measured, a 92,623-byte
# list led by a .swift file classified as `` where a short list of the same
# shape classified as `lint build` (#1498).
#
# That is the "worst case" this script's header names, reached from inside. It
# disarms `swiftlint --strict` and `xcodebuild build` in the pre-commit hook,
# and — because .github/workflows/ci.yml's `changes` job derives `ios` from the
# `build` token — skips lint-and-test and ui-test on CI with every required
# check green. Both fail-safes ci.yml documents miss it: the file list is not
# empty, and this script exits 0, it just prints nothing.
#
# Dropping `-q` is what fixes it, NOT capturing into a variable first — the
# producer here was already `printf`, and re-adding `-q` below reinstates the
# defect unchanged. `.claude/rules/ci-workflows.md` § "Rule 3".
#
# `|| [ $? -eq 1 ]` and not `|| true`: exit 1 is grep's real "no match", exit
# >=2 means the pattern broke. `|| true` would map a broken pattern to "no
# match" — i.e. to no tokens — which is the same silent disarming. Failing the
# assignment under `set -e` instead makes ci.yml's `if ! TOKENS=$(...)`
# fail-safe fire and default to the full suite.

# `lint`: any Swift source, or the SwiftLint config (at any depth).
lint_match="$(printf '%s\n' "$staged" | { grep -E '(\.swift$|(^|/)\.swiftlint\.yml$)' || [ $? -eq 1 ]; })"
if [ -n "$lint_match" ]; then
  tokens="lint"
fi

# `build`: any path NOT on the build-irrelevant denylist. The pattern is
# anchored so a match means the WHOLE path is provably safe; `grep -qv`
# then succeeds when at least one staged path is NOT safe.
#
# `\.md$` treats Markdown as globally build-irrelevant. No `*.md` is a
# compiled app-bundle resource today; if one is ever added under
# Pastura/Pastura/Resources/, carve it out of this denylist so it forces
# the build.
#
# WIDENING THIS DENYLIST DISARMS CI GATES SILENTLY. ci.yml derives the
# `changes` job's `ios` output from the `build` token, and several jobs run
# only when `ios != false` — so a path added here stops reaching them while
# every gate still reports green, having never run. `shared/**` is the live
# example: keeping it non-SAFE is the only reason `harness-build`'s two
# generated-Kotlin drift guards see a PR that hand-edits one of those files.
# scripts/tests/precommit-gate-classify-test.sh pins that case.
SAFE='(^(web/|docs/|\.github/|\.claude/))|(\.md$)|(^(\.gitignore|\.gitattributes|\.editorconfig|LICENSE)$)'
# Capture, don't `grep -qv` — see the note above the `lint` classification.
unsafe_match="$(printf '%s\n' "$staged" | { grep -vE "$SAFE" || [ $? -eq 1 ]; })"
if [ -n "$staged" ] && [ -n "$unsafe_match" ]; then
  tokens="${tokens:+$tokens }build"
fi

printf '%s\n' "$tokens"
exit 0

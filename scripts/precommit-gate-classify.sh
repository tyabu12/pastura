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

# `lint`: any Swift source, or the SwiftLint config (at any depth).
if printf '%s\n' "$staged" | grep -qE '(\.swift$|(^|/)\.swiftlint\.yml$)'; then
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
if [ -n "$staged" ] && printf '%s\n' "$staged" | grep -qvE "$SAFE"; then
  tokens="${tokens:+$tokens }build"
fi

printf '%s\n' "$tokens"
exit 0

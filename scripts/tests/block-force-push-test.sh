#!/usr/bin/env bash
#
# scripts/tests/block-force-push-test.sh — regression test for
# scripts/hooks/block-force-push-and-pr-ready.sh (issue #616).
#
# Feeds synthetic PreToolUse(Bash) payloads to the hook and asserts the
# exit code: 0 = allowed, non-zero (2) = blocked. The headline case is
# the #616 false-fire — a `git push` compound whose SIBLING subcommand
# body carries a `+`-leading or `-f`-clustered token must be ALLOWED,
# while every real force-push shape must stay BLOCKED.
#
# CI-wired: the `*-test.sh` naming convention makes this a gate under
# `.github/workflows/ci.yml` ("Run scripts/tests/*-test.sh"). That job
# runs on ubuntu (bash 5+), so it CANNOT catch a bash-3.2 regression in
# the hook itself — the hook ships to a macOS (bash 3.2) machine. Run
# the hook manually under /bin/bash before merge for 3.2 coverage.
#
# Run manually:
#   bash scripts/tests/block-force-push-test.sh

set -euo pipefail

HOOK="$(git rev-parse --show-toplevel)/scripts/hooks/block-force-push-and-pr-ready.sh"
fail=0

# Run the hook with `.tool_input.command` set to $1; return its exit code.
# `jq -Rs` slurps stdin (incl. embedded newlines) into a single JSON
# string — the same shape the harness sends.
run_hook() {
  printf '%s' "$1" | jq -Rs '{tool_input:{command:.}}' | bash "$HOOK"
}

assert_allow() {
  if run_hook "$2" >/dev/null 2>&1; then
    : # exit 0 — allowed, as expected
  else
    echo "FAIL [expected ALLOW, got BLOCK]: $1" >&2
    fail=1
  fi
}

assert_block() {
  if run_hook "$2" >/dev/null 2>&1; then
    echo "FAIL [expected BLOCK, got ALLOW]: $1" >&2
    fail=1
  fi
}

# --- ALLOW cases ---------------------------------------------------------

# The #616 headline: force-looking tokens (+foo, -fv) live in a SIBLING
# `gh pr create` body, not in the push. Must be allowed.
assert_allow "compound: + and -f tokens in sibling --body" \
  'git push -u origin x && gh pr create --body "fixes +foo and use -fv prose"'

# A quoted `&&` inside the body splits via tr alongside the real `&&`;
# the resulting body fragments are not `git push` invocations.
assert_allow "compound: quoted && plus +foo inside --body" \
  'git push -u origin x && gh pr create --body "fixes +foo and a && b -f"'

# Newline-separated sibling commands (a single Bash call with a literal
# newline, no &&) — the second line is not a push.
assert_allow "newline-separated sibling with + and -f in body" \
  "$(printf 'git push -u origin x\ngh pr create --body "has +foo and -f"')"

assert_allow "plain push, no force" 'git push -u origin main'

# Tokenized scan drops the old substring false-fire: a foreign command
# (echo) or a sibling non-push carrying a force-looking token must be
# ALLOWED — the old whole-command `--force` arm BLOCKED the echo case.
assert_allow "prose: force flag inside echo" 'echo "git push --force in prose"'
assert_allow "benign -f in sibling rm" 'git push origin x && rm -f stale.txt'

assert_allow "empty command" ''

# Malformed JSON falls through to a silent allow (fail-open) — bypass
# run_hook so we feed raw non-JSON straight to the hook.
if printf 'this is not json at all' | bash "$HOOK" >/dev/null 2>&1; then
  : # allowed, as expected
else
  echo "FAIL [expected ALLOW, got BLOCK]: malformed JSON input" >&2
  fail=1
fi

# --- BLOCK cases ---------------------------------------------------------
#
# Note: detection is now tokenized (a 3-phase per-segment state machine),
# not a whole-command `--force` substring plus segment-scoping split. The
# cases that lock in the tokenization are the sibling-body / echo-prose
# ALLOWs above (BLOCKED by the old substring gate), the prefix-wrapped
# AMBIGUOUS cases (env/sudo/command + `-uf`/`+refspec`), and the BLOCKs
# that the old `git push` substring gate let slip — `git -c … push`,
# `git --no-pager push`, `timeout … git push`, double-space `git  push`.

assert_block "long force flag" 'git push origin x --force'
assert_block "force-with-lease" 'git push --force-with-lease origin x'
assert_block "+refspec" 'git push origin +main'
assert_block "-uf short-flag cluster" 'git push -uf origin x'
assert_block "line-continuation force" "$(printf 'git push origin x \\\n--force')"
assert_block "line-continuation +refspec" "$(printf 'git push origin \\\n+main')"
assert_block "env-prefixed long force" 'env FOO=bar git push --force'
assert_block "env-prefixed -uf cluster" 'env FOO=bar git push -uf origin x'
assert_block "sudo-prefixed +refspec" 'sudo git push origin +main'
assert_block "command-prefixed -uf cluster" 'command git push -uf origin x'
assert_block "bare VAR=value prefix +refspec" 'FOO=bar git push origin +main'
# Tokenization closes shapes the old `git push` substring gate let slip:
assert_block "git global -c then push --force" 'git -c k=v push --force'
assert_block "git --no-pager push -f" 'git --no-pager push -f'
assert_block "timeout wrapper then push -f" 'timeout 5 git push -f'
assert_block "double-space git push --force" 'git  push --force'
assert_block "gh pr ready" 'gh pr ready 123'

# --- result --------------------------------------------------------------

if [ "$fail" -eq 0 ]; then
  echo "block-force-push: all cases passed"
else
  echo "block-force-push: FAILURES" >&2
  exit 1
fi

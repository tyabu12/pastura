#!/usr/bin/env bash
#
# check-claude-md-modified.sh — project-knowledge update reminders.
#
# Inner script for the `Bash(gh pr create*)` PreToolUse hook. The
# prefix-gating is handled upstream by `scripts/hooks/gated-runner.sh`,
# so this script only runs when the runner has already confirmed the
# user-invoked command starts with `gh pr create`. It emits AT MOST ONE
# `hookSpecificOutput.additionalContext` nudge, choosing between two
# mutually-exclusive reminders (mutual exclusivity holds because the
# convention nudge fires only when CLAUDE.md is UNchanged, the mirror
# nudge only when it changed):
#
#   1. Convention nudge — if `git diff main...HEAD --name-only` shows
#      NEITHER CLAUDE.md NOR any `.claude/rules/` file, remind the operator
#      to record a new convention / trap / Phase 2 progress entry. (Touching
#      a `.claude/rules/` file also silences the CLAUDE.md "Phase 2 progress"
#      nudge — an intentional "you edited conventions, you likely considered
#      it" trade-off.)
#
#   2. Mirror-sync nudge — if CLAUDE.md changed inside one of the sections
#      the "Reference Documents" table mirrors to README / CONTRIBUTING, but
#      README.md / CONTRIBUTING.md was NOT changed on the branch, remind the
#      operator to check whether the mirror needs the same edit. This closes
#      the gap where the hook went silent EXACTLY when CLAUDE.md changed —
#      the moment a mirror update is most likely required.
#
# Mirror detection is SECTION-RANGE overlap, not "any CLAUDE.md change": a
# change confined to a non-mirrored section (Current Phase, the ADR index,
# Test Execution, …) must not nudge, or the reminder becomes noise. Section
# ranges are computed from `HEAD:CLAUDE.md` so their line numbers match the
# diff's new-side (`+c,d`) hunk numbers; a range ends at the next heading of
# level <= its own (so the `### Git Conventions` range stops at its sibling
# `### Test Execution`, not at the next `##`).
#
# Mirrored sections (heading -> mirror file, per the Reference Documents
# table):
#   ## Architecture / ## Hard Rules / ## Dependency Rules (STRICT)
#                                          -> README.md + CONTRIBUTING.md
#   ## Tech Stack / ## Directory Structure -> README.md
#   ### Git Conventions                    -> CONTRIBUTING.md
# Deliberately NOT covered (documented so a future reader doesn't file a
# "missing nudge" bug): the "Bundled models" mirror is source-driven
# (`ModelRegistry.swift`, not a CLAUDE.md section edit), and the
# i18n / ContentBlocklist mirror lives inside `## Swift Coding Conventions`
# — a section that also holds non-mirrored content, so it is not cleanly
# range-detectable without per-bullet logic.
#
# Fail-open: this is a PreToolUse hook, so a non-zero exit would surface a
# hook error on every `gh pr create`. The mirror detection therefore runs in
# a `set +e` subshell whose failures degrade to "no nudge", and the script
# ends on an unconditional `exit 0`.
#
# Reads no stdin. Reference: PR #406/#407; .claude/rules/ in #1026.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

CHANGED=$(git diff main...HEAD --name-only 2>/dev/null || true)

# --- 1. convention nudge ----------------------------------------------------
if ! printf '%s\n' "$CHANGED" | grep -qE 'CLAUDE\.md|\.claude/rules/'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      additionalContext: "Neither CLAUDE.md nor .claude/rules/ was modified in this branch. If this change adds or alters a convention, trap, or Phase 2 progress entry, record it — CLAUDE.md for project-wide / phase progress, .claude/rules/ for scoped conventions."
    }
  }'
  exit 0
fi

# --- 2. mirror-sync nudge ---------------------------------------------------
# Reached only when CLAUDE.md and/or .claude/rules/ changed (convention nudge
# silenced). Fires only when CLAUDE.md ITSELF changed and no mirror was touched.

# echoes the space-joined mirror files ("README.md" / "CONTRIBUTING.md" /
# "README.md CONTRIBUTING.md") for the touched mirrored sections, else
# nothing. `set +e` (this always runs in a `$()` subshell) makes every step
# fail-open to empty output.
mirror_targets() {
  set +e
  local head_md hunks
  head_md=$(git show HEAD:CLAUDE.md 2>/dev/null)
  [ -n "$head_md" ] || return 0
  hunks=$(git diff main...HEAD -U0 -- CLAUDE.md 2>/dev/null | grep '^@@')
  { printf '%s\n' "$hunks"; printf '===CLAUDEMD===\n'; printf '%s\n' "$head_md"; } \
    | awk '
      BEGIN { mode=0; nh=0; ln=0; infence=0; cur=""; curlvl=0 }
      mode==0 && $0=="===CLAUDEMD===" { mode=1; next }
      mode==0 {
        i=index($0, "+"); if (i==0) next
        rest=substr($0, i+1); sp=index(rest, " ")
        if (sp>0) rest=substr(rest, 1, sp-1)
        cm=index(rest, ",")
        if (cm>0) { c=substr(rest,1,cm-1)+0; d=substr(rest,cm+1)+0 }
        else { c=rest+0; d=1 }
        if (d==0) { hs[nh]=c; he[nh]=c+1 } else { hs[nh]=c; he[nh]=c+d }
        nh++; next
      }
      {
        ln++; line=$0
        if (line ~ /^(```|~~~)/) { infence=1-infence }
        else if (infence==0 && line ~ /^#+ /) {
          lvl=0; while (substr(line,lvl+1,1)=="#") lvl++
          if (cur!="" && lvl<=curlvl) { cur=""; curlvl=0 }
          t=target(line)
          if (t!="") { cur=t; curlvl=lvl }
        }
        if (cur!="") {
          for (k=0;k<nh;k++) if (ln>=hs[k] && ln<he[k]) {
            n=split(cur, tk, " "); for (j=1;j<=n;j++) hit[tk[j]]=1; break
          }
        }
      }
      END {
        out=""
        if ("README" in hit) out="README.md"
        if ("CONTRIBUTING" in hit) out=(out=="" ? "CONTRIBUTING.md" : out " CONTRIBUTING.md")
        print out
      }
      function target(h) {
        if (h=="## Architecture" || h=="## Hard Rules" || h=="## Dependency Rules (STRICT)") return "README CONTRIBUTING"
        if (h=="## Tech Stack" || h=="## Directory Structure") return "README"
        if (h=="### Git Conventions") return "CONTRIBUTING"
        return ""
      }
    '
}

if printf '%s\n' "$CHANGED" | grep -Fxq 'CLAUDE.md' \
   && ! printf '%s\n' "$CHANGED" | grep -Fxq -e README.md -e CONTRIBUTING.md; then
  TARGETS=$(mirror_targets || true)
  TARGETS=$(printf '%s' "$TARGETS" | tr -s ' ' | sed 's/^ //; s/ $//')
  if [ -n "$TARGETS" ]; then
    FILES=$(printf '%s' "$TARGETS" | sed 's/ / and /')
    jq -n --arg files "$FILES" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: ("CLAUDE.md changed in a section the \"Reference Documents\" table mirrors to " + $files + ", but " + $files + " was not updated on this branch. Before opening the PR, verify whether the mirror needs the same change.")
      }
    }'
  fi
fi

exit 0

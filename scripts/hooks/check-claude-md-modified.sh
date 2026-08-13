#!/usr/bin/env bash
#
# check-claude-md-modified.sh — project-knowledge update reminders.
#
# Inner script for the `Bash(gh pr create*)` PreToolUse hook. The
# prefix-gating is handled upstream by `scripts/hooks/gated-runner.sh`,
# so this script only runs when the runner has already confirmed the
# user-invoked command starts with `gh pr create`.
#
# EMIT CONTRACT: the script emits AT MOST ONE JSON document. The applicable
# sections below are concatenated (blank-line separated, in section order)
# into that single `hookSpecificOutput.additionalContext`. Never two JSON
# documents — Claude Code's hook schema documents a single stdout object and
# multi-object behaviour is undefined. The convention nudge (1) stays
# mutually exclusive with the rest BY CONSTRUCTION: it fires only when no
# agent-instruction file changed at all, which implies zero instruction
# growth, so sections 2–4 cannot apply.
#
# "Agent-instruction files" = CLAUDE.md + `.claude/rules/**` + `.claude/agents/**`.
# Two tiers, because their context cost differs by an order of magnitude:
#   - ALWAYS-LOADED: CLAUDE.md, `.claude/agents/*`, and any `.claude/rules/*.md`
#     whose first 14 lines contain NO line starting `paths:`. Paid on every
#     turn of every session.
#   - PATH-SCOPED: a `.claude/rules/*.md` whose first 14 lines DO contain
#     `^paths:`. Loaded only when a matching path is read.
# The head-14 approximation mirrors `.claude/agents/code-reviewer.md`'s
# documented sweep; the longest real frontmatter block closes at line 7.
#
#   1. Convention nudge — if `git diff main...HEAD --name-only` shows NO
#      agent-instruction file at all, remind the operator to record a new
#      convention / trap / Phase 2 progress entry. (Touching a
#      `.claude/rules/` or `.claude/agents/` file also silences the CLAUDE.md
#      "Phase 2 progress" nudge — an intentional "you edited conventions, you
#      likely considered it" trade-off.) Emits and exits immediately.
#
#   2. Mirror-sync nudge — if CLAUDE.md changed inside one of the sections
#      the "Reference Documents" table mirrors to README / CONTRIBUTING, but
#      README.md / CONTRIBUTING.md was NOT changed on the branch, remind the
#      operator to check whether the mirror needs the same edit. This closes
#      the gap where the hook went silent EXACTLY when CLAUDE.md changed —
#      the moment a mirror update is most likely required.
#
#   3. Trim nudge — if the branch's ADDED lines across agent-instruction files
#      cross a per-tier threshold, ask for a `context-budget.md` Keep/Drop
#      pass recorded as a `Context-economy:` line in the PR body. Size is a
#      trigger, not a verdict. Threshold rationale: #1361.
#
#   4. Footprint nudge — if the branch ADDED lines to any ALWAYS-LOADED
#      instruction file and the repo-wide always-loaded byte total exceeds a
#      ceiling, surface the aggregate and suggest a slim campaign. Only fires
#      when the operator is already growing that tier, so it is advice at the
#      moment it is actionable rather than a standing alarm.
#
#   5. Compose + emit — the applicable sections 2-4 join into the one JSON
#      document per the EMIT CONTRACT above.
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
# hook error on every `gh pr create`. The mirror detection and the footprint
# measurement therefore each run in a `set +e` subshell whose failures degrade
# to "no section", every other external command is guarded with
# `2>/dev/null` / `|| true`, and the script ends on an unconditional `exit 0`.
#
# Reads no stdin. Reference: PR #406/#407; .claude/rules/ in #1026;
# trim + footprint sections in #1361.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

CHANGED=$(git diff main...HEAD --name-only 2>/dev/null || true)

# --- 1. convention nudge ----------------------------------------------------
# Early emit + exit. Mutually exclusive with sections 2-4 by construction: no
# agent-instruction file changed => no mirror-relevant CLAUDE.md edit and zero
# instruction growth, so nothing below could have fired anyway. Anchored to
# match section 3's root-exact pathspec — a stray `docs/foo/CLAUDE.md` must
# not silence this nudge while contributing nothing to the tier sums.
if ! printf '%s\n' "$CHANGED" | grep -qE '^CLAUDE\.md$|^\.claude/(rules|agents)/'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      additionalContext: "No agent-instruction file (CLAUDE.md, .claude/rules/, .claude/agents/) was modified in this branch. If this change adds or alters a convention, trap, or Phase 2 progress entry, record it — CLAUDE.md for project-wide / phase progress, .claude/rules/ for scoped conventions."
    }
  }' || true
  exit 0
fi

# --- 2. mirror-sync nudge ---------------------------------------------------
# Reached only when an agent-instruction file changed (convention nudge
# silenced). Fires only when CLAUDE.md ITSELF changed and no mirror was touched.
# Captures its message into MIRROR_MSG for composition in section 5.

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
  # Sentinel separates the hunk headers from the CLAUDE.md body on one
  # stream. It is deliberately collision-resistant — a CLAUDE.md line equal
  # to it would corrupt parsing, so it is not a string anyone would type.
  { printf '%s\n' "$hunks"; printf '%s\n' "@@@PASTURA-CLAUDEMD-BOUNDARY@@@"; printf '%s\n' "$head_md"; } \
    | awk '
      BEGIN { mode=0; nh=0; ln=0; infence=0; cur=""; curlvl=0 }
      mode==0 && $0=="@@@PASTURA-CLAUDEMD-BOUNDARY@@@" { mode=1; next }
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
        # Only column-0 fences toggle (matches every fence in the mirrored
        # sections today); an indented fence inside a list item would not.
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

MIRROR_MSG=""
if printf '%s\n' "$CHANGED" | grep -Fxq 'CLAUDE.md'; then
  TARGETS=$(mirror_targets || true)
  TARGETS=$(printf '%s' "$TARGETS" | tr -s ' ' | sed 's/^ //; s/ $//')
  # Subtract mirror files already updated on this branch. A dual-mirror
  # section (## Architecture / Hard Rules / Dependency Rules -> README AND
  # CONTRIBUTING) must still nudge for the half that is stale when only one
  # mirror was synced — a coarse "any mirror changed -> silent" guard would
  # miss exactly the drift this hook exists to catch.
  REMAIN=""
  for f in $TARGETS; do
    if ! printf '%s\n' "$CHANGED" | grep -Fxq "$f"; then
      REMAIN="${REMAIN:+$REMAIN }$f"
    fi
  done
  if [ -n "$REMAIN" ]; then
    FILES=$(printf '%s' "$REMAIN" | sed 's/ / and /')
    MIRROR_MSG="CLAUDE.md changed in a section the \"Reference Documents\" table mirrors to ${FILES}, but ${FILES} was not updated on this branch. Before opening the PR, verify whether the mirror needs the same change."
  fi
fi

# --- 3. trim nudge (#1361 proposal A) ---------------------------------------
# Calibrated on 16 weeks of numstat (#1361): the path-scoped 20 is pinned by
# the acceptance criterion — it must catch #1360's +22-line addition AS IT
# STOOD AT PR-CREATE TIME, which is when this hook fires (the merged commit
# shows +18/-1 only because a review round then compacted it, so re-deriving
# the margin from `git show 15a744c0 --numstat` understates it by exactly that
# round). The always-loaded 10 follows from the issue's ~2x-stricter tiering
# for the bytes paid on every turn. Sums are per tier, per branch.
AL_TRIM_THRESHOLD=10
PS_TRIM_THRESHOLD=20

# `--no-renames`: a rule split/rename then counts at full size. Over-counting
# is the safe direction for an advisory nudge, whereas letting git pair the
# halves would report a split — the exact growth event this nudge exists for —
# as near-zero added lines.
NUMSTAT=$(git diff main...HEAD --numstat --no-renames -- CLAUDE.md .claude/rules .claude/agents 2>/dev/null || true)

AL_ADD=0
PS_ADD=0
TOUCHED_ALWAYS_LOADED=0

# Deliberately NOT `printf ... | while read`: the loop body would run in a
# subshell and every sum would be lost on exit. Neither macOS bash 3.2 nor
# ubuntu bash 5 enables `lastpipe`, so the here-doc feed is the portable form.
# (`<<<` here-strings and `mapfile` are bash-4+ / unavailable on 3.2.)
while IFS=$'\t' read -r added _removed path; do
  [ -n "${path:-}" ] || continue
  # Binary files report `-` for both counts; skip anything non-numeric.
  case "$added" in
    ''|*[!0-9]*) continue ;;
  esac
  tier="always"
  case "$path" in
    .claude/rules/*)
      # Classify from HEAD, the same side of the diff the added lines land on.
      # A file deleted on this branch has no HEAD copy, so `git show` fails and
      # we fail open to the stricter (always-loaded) tier — harmless, since a
      # deletion contributes 0 ADDED lines and the footprint gate below arms
      # only on added > 0.
      if git show "HEAD:$path" 2>/dev/null | head -n 14 | grep -q '^paths:'; then
        tier="scoped"
      fi
      ;;
  esac
  if [ "$tier" = "scoped" ]; then
    PS_ADD=$((PS_ADD + added))
  else
    AL_ADD=$((AL_ADD + added))
    # Arm the footprint gate only on real growth: a deletion-only touch (or a
    # deleted path-scoped rule fail-opening into this branch) must not turn a
    # shrinking PR into a "consider slimming" alarm.
    if [ "$added" -gt 0 ]; then
      TOUCHED_ALWAYS_LOADED=1
    fi
  fi
done <<EOF
$NUMSTAT
EOF

TRIM_MSG=""
if [ "$AL_ADD" -ge "$AL_TRIM_THRESHOLD" ] || [ "$PS_ADD" -ge "$PS_TRIM_THRESHOLD" ]; then
  # The `Context-economy:` token is fixed on purpose: it makes compliance
  # grep-able from `gh pr list` later, which is the data source for the
  # deferred reflection-hook-backstop decision (#1361).
  TRIM_MSG="This branch adds +${AL_ADD} always-loaded / +${PS_ADD} path-scoped lines to agent-instruction files (nudge thresholds: ${AL_TRIM_THRESHOLD} always-loaded / ${PS_TRIM_THRESHOLD} path-scoped). Size is a trigger, not a verdict: apply .claude/rules/context-budget.md's Keep/Drop classifier to each added paragraph, compress what fails it, and record the outcome in the PR body as a 'Context-economy:' line (e.g. 'Context-economy: kept N paragraphs, compressed/dropped M — one-line rationale')."
fi

# --- 4. always-loaded footprint nudge (#1361 proposal B) --------------------
# The total was 91,615 bytes when this was introduced (#1361, 2026-08-05); it
# had drifted to 98,036 — above the then-96,000 ceiling — by 2026-08-13, when
# #1442 evacuated the kit-mirror rules' depth to docs/agent-tooling/ and brought
# it to 94,640 (measured on that PR's final commit — the mid-review figure was
# 890 bytes lower, which is why this is re-derived rather than quoted forward).
# A slim campaign (#1310 / #1315 style) that lands below the ceiling should
# re-baseline this default in its own PR — otherwise the nudge decays into
# permanent wallpaper that everyone scrolls past. Ratchet it DOWN to just above
# the new total so the campaign's gain is held. The headroom below is ~0.9%,
# deliberately far tighter than the 4.8% this started with: the observed drift
# rate (+6,400 bytes in 8 days) makes a loose ceiling silent for months. The
# accepted cost is the symmetric failure — at this tightness roughly one added
# rule paragraph trips it. That is tolerable only because the nudge is
# non-blocking `additionalContext`, so the remedy is a one-line Context-economy
# record in the PR body, not a blocked commit. The env var exists so the test
# harness can force the firing branch.
#
# Held in one variable because the value is needed twice (the `:-` default and
# the malformed-input fallback). Nothing exercises the fallback branch — it runs
# only on non-numeric env input — so two literals would let a future re-baseline
# update one and diverge silently, which is the same drift class #1442 was
# cleaning up when it set this value.
FOOTPRINT_CEILING_DEFAULT=95500
FOOTPRINT_CEILING="${PASTURA_FOOTPRINT_CEILING:-$FOOTPRINT_CEILING_DEFAULT}"
# The one external input; a non-numeric value would make the -gt test below
# spray `[: illegal number` on stderr, so guard it like $added and $n.
case "$FOOTPRINT_CEILING" in
  ''|*[!0-9]*) FOOTPRINT_CEILING="$FOOTPRINT_CEILING_DEFAULT" ;;
esac

# echoes the total byte size of every tracked always-loaded instruction file,
# else nothing. `set +e` (this always runs in a `$()` subshell) makes every
# step fail-open to empty output => no section.
always_loaded_bytes() {
  set +e
  local files f total
  files=$(git ls-files 'CLAUDE.md' '.claude/agents/*.md' '.claude/rules/*.md' 2>/dev/null)
  [ -n "$files" ] || return 0
  total=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in
      .claude/rules/*)
        head -n 14 "$f" 2>/dev/null | grep -q '^paths:' && continue
        ;;
    esac
    local n
    n=$(wc -c < "$f" 2>/dev/null | tr -d ' ')
    case "$n" in
      ''|*[!0-9]*) continue ;;
    esac
    total=$((total + n))
  done <<INNER_EOF
$files
INNER_EOF
  printf '%s' "$total"
}

FOOTPRINT_MSG=""
if [ "$TOUCHED_ALWAYS_LOADED" -eq 1 ]; then
  TOTAL=$(always_loaded_bytes || true)
  case "$TOTAL" in
    ''|*[!0-9]*) TOTAL="" ;;
  esac
  if [ -n "$TOTAL" ] && [ "$TOTAL" -gt "$FOOTPRINT_CEILING" ]; then
    FOOTPRINT_MSG="Always-loaded instruction footprint is ${TOTAL} bytes, above the ${FOOTPRINT_CEILING}-byte ceiling — every byte is paid on every turn of every session. Consider proposing a #1310/#1315-style slim campaign; if the current level is deliberate, re-baseline the ceiling default in scripts/hooks/check-claude-md-modified.sh."
  fi
fi

# --- 5. compose + emit ------------------------------------------------------
# Exactly one JSON document, or none. Sections join in declaration order,
# blank-line separated.
CONTEXT=""
for section_var in "$MIRROR_MSG" "$TRIM_MSG" "$FOOTPRINT_MSG"; do
  [ -n "$section_var" ] || continue
  if [ -n "$CONTEXT" ]; then
    CONTEXT="${CONTEXT}

${section_var}"
  else
    CONTEXT="$section_var"
  fi
done

if [ -n "$CONTEXT" ]; then
  # `|| true`: jq failure must not exit non-zero — this is a PreToolUse hook.
  jq -n --arg ctx "$CONTEXT" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      additionalContext: $ctx
    }
  }' || true
fi

exit 0

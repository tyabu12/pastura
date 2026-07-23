#!/usr/bin/env bash
#
# scripts/tests/kmp-status-gate-test.sh — regression test for the KMP migration
# status board drift gate (#1231): scripts/check-kmp-status.py and its pre-commit
# wrapper scripts/kmp-status-precommit-gate.sh.
#
# Two scopes:
#   Part A — the checker's real --check I/O path, driven by a throwaway fixture
#            repo. check-kmp-status.py derives REPO from its own location
#            (`__file__.parent.parent`), so copying it into a fixture's scripts/
#            makes the fixture the repo. This exercises fence parsing + the row
#            regex + `git ls-files` against a REAL drift, which the checker's own
#            pure-evaluate() --self-test cannot. Perturbation-first: a guard's
#            pass case proves nothing, so every failure mode must flip red.
#   Part B — the wrapper's TRIGGER decision (fires on the board / ledger / a
#            ported .kt / the checker; skips otherwise), via a python3 stub, the
#            way navigation-map-precommit-gate-test.sh does.
#
# CI-wired by the `*-test.sh` name (ci.yml "Shell gate tests", ubuntu bash 5+).
# That runner does NOT catch a bash-3.2 regression in the gate wrapper — keep the
# wrapper 3.2-clean by hand. Run manually:
#   bash scripts/tests/kmp-status-gate-test.sh

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
CHECKER="$ROOT/scripts/check-kmp-status.py"
GATE="$ROOT/scripts/kmp-status-precommit-gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
expect() {
  desc="$1"; got="$2"; want="$3"
  if [ "$got" != "$want" ]; then
    echo "FAIL: $desc — expected $want, got $got" >&2
    fail=1
  fi
}

KT_DIR="shared/engine/src/commonMain/kotlin/com/pastura/engine/Phases"

# Build a fixture repo. Args: <name> <board-file> <space-separated ported names>.
# The ledger carries 12 handlers (H01Handler..H12Handler) to clear the checker's
# MIN_HANDLERS floor; the board file is supplied by the caller so it can drift.
build_repo() {
  name="$1"; board_src="$2"; ported="$3"
  repo="$TMP/$name"
  mkdir -p "$repo/scripts" "$repo/docs" "$repo/shared" "$repo/$KT_DIR"
  cp "$CHECKER" "$repo/scripts/check-kmp-status.py"
  cp "$board_src" "$repo/docs/kmp-migration-status.md"
  {
    printf 'swift_path\tdisposition\tkotlin_target\n'
    i=1
    while [ "$i" -le 12 ]; do
      printf 'Pastura/Pastura/Engine/Phases/H%02dHandler.swift\tPORT\n' "$i"
      i=$((i + 1))
    done
  } > "$repo/shared/adr-023-port-ledger.tsv"
  for h in $ported; do
    printf 'class %s\n' "$h" > "$repo/$KT_DIR/$h.kt"
  done
  git init -q "$repo"
  (
    cd "$repo"
    git config user.email test@example.com
    git config user.name test
    git add -A
    git commit -qm fixture
    python3 scripts/check-kmp-status.py --check >/dev/null 2>&1
    echo "$?"
  )
}

# Board fixtures. `mkboard <file> <extra checklist lines...>` writes a board whose
# Wave B fence starts with H01..H04 ([x] H01/H02 ported, [ ] H03/H04) plus any
# extra rows, followed by [ ] H05..H12 so the ledger set is fully listed.
mkboard() {
  out="$1"; shift
  {
    printf '# fixture board\n\n'
    printf '<!-- kmp-status:wave-b:start -->\n'
    printf -- '- [x] H01Handler — #1\n'
    printf -- '- [x] H02Handler — #2\n'
    printf -- '- [ ] H03Handler\n'
    printf -- '- [ ] H04Handler\n'
    for extra in "$@"; do printf -- '%s\n' "$extra"; done
    i=5
    while [ "$i" -le 12 ]; do printf -- '- [ ] H%02dHandler\n' "$i"; i=$((i + 1)); done
    printf '<!-- kmp-status:wave-b:end -->\n'
  } > "$out"
}

# --- Part A: checker --check perturbations ---

# Consistent: H01/H02 ported and [x]; H03..H12 [ ] and not ported.
mkboard "$TMP/good.md"
expect "consistent board passes" "$(build_repo good "$TMP/good.md" "H01Handler H02Handler")" 0

# False tick: H03 [x] but not ported.
mkboard "$TMP/false_tick.md"
sed 's/- \[ \] H03Handler/- [x] H03Handler/' "$TMP/false_tick.md" > "$TMP/false_tick2.md"
expect "false tick fails" "$(build_repo false_tick "$TMP/false_tick2.md" "H01Handler H02Handler")" 1

# Un-flipped fresh port: H03 ported but row still [ ].
mkboard "$TMP/unflipped.md"
expect "un-flipped port fails" "$(build_repo unflipped "$TMP/unflipped.md" "H01Handler H02Handler H03Handler")" 1

# Missing row: drop H12 from the board (ledger still has it).
mkboard "$TMP/missing.md"
grep -v 'H12Handler' "$TMP/missing.md" > "$TMP/missing2.md"
expect "missing row fails" "$(build_repo missing "$TMP/missing2.md" "H01Handler H02Handler")" 1

# Orphan row: a board row naming no ledger handler.
mkboard "$TMP/orphan.md" "- [ ] GhostHandler"
expect "orphan row fails" "$(build_repo orphan "$TMP/orphan.md" "H01Handler H02Handler")" 1

# Stray ported .kt: a ported handler outside the ledger set.
mkboard "$TMP/stray.md"
expect "stray ported .kt fails" "$(build_repo stray "$TMP/stray.md" "H01Handler H02Handler StrayHandler")" 1

# Malformed fence: no start/end markers.
printf '# board\n- [x] H01Handler\n' > "$TMP/nofence.md"
expect "missing fence fails" "$(build_repo nofence "$TMP/nofence.md" "H01Handler H02Handler")" 1

# Floor guard negative control: a ledger below MIN_HANDLERS must fail on the floor
# regardless of the board. The board here lists exactly the 5-handler ledger (fully
# consistent), so the floor is the ONLY thing that can fail it — isolating the guard.
floor_case() {
  repo="$TMP/floor"
  mkdir -p "$repo/scripts" "$repo/docs" "$repo/shared" "$repo/$KT_DIR"
  cp "$CHECKER" "$repo/scripts/check-kmp-status.py"
  {
    printf 'swift_path\tdisposition\tkotlin_target\n'
    for i in 01 02 03 04 05; do
      printf 'Pastura/Pastura/Engine/Phases/H%sHandler.swift\tPORT\n' "$i"
    done
  } > "$repo/shared/adr-023-port-ledger.tsv"
  {
    printf '<!-- kmp-status:wave-b:start -->\n'
    printf -- '- [x] H01Handler\n- [x] H02Handler\n'
    printf -- '- [ ] H03Handler\n- [ ] H04Handler\n- [ ] H05Handler\n'
    printf '<!-- kmp-status:wave-b:end -->\n'
  } > "$repo/docs/kmp-migration-status.md"
  printf 'class H01Handler\n' > "$repo/$KT_DIR/H01Handler.kt"
  printf 'class H02Handler\n' > "$repo/$KT_DIR/H02Handler.kt"
  (
    cd "$repo"
    git init -q
    git config user.email test@example.com
    git config user.name test
    git add -A
    git commit -qm fixture
    err="$(python3 scripts/check-kmp-status.py --check 2>&1 >/dev/null)"
    code=$?
    printf '%s|%s' "$code" "$err"
  )
}
floor_res="$(floor_case)"
expect "sub-floor ledger exits 1" "${floor_res%%|*}" 1
case "${floor_res#*|}" in
  *"handler(s) parsed from the ledger"*) : ;;
  *) echo "FAIL: sub-floor did not emit the floor diagnostic — got: ${floor_res#*|}" >&2; fail=1 ;;
esac

# --- Part B: wrapper trigger decision (python3 stub) ---

STUB_BIN="$TMP/bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/python3" <<'STUB'
#!/usr/bin/env bash
touch "$KMP_GATE_MARKER"
exit 0
STUB
chmod +x "$STUB_BIN/python3"

run_trigger() {
  repo="$TMP/trig_$1"; staged="$2"; marker="$TMP/trig_$1.marker"
  git init -q "$repo"
  (
    cd "$repo"
    git config user.email test@example.com
    git config user.name test
    mkdir -p "$(dirname "$staged")"
    : > "$staged"
    git add -f "$staged"
    KMP_GATE_MARKER="$marker" PATH="$STUB_BIN:$PATH" bash "$GATE" >/dev/null 2>&1
  )
  if [ -f "$marker" ]; then echo "fired"; else echo "skipped"; fi
}

expect "board fires" "$(run_trigger board docs/kmp-migration-status.md)" fired
expect "ledger fires" "$(run_trigger ledger shared/adr-023-port-ledger.tsv)" fired
expect "ported kt fires" "$(run_trigger kt "$KT_DIR/AssignHandler.kt")" fired
expect "checker fires" "$(run_trigger checker scripts/check-kmp-status.py)" fired
expect "unrelated doc skips" "$(run_trigger doc docs/ROADMAP.md)" skipped
expect "unrelated swift skips" "$(run_trigger swift Pastura/Pastura/Engine/Foo.swift)" skipped

if [ "$fail" -eq 0 ]; then
  echo "kmp-status-gate: all cases passed"
else
  echo "kmp-status-gate: FAILURES" >&2
  exit 1
fi

#!/usr/bin/env python3
"""Publish the scenario-factory nightly digest to a rolling Draft PR.

The factory's digest (`data/factory/digest.md`) is the cycle's only
repo-visible artifact, but `main` is push-protected (PR-only) — committing it
to `main` directly would diverge the local checkout from `origin/main` and
break `git pull --ff-only`. So the nightly Routine routes the digest through a
rolling `factory/digest-<YYYYMMDD>` branch with one open Draft PR; the human
merges that PR periodically. `main` is reached only via that merge.

Two subcommands, run in the dedicated worktree around `/scenario-factory`:

  prepare  — pick (or create) the rolling branch BEFORE the digest is written,
             fast-forwarding it to the remote tip so dedup reads the latest.
  publish  — commit the digest, push, and ensure a Draft PR exists. Idempotent;
             a no-op when the factory produced no digest change.

CONTAINMENT (load-bearing — read before editing the guards):
This script runs git/gh via `subprocess`, so the PreToolUse
`block-force-push-and-pr-ready.sh` hook — which only inspects Bash *tool*
calls — does NOT fire here. The in-script guards below are therefore the
SOLE protection, not defense-in-depth. Do not weaken them assuming the hook
still backstops: every push goes through `_git_push()`, which hardcodes the
safe shape (`git push -u origin <branch>`, never `--force`/`-f`/`+`, never
`main`) and validates the branch against `BRANCH_RE`. `publish` also gates on
`BRANCH_RE` before any commit/push, and only ever `git add`s the digest path.
Encapsulation is acceptable here only because factory's injection surface is
low (it generates its own scenarios; nothing external feeds the push decision).
"""

import argparse
import datetime
import json
import re
import subprocess
import sys

# Anchored to the exact dated form — rejects `main`, `factory/digest` (no
# date), and any non-8-digit suffix. Used identically for PR-matching and the
# commit/push guard so a stray `factory/digest-foo` can never be operated on.
BRANCH_RE = re.compile(r"^factory/digest-\d{8}$")
DIGEST_PATH = "data/factory/digest.md"
BASE = "main"
REMOTE = "origin"
PR_BODY = (
    "Rolling nightly digest from `/scenario-factory` (Model B). Each night "
    "appends one `## <date>` section to `data/factory/digest.md`; merge "
    "whenever convenient — after a merge the next cycle opens a fresh PR. "
    "Machine-generated; never touches `main` directly."
)


def _run(args, *, capture=False):
    """Run a checked git/gh command, raising SystemExit on nonzero.

    Never use for `git push` — pushes must go through `_git_push()`, which
    validates the target. Enforced with an explicit raise (not `assert`, so
    it survives `python3 -O`) since this is a containment guard.
    """
    if args[:2] == ["git", "push"]:
        raise SystemExit("internal error: pushes must go through _git_push()")
    proc = subprocess.run(args, capture_output=True, text=True)
    if proc.returncode != 0:
        raise SystemExit(
            f"command failed ({proc.returncode}): {' '.join(args)}\n"
            f"{proc.stderr.strip()}"
        )
    return proc.stdout.strip() if capture else None


def _ok(args):
    """True iff the command exits 0 (for boolean probes; no raise)."""
    return subprocess.run(args, capture_output=True).returncode == 0


def _git_push(branch):
    """The ONLY push site. Hardcodes the safe shape; validates the branch.

    See the module CONTAINMENT note: this is the sole guard against a bad
    push, since the block-force-push hook does not see subprocess git.
    """
    if not BRANCH_RE.match(branch) or branch == BASE:
        raise SystemExit(f"refusing to push non-factory branch: {branch!r}")
    # Fixed shape — no --force / -f / + refspec is constructible from here.
    proc = subprocess.run(
        ["git", "push", "-u", REMOTE, branch], capture_output=True, text=True
    )
    if proc.returncode != 0:
        raise SystemExit(f"git push failed: {proc.stderr.strip()}")


def _current_branch():
    return _run(["git", "rev-parse", "--abbrev-ref", "HEAD"], capture=True)


def _open_factory_prs():
    """Open PRs whose head is a dated factory branch, ANY draft state.

    Draft-agnostic on purpose: a human flipping the rolling PR to
    ready-for-review (a natural pre-merge step) must not make prepare blind to
    it and cut a second branch (single-writer violation).
    """
    out = _run(
        ["gh", "pr", "list", "--state", "open", "--limit", "100",
         "--json", "number,headRefName,url,isDraft"],
        capture=True,
    )
    prs = json.loads(out) if out else []
    return [p for p in prs if BRANCH_RE.match(p.get("headRefName", ""))]


def cmd_prepare():
    # A dirty tree means a prior run died mid-cycle; abort rather than
    # contaminate the branch (mirrors queue-consumer Step 0.5).
    dirty = _run(["git", "status", "--porcelain"], capture=True)
    if dirty:
        raise SystemExit(
            "working tree not clean — a prior cycle may have died mid-run; "
            f"resolve before continuing:\n{dirty}"
        )
    _run(["git", "fetch", REMOTE])
    matches = _open_factory_prs()
    if len(matches) > 1:
        names = ", ".join(p["headRefName"] for p in matches)
        raise SystemExit(
            "single-writer violation: multiple open factory digest PRs "
            f"({names}); merge or close all but one before the next cycle."
        )
    if len(matches) == 1:
        branch = matches[0]["headRefName"]
        _run(["git", "fetch", REMOTE, branch])
        _run(["git", "switch", branch])
        # Fast-forward to the remote tip so /scenario-factory's dedup (Step 1)
        # reads the latest pushed digest. --ff-only fails loudly on divergence,
        # which is exactly the signal we want (single-writer invariant broken).
        _run(["git", "merge", "--ff-only", f"{REMOTE}/{branch}"])
        print(branch)
        return
    # No open factory PR. If the current branch is a factory branch with
    # commits NOT yet in origin/main, a prior publish committed but failed to
    # push/PR — recover it rather than silently dropping that night's digest.
    cur = _current_branch()
    if BRANCH_RE.match(cur) and not _ok(
        ["git", "merge-base", "--is-ancestor", "HEAD", f"{REMOTE}/{BASE}"]
    ):
        print(f"recovering orphaned unpushed commit on {cur}", file=sys.stderr)
        print(cur)
        return
    # Fresh cycle off the just-fetched base.
    today = datetime.date.today().strftime("%Y%m%d")
    branch = f"factory/digest-{today}"
    created = subprocess.run(
        ["git", "switch", "-c", branch, f"{REMOTE}/{BASE}"],
        capture_output=True, text=True,
    )
    if created.returncode != 0:
        # Same-day re-cut (a prior same-date branch was already merged): reuse
        # it, fast-forwarded onto the new base.
        _run(["git", "switch", branch])
        _run(["git", "merge", "--ff-only", f"{REMOTE}/{BASE}"])
    print(branch)


def cmd_publish():
    branch = _current_branch()
    if not BRANCH_RE.match(branch):
        raise SystemExit(
            f"refusing to publish from {branch!r} — not a "
            "factory/digest-<date> branch (run prepare first)"
        )
    if _run(["git", "status", "--porcelain", "--", DIGEST_PATH], capture=True):
        _run(["git", "add", DIGEST_PATH])  # only the digest — never -A
        # Date from the branch (cycle-start), not today: a recovered orphan
        # publishes under its original cycle date. The digest section itself
        # is dated independently by append_digest.py.
        date = branch.rsplit("-", 1)[-1]
        _run(["git", "commit", "-m",
              f"📝 chore: scenario-factory nightly digest ({date})"])
    # Publish only if the branch carries a digest commit beyond the base. A
    # fresh branch with no digest change (factory produced nothing) is a no-op
    # — never open an empty PR.
    if not _run(["git", "rev-list", f"{REMOTE}/{BASE}..HEAD"], capture=True):
        print("no new digest — nothing to publish")
        return
    _git_push(branch)
    if _open_pr_for(branch):
        print(f"updated rolling digest PR for {branch}")
    else:
        _run(["gh", "pr", "create", "--draft", "--base", BASE, "--head", branch,
              "--title", f"📝 chore: scenario-factory rolling digest ({branch})",
              "--body", PR_BODY])
        print(f"opened rolling digest Draft PR for {branch}")


def _open_pr_for(branch):
    out = _run(
        ["gh", "pr", "list", "--head", branch, "--state", "open", "--json",
         "number"],
        capture=True,
    )
    return bool(json.loads(out) if out else [])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["prepare", "publish"])
    args = parser.parse_args()
    if args.command == "prepare":
        cmd_prepare()
    else:
        cmd_publish()


if __name__ == "__main__":
    main()

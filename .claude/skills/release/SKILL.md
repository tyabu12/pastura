---
name: release
description: Cut a Pastura TestFlight release — guide the semver bump, synthesize and review the "What to Test" notes, run the preflight dry-run, then drive scripts/release.sh through a confirmation gate to archive, upload, and tag. Use when the user asks to cut/ship a release, upload a build to TestFlight, or run the release pipeline.
allowed-tools: Read, Grep, Glob, Bash
argument-hint: "[X.Y.Z]"
---

# /release

Drive one TestFlight release of Pastura. This skill is the **interactive
judgment layer** over the deterministic mechanism in
`scripts/release.sh` (ADR-014). The script owns preflight → archive →
symbol check → export → upload → tag; this skill owns the human
decisions around it: the semver bump, the release notes, and the
**mandatory confirmation before the irreversible upload**.

> **Not an `/orchestrate` task.** `/release` drives an *external*
> release (App Store Connect), not repo file edits. It does not create
> branches or commit tracked files. The one push it triggers — the
> annotated release tag, inside `scripts/release.sh` — is a deliberate,
> benign exception to the "`/orchestrate` is the only entry point for
> pushes" rule (see CLAUDE.md § Development Workflow): a tag ref is not
> branch-protected, touches no tracked files, and is gated behind the
> confirmation below. Any *code* change a release needs (a version
> bump) is a separate `/orchestrate` PR — see Step 2.

Run from the repository root.

## One-time bootstrap (must be done before the first release)

These are human-only, performed once (ADR-014 § bootstrap). The full
step-by-step walkthrough is [`docs/release-setup.md`](../../../docs/release-setup.md);
verify the checklist below holds before starting:

- App Store Connect **app record** exists for `app.pastura.Pastura`.
- An ASC **API key** (`.p8`) is generated and stored outside the repo
  (fastlane reads `~/.appstoreconnect/private_keys/`). Its identifiers
  live in **`fastlane/.env`** (gitignored, project-scoped — fastlane
  auto-loads it via dotenv; do NOT export them in `~/.zshrc`):
  `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`. Copy from
  `fastlane/.env.example`.
- An **Apple ID signed into Xcode** whose account can sign for
  distribution (automatic signing, team `52G26234A3`). Distribution
  signing is cloud-managed — no local distribution cert is needed;
  `release.sh` passes `-allowProvisioningUpdates` to resolve the App
  Store profile + cloud cert via that session.
- `bundle install` has been run once so `Gemfile.lock` pins fastlane.

Confirm with the operator that these hold before continuing. The
encryption export-compliance declaration is already in place
(`INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`, ADR-005 §8.6) — no
action needed.

## Step 1 — Decide the version

Read the commits since the last release tag and propose a semver bump:

```bash
LAST_TAG="$(git describe --tags --abbrev=0 2>/dev/null || echo '(none)')"
git log --pretty='- %s' "${LAST_TAG}..HEAD" 2>/dev/null || git log --pretty='- %s' -n 20
```

Propose **major / minor / patch** from the change content (breaking →
major, new feature → minor, fixes only → patch) and **ask the operator
to confirm** the target `X.Y.Z`. If `$ARGUMENTS` already carries a
version, treat it as the proposal and still confirm.

## Step 2 — Ensure the version is on a green `main` (sequencing)

`scripts/release.sh` releases only from a checkout that equals
`origin/main` and is CI-green, and it asserts the **archived**
`MARKETING_VERSION` equals `--version`. So the target version must
already be the `MARKETING_VERSION` on `main`.

- **If the chosen version already matches `main`'s `MARKETING_VERSION`**
  (a re-release or notes/build-only change): proceed to Step 3.
- **If the version needs to change**: it is a code edit — bump it in a
  **separate `/orchestrate` PR**, merge it, and wait for `main` CI to go
  green, *then* return here. Bump **only the app target's two
  `MARKETING_VERSION` entries** (Debug + Release, the ones near
  `PRODUCT_BUNDLE_IDENTIFIER = app.pastura.Pastura`) — not the
  `PasturaTests` / `PasturaUITests` entries. The build number
  (`git rev-list --count HEAD`) advances automatically with the bump
  commit, so the release.sh build-number guard is satisfied for free.

Do **not** try to bump and release in one local step — a local bump
commit would make `HEAD` diverge from `origin/main` and fail preflight.

## Step 3 — Synthesize and review the release notes

Turn the commit subjects (Step 1) into concise **tester-facing "What to
Test"** prose. These notes are published to TestFlight testers, so:

- **Keep only tester-facing changes** — new features and user-visible
  fixes. Drop internal-only commits entirely: refactors, chores, docs,
  tests, CI, tooling. A build of only internal work gets a single
  "internal improvements" line, not a padded list.
- **Drop all PR/issue numbers, SHAs, and emoji prefixes** — those live in
  git history / a GitHub Release, not tester notes.
- **Write plainly** — no marketing adjectives, no effusive openers /
  closers, no AI-tell rhythms (rule-of-three triads, em-dash pile-ups).
  State what changed and what to check, like a short developer note to a
  peer.

The **first** build is the exception: with no prior release to diff, write
a brief app intro + what to test rather than a changelog.

**The operator must review the final notes at the gate (Step 5)** — they
go to humans and are not content-safety-screened. Never ship raw commit
subjects unreviewed (a subject can carry a token, internal URL, or
unpolished text).

Write the finalized notes to a temp file so `release.sh` ships them
verbatim as the TestFlight changelog:

```bash
NOTES_FILE="$(mktemp -t pastura-release-notes)"
cat > "$NOTES_FILE" <<'NOTES'
<the reviewed tester-facing prose from above>
NOTES
```

Pass `--notes-file "$NOTES_FILE"` to `release.sh` in Steps 4 and 6.
**Without it**, the script falls back to raw commit subjects
(`build_notes`) — exactly what this step exists to prevent — so always
pass the file once notes are prepared. A given-but-empty/missing file is a
hard error, so the fallback never fires silently mid-release.

## Step 4 — Dry-run the preflight

```bash
scripts/release.sh --version X.Y.Z --notes-file "$NOTES_FILE" --dry-run
```

This runs the full preflight (HEAD == origin/main, every required check
green — the required list is derived from the branch ruleset) and prints
the planned version / build / tag plus a **"What to Test" preview** — with
`--notes-file` that preview is your reviewed prose, so a missing/empty
notes file fails here (fail-fast) rather than mid-upload, and the Step 5
gate reviews the exact text that will ship. It then stops before any
archive or upload. Resolve any preflight failure (usually: `main` not
green yet, or HEAD not synced) before continuing. `scripts/release.sh` is not in the
permission allowlist, so the first invocation prompts for approval — that
prompt is itself a safety gate for an irreversible action.

## Step 5 — Confirmation gate (MANDATORY)

Before the real run, present to the operator and get explicit approval:

- target **version** and computed **build number** and **tag**
- the final **"What to Test" notes** (Step 3) for sign-off
- confirmation that the one-time bootstrap holds (env vars set, key in
  place)

Only on explicit "yes" proceed. This is the last reversible point — the
upload that follows cannot be undone.

## Step 6 — Release

```bash
scripts/release.sh --version X.Y.Z --notes-file "$NOTES_FILE"
```

The script archives, re-checks the ADR-005 §8.5 Ollama-symbol guard on
the signed binary, exports an `app-store` `.ipa`, uploads via fastlane
(waiting for ASC processing), and — only on a successful upload —
creates and pushes the annotated tag `vX.Y.Z+<build>`. Report the result
and that the build is processing on TestFlight.

## Step 7 — Promote to a public GitHub Release (at App Store publish)

> **Optional and decoupled — NOT part of the per-build flow above.** Steps
> 1–6 cut one *TestFlight* build and tag it; this step is run separately,
> by hand, and only when a version actually ships publicly. Do not wire it
> into `scripts/release.sh` — most TestFlight builds never go public, so a
> Release per build would be pre-release clutter.
>
> **Not yet exercised.** This procedure is defined ahead of Pastura's first
> App Store publish — a Phase 3 event (ADR-014's scope covers TestFlight
> upload only). It becomes live once a build is actually approved; until
> then it is documentation, not an expected per-version deliverable.

**Trigger:** a build has been **approved and released on the App Store** (an
App Store Connect–side event this repo does not observe). Each `/release`
run already tagged its build `vX.Y.Z+<build>`; this step attaches a *public*
GitHub Release to the tag of the build that went live — titled `Pastura
X.Y.Z` (the public marketing version, no build suffix), marked `--latest`,
never a pre-release.

**Changelog source.** The GitHub Release carries the developer-facing
changelog — merged PRs, contributor handles, issue numbers — deliberately
kept *out* of the tester-facing "What to Test" notes (Step 3). Its base is
the **previous public release**: because public releases are the only
GitHub Releases in this design, `gh release list` returns them directly, so
"previous GitHub Release" == "previous public release" automatically even
though many TestFlight tags sit in between. Pass `--exclude-drafts` so a
leftover draft from an aborted run (below) cannot become the base.

**Recipe — draft first, review, then publish.** The draft is both a
body-assembly mechanism (so the hand-written intro lands *above* the
auto-generated "What's Changed") and a review pause — a public Release is
notified to watchers and indexed, so it inherits this skill's
confirmation-gate discipline (Step 5): never flip `--draft=false` on an
unreviewed auto-changelog.

```bash
TAG="vX.Y.Z+<build>"                       # the approved build's tag
PREV=$(gh release list --exclude-drafts --limit 1 --json tagName -q '.[0].tagName')

# 1. Create as a DRAFT with the auto-generated changelog. Build the
#    optional flag as an array — an unquoted ${PREV:+--notes-start-tag …}
#    is NOT word-split under zsh (the default macOS shell) and would
#    collapse into one bad argument that gh rejects.
notes_args=()
[ -n "$PREV" ] && notes_args=(--notes-start-tag "$PREV")
gh release create "$TAG" --title "Pastura X.Y.Z" --latest --draft \
  --generate-notes "${notes_args[@]}"

# 2. Prepend a hand-written 2–3 line intro (the release headline) above
#    the generated "What's Changed". (gh resolves a draft by tag via a
#    list-and-match fallback, so view/edit by "$TAG" work here — confirm
#    on the first live run, since this flow is not yet exercised.)
BODY="$(mktemp)"
{ printf '%s\n\n' "<hand-written 2–3 line intro>"; \
  gh release view "$TAG" --json body -q '.body'; } > "$BODY"
gh release edit "$TAG" --notes-file "$BODY"

# 3. Review the draft in the GitHub UI (Releases → the draft). Only once
#    the intro + generated changelog read correctly:
gh release edit "$TAG" --latest --draft=false
rm -f "$BODY"
```

**First public release** (no prior Release exists): `--generate-notes` would
otherwise pick the most recent *git tag* as its base and truncate the log to
one build's worth of commits. Instead **drop `--generate-notes`** and
hand-write the whole body — a short app intro + notable first-release
capabilities (mirroring the Step 3 first-build guidance) — passing it via
`--notes-file` at create time. `PREV` is empty, so no base tag is involved.

**Aborted run:** if the flow dies between create and publish, a draft
Release lingers (and `gh release list` without `--exclude-drafts` would see
it). Delete it before re-running: `gh release delete "$TAG" --yes` (no
`--cleanup-tag` — the git tag from `release.sh` must survive).

## Failure → recovery

Map the failure point to the recovery — the build number is commit-derived,
so the right move differs by *where* it failed:

| Failure point | State | Recovery |
|---|---|---|
| preflight / archive / export / **upload before ASC ingest** | nothing ingested, no tag (tag is last) | fix the cause and re-run `/release` — the build number is unchanged and that is fine |
| **upload fails after ASC has ingested the build** | the build number now collides with an ingested build; a naive re-run is **correctly blocked** by release.sh's strict-exceeds guard | land a **new commit on `main`** (a no-op commit or a `MARKETING_VERSION` patch bump) via `/orchestrate`, wait for green, then re-`/release`. This is a new green-main cycle, not an in-place retry — the build number must advance |
| **tag pushed but the release must be retracted** | tag exists locally + remotely | `git tag -d vX.Y.Z+<build>` and `git push origin :refs/tags/vX.Y.Z+<build>` |
| **public GitHub Release (Step 7) published then must be retracted** | Release is public; git tag is fine | `gh release delete vX.Y.Z+<build> --yes` (no `--cleanup-tag` — keep the tag). Re-cutting can re-promote it |

## ASC API key revocation (leak response)

If the `.p8` API key is ever exposed (committed, shared, lost): revoke it
immediately in **App Store Connect → Users and Access → Integrations →
App Store Connect API → (select the key) → Revoke**, then generate a
fresh key and update `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_PATH`. The
`scripts/p8-precommit-gate.sh` gate and the `*.p8` gitignore are the
preventative layers (ADR-014 § Secrets); revocation is the response.

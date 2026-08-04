---
name: release
description: Cut a Pastura release — version bump, TestFlight and App Store release notes, then a gated scripts/release.sh archive/upload/tag. Use when asked to cut or ship a release, upload a build to TestFlight, or run the release pipeline.
allowed-tools: Read, Grep, Glob, Bash, Write, Agent
argument-hint: "[X.Y]"
---

# /release

Drive one TestFlight release of Pastura. This skill is the **interactive
judgment layer** over the deterministic mechanism in
`scripts/release.sh` (ADR-014). The script owns preflight → archive →
symbol check → export → upload → tag; this skill owns the human
decisions around it: the version bump, the release notes, and the
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

Read the commits since the last release tag and propose a version bump:

```bash
LAST_TAG="$(git describe --tags --abbrev=0 2>/dev/null || echo '(none)')"
git log --pretty='- %s' "${LAST_TAG}..HEAD" 2>/dev/null || git log --pretty='- %s' -n 20
```

Propose **major / minor** from the change content (breaking → major,
anything else → minor) and **ask the operator to confirm** the target
`X.Y`. If `$ARGUMENTS` already carries a version, treat it as the
proposal and still confirm. The Steps 4 and 6 commands run in **later,
separate Bash tool calls** that inherit no shell state from here, so every
value they carry must be **substituted concretely — never left as a shell
variable that would expand empty in the later call**. This covers the
version *and* the `--notes-file` path (produced and echoed in Step 3): write
the confirmed `X.Y`, and substitute Step 3's echoed path, in place of the
`X.Y` and `/REPLACE-WITH-NOTES-PATH` placeholders those commands show. Both
placeholders are values `release.sh` rejects when left unsubstituted — `X.Y`
fails the version validator (it does not start with a digit), and
`/REPLACE-WITH-NOTES-PATH` fails the `--notes-file` existence check — so an
unsubstituted value dies fast — the version at argument validation, and (once
the version is substituted) the path at the Step 4 dry-run — instead of
binding a plausible wrong value and surfacing it only after the archive, past
the Step 5 gate.

**Two components is the shape** (`ADR-014` § Decision, item 4). Pastura
ships `1.0`, `1.1`, … so a **fixes-only release is still a minor bump**
(`1.1` → `1.2`), not a third component. Reserve `X.Y.Z` for a hotfix on a
version already published to the App Store: `release.sh` accepts either
shape, but a normal release never carries a third component.

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

### Three cuts before writing

Apply in order. Each carries a mechanical check — **run it**; do not reason
from the commit log alone. Every cut below exists because a plausible-sounding
claim failed its check.

**Cut 1 — by what the update delivers, not by where the file lives.** The
question is "can the user do something now that they could not before?", not
"is the file in the app bundle". Gallery scenarios (`docs/gallery/`) are
fetched at runtime by `URLSessionGalleryService`, so any that already ran on
the previous version reached users *without* this update — leave them out.

The exception is gallery content the previous version **gated** (ADR-020
`EngineSchemaVersion.isCompatible`: D2 rejects an unknown phase kind, D3
rejects `min_engine_version > current`). That does arrive with the update, so
name the scenarios. **Compute the set — never assume it is non-empty:**

```bash
LAST_TAG="$(git describe --tags --abbrev=0)"; [ -n "$LAST_TAG" ] || exit 1
OLD="$(git show "$LAST_TAG":Pastura/Pastura/Models/PhaseType.swift)"
jq -r '[.. |objects|select(has("phases")).phases[]]|unique[]' docs/gallery/gallery.json |
  while read -r p; do
    printf '%s' "$OLD" | grep -qE "\"${p}\"|case ${p}$" || echo "D2 gated: $p"
  done
jq '[.. |objects|select(has("min_engine_version")).min_engine_version]' docs/gallery/gallery.json
```

Both details are load-bearing and both fail silently toward "nothing gated":
re-derive `LAST_TAG` here (Bash calls share no shell state, and an empty one
makes `git show :path` read the *index* and exit 0), and match **raw values**,
not case identifiers (`case speakAll = "speak_all"`).

No `D2 gated:` line **and** an empty array ⇒ nothing was gated ⇒ **write no
unlock line at all**; a raised `ENGINE_SCHEMA_VERSION` alone gates nothing.
When one *is* earned, name the scenarios, keep mechanism words out, and echo
what the app showed:
「このシナリオの実行にはより新しいバージョンの Pastura が必要です。アプリを更新してください。」

**Cut 2 — advertise only capabilities a shipped scenario exercises.** A new
engine capability no bundled preset uses is an *authoring* feature; a player
cannot encounter it, so listing it as a headline feature promises nothing.
Substitute a real key before reading the result — an unsubstituted run returns
zero hits, i.e. the suppressing answer:

```bash
CAP='secret:'   # ← replace per capability; a placeholder yields a false "not shipped"
grep -l "$CAP" Pastura/Pastura/Resources/Presets/*.yaml
```

No hits ⇒ it belongs on an editor/author line, or nowhere.

**Cut 3 — by likelihood of encounter.** Itemize fixes a tester could plausibly
hit or should re-check; fold the rest — unusual configuration, malformed input,
internal-consistency repairs — into a single "other minor fixes" line.

**Use the app's own wording.** Feature and phase names must match the ja values
in `Localizable.xcstrings`, not internal identifiers: `whisper` is 密談,
`narrate` is 実況. "ラン" is developer vocabulary — the UI says 実行 /
シミュレーション.

### Two surfaces, two texts

`--notes-file` reaches **TestFlight only** (see the `--notes-file` paragraph
below). The App Store "What's New" is a separate App Store Connect field,
entered by hand **per locale** — Pastura ships **ja + en-US** — in App Store
Connect when the build is submitted. No step of this skill performs that
submission; the text is signed off at the Step 5 gate below, and
`release.sh` never touches it. Write both from one shared body:
TestFlight adds internal-behaviour detail and a "確認してほしいこと" list covering
every new feature group; the App Store text drops both, since to a general user
they read as instructions, or as defect reports. **Both texts go to the Step 5
gate** — the App Store one is the copy that reaches the public.

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
echo "$NOTES_FILE"   # ← the concrete path; substitute it into Steps 4 and 6
```

Binding and reading `$NOTES_FILE` **within this single tool call** is fine —
the no-shell-state rule (Step 1) is about *later, separate* calls, so the
path must be carried into Steps 4 and 6 by substituting the echoed value, not
by reusing the variable.

Pass `--notes-file` with the echoed path to `release.sh` in Steps 4 and 6 —
substitute that concrete path in place of the `/REPLACE-WITH-NOTES-PATH`
placeholder those commands show (per Step 1).
**Without `--notes-file`**, the script falls back to raw commit subjects
(`build_notes`) — exactly what this step exists to prevent — so always pass
the file once notes are prepared. A given `--notes-file` path that is missing
or points to an empty file is a hard error, so that fallback never fires
silently once a real path is passed. The one gap it does **not** cover is an
*empty path string*: `--notes-file ""` reads to `release.sh` as "flag never
passed" and takes the silent fallback — which is exactly why Steps 4/6 carry a
guaranteed-nonexistent literal placeholder, not a bare `$NOTES_FILE` that would
expand empty in those later calls.

## Step 4 — Dry-run the preflight

```bash
scripts/release.sh --version X.Y --notes-file /REPLACE-WITH-NOTES-PATH --dry-run
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
- the final **App Store "What's New" text, per locale** (Step 3), if this
  version is headed for submission — it is the only public-facing copy the
  skill produces, and no later step gates it
- confirmation that the one-time bootstrap holds (env vars set, key in
  place)

Only on explicit "yes" proceed. This is the last reversible point — the
upload that follows cannot be undone.

## Step 6 — Release

```bash
scripts/release.sh --version X.Y --notes-file /REPLACE-WITH-NOTES-PATH
```

The script archives, re-checks the ADR-005 §8.5 Ollama-symbol guard on
the signed binary, exports an `app-store` `.ipa`, uploads via fastlane
(waiting for ASC processing), and — only on a successful upload —
creates and pushes the annotated tag `v<version>+<build>`. Report the result
and that the build is processing on TestFlight.

## Step 7 — Promote to a public GitHub Release (at App Store publish)

> **Optional and decoupled — NOT part of the per-build flow above.** Steps
> 1–6 cut one *TestFlight* build and tag it; this step is run separately,
> by hand, and only when a version actually ships publicly. Do not wire it
> into `scripts/release.sh` — most TestFlight builds never go public, so a
> Release per build would be pre-release clutter.
>
> **Exercised twice** — `v1.0+522` and `v1.1+671`. ADR-014's scope still
> covers TestFlight upload only, so nothing here is automated; read the two
> published bodies as the reference shape before writing a third.

**Trigger:** a build has been **approved and released on the App Store** (an
App Store Connect–side event this repo does not observe). Each `/release`
run already tagged its build `v<version>+<build>`; this step attaches a *public*
GitHub Release to the tag of the build that went live — titled `Pastura
<version>` (the public marketing version, no build suffix), marked `--latest`,
never a pre-release.

### What the body is

**A curated, user-facing highlights document — not a changelog.** The
`--generate-notes` PR list is **material the author reads, never text that
gets published**: for 1.1 it ran to 149 lines of commit subjects, which no
one reads. Nothing of it survives into the body except the facts you rewrite
by hand; the `## What's Changed` list is not kept at all, because the
`**Full Changelog**` compare link already reaches every PR.

Its base is the **previous public release**: because public releases are the
only GitHub Releases in this design, `gh release list` returns them directly,
so "previous GitHub Release" == "previous public release" automatically even
though many TestFlight tags sit in between. Pass `--exclude-drafts` so a
leftover draft from an aborted run (below) cannot become the base.

### Body structure

In this order. Omit a section that has no qualifying items — a fixes-only
release carries no `## Features`, and vice versa.

1. **Opening line**, italic. One or two sentences, written fresh for this
   release (see below).
2. `This is the X.Y release of Pastura, <one clause placing it>.` followed by
   a short factual summary paragraph naming the two or three things the
   release is actually about. For a hotfix `X.Y.Z`, say what it fixes instead
   of placing it in the sequence.
3. `## Features`
4. `## Fixes`
5. `**Full Changelog**: https://github.com/<owner>/<repo>/compare/<PREV>...<TAG>`
6. `## Get it` — fixed boilerplate, unchanged every release (the App Store URL
   is the one in `README.md`):
   ```markdown
   - Download on the App Store: https://apps.apple.com/app/pastura-local-llms-simulator/id6788409688
   - Product story, design, and FAQ: https://pastura.app
   - Source and docs: this repository's [README.md](./README.md).
   ```
7. **Closing line**, italic. Written fresh, same as the opener.

**Bullet format** inside a section:

```markdown
- **Bold lead:** One or two factual sentences. (#1070, #1078, #1081)
```

The bold lead names the thing itself (`` `narrate` phase ``), not a headline
about it. Order bullets by impact **within** the section — what a user touches
first, then correctness, then the rest. Fold every low-impact item into a
single trailing `- **Smaller fixes:**` bullet carrying their numbers, rather
than giving each its own line.

### What goes in

**Only what reached users.** Work merged but not wired into the shipping app —
an in-progress port, an evaluated-but-unshipped backend spike — is invisible
to every reader of this page and is omitted entirely, along with docs, chore,
CI and dependency commits. This is Step 3's **Cut 1** (judge by what the
update delivers, not by where the file lives) applied to this surface.

Inheritance from Step 3 is partial — name it exactly:

| Step 3 rule | Applies here? |
|---|---|
| **Write plainly** (no marketing adjectives, no effusive openers/closers, no AI-tell rhythms) | **Yes** — and it is the rule most easily lost. The sole exception is the two authored lines below. |
| **Cut 1** — by what the update delivers | **Yes**, as above. |
| **Cut 3** — fold by likelihood of encounter | **Yes** — it is what the trailing "Smaller fixes" bullet implements. |
| **Drop all PR/issue numbers** | **No.** That rule exists because tester notes are not a changelog; here the numbers are the point. |

Verify a claim before writing it, the same as Step 3's cuts: a bullet
paraphrasing a commit subject is a claim about behaviour, and a subject can be
shorthand for something narrower.

### The two authored lines

They carry the release's voice; the body between them is deliberately flat.
Both are **written fresh each release** — no line is reused, including 1.0's
tagline, which belongs to 1.0. Set both in italics so they read as distinct
from the factual body.

Because they matter out of proportion to their length, **delegate them to a
Fable subagent**. Per the operator's global rules a Fable spawn needs explicit
approval, so ask first; if the operator declines, draft them in-session and say
so at the draft review so they can be rewritten. Give the subagent the finished
body plus the previous releases' opening and closing lines as **voice
reference**, and withhold your own candidates so its output stays independent.
Ask for several options of each rather than one.

### Recipe — draft, review, publish

The draft is the review pause. A public Release notifies watchers and is
indexed, so it inherits this skill's confirmation-gate discipline (Step 5):
the operator reviews the **rendered** draft — links and emphasis included —
and only then is it published.

```bash
OWNER_REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner')
TAG="v<version>+<build>"                   # the approved build's tag
PREV=$(gh release list --exclude-drafts --limit 1 --json tagName -q '.[0].tagName')

# 1. Material only. Read-only — creates nothing, so there is no throwaway
#    draft to clean up if you stop here.
gh api -X POST "repos/${OWNER_REPO}/releases/generate-notes" \
  -f tag_name="$TAG" -f previous_tag_name="$PREV" --jq '.body'

# 2. Write the body per the structure above with the Write tool (not an
#    inline heredoc — CLAUDE.md § Git Conventions), then create the DRAFT
#    from it. gh resolves a draft by tag for later view/edit even though
#    its URL shows `untagged-…` (confirmed on the 1.1 run).
BODY="<path you wrote the body to>"
gh release create "$TAG" --title "Pastura <version>" --latest --draft \
  --notes-file "$BODY"

# 3. Operator reviews the rendered draft in the GitHub UI. Only then:
gh release edit "$TAG" --latest --draft=false
```

To confirm the publish landed, read `gh api "repos/${OWNER_REPO}/releases/latest"
--jq '.tag_name'` — `gh release view --json isLatest` is not a field and fails.

`PREV` is non-empty from 1.1 onward, so `previous_tag_name` always has a base;
1.0 was hand-written with no prior release and is not a case that recurs.

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
| **upload fails after ASC has ingested the build** | the build number now collides with an ingested build; a naive re-run is **correctly blocked** by release.sh's strict-exceeds guard | land a **new commit on `main`** (a no-op commit or a `MARKETING_VERSION` bump) via `/orchestrate`, wait for green, then re-`/release`. This is a new green-main cycle, not an in-place retry — the build number must advance |
| **tag pushed but the release must be retracted** | tag exists locally + remotely | `git tag -d v<version>+<build>` and `git push origin :refs/tags/v<version>+<build>` |
| **public GitHub Release (Step 7) published then must be retracted** | Release is public; git tag is fine | `gh release delete v<version>+<build> --yes` (no `--cleanup-tag` — keep the tag). Re-cutting can re-promote it |

## ASC API key revocation (leak response)

If the `.p8` API key is ever exposed (committed, shared, lost): revoke it
immediately in **App Store Connect → Users and Access → Integrations →
App Store Connect API → (select the key) → Revoke**, then generate a
fresh key and update `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_PATH`. The
`scripts/p8-precommit-gate.sh` gate and the `*.p8` gitignore are the
preventative layers (ADR-014 § Secrets); revocation is the response.

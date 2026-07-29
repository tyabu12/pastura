# Contributing to Pastura

Thanks for taking the time to look. Pastura is small and primarily
maintained by one person, so the workflow stays light.

## Where to start

- File a bug as a GitHub issue and include what you saw, what you
  expected, the device, and the iOS version.
- Feature ideas go in an issue first so we can talk through scope
  before code lands. [`docs/ROADMAP.md`](docs/ROADMAP.md) shows what's
  in flight and what's out of scope for the current phase.
- Doc fixes and typos can go straight to a PR.

## Design principles

Pastura is layered to make a future SPM module split painless. The
authoritative rules live in [`CLAUDE.md`](CLAUDE.md).

- [Hard Rules](CLAUDE.md#hard-rules) cover the force-unwrap policy, the
  Engine to Data dependency ban, and required doc comments on public
  types.
- [Dependency Rules](CLAUDE.md#dependency-rules-strict) describe the
  allowed import direction between layers.
- [Swift Coding Conventions](CLAUDE.md#swift-coding-conventions) cover
  actor isolation, error types, logger privacy, and the i18n workflow.

If your change touches an architectural boundary, check
[`docs/decisions/`](docs/decisions/) for the relevant ADR.

## Workflow

1. Fork the repo, then clone your fork.
2. Create a branch named `feature/<description>`, `fix/<description>`,
   or `docs/<description>`.
3. Make your changes following the rules linked above.
4. Run the test suite locally (see Testing below).
5. Open a PR against `main` and reference the issue you're closing.

`main` is push-protected, so all changes land via PR.

On PRs and `main`, CI auto-reruns the `ui-test` job on intermittent
runner-init failures (up to 2 total attempts on PRs, 3 on `main`). Other
failures fall through unchanged. If attempt 2 turns the run green after
attempt 1 failed, that is the retry firing as designed; the latest
attempt holds the real verdict. See
[`.github/workflows/ci-retry.yml`](.github/workflows/ci-retry.yml) for
the trigger and gating logic.

### Commits

Conventional Commits with an emoji prefix, under 72 chars on the
subject line.

```
✨ feat(engine): add `reflect` phase type
🐛 fix(views): pop after Editor save on iPad split view
♻️ refactor(llm): extract grammar builder
📝 docs(roadmap): mark Step C-1 as Done
```

The full prefix list lives in
[`CLAUDE.md`](CLAUDE.md#git-conventions). Keep each commit focused on
one logical change. Add a body when "why" isn't obvious from the diff.

### Testing

TDD is required for `Engine/` and `LLM/`. For `Data/` and `Views/`
write tests after the fact when there's non-trivial logic to cover.

```bash
# Full test suite (slow, useful before pushing)
scripts/xcodebuild.sh test

# Single suite during red / green / refactor
scripts/xcodebuild.sh test -only-testing PasturaTests/ScenarioLoaderTests
```

The wrapper handles simulator selection, derived-data paths, and the
localization-catalog sync. See
[`.claude/rules/xcodebuild-cli.md`](.claude/rules/xcodebuild-cli.md)
for timeouts, recovery, and CI parity.

## Before your first PR

A few traps the project enforces with pre-commit hooks and CI. Knowing
them up front saves a round-trip.

### Pre-commit hooks

Run **`./scripts/setup.sh`** once after your first clone. It points
git's `core.hooksPath` at `scripts/git-hooks/`, activating the
repo-tracked `pre-commit` hook for every `git commit` (no per-clone
hand-config needed).

`git commit` then runs, in fail-fast order, `swiftlint lint --strict`,
`xcodebuild build`, and a set of self-gating content/consistency checks
(blocklist integrity, gallery schema, a `*.p8` secret block, and several
more — `scripts/git-hooks/pre-commit` is the authoritative list). Lint
violations or compile errors block the commit. The two expensive steps (`swiftlint`, `xcodebuild
build`) are skipped when the staged changeset touches no Swift or
build-relevant files — a docs-only or `web/`-only commit skips the iOS
build. The classifier is conservative: any unrecognized path runs the
full gate.

SwiftFormat and `swiftlint --fix` continue to run automatically on
file edit when you use Claude Code's PostToolUse hooks. A
`gh pr create`-time reminder also fires if the branch hasn't
touched CLAUDE.md (helpful when adding Phase 2 entries).

### Localization

Any new user-facing English string literal (`Text("...")`, alerts,
accessibility labels, and so on) must be wrapped in
`String(localized: "...")` so it lands in `Localizable.xcstrings` and
gets a Japanese translation. SwiftLint has a tripwire for this, and CI
checks coverage. See
[`docs/i18n/leak-detection.md`](docs/i18n/leak-detection.md) for the
architecture, [`.claude/rules/i18n.md`](.claude/rules/i18n.md) for the
Swift-side conventions, and
[`.claude/rules/i18n-catalog.md`](.claude/rules/i18n-catalog.md) when you
edit `Localizable.xcstrings` itself.

### Content blocklist

The content blocklist source is `docs/blocklist/source.json`. If you
edit it, rebuild and check.

```bash
brew install jq   # one-time
bash scripts/build-blocklist.sh --check
```

CI runs the same `--check`. Background and policy are in
[`docs/decisions/ADR-005.md`](docs/decisions/ADR-005.md).

### Architectural changes

Anything touching public protocol signatures, the Engine to LLM to Data
direction, or `AppRouter` should land a heads-up issue first. Larger
structural shifts usually need an ADR in `docs/decisions/` before the
code does.

## Submitting changes

1. Push your branch to your fork.
2. Open a PR against `tyabu12/pastura:main` and reference the issue
   you're addressing (`Closes #42`).
3. Make sure CI is green and SwiftLint is clean.
4. The maintainer reviews and merges. Squash-merge is the default.

PRs from forks may take a few days to get a first review. Pastura is
hobby-pace at the moment, so patience is appreciated.

## If you use Claude Code

This repo is heavily AI-agent-friendly. A few things worth knowing if
you have Claude Code installed.

- [`CLAUDE.md`](CLAUDE.md) is loaded automatically and carries the
  full project context.
- The `/orchestrate` slash command (defined in
  `.claude/skills/orchestrate/`) takes a task description and runs the
  full plan, worktree, TDD, review, and PR loop. It's the recommended
  entry point for non-trivial work because `main` is push-protected
  and the Xcode project file is concurrent-edit-hostile.
- Other skills live in `.claude/skills/`.

### The claude-kit plugin

Some of that tooling is not in this repo. `.claude/settings.json`
declares a marketplace and enables the
[`claude-kit`](https://github.com/tyabu12/claude-kit) plugin, which
supplies the `critic` and `implementer` agents and the
`/claude-kit:write-adr` skill. Manage it with `/plugin` — that is also
how you update an already-installed copy.

Without it:

- `/orchestrate` **stops at Step 1b** — its plan-critique gate requires
  `claude-kit:critic` and refuses to skip silently.
- `/claude-kit:write-adr` does not resolve, and this repo keeps no local
  copy — see [`.claude/rules/adr-writing.md`](.claude/rules/adr-writing.md).

The plugin is versioned independently of this repo, so an installed copy
can lag the kit. If a `claude-kit:*` skill or agent is missing rather
than misbehaving, update the plugin before investigating further.

Several `.claude/rules/*.md` files are one-way mirrors of kit rules; each
says so in its own header. Fix those upstream in claude-kit, never in the
mirror.

If you don't use Claude Code, ignore this section. The fork, branch,
PR flow above is the canonical contributor path.

## License

By contributing you agree your changes are released under the
[MIT License](LICENSE), same as the rest of the project.

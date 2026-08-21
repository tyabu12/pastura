---
paths:
  - "Pastura/Pastura/**/*.swift"
  - "Pastura/PasturaTests/**"
  - "Pastura/PasturaUITests/**"
  - "tools/harness/**"
  - "tools/kmp-gate-spike/**"
---

# Build & Lint Traps

Traps that fire when **adding or naming a Swift file**, or when writing about
SwiftLint in a Swift comment — hence the globs above, the union of their reach.

Each gate below names the offending line and why it fails. What no gate can do is
pick your new filename, remove the *need* for a directive, or read a sentence. That
residue is all the sections carry.

| Trap | Gate |
|---|---|
| Duplicate base filename within one target | `scripts/duplicate-basename-gate.sh` — pre-commit sub-gate 17, CI shell-tests |
| Directive inside a `///` doc comment — a silent no-op | `.swiftlint.yml` custom rule `swiftlint_directive_in_doc_comment` |
| Directive between the doc comment and the declaration | stock `orphaned_doc_comment` |
| Prose about a directive parsed as one | **none, and it is not reliably loud** |
| `swiftlint --path <file>` reads as "clean" | none, deliberately |

## Duplicate base filename → `.stringsdata` collision

Pastura's `PBXFileSystemSynchronizedRootGroup` auto-includes every new file under
`Pastura/`, so the name you pick can collide **cross-layer**, with a file three
directories away that you never opened.

**Apply**: rename to something distinct — and rename the type too if it also
clashes. Case study: #759 renamed a new `ScenarioSummary.swift` (Views) that
collided with the Data-layer `ScenarioSummary` → `ScenarioSummaryStrip`.

## SwiftLint directive placement around a `///` doc comment

Both placements fail: inside the `///` block the directive is a silent no-op,
between the block and the declaration it detaches the doc comment. So don't
relocate the directive — remove the need for it:

- `function_body_length` → **extract a helper** so each body stays under the
  threshold. Ref: `BundledDemoReplaySource.loadOne` → `buildSourceOrSkip`.
- `identifier_name` (short domain identifiers like `ja` / `en`) → add a
  **`.swiftlint.yml` `identifier_name.excluded`** entry (ref: the `ja` / `en`
  exclusions consumed by `pickLanguage(_:ja:en:)`), or rename to 3+ chars.

Suppressing the doc-comment rule is not an option either: a `disable`/`enable`
pair inside a block splits it into an `orphaned_doc_comment`. Reword — name the
directive, don't spell it.

## Prose ABOUT a directive is parsed AS one

The comment-command parser scans every `//` comment **and honours a directive
mid-sentence**, so one sentence quoting a directive's literal text applies it.

Ungated, and **not reliably loud** — what decides that is the token after the rule
name (measured on 0.65.0 against a bare-violation control):

- a non-rule word follows → `superfluous_disable_command` names that word, which
  reads as a problem with the code rather than the sentence (adjacent backticks
  get swept into the rule name and land here);
- **the sentence ends at the rule name → the rule is silently disabled on the next
  line, no diagnostic at all.** The prose changes behaviour, it does not just
  make noise.

**Apply**: in a **Swift** comment, name a directive rather than spelling it — "a
blanket `file_length` disable directive on line 6", not the text itself. The
examples here are spelled out because this file is Markdown, which SwiftLint does
not scan; that asymmetry is the whole trap, so do not read them as licence to
quote a directive in a `.swift` file.

## `swiftlint --path <file>` is not an option, and its error reads as "clean"

`swiftlint lint --path X` exits with `Error: Unknown option '--path'` (the
positional form `swiftlint lint [options] [paths...]` is the real one). A probe
that greps that output for a rule name finds nothing and concludes the rule did
not fire. Measured 2026-08-21 (0.65.0, #1505). Left ungated on purpose: a wrapper
only protects whoever uses it.

**Apply**: to test whether a rule fires, put the fixture **inside**
`.swiftlint.yml`'s `included:` tree and run the form the gates run
(`scripts/git-hooks/pre-commit`, `ci.yml`): `swiftlint lint --strict`. Two things
genuinely suppress a rule and are easy to mistake for "not enabled" — a fixture
outside `included:` (path-independent rules still fire there, so the run looks
live), and a file-level disable directive already in the target file.

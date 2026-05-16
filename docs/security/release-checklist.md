# Security Release Checklist

A consolidated checklist for the security-sensitive work that lives
outside the codebase. Three sections:

1. [GitHub repository settings](#1-github-repository-settings).
   One-time configuration kept current; commands are idempotent.
2. [iOS pre-submission audit](#2-ios-pre-submission-audit).
   Runs on the eve of an App Store submission (Phase 3, requires Apple
   Developer Program registration).
3. [Recurring review](#3-recurring-review). Periodic operator tasks.

The aim is to leave a paper trail of *what* should be true, *how* to
verify, and *how* to remediate. Re-run the verifier on each release.

---

## 1. GitHub repository settings

These settings are GitHub-side state, not files in this repo. Some
were enabled when introducing this checklist (PR #425); others remain
manual because the REST API path is undocumented or restricted.

### Current state verifier

```bash
gh api repos/tyabu12/pastura --jq '.security_and_analysis'
gh api repos/tyabu12/pastura/private-vulnerability-reporting -i \
  | head -1  # Expect: HTTP/2.0 204 No Content (enabled)
```

### Settings to keep enabled

| Setting | API field | How to enable |
|---------|-----------|---------------|
| Secret scanning | `secret_scanning.status = enabled` | UI: Settings > Code security |
| Secret scanning push protection | `secret_scanning_push_protection.status = enabled` | UI: Settings > Code security |
| Dependabot security updates | `dependabot_security_updates.status = enabled` | UI: Settings > Code security |
| Private Vulnerability Reporting | (no field; `PUT /.../private-vulnerability-reporting`) | `gh api -X PUT repos/tyabu12/pastura/private-vulnerability-reporting` |
| Vulnerability alerts | (no field; `PUT /.../vulnerability-alerts`) | `gh api -X PUT repos/tyabu12/pastura/vulnerability-alerts` |
| Automated security fixes | (no field; `PUT /.../automated-security-fixes`) | `gh api -X PUT repos/tyabu12/pastura/automated-security-fixes` |

### Secret-scanning sub-settings: free vs paid

Two `security_and_analysis` API fields show `disabled` after PVR /
push-protection / dependabot-security-updates are on. Subsequent
verification (2026-05) reveals they have different plan requirements,
not just a UI gap:

* **`secret_scanning_non_provider_patterns`** (UI label: "Scan for
  non-provider patterns"): requires **GitHub Secret Protection**, a
  paid add-on. The UI option does not surface for free public repos
  without GHAS / Secret Protection enabled. Track this as a paid-plan
  upgrade consideration; the field will stay `disabled` until the
  add-on is purchased.

* **`secret_scanning_validity_checks`** (UI label: "Automatically
  verify if a secret is valid by sending it to the relevant partner"):
  free for public repositories per GitHub's docs. Enable from Settings
  > Code security and analysis > Secret scanning. If the option does
  not appear, try an incognito browser session (cache) and search the
  page for `verify`; if still absent, contact GitHub support since the
  rollout has been account-dependent historically.

After enabling Validity checks, the verifier output should change to:

```json
"secret_scanning_validity_checks": {"status": "enabled"}
```

(`secret_scanning_non_provider_patterns` will stay `disabled` on the
current free plan; that is expected, not a regression.)

### Branch protection

`main` is protected via a ruleset (NOT a classic branch-protection
rule). Verify with:

```bash
gh api repos/tyabu12/pastura/rules/branches/main \
  --jq '.[] | {type, parameters}'
```

Expected rule types: `deletion`, `non_fast_forward`, `pull_request`
(with `required_approving_review_count` >= 0; the solo-maintainer
baseline is 0; raise once a second maintainer is onboarded),
`required_status_checks` (must include `lint-and-test`).

---

## 2. iOS pre-submission audit

Run this section in the same week as an App Store or TestFlight
external-tester submission. Many items are confirmed continuously by
CI (SwiftLint, the i18n leak audit, the no-force-unwrap rule), but the
release pass cross-checks them.

> Phase note: Pastura's Apple Developer Program registration is not yet
> in place at the time of writing. This section is dormant until that
> registration unlocks Phase 3 release work. See
> `project_pastura_distribution_status.md` for context.

### 2.1 Privacy Manifest

* `Pastura/Pastura/PrivacyInfo.xcprivacy` must declare every reason code
  used by required-reason APIs (`file timestamps`, `UserDefaults`,
  `disk space`, `active keyboard`, `system boot time`).
* If a new SDK or framework is added, audit the `PrivacyInfo.xcprivacy`
  inside the framework bundle for required-reason matches.
* Confirm `NSPrivacyTracking = false` (Pastura ships no trackers).

### 2.2 App Transport Security (ATS)

* `Info.plist` MUST NOT contain `NSAllowsArbitraryLoads = true`.
* No `NSExceptionDomains` entries should weaken HTTPS for production
  hosts. Dev-only ATS exceptions (e.g., for local Ollama testing) belong
  in the dev scheme, not the release scheme.

Quick check:

```bash
plutil -p Pastura/Pastura/Info.plist | grep -i "AllowsArbitrary\|ExceptionDomains"
```

### 2.3 Hardcoded secrets sweep

CI runs secret scanning continuously, but do a release-eve scan to
catch additions since the last release:

```bash
gh api repos/tyabu12/pastura/secret-scanning/alerts \
  --jq '.[] | select(.state == "open") | {number, secret_type, locations_url}'
```

Confirm no API keys, credentials, or auth tokens are embedded in
`Resources/`, `Models/`, or scenario YAML files.

### 2.4 Network destinations

Pastura's only outbound network is the model download. Cross-check:

* `App/ModelRegistry.swift` URLs are HTTPS and point to known publishers
  (Hugging Face, Kaggle).
* `Info.plist` does not declare any `NSAppTransportSecurity` overrides.
* The privacy policy at `pages/legal/privacy-policy/` accurately reflects
  the model-download host list.

### 2.5 Account deletion

Pastura has no user accounts. This row is a placeholder until that
changes. If you add an account-creation flow, Apple requires an in-app
account-deletion flow as a hard gate.

---

## 3. Recurring review

### 3.1 Dependabot PRs

Triage on the first weekday of each month after the new Dependabot PRs
land. Three buckets:

* **Yams, GRDB**: read upstream changelog, run the full test suite
  through `scripts/xcodebuild.sh test`, merge.
* **llama.swift**: read upstream `mattt/llama.swift` and the matching
  `ggerganov/llama.cpp` release notes. Run an end-to-end inference
  smoke test before merging. Date-encoded tags mean even apparent-patch
  bumps can include large upstream movement.
* **GitHub Actions bumps**: verify the bumped action is still SHA-pinned
  by Dependabot's PR (Dependabot preserves the comment-style version
  marker); skim release notes for breaking changes.

### 3.2 CodeQL findings

Run `gh api repos/tyabu12/pastura/code-scanning/alerts \
  --jq '.[] | select(.state == "open") | {number, rule: .rule.id, severity: .rule.severity}'`
on the first weekday of each month. The daily schedule means findings
arrive within 24 hours of landing on `main`; that is acceptable for a
pre-release codebase, and the workflow runs free against the public
repository's unlimited GitHub-hosted runner minutes.

For the first public release: dispatch a manual CodeQL run (Actions tab
> CodeQL > Run workflow) against the exact release commit and resolve
all findings of severity `error` or `high` before tagging.

### 3.3 Secret-scanning open alerts

```bash
gh api repos/tyabu12/pastura/secret-scanning/alerts \
  --jq '.[] | select(.state == "open")'
```

Should return an empty array. Investigate any non-empty result the same
day.

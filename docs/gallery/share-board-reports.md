# Share Board Report Handling

Operational procedure for Share Board scenario reports, per
[ADR-005 §6](../decisions/ADR-005.md).

This document is **maintainer-facing**. User-visible copy in the app
does not state any specific response-time number — this is intentional
(see ADR-005 §6.3). Keep the internal commitments tracked here only.

## 1. Reporting channel configuration

Two surfaces are exposed to users from `ReportScenarioSheet`:

1. **Primary — Google Forms.** Private report destination.
2. **Secondary — GitHub issue.** Public discussion path (opt-in).

### 1.1 Google Form required settings

The form is the load-bearing surface for Apple §1.2 "timely responses"
compliance — the response receipt delivers the immediate
auto-acknowledgement that the reviewer observes at submission test
time. Misconfiguring any of the below breaks that compliance claim.

**Settings → Responses:**

| Setting | Required value | Why |
|---------|----------------|-----|
| Collect email addresses | **Responder input** | User types email, no Google account required. `Verified` would force Google sign-in. |
| Response receipts | **Always** | Auto-ack on every submission is the §1.2 "timely" signal. `If requested by respondent` is NOT acceptable. |
| Limit to 1 response | **Off** | `On` forces Google sign-in. |
| Restrict to users in org | **Off** | GWS-only would reject non-org users. |

**Form fields (in order):**

| # | Type | Label | Required | Note |
|---|------|-------|----------|------|
| auto | Email | Email | yes (enforced) | Auto-added by Responder input. Not pre-fillable by URL parameter (Google design). |
| 1 | Short answer | Scenario ID | yes | Pre-filled by the app via URL parameter. |
| 2 | Short answer | App Version | no | Pre-filled by the app. |
| 3 | Paragraph | Reason | yes | User writes the report body. |

**Settings → Presentation → Confirmation message:** see §2.1.

The form ID and each field's `entry.xxxxxxx` parameter ID must be
mirrored as compile-time constants in
`Pastura/Pastura/Utilities/ReportURLBuilder.swift`. When the form is
ever re-created or migrated, update those constants in the same PR
that changes the form.

### 1.2 GitHub issue template

Located at `.github/ISSUE_TEMPLATE/share-board-report.yml`. Issues
filed via this template carry the `share-board-report` label.

Reporter contact is **not collected** — reply via @-mention on the
issue (the GitHub author is visible in the issue header). This keeps
the public tracker free of PII.

## 2. Response templates

### 2.1 Normal-mode confirmation message

Shown to the reporter on the form success page and in the
response-receipt email.

**English:**

> Thanks for your report. We've received it and will review as
> needed. If the content clearly violates policy, it will be hidden
> from the gallery during triage.

**Japanese:**

> 報告ありがとうございます。受領し、必要に応じて確認します。
> 明らかな policy 違反が確認できた場合は、triage 中にギャラリーから
> 該当シナリオを非表示にします。

### 2.2 Vacation-mode confirmation message

Before any planned absence longer than **5 days**, override the
confirmation message with a variant that states the expected return
date. This is the **only** user-visible surface where a specific date
appears (ADR-005 §6.3).

**Template (English):**

> Thanks for your report. We've received it.
>
> Note: the maintainer is currently away through **YYYY-MM-DD** and
> will resume reviewing reports after that date. Reports indicating
> clearly policy-violating content may still be actioned before then.

**Template (Japanese):**

> 報告ありがとうございます。受領しました。
>
> メンテナ不在期間: **YYYY-MM-DD** まで。復帰後に順次確認します。
> 明らかな policy 違反が確認できる場合は、不在期間中でも対応する
> ことがあります。

**Procedure:**

1. Google Forms → Settings → Presentation → Confirmation message →
   paste the vacation-mode template with the actual return date.
2. On return, revert the confirmation message back to the normal
   text in §2.1.

### 2.3 First human response

Sent privately by the maintainer after triage (email reply or GitHub
issue comment). Not templated — respond in the tone and language of
the original report. Internal target: within **7 days** of submission,
best-effort (ADR-005 §6.3). Not surfaced in the app.

## 3. Triage playbook

For each incoming report (Google Forms inbox **or** GitHub issue):

1. **Classify:**
   - **Clearly violating** — slur, personal attack on an identifiable
     real person, explicit sexual content, impersonation. Proceed to
     §4 (gallery hot-fix).
   - **Borderline / substantive** — policy question, quality concern,
     metadata error. Reply with judgment; no hide needed.
   - **Spam / test** — ignore; optionally close the GitHub issue or
     mark the Google Forms row as resolved in the spreadsheet view.
2. **Acknowledge** where needed — GitHub issues do NOT auto-ack, so
   leave a short comment confirming receipt. Google Forms submissions
   are already acked by the response receipt.
3. **Hide** per §4 (within 72h of receipt for clearly-violating
   reports).
4. **Close the loop** — private reply to the reporter within the
   internal 7-day target where applicable.

## 4. Gallery hot-fix procedure

A clearly-violating report must result in the offending scenario being
hidden from `docs/gallery/gallery.json` **within 72 hours of receipt**
(ADR-005 §6.3). Do this from a phone (GitHub mobile / web) during
travel if necessary — the bound is designed to be met without desktop
access.

### 4.1 Fast procedure

1. Open `docs/gallery/gallery.json` on github.com.
2. Tap the pencil (Edit) icon.
3. Remove the offending scenario's object from the `scenarios` array,
   including its trailing comma.
4. Commit directly to `main` with a clear message, e.g.
   `🐛 fix: hide share-board scenario <id> pending triage`.
5. Users pick up the removal on their next Share Board visit via the
   existing ETag-conditional GET (see [`README.md`](README.md)).

The scenario's YAML at `docs/gallery/<id>.yaml` can remain in the
repo; the app does not fetch YAMLs that are not referenced by the
index. Cleaning up the YAML is a follow-up, not part of the 72-hour
bound.

### 4.2 Follow-up

- **Permanent removal:** delete `docs/gallery/<id>.yaml` in a
  follow-up commit.
- **Restore after triage (false-positive):** re-add the entry to
  `gallery.json`. If the scenario was re-authored during the hide
  window, bump the id with a `_v2` suffix so installed copies with
  the old hash don't silently clash (see the "Suffix versioning"
  section of [`README.md`](README.md)).

## 5. Internal response target

- **First human response:** within 7 days of report receipt,
  best-effort. ADR-005 §6.3.
- **Violating-content hide:** within 72 hours of receipt.
- Neither is surfaced in user-visible app copy.

## 6. References

- [ADR-005 §6](../decisions/ADR-005.md) — Share Board Report Mechanism
- [`docs/gallery/README.md`](README.md) — Gallery curation + trust model
- [`.github/ISSUE_TEMPLATE/share-board-report.yml`](../../.github/ISSUE_TEMPLATE/share-board-report.yml)
- [`Pastura/Pastura/Utilities/ReportURLBuilder.swift`](../../Pastura/Pastura/Utilities/ReportURLBuilder.swift)
- [`Pastura/Pastura/Views/Community/ShareBoard/ReportScenarioSheet.swift`](../../Pastura/Pastura/Views/Community/ShareBoard/ReportScenarioSheet.swift)

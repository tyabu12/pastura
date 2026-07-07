# App Store listing — `docs/store/`

Text drafts for Pastura's first App Store submission (1.0). ASC entry itself is
manual (Web UI); `fastlane` is scoped to TestFlight upload only (ADR-014), so
there is no `fastlane/metadata/` here. This directory is the source of truth for
the copy that a human pastes into App Store Connect.

## Files

| File | Contents |
|---|---|
| `listing-en.md` | `en-US` ASC values: description, keywords, promotional text, subtitle, URLs, categories, captions |
| `listing-ja.md` | `ja` ASC values (natural Japanese, not a back-translation) |
| `review-notes.md` | App Review "Notes" field (en) — how to review without the 3 GB download, privacy, content safety, 13+ disclosure |
| `screenshot-plan.md` | Capture plan (iPhone 6.9″, ja/en, 5 shots) + procedure; PNGs are gitignored, not committed |

## Fixed values (do not change)

- **Name**: `Pastura - Local LLMs simulator` (globally unique; `release-setup.md` B2)
- **Subtitle**: `Like stargazing, but for LLMs` (29/30 chars)
- **Primary category**: Developer Tools · **Secondary**: Entertainment (per-version editable, not a one-way door)
- **Age rating**: 13+ (ADR-005 §3.2; 16+ pre-planned fallback)
- **Primary locale**: en (Go criterion = English submission Approved)
- **URLs**: Support `https://pastura.app/support/` · Marketing `https://pastura.app/` · Privacy `https://pastura.app/legal/privacy-policy/`

## Pre-submission checklist (operator)

Copy is ready; these are the gates around it. Not all are in this repo's scope.

### Hard blockers (ADR-005 §9.2 + #233)

- [ ] `OllamaService` wrapped out of the release binary; `nm` audit clean (#148)
- [ ] `PrivacyInfo.xcprivacy` present, required-reason APIs declared (#149)
- [ ] Support URL landing page live at `https://pastura.app/support/` (#182)
- [ ] Privacy Policy URL registered in ASC → App Information (#233)
- [ ] App Privacy questionnaire answered "Data Not Collected" (#233)
- [ ] EU DSA: declare **non-trader** status in ASC → Business (free app, hobby dev) (#233)
- [ ] `ITSAppUsesNonExemptEncryption = NO` declared (#159)

### Ordering / verification gates (this task surfaced these)

- [ ] **`TARGETED_DEVICE_FAMILY` narrowed `"1,2"` → `"1"` (iPhone-only) — merged BEFORE the release archive.** Otherwise ASC still requires 13″ iPad screenshots. (Separate Swift PR, via `/orchestrate`.)
- [ ] After the first build upload, confirm the ASC-computed device list matches the description's "(iPhone 15 Pro and newer)" parenthetical; adjust the copy if the real `UIRequiredDeviceCapabilities` list differs (#233).
- [ ] LP requirement drift fixed on the `web/` side before submission — LP currently says iOS 17 / 8 GB, contradicting the store listing's iOS 18 / 6.5 GB (#966).

### Copy review

- [x] Description direction confirmed (Opus session, 2026-07-07)
- [x] Pre-submission copy review (Fable session, 2026-07-07): accuracy fix applied — on-device claims scoped to inference / your data, not "zero cloud calls" (gallery index + model download are real GETs)

## Character-limit reference

| Field | Limit | en | ja |
|---|---|---|---|
| Subtitle | 30 | 29 | (English, shared) |
| Description | 4,000 | 1,995 | 1,080 |
| Keywords | 100 | 97 | 86 |
| Promotional Text | 170 | 164 | 93 |

(Counts are Unicode code points; ja full-width = 1 each, matching ASC.)

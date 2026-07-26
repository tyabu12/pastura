# App Review notes (App Store Connect → "Notes")

> Paste into the ASC "App Review Information → Notes" field. Written for the
> reviewer. English only. Keep it factual and self-disclosing (ADR-005 §3.3
> posture): acknowledge the mild-conflict content rather than downplay it.
> ASC hard-limits this field to 4000 characters; keep the pasted body under it.

---

Thank you for reviewing Pastura.

Pastura is an on-device sandbox for watching AI multi-agent simulations. The user writes or picks a YAML scenario; a local LLM runs it and the user observes the agents speak, reason, vote, and score. The user does not chat with the agents. Observation only.

## No third-party AI service (re: Guideline 5.1.1(i) / 5.1.2(i))

Pastura integrates no third-party AI service and sends no user data to one. All inference runs on-device via llama.cpp; scenarios and AI outputs are never transmitted off the device on their own. The only automatic outbound requests are one-way downloads of public files: model weights from huggingface.co and the read-only Shared Scenarios index from raw.githubusercontent.com. Nothing is uploaded to any server or AI backend. There is no cloud or remote LLM backend in the shipped build; any dev-only backend is excluded from Release builds at compile time.

New in this version: the user can explicitly share one AI-generated line or a highlight-card image via the iOS share sheet to X or Instagram: a deliberate hand-off to a social app, not a transmission to an AI service (see Sharing below).

To verify: after a model downloads, enable Airplane Mode and run a simulation. It still works, fully offline.

## Reviewing without downloading a 3 GB model

Inference is on-device, so first use downloads a model (~2.5–3.1 GB, Wi-Fi recommended). You do NOT need it to evaluate the app: a built-in demo replay plays a pre-recorded simulation on first launch (no network, no model), showing the full observation UX. For a live run, connect to Wi-Fi and pick a model on the download screen (a few minutes). No demo account is needed; there is no login.

## Privacy: no account, no data collection

- No account, sign-up, or login.
- App Privacy is declared "Data Not Collected"; `PrivacyInfo.xcprivacy` has empty `NSPrivacyCollectedDataTypes` and `NSPrivacyTracking = false`. No analytics, telemetry, or crash-reporting SDKs are linked.
- Sharing is user-initiated and native. The image share, X (`x.com` web composer), and Instagram Stories all use the iOS share sheet or a hand-off URL. Pastura links no social/analytics SDK (the `FacebookAppID` key is Instagram's required client identifier for the Stories hand-off, not an SDK) and transmits no user data; the shared line (optionally its inner-thought line) is already `ContentFilter`-passed.
- Privacy policy: https://pastura.app/legal/privacy-policy/ (also in-app under Settings).

## AI-generated content safety

Output is LLM-generated, so content safety is enforced by two layers (ADR-005 §4/§5):

- Output filter (`ContentFilter`): every user-visible surface (live stream, saved transcript, Markdown export, past-results viewer, and shared highlight cards) passes through a profanity/slur filter before rendering. Unconditional; no flag or setting disables it. The share card re-filters when it is built, even on the past-results path whose persisted text is stored unfiltered, so no unfiltered text can be burned into a shared image.
- Input validation: user-authored scenario/persona/phase text (incl. nested conditional sub-phases) is checked against a bundled blocklist to reduce jailbreak-style prompt content.
- Shared Scenarios is read-only and curated: not user-generated content; user-authored scenarios stay local and are never uploaded.

## Age rating: 13+

Rated 13+. Bundled scenarios (e.g. Prisoner's Dilemma, Word Wolf) involve mild social-deduction / voting-off mechanics and can surface infrequent mild conflict in the generated dialogue; disclosed honestly, per Apple's guidance to consider AI output when rating.

## Device requirements

Requires ~6.5 GB of RAM (`ModelRegistry.minRAM`), gated at install via `UIRequiredDeviceCapabilities`. Minimum iOS 18.0; in practice, iPhone 15 Pro and newer.

# Pastura Privacy Policy

**Effective date:** 2026-04-25
**Last updated:** 2026-04-25

## Who we are

Pastura is an iOS app for running AI multi-agent simulations entirely on-device.
It is developed and maintained by **tyabu12** (an individual developer).
References to "we", "us", or "Pastura" in this policy refer to tyabu12 acting
as the data controller for any data the app might process.

## Summary

**Pastura does not collect, transmit, sell, or share your personal data.**

All AI simulations run on your device using a local large language model
executed via the [llama.cpp](https://github.com/ggerganov/llama.cpp)
inference runtime. Your scenarios, simulation history, and preferences
never leave the device through any mechanism we control. Pastura's App Store privacy nutrition label is
**"Data Not Collected"**.

## Data we do not collect

We do not collect, request, log, or transmit any of the following:

- Names, email addresses, phone numbers, or other contact information
- Account credentials (Pastura has no account system)
- Device identifiers (IDFA, IDFV) for advertising or tracking purposes
- Location data (GPS, IP-based, or otherwise)
- Contacts, photos, calendar, or other personal data on your device
- Behavioural analytics, crash reports, telemetry, or usage statistics
- Health, financial, or biometric data

Pastura ships with no third-party analytics, advertising, attribution, or
crash-reporting SDKs.

## Data that stays on your device

The following information is created or stored locally inside the app's
sandbox and is never transmitted off the device by Pastura:

| Local data                            | Purpose                                                   |
|---------------------------------------|-----------------------------------------------------------|
| Scenario YAML you author or import    | Running simulations you have configured                   |
| Past simulation results (SQLite)      | Letting you revisit and export your simulation history    |
| App preferences (UserDefaults)        | Remembering your active model, playback speed, and similar settings |
| Downloaded LLM model files            | Performing on-device inference                            |

The required-reason API declarations in our
[`PrivacyInfo.xcprivacy`](https://github.com/tyabu12/pastura/blob/main/Pastura/Pastura/PrivacyInfo.xcprivacy)
reflect these uses: the `UserDefaults` API is declared with reason `CA92.1`
("app functionality") and the `FileTimestamp` API with reason `C617.1`
("files inside the app sandbox"). No tracking
domains are declared (`NSPrivacyTrackingDomains` is empty); `NSPrivacyTracking`
is `false`.

You can erase all of this local data at any time by deleting the app from
your device.

## Network connections Pastura makes

Pastura's AI inference is fully on-device, but the app makes a small number
of outbound network requests when you choose to use specific features:

- **Curated scenario gallery** — when you open the in-app Share Board, the
  app fetches a JSON index of curated scenarios from GitHub-hosted content
  at `raw.githubusercontent.com`.
- **LLM model download** — when you install or switch a model, the app
  downloads the model file from Hugging Face
  (`huggingface.co`).

These services see your IP address and a standard `User-Agent` string under
their own privacy policies (see
[GitHub Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement)
and [Hugging Face Privacy Policy](https://huggingface.co/privacy)).
Pastura does not log, store, share, or otherwise process the metadata of
these requests on its side.

## Tracking and advertising

Pastura does not use any tracking technologies, advertising identifiers,
attribution SDKs, fingerprinting, or cross-app/cross-site tracking. We do
not show ads. We do not participate in any data broker or advertising
network.

## Children's privacy

Pastura is rated **13+** on the App Store and is not directed to children
under 13. We do not knowingly collect personal information from children
under 13. Because we do not collect personal information from anyone, no
specific COPPA notice or verifiable parental consent flow is needed; if a
child under 13 uses the app, no personal data leaves the device through
Pastura.

In jurisdictions where the GDPR-K age of digital consent is set higher
than 13 (most EU member states use 16), the same no-collection commitment
applies to all users regardless of age.

## International users

We do not collect or process personal data, so most regional privacy laws
(GDPR, UK GDPR, Japan's APPI, California's CCPA/CPRA, and similar regimes)
have nothing for us to act on. Specifically:

- **GDPR / UK GDPR** — we are not a controller or processor of personal
  data within the meaning of Article 4, because no identifiable personal
  data is collected.
- **APPI (Japan)** — we do not collect or hold 個人情報 (personal information)
  as defined in the Act.
- **CCPA / CPRA (California)** — we do not collect, sell, or share
  personal information of California residents.

If you nonetheless wish to exercise a right granted by your local law
(such as a data subject access request), please contact us via the channel
below; we will respond by confirming that we hold no data about you.

## Future changes (Cloud API)

Pastura currently runs entirely on-device. Future versions may offer
**optional, opt-in** features that send specific user-authored content
(such as scenario prompts) to a named third-party AI provider for
processing. If such a feature is introduced:

- This policy will be revised to name the provider, list the data
  transmitted, identify the legal basis for processing, and link to
  the provider's privacy policy — **before** the feature ships.
- The feature will require explicit user consent; running on-device
  will remain the default.

Any future revision will be announced via the channels described in
"Changes to this policy" below.

## How to contact us

Use the support form at **<https://tyabu12.github.io/pastura/support/>**
for any privacy-related questions, including requests to confirm what (if
any) data we hold about you.

## Changes to this policy

We will revise this policy as Pastura's data practices evolve (notably
when any optional cloud feature is introduced). When we do:

- The "Last updated" date at the top of this document will change.
- Material changes will be summarised in the corresponding TestFlight or
  App Store release notes.
- The latest version is always available at
  <https://tyabu12.github.io/pastura/legal/privacy-policy/>.

Continued use of Pastura after a revision means you accept the revised
policy. If you do not agree with a change, please stop using the app and
delete it from your device.

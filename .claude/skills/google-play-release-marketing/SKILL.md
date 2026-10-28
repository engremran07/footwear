---
name: google-play-release-marketing
description: "Use when: preparing a Google Play release, uploading an Android App Bundle, planning ethical app-store optimization (ASO), creating launch videos, or building a repeatable ShoesERP app-marketing workflow."
---

# Google Play Release and Marketing

## Purpose

Prepare a policy-compliant Google Play release and a measurable, low-cost
launch campaign for ShoesERP. Use the existing APK signing and release
contracts; do not promise virality or bypass store, advertising, or platform
policies.

## Required Boundaries

- Read `AGENTS.md`, `CLAUDE.md`, the release-surface instruction, and
  `.claude/skills/apk-build-signing/SKILL.md` before a release.
- Preserve the active todo list and record the approved artifact, version,
  release track, evidence, and unresolved gates.
- A Google account email is not authentication. Never request, print, store,
  or transmit the user's password, recovery code, OAuth token, signing
  password, keystore, or service-account private key.
- Use an authenticated user-owned Play Console session for manual uploads.
  For authorized CI, prefer short-lived Workload Identity Federation and
  least-privilege permissions. Never commit credentials or put them in the
  app, an APK/AAB, or Firebase data.
- For Play distribution, use the signed `.aab`; split APKs are for device
  installation and are not the release bundle. Google Play generates
  device-specific APKs from the bundle.
- Before uploading an update, confirm the package ID, version name/code,
  release signing certificate SHA-256, and the upload certificate registered
  under Play App Integrity. A local `jarsigner` success does not prove that
  Play accepts the upload key. Stop if fingerprints do not match or cannot be
  checked.
- Upload to a draft or testing track unless the user explicitly selects a
  production rollout. Never submit the final production release, declarations,
  pricing, data-safety answers, or policy attestations on the user's behalf
  without their review and explicit confirmation.
- Do not buy installs, fake ratings/reviews, use engagement bots, keyword
  stuff, fabricate testimonials, spam communities, or claim guaranteed
  rankings/virality. Ask real users for honest feedback without incentives.
- Use synthetic demonstration data in screenshots, screen recordings, and
  generated marketing content. Do not expose customer names, phone numbers,
  balances, invoices, routes, or workspace identifiers.

## Play Release Procedure

1. Confirm the exact source version in `app/pubspec.yaml`, `AppBrand`, and the
   trilingual changelog. Run the required tests and analyzers.
2. Verify release signing configuration is present without displaying its
   contents. Build the AAB from the same source/version as any requested web
   or APK release. Record the artifact path, byte size, version code, and
   SHA-256 file hash.
3. Verify the bundle signature and extract only the public signing-certificate
   fingerprint. Compare it with the Play Console upload-certificate
   fingerprint. Do not upload if the expected app or registered certificate
   is unclear.
4. Confirm the package ID is the existing app entry, the version code is
   unused and increasing, and the user-selected track is clear. Use internal
   testing as the cautious default when a track was not specified; do not
   publish to production by default.
5. Upload the AAB through the authenticated Console session or an approved
   `fastlane supply` workflow. Review Play's validation output and release
   notes. Save as draft or testing release unless production publication was
   explicitly approved.
6. Report the Console result separately from local build/signature evidence.
   A successful upload is not the same as review approval, rollout, or public
   availability.

### Open-Source Deployment Option

`fastlane supply` supports uploading AAB/APK artifacts, localized listing
metadata, and screenshots, and selecting a Play track. For automation, pair
it with GitHub Actions and Google's `google-github-actions/auth` using
Workload Identity Federation, constrained to the repository/workflow and
minimum required Play permissions. Do not introduce CI credentials or
workflow changes until the owner authorizes the Google Cloud/Play Console
configuration and secret/identity setup.

For a one-off release, the Play Console UI is preferable to adding automation.
Do not install Fastlane or add credentials merely to upload one bundle.

## Rapid, Trustworthy Marketing Loop

Use the store listing and short-form product education to improve qualified
discovery and conversion. No workflow can guarantee that a video or app will
go viral.

### Store Listing

- State the target user and real task in the first sentence: footwear
  distributors managing routes, shops, stock, and invoices.
- Keep the title, short description, and full description accurate and
  policy-compliant. The Play short description is limited to 80 characters
  and the full description to 4,000; verify current Console counters before
  saving.
- Localize English, Arabic, and Urdu independently. Review right-to-left
  text, screenshots, and terminology with a fluent reviewer; do not machine
  publish unreviewed translations.
- Show current app screens and honest functionality. Use synthetic data;
  avoid ranking claims, unsupported savings claims, fabricated quotes, and
  competitor names used as search bait.
- Use Play Console store-listing experiments to test one meaningful variable
  at a time (for example, first screenshot or short description). Keep a
  dated record of the hypothesis, audience, result, and decision.

### Short-Video Production

1. Pick one verified user problem per video; demonstrate one complete workflow
   with synthetic data rather than stitching unrelated feature screens.
2. Capture the actual release UI with OBS Studio or a clean device recording.
   Remove notifications and account identifiers before editing.
3. Edit with Kdenlive or Shotcut; use FFmpeg for repeatable crop, resize, and
   encode steps. Optional local speech-to-text such as `whisper.cpp` may draft
   captions, but a human must correct technical terms and each translation.
4. Build vertical and landscape cuts from one source. Start with a clear
   problem statement, show the feature immediately, then end with one truthful
   call to action. Keep voiceover, subtitles, and UI legible without sound.
5. Publish original variations rather than mass-producing near-duplicate
   videos. Share through relevant, opt-in distributor communities and the
   business's own channels; do not automate comments, follows, views, or
   repetitive promotional messages.
6. Review viewer retention, store-listing visits, install conversion, and
   genuine support feedback. Change one element at a time; stop content that
   confuses users or overstates product capabilities.

Example 20-second outline:

- 0–3s: “Still matching stock and shop orders by hand?”
- 3–14s: Show a real route/shop workflow in ShoesERP using fictional data.
- 14–18s: Show the resulting invoice or stock view, without implying
  unsupported automation.
- 18–20s: “See whether ShoesERP fits your distribution workflow.”

### Low-Cost Measurement

- Use Play Console acquisition and store-listing metrics, listing experiments,
  and release/crash health already available to the owner.
- Use campaign-specific tagged links where the destination supports them.
  Avoid adding a new analytics SDK or Firestore listener solely for launch
  tracking.
- Keep a small release log: asset/version, language, channel, date, listing
  experiment, installs/conversion, qualitative feedback, and next action.
- Do not collect customer-level financial data for marketing attribution.

## Reference Material

- [Google Play app bundles and app setup](https://support.google.com/googleplay/android-developer/answer/9859152?hl=en)
- [Google Play store listing best practices](https://support.google.com/googleplay/android-developer/answer/13393723?hl=en)
- [Fastlane `upload_to_play_store`](https://docs.fastlane.tools/actions/upload_to_play_store/)
- [Google GitHub Actions authentication](https://github.com/google-github-actions/auth)
- [YouTube spam policy](https://support.google.com/youtube/answer/2801973?hl=en)
- [OBS Studio](https://obsproject.com/)
- [Shotcut](https://shotcut.org/)
- [FFmpeg documentation](https://ffmpeg.org/documentation.html)
- [Kdenlive](https://kdenlive.org/)
- [whisper.cpp](https://github.com/ggml-org/whisper.cpp)

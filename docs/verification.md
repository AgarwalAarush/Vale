# Verification — Mythos 1.1.0

Verified on the Intel development Mac running macOS 15.7.9 with Swift 6.1.2 Command Line Tools and official Codex CLI 0.160.0 using its existing ChatGPT sign-in. No credentials were copied or logged.

## Final app evidence

- Release executable and embedded Sparkle framework contain **x86_64 and arm64**. Both slices compile; the Intel slice ran here. Apple Silicon runtime verification on the user's laptop remains pending.
- `codesign --verify --deep --strict dist/Mythos.app` passes. The app is **ad-hoc signed**, with no TeamIdentifier; it is not Developer ID signed or notarized.
- Pinned official Sparkle framework reports **2.10.0**, is embedded with symlinks intact, and loads through the bundle's relative Frameworks path.
- **15/15 core checks** pass: atomic storage and permissions, corrupt-library preservation, legacy migration and exact backup, drafts, general-mode default, optional Learn policy, structured replies/point bounds, attachment metadata/search, and updater configuration/origin fixtures.
- **5/5 build-time updater configuration cases** pass: no configuration leaves the plist unchanged, valid existing public configuration enables required verification gates, and missing key/insecure feed/malformed key are rejected without partially rewriting the plist.
- **21/21 native flow checks** pass on the final universal app: immediate general chat, keyboard focus and Return/Shift–Return behavior, cancellation, four-file imports, PDF/text extraction, multiple images, pasted image import, file limits and unsupported-file errors, pause and mode preservation, close/resume, rename/search, deletion of managed bytes, persistence, stable window sizes, and an inactive unconfigured updater.
- **26/26 live integration checks** pass on the final universal app. The real provider identifies a red circle and blue square, reads the PDF's HARBOR-73 token and text-file reminder, retains message attachments, and performs an explicitly enabled live web search. A real `web_search` event is required by the test; a plausible source link alone does not pass. Search can be switched off again.

The initial web integration caught an unavailable tool despite the live-search setting. The provider was corrected to expose the installed CLI's standalone search capability only when enabled; the complete final integration was rerun and passed. Failed intermediate evidence is not used as release evidence.

## Artifacts

- `artifacts/unit-tests-1.1.log`
- `artifacts/update-build-config-results.json`
- `artifacts/universal-build-1.1.log`
- `artifacts/native-ui-1.1-final/results.json`
- `artifacts/integration-1.1-final/results.json`
- Final native PNGs in those two directories. New chat, capsule, attachment composer, PDF preview, chat history, settings/update controls, real multi-file reply, and real web reply were visually inspected. They contain only public generated test fixtures and the public Apple documentation answer.
- `dist/Mythos-1.1.0-release-manifest.json` and `dist/Mythos-1.1.0-SHA256SUMS.txt` record release/source archive identity and verification state.

Test data is isolated under each harness output directory. The harness renders only the app's own views. It does not capture other apps, activate the microphone, alter real chats, or bypass macOS consent. Clipboard import is exercised through the app import function; an interactive user clipboard/drop gesture remains a manual UX check.

## Required first use and production checks

- Microphone/speech and single-window capture require the user's native consent. Live microphone transcription, system-picker selection, and pointing over another app have not been end-to-end exercised here because screen-capture preflight requires consent. Typing and file upload work without these permissions.
- Laptop screenshot delivery and installation remain pending parent confirmation. No denial was bypassed, and no additional access or transfer mechanism was created. The remote installed Lilt 1.0 app was not overwritten by this release build.
- The updater implementation, public configuration gates, origin policy, embedded framework, and inactive state are verified. **Live signed feed retrieval, archive download, signature-tampering rejection by Sparkle, and update installation have not been exercised.** Production activation needs an authorized private HTTPS feed/archive source, existing Ed25519 signing assets, and Developer ID signing/notarization, followed by an installed previous-version update test.
- Large documents use bounded excerpts; scanned PDFs include only their first four pages. Word/Excel/PowerPoint and audio/video uploads are not supported in this release. The app does not control other applications or execute uploaded code.

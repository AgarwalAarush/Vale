# Vale 1.3 verification

The versioned `verification-1.3.0.json` records the published bootstrap’s assertions and evidence boundaries. The 1.3.1 direct-ChatGPT/UI candidate requires fresh source-bound results; genuine consent/inference has not yet been performed. The release manifest identifies the frozen source, architectures, exact packaged hashes, updater configuration and delivery status. Historical 1.2.x totals below do not establish current acceptance.

Native verification uses the actual AppKit workspace, native NSTextView and SwiftUI routes with generated data. It checks one persistent window, draft/selection/marked-text continuity, direct history, Notes/files/PDF, close/reopen, existing recovery, and synthetic capture/voice/privacy transitions. Light/dark and minimum/default/wide view PNGs are inspected separately from assertion counts. Some controls are exercised through their bound model methods; this is not physical mouse/drop/picker, VoiceOver or hardware consent proof. Repeated runs validate fixture isolation; integration totals overlap native checks.

Real Sparkle verification uses two independently compiled, ad-hoc signed disposable app versions. The actual SDK automatically fetches a signed feed/archive, installs and relaunches version 2, and generated draft, note, attachment and preference bytes survive. Altered-feed and altered-archive cases require signature-related SDK errors and an unchanged old executable. These loopback tests do not establish GitHub HTTPS availability, notarization or target installation. The separate release-feed probe uses Vale's actual UpdateController and Settings in a temporary nonce bundle/defaults/data domain, preserving automatic choices off across relaunch before checking the production address. A no-update check is not an older-to-newer installation.

Real provider integration requests public image/PDF/text analysis, explicit Web search and a guide from a labeled synthetic screen. A URL is insufficient for the Web assertion: an actual provider Web event is required. The known unavailable Web assertion remains false in any explicitly acknowledged private candidate. Execution tools and paid fallbacks stay disabled.

Reproduce with `VALE_ARCH=universal scripts/verify.sh --integration --repeat`; developer compilation requires the workspace module-cache environment configured by that script. `scripts/package-release.py --plan` lists precise required results and outputs. Default packaging requires every integration assertion to pass; the explicit private-candidate flag can acknowledge only the named Web failure and leaves `releaseReady:false`. Production signing/publication is a separate parent-authorized step. See [updates](updates.md) and [laptop handoff](laptop-update.md).

<details>
<summary>Historical 1.2.x verification (not current acceptance)</summary>

# Verification

## Vale 1.2.2 branding release

Version 1.2.2 (build 5) updates the app name, menus, permission descriptions, V icon, build/install/package filenames, and public agent documentation. Legacy storage/bundle identifiers, Swift targets and the Lilt persona are preserved. Intel and Apple Silicon slices build. All 28 core, 5 updater configuration, 61 native, repeated 61 native, and 67 integration assertions pass, including three genuine provider requests. Native chat, compact capsule, settings and icon visuals were inspected. The [public result snapshot](verification-results.json) includes each assertion without chat stores or private files. Physical hardware and distribution limits below still apply.

The 1.2.1 release was built and exercised on the Intel development Mac, macOS 15.7.9, Swift 6.1.2 Command Line Tools, and official Codex CLI 0.160.0 using its existing ChatGPT sign-in. Credentials were not read, copied, or logged. Recorded 1.2.1 results: 28/28 core, 5/5 updater configuration, 61/61 native, 61/61 repeated native, and 67/67 provider/fixture integration assertions pass. The 67 include the 61 native assertions; three requests use the genuine provider. See the generated release manifest for artifact hashes.

## What the checks establish

Core checks cover atomic/private session storage, corruption preservation, legacy decoding/backups, targeted Forget and unrelated-record preservation, retryable backup failure, explicit bounded conversation context, guide validation/progress, structured replies, stale/changed/moved/unknown/invalid screen evidence, foreground-window occlusion/unknown metadata, and updater policy fixtures.

The native app runs its actual NSWindows/SwiftUI views with isolated generated data. Return/Shift–Return, Command–N and Escape are sent through its own AppKit event pipeline. Other actions generally call the same model methods bound to UI controls, not physical mouse gestures. Assertions cover startup, files, drafts, close/resume, cancellation, natural fixture error/retry, late provider and speech callbacks, active synthetic voice/live pause, interruption/rearming, repeated suspend/resume, no automatic restart, capture timeout/denial, selected-scope refusal before transmission, no periodic transmission, preview-memory cleanup, fresh guide navigation, missing geometry feedback, explicit context notices, hidden-window refusal before transmission, and explained suppression of covered highlights.

Privacy fixtures invoke the actual AppModel Forget/removal paths against generated migration data and a deliberate file-removal fault. privacy-proof.json records the removed target and matching unrelated IDs in the library/backup, plus managed-byte removal/preservation. The failure fixture verifies retained metadata/bytes and visible Retry Forget, then recovers and removes the data. No real user chats/files or OS permissions are destroyed or changed.

The complete native suite runs twice into the same output directory. An intermediate failure came from reusing a generated backup from a previous run; fixture directories are now unique per run, preserving the product's intended backup semantics. Final repeat evidence must pass before packaging.

The genuine provider integration has three live requests: two-image/PDF/text analysis, explicitly enabled web search requiring a real web_search event, and a validated step guide from a labeled synthetic selected-window image. A valid link alone does not pass search. Capture/voice fixture checks run alongside these requests, but are not real hardware tests. Integration assertions include the native assertions; repeated runs are not independent UX journeys.

Five build-configuration fixtures verify updater inactivity, a valid public configuration, and rejection of missing keys, insecure feeds and malformed keys without partial plist writes. Sparkle is embedded and strict signature verification is checked. This does not verify a production update.

## Visual evidence

Native app-owned PNGs include the general empty chat, compact capsule, uploads/PDF preview/history, paused/Learn states, settings/update controls, selected live window, loading, changed-screen warning, retryable connection error, synthetic spoken conversation, expanded step guide, covered-highlight feedback, visible history limit, deletion failure with retry and recovered empty history. Provider PNGs show actual replies to the public files, web search and synthetic-window guide.

These are app-owned view captures inspected by Codex, not whole-desktop captures or an independent human usability study. Material compositing over other apps, real global-hotkey registration, physical pointer gestures and VoiceOver are not established by them. Voice settings controls are implemented; catalogue/locale/playback behavior still needs hardware UX checks.

## Exact limits and remaining checks

- Synthetic screen sources are available only in explicit test launches. They never select/capture other apps. Synthetic voice skips authorization, audio engines and audible playback. Neither is evidence of consent or hardware behavior.
- Real mic/speech authorization, denial/revocation, dictation/audio quality, actual interruption, native window picker, selected-app capture, and real overlay alignment/freshness/occlusion remain unexercised. Pointing requires macOS 15.2+ geometry and strict matching; animations may cause conservative suppression.
- The provider returns final replies; no streamed text/audio or full-duplex conversation is implemented. Live refresh is local snapshot sampling; there is no continuous cloud screen stream or autonomous app action.
- Login/logout/expiry/quota/offline account recovery, real file picker/drop/clipboard gestures, scanned/locked/corrupt/large document matrices, cold-process restart, multi-display/Spaces/fullscreen, large-library performance, and accessibility/contrast/large-text testing remain pending.
- The universal executable and Sparkle framework contain arm64 and x86_64. Only Intel runtime is verified here. Apple Silicon runtime is not inferred from compilation.
- The app is ad-hoc signed with no Developer ID/TeamIdentifier and is not notarized. No existing production feed or Ed25519 public configuration is supplied. Authentic signed feed/archive retrieval, tamper rejection, version/architecture update selection, install and recovery require existing trusted signing assets and an authorized private source.
- Laptop installation and first-use hardware checks remain pending. Native consent must be granted by the person testing; never bypass OS privacy or Gatekeeper protections.

## Reproduce

Run `VALE_ARCH=universal scripts/verify.sh --integration --repeat`, then `python3 scripts/package-release.py`. Result JSON, logs, public fixtures, privacy proofs, and PNGs are under artifacts/; source/evidence packaging includes curated reviewed PNGs and result/proof files, not test-library user stores or authentication data. The extracted release app is also checked for signature integrity and native behavior before handoff.

</details>

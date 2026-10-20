# Development roadmap

Vale is a general-purpose native macOS companion with an optional learning mode. Read AGENTS.md before making changes. Use the one-window PRODUCT.md/DESIGN.md contract, first-class typed input, explicit capture/mic consent, legacy data compatibility, and signed automatic updates with saved user choices.

## Start here

- Build with `scripts/build.sh`. Set `VALE_ARCH=universal` for Intel + Apple Silicon; the default builds for the current Mac.
- Run `scripts/verify.sh --repeat` for core, updater configuration, and native fixture checks. The native harness requires a logged-in macOS GUI session.
- Run `VALE_ARCH=universal scripts/verify.sh --integration --repeat` for genuine provider requests using Vale’s direct ChatGPT connection after explicit personal browser consent. Generated OAuth/protocol fixtures are not genuine integration evidence. This consumes account usage; synthetic voice/screen fixtures do not request hardware permissions.
- Keep generated artifacts and chat stores out of Git. Never commit credentials, private screenshots/documents, authentication files, or signing keys.
- Use focused branches and pull requests. Capture and inspect the real native views for UI changes; do not substitute a browser mockup. Report checks actually run and hardware checks still pending.

## Priority work

1. Exercise first-run window-picker, microphone and speech consent on real hardware, including denial and revocation; verify typing remains available.
2. Validate capture and pointing on covered/minimized/moving windows, multiple displays, Spaces and fullscreen. Current metadata/pixel checks deliberately suppress uncertain highlights.
3. Run the packaged app on Apple Silicon. Universal compilation is already supported; Intel is the only runtime verified so far.
4. Review VoiceOver, keyboard navigation, contrast, large text, and physical file picker/drop/paste flows.
5. Test account expiry/quota/offline recovery, cold restarts, large histories, and difficult PDFs/documents.
6. The approved Pearl compact companion is implemented at1.3.3/build10 and published as a manual preview. Deliver the identical reviewed app through the signed automatic-update feed using [the release workflow](releases.md). Genuine direct ChatGPT, physical-device and target-laptop acceptance remain separate. The 1.3.0 bootstrap is published: anonymous signed downloads and an actual configured Sparkle production check passed. One-time laptop bootstrap installation remains pending; source, package, live feed and target installation require separate evidence. Preserve the private signing seed across repository maintenance. Developer ID/notarization and an encrypted external key backup remain distribution/maintenance follow-up work.

## Scope

Live context is explicit selected-window sampling kept locally; images are sent on questions or guide actions. Voice currently takes turns through complete provider replies. Network audio/video streaming and full-duplex voice are not implemented. No notch integration, persistent agents, routines/connectors, or autonomous computer control is planned in the current scope.

## Release delivery

| Item | Status | Owner | Outcome | Evidence and remaining work |
| --- | --- | --- | --- | --- |
| V12 | P0 / implementing current-work context and commands | Main chat; bounded context and command workers | Fresh current-display screenshot plus read-only selected text on explicit questions, optional OS access, manual-window precedence, CtrlOptionSpace show/focus/hide and CtrlOptionD dictation; retain the accepted Pearl UI. | Factory job20261020-231230-add-automatic-current-display-screenshot-f8779054 from reviewed1.3.4 tooling15e6fb7. Target1.3.5/build12 through signed automatic updates. Generated functional/native checks and public updater verification pending; physical selection/screen/mic, macOS26 compositor and owner-laptop acceptance remain separate. |
| V10 | P1 / signed automatic delivery verified | Main chat coordinates delivery and independent review | One command builds, checks, packages, signs Sparkle updates, stages verified GitHub assets, promotes latest and verifies public downloads. Reuse exact reviewed Pearl1.3.3/build10 for automatic delivery. | [Release workflow](releases.md). Primary1.3.3/build10 published:9anonymous asset hashes and public signatures match, canonical feed retainsbuild7. Actual isolated SDK7→10 installed exact published bytes and ran new code only in a nonce-ID test clone. Original preview/stable assets remain immutable. Release tooling review is recorded separately from owner-reopened UI acceptance. Developer ID/notarization and target-laptop installation are separate unverified boundaries. |

| V11 | P0 / owner-reported1.3.3 UI defects reopened | Main chat coordinates native implementation and visual acceptance | Fix Ready contrast/alignment and unwanted raster icon, shared native placeholder/caret geometry, content-led Ask, coherent concise Settings and discoverable attachment shortcuts. | Current Factory UI job20261020-213602-fix-owner-reported-vale1-3-3-pearl-contr-a5830575. Publish corrected1.3.4/build11 through signed updates after current native checks and actual screenshot critique. macOS26 compositor and owner-laptop install remain separate evidence boundaries. |

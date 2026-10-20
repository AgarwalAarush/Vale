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
6. Rebuild the owner-rejected1.3.1 native composition under [the native pipeline](design/native-product-pipeline.md), then complete genuine direct ChatGPT consent/inference, frozen-source review and signed candidate delivery. The1.3.2 candidate is not visually accepted or production ready yet. The 1.3.0 bootstrap is published: anonymous signed downloads and an actual configured Sparkle production check passed. One-time laptop bootstrap installation remains pending; source, package, live feed and target installation require separate evidence. Preserve the private signing seed across repository maintenance. Developer ID/notarization and an encrypted external key backup remain distribution/maintenance follow-up work.

## Scope

Live context is explicit selected-window sampling kept locally; images are sent on questions or guide actions. Voice currently takes turns through complete provider replies. Network audio/video streaming and full-duplex voice are not implemented. No notch integration, persistent agents, routines/connectors, or autonomous computer control is planned in the current scope.

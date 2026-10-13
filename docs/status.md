# Release status

Lilt 1.0.0 — local macOS release, 12 October 2026.

- Native SwiftUI / AppKit app implemented and release-built without compiler warnings.
- Original dark floating capsule and compact coach retained.
- First-class typing, optional voice, explicit window context, progressive hints, transient pointing, session library, editable takeaways, Markdown export, and Forget implemented.
- Existing signed-in Codex CLI validated with ChatGPT-only authentication; no API fallback configured.
- Eight core checks and 17 native integration checks passed on the final build.
- Native screen-capture preflight reports that macOS user consent is required. The system picker and microphone flows are ready for first use; permissions were not bypassed.
- App ad-hoc signed for local use; no signing identity or notarization service configured.

Build and verification are reproducible through scripts/build.sh and scripts/verify.sh. Detailed scope and limits are in docs/verification.md.

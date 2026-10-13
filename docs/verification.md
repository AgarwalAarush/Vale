# Verification record

Release 1.0, 12 October 2026. Native macOS application; no browser reconstruction.

## Automated evidence

- Release compilation and ad-hoc bundle signature validation.
- Eight core checks: timer bounds, atomic storage / file permissions, corrupt-library preservation, rectangle bounds, structured reply validation, truthful no-image prompt, explicit walkthrough policy, and Markdown export.
- Native app harness: keyboard focus, Shift–Return newline, Return submission, cancellation identity, pause preserving a draft and stopping input/sharing, resume, stable window sizes, completion / review, resume restoring drafts, persistent storage, and unobstructed work / completion window transitions.
- Real provider integration through the saved ChatGPT Codex sign-in: a typed question receives an answer; the provider reads the data structure named in a screenshot of the app’s own conversation.
- PNGs rendered from the actual native welcome, library, capsule, coach, typing, paused state, conversation, review, settings, and recovery surfaces. Screenshots are 2x rasterizations of their native view bounds.

The initial native pass found an oversized library window and an overly gray material. Hosting view sizing and dark tint were corrected. The coach was reduced to 410 × 480 points. Native snapshots were inspected after the fixes.

## Human / OS mediated checks

Live microphone recognition and selection through the macOS system window picker require the Mac user’s permission and choice. These are implemented but were not exercised by automatically granting permissions. Voice is turn-based Apple speech recognition plus system speech synthesis, rather than a full-duplex Realtime connection.

The overlay verifies image content and geometry before appearing and checks for movement or content changes while visible. Accuracy of model-generated target coordinates remains a limitation. Multiple displays, Spaces, physical microphone quality, screen lock on this Mac, and different language input methods require hands-on validation; they are not claimed as completed automated checks.

No Apple Developer signing identity was present. The delivered app is ad-hoc signed for this Mac and not notarized for public distribution. No production service, launch agent, background coding supervisor, remote server, or paid API fallback was installed.

## Reproduction

`./scripts/verify.sh --integration` runs bounded checks and writes logs and JSON results under `artifacts/`. The native integration report is `artifacts/integration/results.json`; core results are in `artifacts/unit-tests.log`. The integration harness uses its own isolated session store.

# Lilt 1.0

Build a native Mac learning companion from the original dark floating design. The source concept is ../Lilt-concept-2026-10-12/assets/companion-dark.png. Preserve the compact graphite capsule, subtle glass coach, and restrained blue accents. Typing is first-class. Do not replace the companion with a full-height chat sidebar.

## Required paths

- First launch: a focused welcome surface, choose a topic, start a session without system permission prompts.
- Menu bar + Control–Option–Space summon a keyboard-focused text composer.
- Persistent conversation: type, paste multiline code, optionally speak, receive text replies, request one hint at a time or explicitly reveal a walkthrough.
- Use the existing signed-in official Codex CLI. Disable integrations, command tools, browser, memory, and plugins for tutoring. Do not extract or copy authentication tokens. Do not silently switch to API billing.
- Explicit single-window selection through the native ScreenCaptureKit picker. Refresh a screenshot on a question. Provide preview and stop sharing. No ongoing screenshot recording.
- Optional speech recognition and system speech playback. Request permissions when Talk is chosen. Interrupt speech, preserve text draft, never activate the mic on startup.
- Pause cancels pending requests, stops voice, clears sharing and annotations, freezes time. Resume preserves conversation and draft and requires a new sharing choice.
- Pointing: normalized bounded coordinates only; require fresh image content and unchanged window geometry. Expire highlights and clear on cancellation or movement.
- Local session library with editable takeaway, continued sessions, Markdown export, explicit Forget confirmation. No fabricated user data or mastery statistics.
- Build, unit tests, native UI checks, and real provider integration checks are repeatable from scripts. Package an ad-hoc signed local app with no third-party dependencies.

## Scope

This is a local macOS app. macOS 14+ for text and voice; window metadata for pointing uses macOS 15.2+ when available. The build on this Mac targets Intel. Public distribution, Apple Developer notarization, paid realtime audio, proactive monitoring, production deployment, and server job orchestration are separate releases. The supplied autonomy document informs the reproducible build and validation workflow; it is not a requirement to create a second autonomous coding product.

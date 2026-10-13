# Mythos 1.1

A general-purpose native Mac companion based on the original dark floating design. Preserve the compact graphite capsule and assistant card, restrained blue accent, and first-class typing. Learning is optional. The product rename preserves the Lilt assistant persona, legacy bundle identity, preferences, and saved chats.

## Product behavior

- First launch goes directly to an untimed general-assistant chat without a topic form or permission prompt.
- Menu bar and Control–Option–Space summon a keyboard-focused composer. Return sends, Shift–Return inserts a newline, and input-method composition is preserved.
- General mode responds directly. Optional Learn mode offers progressive hints and an explicitly requested walkthrough. Focus timers are optional.
- Upload multiple images, PDFs, text, and code through a picker, drop, or clipboard. Preview files, retain them with messages, remove them, and recover after a failed request. Limits are explicit: eight files/chat, 25 MB/file, twelve visual pages/request, 60k text characters/file and 100k total. Image inputs are normalized to bounded PNGs; scanned PDFs provide the first four pages with an explicit limitation.
- Use saved official Codex CLI ChatGPT sign-in without extracting tokens or switching to paid API use. Disable command, browser, computer, app, plugin, memory, and other integrations. Expose only web search when explicitly enabled.
- Explicit single-window context through the system picker; fresh capture per question, preview, stop sharing. No automatic screen capture. Optional turn-based Apple speech recognition/playback.
- Pause stops voice, pending requests, sharing, and annotations; preserves chat, files, and draft. Late completions cannot cross sessions or replace newer requests.
- Bounded, fresh screen pointing with unchanged window geometry. Highlights expire and clear on change/cancellation.
- Local searchable chat history, notes, rename, continue, Markdown export, and confirmed Forget. Atomic private session storage; exact legacy backup before migration. Uploaded files are deliberately retained; captured screen images and microphone audio are not stored as chat attachments.
- Mythos app branding and icon, universal Mac artifact, repeatable native checks, private local release packaging, and an implemented signed updater with inactive production configuration.

## Release limits

macOS 14+; window geometry for pointing uses macOS 15.2+ when available. Intel runtime verification is available here. Apple Silicon compilation is separate from runtime verification on the user's laptop. This release does not implement autonomous app control, background monitoring, arbitrary tool execution, audio/video uploads, Word/Excel/PowerPoint parsing, or a paid Realtime backend.

Developer ID signing/notarization, an authorized private HTTPS update feed, and existing Ed25519 signing assets are required for a production update rollout. Do not create credentials, publish private assets, bypass Gatekeeper, or change login/permissions to complete a local build.

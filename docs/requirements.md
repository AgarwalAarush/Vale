# Mythos 1.2

Build a general-purpose companion with explicit live-window context, interruption-safe spoken turn-taking, typing fallback, and step-by-step learning help. Preserve the dark floating UI, Lilt persona, legacy bundle/data identity, uploaded files, and saved chats. Exclude notch integration, persistent agents, routine/connector platforms, and autonomous computer actions.

## Required behavior

- Start in an untimed general chat. Learning mode and guide plans are explicit choices. Typing remains available without screen/mic permission.
- Capture only the window selected through the native single-window picker. Live is separately opt-in, scoped to that selection, refreshed locally roughly every two seconds, with one RAM preview and a six-second capture deadline. No auto-selection, full-display fallback, startup capture, or periodic cloud transmission.
- A question/guide step uses fresh window context. Compare scope, pixels and geometry again before presenting a point. Mark changed-screen answers, suppress stale guides/points, and offer explicit refresh. Unknown or invalid geometry fails closed for pointing. Stop/reset closes screen previews and clears pixels.
- Conversation requires explicit opt-in. Reopen the mic only after the current reply playback finishes. The microphone is off while thinking/speaking; a mic tap interrupts and listens. Typing, stop, pause, Escape, session changes, sleep/lock, and errors prevent unwanted rearming. No full-duplex or streaming claims.
- Show capture/mic state and last refresh. Permission denial, capture timeouts and connection failures retain messages/drafts with clear recovery and text fallback. Never grant OS permissions automatically.
- Validate short guide plans (2–8 steps, bounded text), persist the user's place, and ask against fresh context on navigation. Do not fabricate completion or mastery.
- Preserve Return/Shift–Return and input-method composition, native shortcuts, optional panel expansion, accessible button labels, loading/empty/error states, and optional voice controls.
- Keep attachment/history behavior: eight files/chat, 25 MB/file, up to twelve uploaded visual pages/images plus one selected-window frame; 60k extracted text/file and 100k total. Scanned PDFs contribute their first four pages. Images normalize to bounded PNGs.
- Send at most eighteen recent conversation messages, excerpted to 8k characters each and 48k total, with a visible notice when context is limited. Full history remains saved locally.
- Forget must purge target content from the active library and legacy backup, preserve unrelated sessions/files, and propagate unlink/write failures. Partial deletion stays retryable and reports its state. Do not discard a chat while its files are importing.
- Use existing official CLI ChatGPT auth, ephemeral requests, ignored user rules/config and disabled local/integration tools. Only explicitly enabled web search is exposed. No credentials, subscriptions, paid API fallback, or external publication.
- Build universal Intel/Apple Silicon artifacts, repeat native checks into the same output to validate isolation, exercise generated privacy and voice/capture failure fixtures, ask the real provider, inspect native screenshots, and package private local evidence with hashes.

## Limits

Local refresh is bounded snapshot context, not video streaming. Spoken interaction is turn-taking through final CLI responses. Synthetic adapters do not establish real microphone, speech, picker, capture or overlay accuracy. Hardware consent, VoiceOver, real drop/paste/picker gestures, multi-display/fullscreen behavior, and Apple Silicon runtime require further testing. Strict pixel comparison can react to animations and needs hardware UX validation.

The embedded Sparkle updater remains manual and inactive without an authorized private HTTPS feed, existing trusted Ed25519 signing assets and a signed/notarized deployment workflow. No Gatekeeper or denied computer-use access may be bypassed. Screenshot delivery must precede laptop installation.

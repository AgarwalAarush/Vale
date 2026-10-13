# Release status

Mythos 1.2.1 (build 4) implements the selected-window conversational companion scope. General chat stays the default. Live context refreshes locally on explicit opt-in; questions and guide steps send fresh frames. Conversation provides interruption-safe hands-free turn-taking and typing fallback, with optional language/voice/speed/silence settings. Step guides, stale-screen warnings, panel expansion, and visible context limits are implemented.

The confirmed privacy defects are fixed: Forget filters the target out of the migration backup while preserving unrelated records, file-removal failures propagate into retryable state, pending imports are protected, and open previews release pixels on stop/removal. Generation guards, bounded capture, geometry validation and callback checks prevent stale or unrelated context from being used.

Final checks pass: 28 core, 5 updater configuration, 61 native, a repeated 61 native, and 67 integration assertions (including those native assertions). Hashes are recorded in the release manifest. Core, native, repeat-run, generated privacy and real provider evidence are in artifacts/. The earlier repeated-run privacy failure was fixture reuse: old generated backup UUIDs contaminated a later fixture. Unique per-run fixture directories fixed isolation; the native suite is rerun twice into the same output before packaging.

Intel and Apple Silicon slices are built; runtime verification here is Intel only. The app is ad-hoc signed and not notarized. Sparkle 2.10.0 remains implemented but inactive; no credentials, keys, feed or publication were created.

Version 1.2.1 adds on-screen capture gating and foreground-window occlusion checks; hidden windows stop before transmission and covered points receive visible feedback. These checks are verified with metadata fixtures, not a physical overlay test.

Real hardware capture/voice, real pointing alignment, Apple Silicon runtime, laptop delivery/installation and production signed updates remain pending. The prior Codex UI denial remains respected. No notch, persistent agents, routine/connector platform or autonomous computer control was added.

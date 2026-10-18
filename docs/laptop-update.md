# Vale laptop update

Requested on 2026-10-17: install the latest Cursor changes and new icon on the user's laptop, remove obsolete installed app bundles, and preserve chats/settings. This chat executes on the Intel `macserver`; laptop installation, cleanup and relaunch are still pending laptop execution access.

## Source reconciliation

- GitHub main `358ed7662de4ad6f31c5eb7faeb21d6b80e78019` includes Cursor's consolidated PR 211, which combines drafts 6–210. Older draft PRs were intentionally left open; they are not separate merges still needed wholesale.
- The newer PR 212, tip `72ea496e42c9795ea692719f400832f25784d829`, was also merged into the local candidate. It remains unmerged on GitHub.
- The new icon is retained from local commit `87cd130`. No source or binary has been published by this update task.
- A runtime review found that the consolidation included many tested helper definitions without their app wiring. The local candidate connects compatible fixes across composer/clipboard/drop/focus, reply controls and transcript/history UI, pending/sent files and previews, capture, microphone sequencing, Codex subprocess handling and draft-safe request handling. Superseded whole-layout experiments are not reapplied over the integrated companion.
- UI review compared 112 Cursor feature tips. Deliberate reconciliations retain the combined quiet layout, canonical artwork, latest empty greeting, unified labels and focus timer. New chat preserves the previous chat's draft/files in history; the alternative draft that blocks New chat while text is unsent was omitted. Individual draft PRs have not all been independently merged or accepted.
- The previous laptop's local startup and SwiftPM-path repairs are preserved semantically: startup resumes the saved chat/draft, and packaging resolves actual native/alternate product paths with explicit architecture verification. Full-app compile errors in startup, glass tint, image encoding and an unsupported AppKit property were corrected.

## Candidate and acceptance

The candidate is Vale 1.2.3, build 6, using legacy bundle ID `local.lilt.companion` and the existing `Application Support/Lilt` store. It is a private local build with ad-hoc signing. Production updates remain inactive because no authorized feed/signing deployment is configured.

Core checks pass 234/234 and updater configuration fixtures pass 5/5. The universal build contains Intel and Apple Silicon slices, with strict signature verification passing. Native fixtures pass 67/67 and the required repeat passes the same 67/67. Actual native screenshots were inspected; the discovered notes refresh defect was corrected and the populated notes recaptured. Genuine provider integration passes 72/73 checks, including those 67 native checks. File/PDF/image answers and a guide against a synthetic screen pass. Intel checks do not establish Apple Silicon runtime or laptop installation.

The failed integration assertion is `explicitWebSearchUsesRealTool`. Codex CLI 0.160.0 did not provide web search with host execution disabled. Two bounded public-query probes found no safe compatible route: GPT-5.5 was rejected by this account, while GPT-6 Sol with the documented `--search` route failed closed because its code-mode host was disabled. Bundled model metadata is consistent with a model/runtime tool-mode limitation; it does not establish that all CLI versions or the laptop's configuration are affected. Host code execution remains disabled as required by AGENTS.md. No fallback provider, paid API, model preference change or credential change was made. See `artifacts/web-search-runtime-1.2.3.json` and the [official web-search compatibility documentation](https://learn.chatgpt.com/docs/web-search).

The failed result is preserved. `scripts/package-release.py` still requires every integration check to pass and has not been weakened. The laptop setup archive is an explicitly private candidate with this known limitation, not an accepted public release. Production signed updates remain inactive.

New native regressions exercise cold-launch restoration after Close chat, preservation of the personal draft/files when saving a generated command fails, retention of sent files, held-preview gating, and Conversation opt-out without discarding the late answer or rearming the microphone. The screen/guide fixtures wait for the validation outcome because replies are intentionally displayed before the fresh-window check completes. The earlier fixture run reported six failures from checking that later state as soon as waiting-for-reply ended; the corrected run and repeat both pass all 67 checks.

The installer must stage and verify the new app before replacing installed copies, quit matching apps gracefully, retain rollback until the new app launches, and move only superseded app bundles to Trash. It must leave chats, attachments, preferences, credentials, macOS privacy/security settings and project/test copies intact.

## Laptop handoff

Extract `dist/Vale-1.2.3-laptop-setup.zip` on the laptop and open `Install Vale.command`. The command runs the staged installer with `--replace`; it requires no Swift, Python, lipo or developer tools. Respond personally to any normal macOS security confirmation. This chat has no laptop filesystem/app execution access and has not downloaded, installed, removed or relaunched anything there. The macserver's older installed Lilt is also untouched.

# Vale

<!-- impeccable:product-schema 1 -->

## Platform

macos

Native macOS app using AppKit and SwiftUI, minimum macOS14. Impeccable currently has no macOS enum/reference; this accurate platform declaration intentionally does not label the app iOS, Android, or web.

## Users and purpose

A tiny desktop companion beside the user's work: summon it with a keyboard shortcut at the top right, type or dictate a question with fresh current-display/selected-text context when permitted, optionally choose a window or add files, and read a compact reply while continuing the original task. The owner clarified on 2026-10-20 that the resting footprint is approximately 300×45pt and the panel expands in place. The large chat-history/sidebar workspace is a rejected product direction. Chats/files, Learn, notes and opt-in screen/voice help remain available through secondary on-demand routes.

## Operating context

Typing is first-class. The 1.3.1 candidate connects through direct ChatGPT browser sign-in and eligible plan usage, with no Codex CLI or paid API fallback. Genuine personal consent and inference must be verified separately from protocol fixtures. Automatic current-work context defaults on with an off control; Screen Recording/Accessibility permission prompts require explicit user actions and denial never blocks typing. Optional selected-window capture and voice stay explicit and visible. Current factory execution is on Intel macserver; target laptop runtime is a separate delivery acceptance.

## Capabilities and constraints

Preserve general chat, Learn/hints/step guides, notes, focus timer, history/search, rename/export/Forget, files/PDF/images, read-aloud/Talk/Conversation, automatic current-display/selected-text context, and optional fresh selected-window context. One small floating assistant panel changes size in place. History and settings must not create a permanent large default workspace; preserve capabilities without presenting all navigation at rest. Native OS dialogs remain appropriate; the deliberate temporary click-through pointing annotation is feedback, not a second assistant workspace.

Remember the external source app/display and read its selection before an explicit invocation activates Vale. Each explicit question refreshes only that app's read-only AXSelectedText and captures a fresh current-display screenshot excluding Vale; an explicitly chosen window supplies screenshot context instead. Selection is bounded to16000 UTF-16 units and screenshots to1600px on the long edge. Both stay transient in RAM/current provider input; never append raw context to saved user questions or retain it as attachments. Skip secure/password fields. App-activation observation tracks source identity only; no continuous selection reads, background screen capture or simulated clipboard Copy to read selection. Disable, pause/hide, sleep/lock and session changes clear transient context and invalidate pending capture.

Control–Option–Space shows Vale with the composer focused, or hides it when already active. Control–Option–D explicitly toggles dictation through existing permission/status/Stop and utterance-completion handling. The microphone remains off at startup.

Preserve legacy bundleID local.lilt.companion, store, chats, drafts, attachments and settings. Do not add model command/file/app/browser/code execution, startup capture/mic, login agents, automatic selected-window choice or credentials logging. Only explicitly enabled supported web search may be exposed. Web availability depends on the connected account/workspace/model and must not be advertised as working without a genuine hosted-tool event.

## Brand commitments

Vale name and canonical folded-ribbon V artwork remain for app/system identity. The latest owner defect report removes the raster icon from the compact panel itself. The owner requests exceptional native craft and a Liquid Glass look, informed by the supplied Refero/Uiarc references and Freya/Stratum density. Both the old two-window appearance and the large workspace are anti-references. The latest request explicitly chooses generated visual mockups before further implementation; this supersedes the earlier code-first choice. See [compact companion exploration](docs/design/compact-companion-2026-10-20/README.md).

## Evidence on hand

The published 1.3.0 bootstrap includes the latest Cursor PR212 consolidation and the reviewed single-window/updater implementation (PR213). Anonymous signed release downloads and an actual configured Vale/Sparkle live-feed check passed. The published 1.3.1 preview replaced the CLI connection with direct ChatGPT; protocol fixtures do not establish official third-party support or genuine account use. The current rework must repair its rejected native composition. The prior1.2.3DMG has no active update source; it cannot bootstrap itself. Existing native/provider checks are historical, overlapping and not acceptance of the redesign. The latest owner screenshot rejects the published 1.3.1 single-window preview itself: duplicate chrome, oversized empty modules and ambiguous connection/send hierarchy. The original split capsule/coach screenshot is historical. Earlier visual approval is reopened. Use generated fixtures for screenshots and keep private user content out of evidence.

## Product principles

- One place to continue the task, with clear navigation and preserved draft ownership.
- Make the answer and composer primary; secondary tools reveal in context.
- Optional capture and voice never become prerequisites for typing.
- Preserve data and fail closed at update/context trust boundaries.
- Report source, package, publication and installed outcomes separately.

## Accessibility

Preserve native keyboard/IME/undo behavior, readable semantic colors, labeled controls, visible focus, Reduce Motion and Reduce Transparency. Use system typography and symbols; do not transplant marketing web layouts into the app.

## Open decisions

The owner selected the Pearl Glass Ready→Ask→Answer mockup on 2026-10-20. Implement its compact topology and hierarchy with native text/material and one coherent appearance that honors System, Light and Dark preferences. The October20 owner screenshots reopen contrast, caret, layout and Settings acceptance. Generated images do not prove native material rendering or measured dimensions. Publication remains authorized in the broader task. Fresh native, package and delivery evidence is recorded in the current Factory round; prior preview evidence does not approve the compact rebuild. Preserve protected signing-key custody. Direct ChatGPT consent/inference, compact native visual/interaction acceptance and target-laptop installation remain separate milestones.

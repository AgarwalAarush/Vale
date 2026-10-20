# Vale: native product workflow research

Researched October 19, 2026. This document answers the owner's request to investigate macOS design practice, online workflows and skills before rebuilding Vale's process. It is research and a proposed direction, not product acceptance. See the companion [Apple and original-skill source audit](apple-native-research-2026-10-19.md) for fifteen detailed primary-source groups, API availability and capture limitations. The independent critique and resulting execution pipeline follow this dossier; they must not be silently substituted by this author's conclusions.

## The defect that reopened acceptance

The owner rejected the actual 1.3.1 preview window. Its empty state shows a tall blank titlebar above a second application toolbar, oversized sidebar actions, redundant New chat content, a large generic welcome heading, separately competing connection and message actions, and a deep empty editor with disconnected status/voice controls. These are visible defects in task hierarchy and native density. The earlier visual pass is reopened. The source checks and signed-download receipts remain valid only for the things they actually measured.

The process allowed this because content-only captures omitted system chrome; fixture success was conflated with visual readiness; review checked a self-authored design contract without sufficiently challenging its composition; and release preparation continued before convincing visual acceptance. More agents or more assertions would not fix those incentives. We need complete-window evidence, a concrete task brief, a critic allowed to reject, and distinct finish lines for design, behavior, live services and delivery.

## How to read the evidence

1. Apple API contracts, SDK availability and HIG establish platform behavior and conventions. They do not certify Vale's layout.
2. Original authors' shipped-app cases and documented design processes provide contextual lessons, not universal recipes.
3. Public social search results establish discovery only. An indexed caption is not a read thread, watched video or independently reproduced technique.
4. Our proposed dimensions, composition and pipeline are product judgments to test in Vale. They are not Apple mandates.

Keep the app's macOS 14 minimum, existing AppKit/SwiftUI architecture, stable native text editor, single workspace and complete capabilities. Never import an iOS 26 or web default solely because a skill contains it. No new paid tool or global skill installation is required for this work.

## Search and access record: all four requested platforms

| Platform | Searches / access attempted | What was actually available | Consequence |
|---|---|---|---|
| Medium | Native macOS SwiftUI AppKit design workflow; native settings; shipped utility lessons | Readable original author article bodies in search results | Four cases below, with dated scope and rejected advice identified |
| X | Native macOS workflow, toolbar styling, SwiftUI craft, agent shipping workflows | Relevant indexed posts; direct post opens returned login/empty shells or 403 | Cite the discovery post and use the author's readable original article for substantive conclusions |
| Instagram | Site-scoped app design/workflow/prototype, macOS UI, SwiftUI/native and Design+Code searches; public Play profile open | No useful readable indexed result; direct profile fetch throttled | No reel watched or recommendation attributed to Instagram; this coverage is attempted, not completed reading |
| Threads | Site-scoped threads.com / threads.net native macOS, SwiftUI, design workflow; public profile open | Empty or irrelevant clone tutorials; direct profile returned HTTP 429 | No thread content claimed; irrelevant tutorials rejected |

The browser inventory on this host exposed no available interactive surface. We did not access private accounts, bypass platform restrictions or invent social findings. The inaccessible social material is a research limitation, not a reason to repeat empty searches indefinitely or stop independent native implementation. A source's accessibility and the strength of its advice are separate questions.

## Practitioner cases and current craft guidance

### Medium: native app architecture should serve the interface

[Andreas Link's Licenses case, March 2021](https://linkandreas.medium.com/building-a-native-macos-app-using-swiftui-and-combine-ee076d337cef) describes separating state/actions and composing smaller views, with real Mac application integration. Adopt bounded view composition and previewable states. Do not transplant its SwiftUI 2/Combine architecture or impose a Redux-style rewrite on Vale. This is a historical shipped-app case, not current API documentation.

[Anh Phong's VPNPeek lessons, January 2026](https://medium.com/@p_anhphong/what-i-learned-building-a-native-macos-menu-bar-app-eacbc16c2e14) support pragmatic SwiftUI/AppKit integration and careful dismissal, keyboard and settings behavior. Its menu-versus-popover judgment belongs to that menu-bar utility. Vale is a standard workspace; neither a fixed framework ratio nor a menu-bar layout follows from this case.

[Schopenlaam's native settings example, October 2024](https://medium.com/@schopenlaam/how-to-build-macos-system-like-app-settings-in-swiftui-9ee3f8d50e57) uses familiar split navigation and grouped forms. Adopt a coherent native form vocabulary and meaningful labels. The example's measured sidebar/window numbers are not universal standards. Don't copy fixed sizes or sacrifice accessibility to mimic a screenshot.

[Srishti Tayal's Fluxo case, December 2025](https://medium.com/@srishtayal/reclaiming-the-notch-how-i-built-a-native-macos-utility-in-swiftui-04de80137e5f) illustrates feature restraint and platform-specific integration, but also demonstrates why research needs filtering. Reject its high window-level, sandbox removal and quarantine workaround advice for Vale. A notch utility's special window behavior does not belong in a normal chat workspace. Permission, signing and notarization claims require Apple's documentation.

### X discoveries, checked against original author material

[Natalia Panferova's indexed X post](https://x.com/natpanferova/status/1873637008628990251) led to her readable [window-background article, December 2024](https://nilcoalescing.com/blog/CustomizingMacOSWindowBackgroundInSwiftUI/) and [toolbar-style guide, May 2026](https://nilcoalescing.com/blog/AGuideToMacOSToolbarStylesInSwiftUI/). Window background, title visibility and toolbar style interact; visual chrome must be configured at the real window owner. Keep a meaningful accessibility/window title even when visually hidden. Some examples target newer macOS, so check availability against macOS 14 and the installed SDK. The [Apple toolbar-style reference](https://developer.apple.com/documentation/swiftui/windowtoolbarstyle) is the API authority. A modifier on a SwiftUI scene is not automatically effective on Vale's independently created AppKit window.

[Peter Steinberger's indexed X workflow post](https://x.com/steipete/status/2005451576971043097) led to [Shipping at Inference-Speed, December 2025](https://steipete.me/posts/2025/shipping-at-inference-speed). Useful principles are fast observable build feedback, current documentation, native Swift for Mac work, narrow task dispatch and playing the actual result. Do not adopt unread security changes, direct-to-main integration, unbounded computer access, model benchmarks or paid tooling as prerequisites. His personal working style does not replace independent acceptance or Vale's trust boundaries.

### Product redesign: compare flows, then implement real code

[Linear's own redesign account, March 2024](https://linear.app/now/how-we-redesigned-the-linear-ui) describes reducing chrome noise, improving hierarchy/density and alignment, comparing complete flows, and iterating real code with designers and engineers before staged release. Adopt the workflow: compare the same task and state, inspect the actual product, then dogfood. Its Electron implementation and visual system are not a reason to rewrite Vale or copy CSS, fonts or color infrastructure. Preserve behavior while changing composition.

[Martin Lexow's SwiftUI Window Styles source gallery](https://github.com/martinlexow/SwiftUIWindowStyles) makes window/toolbar combinations concrete. Use native source-backed experiments to compare structure instead of designing imaginary window chrome. [Ohanaware's toolbar examples](https://ohanaware.com/swift/macOSToolbarExamples.html) are another original implementation reference. Check APIs and ownership rather than pasting examples wholesale.

[Rauno's craft gallery](https://rauno.me/craft) is evidence of a practitioner organizing detailed interaction work, including native SwiftUI examples. We inspected the listing, not every demo or a watched video. It is a source for focused interaction investigation, not proof that decorative animation belongs in Vale.

[Emil Kowalski's animation guidance](https://emilkowal.ski/ui/good-vs-great-animations) supports purposeful anchored transitions and timing that follows interaction. Adapt principles through native APIs and Reduce Motion. Do not import web animation libraries, arbitrary choreography or animation where immediate task feedback is clearer.

### Tool recommendation must be current

Older social material recommends Play for native prototypes. Its [official site](https://createwithplay.com/) now says support ended April 20, 2026. Its [handoff documentation](https://docs.createwithplay.com/en/articles/dev-handoff) also distinguishes exported packages from reference-code tooling. Do not introduce a discontinued tool or mistake a prototype export for production integration. The useful lesson is to prototype using real native components; Vale already has the required AppKit/SwiftUI stack.

## Skills: select roles, not a pile of style prompts

The companion audit checks original Paul Hudson, Antoine van der Lee/Omar Elsayed, Anthropic and Impeccable sources. Locally, use these bounded roles:

- **Factory:** coordinator, immutable review target, independent source reviews, guarded integration and delivery receipts. It is an execution discipline, not an art director.
- **Impeccable Operate:** task hierarchy, consistent controls, bounded visual inspection and a fresh critic. Its current launcher has no macOS enum and incorrectly falls back to web. Keep the accurate platform declaration and apply native guidance directly; don't relabel Vale iOS or web to satisfy a tool.
- **Taste:** general hierarchy, restraint and reference interpretation only. Its own current scope excludes dashboards and complex multi-step product UI. Its landing-page recipes, heroes and display-font rules are a poor fit for Vale.
- **SwiftUI Pro / original expert references:** targeted availability, state ownership, layout, accessibility and performance review. New iOS/SDK defaults cannot override macOS 14. No new installation is necessary.
- **Emil:** optional interaction polish after the native task structure works. Motion cannot repair wrong layout or establish production quality.

The owner already chose direct native implementation followed by inspection. Do not reopen a mockup interview, install a web kit, generate marketing variants, or turn a user complaint into more procedural approval requests.

## Native principles supported by the research

Apple's [Mac fundamentals session](https://developer.apple.com/videos/play/wwdc2021/10062/) and [macOS design guidance](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/) emphasize flexible, familiar, precise, comfortably dense workspaces. For Vale this means one coherent window frame, a quiet history collection, readable messages, a compact stable editor and contextual secondary actions. These are design inferences, not an Apple-prescribed chat layout.

Use the native toolbar and menu/responder system; semantic system typography/colors; conventional sidebar selection; sensible resizing; preserved draft/editor identity; and optional permissions requested at feature use. Prioritize normal first-run and restored sessions, including unconfigured/loading/error states. Verify message editing, selection, undo, IME, keyboard commands, accessible labels, appearance and increased contrast. Details and limitations are recorded in the companion research.

## Capture and acceptance must be honest

An `NSView.cacheDisplay` image of content omits the titlebar. A complete in-process window-frame raster can reveal duplicate chrome and traffic-light geometry, but is still not a compositor screenshot or real typing/clicking. Apple's SDK deprecates `CGWindowListCreateImage` at 14 and obsoletes it at 15; do not bypass availability with private symbols. ScreenCaptureKit's supported user-mediated path is not permission to silently capture a whole display. See the companion evidence-tier matrix.

Each image must name source revision, state, logical frame, scale, appearance and method. Inspect image coverage rather than trusting a filename. No private conversation/background-window content belongs in committed visual evidence. Actual hardware, genuine ChatGPT consent/inference, signed feed retrieval, package installation and laptop relaunch each require their own evidence. A missing capability keeps that acceptance open; it does not erase completed independent work.

## Proposed direction to challenge before constructing the pipeline

The primary task is to write and read a conversation with optional files, learning, voice and explicitly selected screen context. The proposed structural change is one real compact native toolbar, smaller conventional history rows, no redundant empty history entry, and a short task-oriented empty state close to a compact growing editor. Auth, retry and permissions should appear where they block a task. Keep saved Web on/off visible and never imply opt-in means a tool succeeded. Preserve all current capabilities and persistent identifiers.

Candidate geometry must be tested rather than presented as HIG law: approximately 190–208 pt sidebar, ordinary 24–28 pt rows, 13 pt controls, 14–15 pt message text, 20–22 pt empty heading, a growing composer starting around 70–90 pt, readable prose around 640–700 pt. The chosen layout must work at the owner's ordinary window size, minimum and wide frames, light/dark, and with realistic content. Density must not become tiny type or hidden required actions.

The next independent agent should challenge source quality, missing/contradictory evidence, skill misuse, first-run task clarity, capture feasibility, and unnecessary steps. Only then should the coordinator write the canonical project pipeline and replace the rejected DESIGN contract. Required quality comes from concrete acceptance and inspection, not the label “optimal.”

## Post-critique resolution: the exact ChatGPT route

The critic correctly required official evidence beyond the UI dossier. The existing implementation links were then opened and checked against [OpenAI's registration/sign-in guide](https://developers.openai.com/siwc/token-sharing-open-source/sign-in), [models/inference guide](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference) and [preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations). They document the implemented dynamic open-source registration, host ID, issued client ID, PKCE/OIDC validation and direct OAuth Responses route. This establishes a documented integration path; it does not establish successful personal consent, eligible account/model access or live inference in Vale. The route remains subject to its documented preview limitations. No Codex CLI, backend-api endpoint or paid API fallback is introduced.

The [official UI/UX guidelines](https://developers.openai.com/siwc/ui-ux-guidelines) specify Continue with ChatGPT for an action that starts sign-in, a one-time dismissible explanation after initial plan-enabled sign-in, and a quiet plan-use indication/usage link near the composer or model selector. Therefore Connect ChatGPT to send describes the local dependency; the actual primary sign-in button retains Continue with ChatGPT. Connected plan indication must remain subordinate to writing. A successful connection never auto-sends the retained draft.

The current [Refero Linear reference](https://styles.refero.design/style/90ce5883-bb24-4466-93f7-801cd617b0d1) explicitly identifies measurements as normalized, recommendations as interpreted and HTML as reconstructed. Treat it as secondary inspiration. A direct Uiarc fetch failed during this research; do not imply all of its demos were inspected.

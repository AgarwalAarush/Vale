# Native macOS workflow research for Vale

Researched 2026-10-19. Scope: primary Apple guidance and original authors' material; research only. No app, build, source, skill installation, account, or permission changes. Vale's stated baseline is macOS 14, an AppKit `NSWindow` hosting SwiftUI, and one workspace. Those constraints take priority over newer SDK examples. The owner-rejected screenshot and the coordinator's report of content-only snapshots are defect evidence, not an accepted design reference.

## Findings that should change the next round

- Repair the window structure before styling individual panels. The tall detached title bar and a second toolbar consume attention and content space. Apple's native toolbar supports a compact title-and-action row; the platform already supplies window controls and behavior. Prototype one real window with its actual titlebar and traffic lights before adding surface decoration.
- Design around writing and reading a conversation. The empty invitation should not resemble a website hero, and the composer should not resemble a large landing-page form. A short useful prompt, visible insertion point, concise capability affordances, and a compact editor establish the task. This is a Vale-specific inference from Apple's content-density and onboarding guidance, not a prescribed Apple chat layout.
- Use familiar compact rows, selection, menus, keyboard focus, and semantic colors. Make the primary action and active conversation obvious; make optional capabilities subordinate. High density means more useful content with less navigation, not tiny unreadable type.
- Keep the existing AppKit/SwiftUI boundary unless a concrete defect requires changing it. Apple's own Shortcuts implementation uses both. Treat the text editor's identity, selection, composition, undo, and responder behavior as product requirements.
- Replace “snapshot exists” acceptance with explicit evidence classes. A content snapshot cannot reveal titlebar geometry. A frame-view raster is useful but still is not window-server or physical-input evidence. Passing fixture assertions cannot establish visual quality, live provider behavior, hardware consent, delivered updates, or release trust.

## Fifteen source groups, with applications and limits

All takeaways below are paraphrases. “Apply” is our recommendation for Vale, not a claim that the source reviewed Vale. HIG pages are living documentation; publication dates are stated only where a visible changelog or dated session establishes them.

### 1. Apple — Designing for macOS

Primary: [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/). Living HIG; indexed body verified on this research date. Quality: authoritative platform design guidance, not a usability study of this app.

Source: Mac workflows use large displays, multiple apps, precision pointers, keyboards, resizable windows, menu-bar commands, and user configuration. The guidance calls for comfortable density, fewer nested navigation levels, and less unnecessary modality.

Apply: evaluate Vale in an ordinary window alongside other work, not only a spacious isolated canvas. Give conversation content useful room; keep history and settings reachable without excessive navigation. Preserve resizing and keyboard use. Do not import touch-first dimensions or a marketing-page hierarchy simply because SwiftUI can render them.

Limit: this page does not prescribe exact row heights, composer height, window dimensions, or a chat visual language. Choose those from actual content and native prototypes.

### 2. Apple — SwiftUI on the Mac: Build the fundamentals

Primary: [WWDC21 session 10062](https://developer.apple.com/videos/play/wwdc2021/10062/), 2021. Full Apple transcript read, especially the opening platform principles and the sidebar/toolbar/menu demonstration.

Source: native Mac UI is flexible, familiar, expansive, and precise. The talk connects tighter margins and spacing with useful content density, places navigation in a sidebar, content centrally, and actions in familiar toolbar/menu locations. Its example persists selection and sidebar state.

Apply: use this as a composition reference: a quiet history sidebar, a clear conversation surface, and a small action set in the top frame. Compact the sidebar and remove duplicated navigation/action layers. Persist the current conversation and drafts. Prototype in SwiftUI/AppKit and inspect a running window.

Limit: the example uses 2021 APIs and a gardening data app. Do not copy obsolete navigation code or treat a table example as a reason to turn chat into a dashboard.

### 3. Apple — Toolbars and native toolbar styles

Primary: [HIG Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars), and [NSWindow.ToolbarStyle](https://developer.apple.com/documentation/appkit/nswindow/toolbarstyle-swift.enum). Living documentation; indexed Apple body verified. Direct HIG open produced a JavaScript shell; its indexed full text was available.

Source: prioritize commands deliberately, let system overflow handle narrowing, and expose toolbar actions in the menu bar. A useful content title helps orientation; repeating the app's name is not useful context. AppKit distinguishes expanded, unified, and unified-compact styles; the compact variant reduces margins around title and controls.

Apply: prototype a genuine `NSToolbar` and `.unifiedCompact` on Vale's existing `NSWindow` rather than drawing a second toolbar below a decorative header. Keep ordinary traffic lights and drag regions. Use a conversation title only when it helps orientation. Confirm controls fit at the minimum supported width.

Limit: compact style alone will not fix duplicate actions or a wrong content hierarchy. SwiftUI scene modifiers do not automatically configure an independently owned AppKit window; use the appropriate owner.

### 4. Apple — Sidebars

Primary: [HIG Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars). Living HIG; visible changelog June 8, 2026. Indexed full body verified; direct HTML open required JavaScript.

Source: sidebars navigate top-level areas or content collections. Use short labels, manageable disclosure hierarchy, familiar symbols, and a way to hide the sidebar. Color needs a semantic purpose and should respect the user's system accent choice.

Apply: keep history rows compact and scannable, with a clear selected conversation, short titles, and restrained timestamps. Use disclosure only if the real information hierarchy warrants it. Provide the standard View-menu sidebar command. Separate settings or optional modes with hierarchy rather than padding and repeated rounded cards.

Limit: current HIG includes Liquid Glass and adaptable-tab guidance. Those newer visual and API details are not a mandate for Vale's macOS 14 baseline. No exact row measurement is supplied by the source.

### 5. Apple — Windows and full-size content layout

Primary: [HIG Windows](https://developer.apple.com/design/human-interface-guidelines/windows), [NSWindow](https://developer.apple.com/documentation/appkit/nswindow), and [fullSizeContentView](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/fullsizecontentview). HIG changelog includes June 9, 2025; current API references checked.

Source: standard windows should adapt to resizing; excessive new windows add confusion. AppKit distinguishes the full frame, including its titlebar, from unobscured content geometry. With full-size content enabled, content extends into the titlebar region and layout should use the content layout guide/rectangle appropriately.

Apply: fix launch-safe-area geometry in the actual window. Compare normal, minimum-width, wider, and restored window states. Keep traffic lights, toolbar controls, and content from overlapping. Test both first launch and restoration after relaunch.

Limit: sections of the current HIG discuss visionOS dimensions and glass; they are platform-specific and must not be applied to a Mac window. In particular, its 1280×720 spatial example is not a default-size prescription for Vale.

### 6. Apple — Accessible typography and semantic color

Primary: [HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [HIG Color](https://developer.apple.com/design/human-interface-guidelines/color), and [Fonts technology overview](https://developer.apple.com/documentation/technologyoverviews/fonts). Living Apple references; indexed body verified.

Source: Mac UI text defaults differ from touch platforms; Apple's table gives 13 pt as a custom-type default and 10 pt as a minimum, not an instruction to use the minimum. Contrast, text enlargement, VoiceOver, and state differentiation matter. Semantic system colors adapt to appearance/accessibility settings. Obtain system fonts through framework APIs.

Apply: establish a restrained native type scale; use system text roles and deliberate weight changes to distinguish conversation, metadata, section labels, and actions. Keep secondary text readable in light/dark/increased contrast. Indicate selection, failure, and recording state with more than hue. Keep actual message prose comfortably readable.

Limit: smaller type does not compensate for wasted geometry. Dynamic Type assumptions from iOS skills are not automatically macOS text-scaling support. Verify what Vale actually supports.

### 7. Apple — Keyboard access

Primary: [HIG Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards/). Visible changelog June 9, 2025; indexed full body and shortcut table verified.

Source: respect standard shortcuts and support keyboard-only interaction through Full Keyboard Access. Define a few useful app-specific shortcuts rather than repurposing familiar ones.

Apply: audit New Conversation, search/history selection, focus composer, send/newline behavior, cancel, settings, copy/paste, undo/redo, and sidebar visibility. Check focus indication and traversal, including disabled controls. Route menu commands to the active workspace and responder. Have actual keyboard/input evidence in addition to programmatic action invocation.

Limit: an accessibility label assertion does not prove keyboard traversal or VoiceOver usability. A harness calling an action directly does not prove the user can invoke it.

### 8. Apple — Onboarding and restoration

Primary: [HIG Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding) and [HIG Launching](https://developer.apple.com/design/human-interface-guidelines/launching). Onboarding changelog June 10, 2024; indexed bodies verified.

Source: teach through doing, keep prerequisites brief, defer nonessential setup, and request optional permissions in the context of the feature. Launching should restore meaningful prior state.

Apply: first run should make writing a first useful message obvious. Keep any required provider setup actionable and local to the blocked action; put voice/screen permissions behind explicit feature use. Returning users should resume the conversation and draft, not repeatedly encounter an invitation. Keep empty, unconfigured, loading, error, and ready states distinct.

Limit: a tutorial is not a substitute for a comprehensible interface. Specific provider requirements and consent rules come from Vale's product contract, not from generic HIG prose.

### 9. Apple — Use SwiftUI with AppKit

Primary: [WWDC22 session 10075](https://developer.apple.com/videos/play/wwdc2022/10075/), 2022. Apple transcript read. This is deliberately an older baseline-compatible interoperability reference.

Source: Shortcuts combines an AppKit split-view controller with a SwiftUI sidebar and embedded AppKit controls. The talk covers shared selection state, hosting, sizing, responder-chain participation, focus, and view reuse.

Apply: keep one clear owner for window geometry and shared selection. Use SwiftUI for suitable composition while preserving the AppKit text editor and window behavior where needed. Treat hosting boundaries as real layout/focus boundaries. Repair one surface at a time, with a runnable native prototype before a broad restyle.

Limit: this does not mean all AppKit or all SwiftUI is preferable. The 2026 sequel contains newer hosting APIs; do not substitute those without availability/toolchain checks.

### 10. Chris Eidhof — Representable state and AppKit text editing

Primary: [Working With UIViewRepresentable](https://chris.eidhof.nl/post/view-representable/), September 13, 2023; updated September 15, 2023. Original author article, including AppKit discussion; body and date verified.

Source: update underlying platform-view properties only when values differ; avoid feedback loops when platform events update SwiftUI state. The article examines timing/order issues and notes that AppKit needs particular care.

Apply: preserve a stable editor instance; do not continually replace text or selection during body/update cycles. Define ownership for draft text and selection; guard equal-value updates. Reproduce cursor jumps, selection collapse, event ordering, undo, and composition in an isolated editor prototype before integrating the composer redesign.

Limit: the author explicitly presents evolving patterns, not a blanket rule that every delegate event should be deferred. Copying asynchronous dispatch indiscriminately can introduce event-order bugs. Diagnose the actual update cycle.

### 11. Apple — Text input contracts

Primary: [NSTextInputClient](https://developer.apple.com/documentation/appkit/nstextinputclient) and [NSTextInputContext](https://developer.apple.com/documentation/appkit/nstextinputcontext). Current indexed API documentation verified.

Source: native text input involves marked text, selected ranges, replacement ranges, character geometry, input context, and command dispatch. `NSTextView` implements this contract; building a custom text view entails preserving it.

Apply: keep a standard native editor unless there is a measured need otherwise. Verify multiline editing, selection changes, paste, undo, keyboard commands, long drafts, and IME marked text. Avoid treating Return as Send while an input method is committing marked text. Make draft preservation survive session changes and relaunch.

Limit: the API contract motivates these checks; it does not prove Vale's existing wrapper is correct. Direct text assignment or fixture strings do not establish IME behavior or physical typing.

### 12. Apple — Measured performance

Primary: [Demystify SwiftUI performance, WWDC23 session 10160](https://developer.apple.com/videos/play/wwdc2023/10160/?time=0) and [Optimize SwiftUI performance with Instruments, WWDC25 session 306](https://developer.apple.com/videos/play/wwdc2025/306/). Apple transcripts verified.

Source: profile causes of work, view identity/dependencies, slow body/representable updates, and responsiveness. The newer instrument combines SwiftUI diagnostics with Time Profiler, hangs, and hitches; it requires a compatible toolchain/OS for the described traces.

Apply: exercise a long transcript, live response updates, sidebar search/selection, resizing, and typing while response state changes. Profile observed stalls; isolate frequently changing state to the smallest relevant subtree. Record trace/toolchain/OS and workload, not only an assertion count.

Limit: do not claim the Xcode 26 SwiftUI instrument exists on an older installed toolchain or macOS 14. Use compatible profiling tools when needed. Performance evidence and visual acceptance remain separate.

### 13. Paul Hudson — SwiftUI Pro skill source audit

Primary files read: [SKILL.md](https://raw.githubusercontent.com/twostraws/SwiftUI-Agent-Skill/main/swiftui-pro/SKILL.md), [design reference](https://raw.githubusercontent.com/twostraws/SwiftUI-Agent-Skill/main/swiftui-pro/references/design.md), [accessibility reference](https://raw.githubusercontent.com/twostraws/SwiftUI-Agent-Skill/main/swiftui-pro/references/accessibility.md). Current remote entrypoint identifies author Paul Hudson and version 2.0.0. No installation performed.

Useful: topical review routing, genuine-problem reporting, data flow, resizing, accessibility, efficiency, and shared design constants. It explicitly checks the project's deployment target and keeps it unchanged.

Apply: use a bounded code-quality reviewer after the native structure is chosen; request window resizing, data flow, accessibility, and editor identity rather than a vague “make production ready” pass. Review only relevant references.

Limit: the entrypoint also assumes newer Swift/Xcode/iOS defaults. Filter these through Vale's actual toolchain and macOS 14 target. A code-review skill does not provide art direction, screenshot acceptance, provider validation, or distribution proof.

### 14. Antoine van der Lee and Omar Elsayed — SwiftUI Expert skill source audit

Primary files read: [SKILL.md](https://raw.githubusercontent.com/AvdLee/SwiftUI-Agent-Skill/main/skills/swiftui-expert-skill/SKILL.md), [macOS window styling](https://raw.githubusercontent.com/AvdLee/SwiftUI-Agent-Skill/main/skills/swiftui-expert-skill/references/macos-window-styling.md), [macOS views](https://raw.githubusercontent.com/AvdLee/SwiftUI-Agent-Skill/main/skills/swiftui-expert-skill/references/macos-views.md). Original [repository](https://github.com/AvdLee/SwiftUI-Agent-Skill) identifies the authors. Current main inspected; no version pin or installation assumed.

Useful: small invalidation boundaries, state ownership first, native buttons/accessibility labels, availability checks, macOS-specific window/toolbar references, and trace-driven investigation. It makes Liquid Glass adoption conditional on an explicit request.

Apply: a targeted reviewer can audit the composer/state boundary and macOS toolbar ownership. Check each recommendation against Apple docs and the installed SDK before changing code.

Limit: current references span newer SDK 27 APIs and broad platform advice. Some categorical sidebar statements are simplifications; inspect the actual runtime behavior. Do not treat source popularity, a compatibility table, or generated skill output as acceptance evidence.

### 15. Anthropic frontend-design and Paul Bakaus Impeccable — design-process audit

Primary files read: Anthropic's [frontend-design SKILL.md](https://raw.githubusercontent.com/anthropics/skills/main/skills/frontend-design/SKILL.md); Impeccable's [SKILL.src.md](https://raw.githubusercontent.com/pbakaus/impeccable/main/skill/SKILL.src.md), [Operate guidance](https://raw.githubusercontent.com/pbakaus/impeccable/main/skill/reference/operate.md), and [critique workflow](https://raw.githubusercontent.com/pbakaus/impeccable/main/skill/reference/critique.md). Current main, inspected 2026-10-19; no installation performed.

Useful: Anthropic requires deliberate product-specific choices, real content, a compact design plan, and critique against the brief. Impeccable distinguishes task-oriented product UI from marketing surfaces: familiar patterns, restraint, tighter hierarchy, and visual verification at shipping sizes. Its critique workflow calls for independent assessments of one stable target.

Apply: use the design vocabulary and an independent critic on full-window images. Constrain the reviewer to native Mac affordances and the product's real tasks. Ask for specific defects, priorities, and acceptance criteria.

Limit: web-hero, font-personality, CSS/rem, browser detector, and iOS/Android references are not a Mac design specification. Do not import a display-font pairing, oversized hero, card grid, web framework, or browser preview as proof of a native result. A skill's default request to ask what to improve next does not override the owner's instruction to keep working.

## Full-window visual acceptance and capture feasibility

### Verified primary facts

1. [NSView.cacheDisplay(in:to:)](https://developer.apple.com/documentation/appkit/nsview/cachedisplay%28in%3Ato%3A%29) renders only the requested view region and descendants. Therefore a bitmap of `window.contentView` is content evidence; it does not establish the appearance of everything outside that subtree. [NSView.visibleRect](https://developer.apple.com/documentation/appkit/nsview/visiblerect) also does not prove on-screen visibility/occlusion.
2. [NSWindow.frame](https://developer.apple.com/documentation/appkit/nswindow/frame) includes the titlebar; [NSWindow.dataWithPDF(inside:)](https://developer.apple.com/documentation/appkit/nswindow/datawithpdf%28inside%3A%29) can render a window region through an in-process public API. Both must still be inspected for actual chrome/material fidelity; PDF and view rendering are not window-server capture.
3. Apple's [Advances in macOS Security, WWDC19 session 701](https://developer.apple.com/videos/play/wwdc2019/701/), especially 15:36–18:59, describes the historical exemption for a process capturing its own windows with Core Graphics. It distinguishes that from capturing another app or an entire display.
4. [CGWindowListCreateImage](https://developer.apple.com/documentation/coregraphics/cgwindowlistcreateimage?language=objc) is marked deprecated. The installed Apple SDK header was inspected on this host: `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/CoreGraphics.framework/Versions/A/Headers/CGWindow.h`, lines 223–224 and 271–274. Its availability macro marks this function introduced 10.5, deprecated 14.0, obsoleted 15.0. It is not a viable default for a new macOS 15 capture implementation.
5. [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit) is Apple's replacement, with permission requirements. [What's new in privacy, WWDC23 session 10053](https://developer.apple.com/videos/play/wwdc2023/10053/) explains how the system sharing picker can mediate selected content without separate full-screen permission. That involves a real user selection; it is not silent authorization for automated screenshots.

### Proposed evidence tiers for Vale (our workflow, not an Apple certification)

| Tier | Feasible method | What it establishes | What it does not establish |
|---|---|---|---|
| Component | SwiftUI/native view rendering with representative fixture data | Layout, typography, state content inside that subtree | Window chrome, launch geometry, input, compositor |
| Whole window in-process | Launch the app's real `NSWindow` with isolated test data; render a complete window region or enclosing frame-view hierarchy; inspect traffic lights and toolbar in the output | Native hierarchy, frame/content relationship, settled geometry, many chrome defects | Exact compositor materials/shadows/occlusion, physical typing or clicks |
| Own-window window-server capture | On an actually supported OS/toolchain, capture only the calling process's known test window; verify dimensions and content; stop if unavailable | Pixels supplied by the window server for that own window | Hardware/input correctness or unrelated journeys |
| User journey | Actual focus/typing/selection/resize/relaunch with available desktop input; scoped recording if authorized | The concrete exercised interaction on that host | Other OS versions/hardware, release delivery |

For whole-window rasterization, walking from the actual content view to an enclosing frame view may be a useful harness technique, but relying on a private frame-class name or assuming its shape is not a public AppKit contract. Validate coverage from actual standard-window-button ancestry and frame bounds, then inspect the image. Label the result “in-process full-window render.” Public `NSWindow.dataWithPDF` is another candidate, not a promise of faithful composited materials. A blank, transparent, clipped, or chrome-free result must fail the coverage check.

The app-owned screenshot harness must run inside the app process and use only its isolated data/window IDs. A separate shell process does not become the owning app merely because it knows the window number. Do not fall back from an own-window request to full-screen capture; do not enumerate private titles, capture another app, reset TCC, or request new recording access to make a visual fixture pass. On macOS 15, capability-test legitimate current APIs; if no authorized compositor path exists, record that gap rather than relabel a raster as a screenshot.

The coordinator reports that native CUA surfaces are unavailable on this host. That is a current capability boundary, not a reason to drop the checks. Complete native in-process verification, prepare the remaining genuine-input journey, and keep compositor/physical-input acceptance explicitly open until evidence exists. Never request owner approval to perform work already authorized; only an actually missing capability/authority should become an owner action.

## Recommended pipeline for the coordinator to critique and refine

1. Freeze the rejected build and evidence. Record the exact source revision, executable, launch mode, display scale, OS, window frame, and whether each image is content, frame raster, or compositor capture. Keep the rejection open.
2. Write a one-page native task brief: primary job, normal content, first useful action, required capabilities, prohibited side effects, supported OS, and high-priority owner complaints. Rewrite the rejected design contract around the new native direction instead of treating its old numbers as requirements.
3. Build two or three small native window prototypes using the actual `NSWindow`, toolbar, sidebar, and stable editor. Vary structural choices meaningfully; avoid three color variants. Populate empty, ordinary, long, loading, and failure content. Do not rewrite service/data code to explore composition.
4. Compare complete windows against current native Mac references using the same approximate window size and content class. Resolve chrome, task hierarchy, density, and editor behavior before detail polish. Document the chosen direction and rejected alternatives briefly.
5. Implement in bounded slices: window/toolbar ownership, history/sidebar, conversation typography, composer/editor, contextual states. Keep one coordinator responsible for integration; delegate nonoverlapping implementation and an independent reviewer.
6. Run appropriate functional checks, then inspect the integrated native window with its real chrome. Fix all high-priority visible issues before broadening the checklist. Review normal/minimum/wide/restored states, light/dark, long titles, and populated history. Snapshot dimensions alone are not acceptance.
7. Exercise text and keyboard journeys explicitly. IME, selection, undo, draft persistence, cancellation, focus, and relaunch need evidence appropriate to the claim. Separate programmatic events from physical input.
8. Use a bounded independent critic who did not make the design to inspect the research, proposed pipeline, and representative full-window evidence. Require a clear rejection if visual/native acceptance is missing. Send defects back for repair and integrate them before final verification.
9. Measure actual performance where a realistic workload shows concern. Use compatible Instruments data; keep performance, accessibility, functional, visual, live-service, and hardware evidence separate.
10. Deliver through the authorized surface only after acceptance. For direct Mac distribution, [Apple's notarization guidance](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution?changes=_9) separates Developer ID signing/notarization from visual and product quality. Then verify the downloaded artifact, installation/update, and relaunch when delivery is in scope. Source edits and passing fixture counts do not close these steps.

## Access and evidence limitations

- Several Apple HIG/API pages returned JavaScript-only HTML to direct opens; their Apple-domain indexed bodies supplied the cited guidance. The advertised Markdown link and attempted official Markdown endpoints returned tool errors. No claim is based on hidden content or a successful interactive inspection of those pages.
- Raw author GitHub files were accessible. An obsolete guessed AvdLee path and an obsolete guessed Impeccable path failed; current canonical repository paths were then located and read. No skill was run or installed.
- This research did not independently inspect the owner's image, launch Vale, exercise hardware, profile performance, test a compositor-capture path, or verify a release. Screenshot-specific defects above come from the coordinator's bounded assignment and must be validated against the actual image/runtime.
- A public source describes the author's recommendation or Apple's API contract. Our Vale-specific synthesis remains a proposed workflow for the independent critic, not a claim that any authority certified this product.

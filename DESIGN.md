# Vale design

## Direction

A compact native Mac conversation workspace. Writing and reading are primary; the app should feel ordinary and precise beside other Mac apps. The owner rejected the published1.3.1 single-window composition: double chrome, empty hero, oversized editor and competing first-run actions are anti-references. Earlier visual approval is reopened. Keep the ribbon-V artwork, one workspace and all PRODUCT capabilities.

Design read: a recurring native personal tool, Operate mode, restrained system typography and familiar controls. Follow [native pipeline](docs/design/native-product-pipeline.md), grounded in written research and independent critique. Web landing-page recipes and arbitrary design dials are not Mac acceptance.

## References

The owner's Refero Apple, Linear, Cursor, Vercel, Intercom, Superhuman and Dala links guide quiet surfaces, precise alignment and restrained action hierarchy. Refero measurements/recommendations are interpreted and HTML is reconstructed; these are not source components or native specifications. The uploaded desktop-product images add compact navigation, aligned headers and adjacent muted context. Uiarc is inspiration, not a dependency or a claim every demo was viewed. Apple conventions and native evidence govern implementation. No marketing heroes, display scale, CSS, imported fonts, decorative dashboard furniture or theatrical motion.

## Window and layout

One actual NSWindow with ordinary traffic lights, drag/resize/full-screen behavior, accessible title and a real compact NSToolbar owned by AppKit. No blank top spacer or second custom toolbar in content. Standard sidebar/new-chat/detail commands and a useful conversation title orient the task without large repeated branding. Toolbar commands remain accessible through native menus and narrowing behavior.

Start at existing1040×740 content and740×560 minimum; inspect actual full-frame geometry. History is a conventional quiet collection, initially around200pt with compact rows that accommodate meaningful text. Search is compact. Omit the pristine untitled active empty chat as a redundant retrieval row; preserve real unsent drafts/files. Settings remains a quiet persistent destination.

Conversation prose uses a comfortable maximum around680pt and normal24pt gutters, naturally less in narrow windows. Details appear alongside only when useful conversation width remains; otherwise replace chat with Back. Test combined sidebar/details layouts instead of inheriting the rejected860pt threshold blindly.

The same mounted composer stays at the bottom across empty/populated and secondary-route states. Start near one or two text lines and grow for actual content before scrolling. No empty slab or centered first-run hero. Native NSTextView retains focus, selection, marked text, undo and draft ownership. Empty content is one short useful invitation near the task. Remove permanent Ready-to-type and idle voice/status footer modules.

## State hierarchy

- Disconnected: local draft/attachments work; one Connect ChatGPT to send action replaces unavailable Send at the composer. Explain the dependency once.
- Connecting/error: local progress, Cancel or Retry and precise error; preserve draft/files. Browser return never sends automatically.
- Connected empty: focused editor and normal Send, no setup block. Restored work resumes directly.
- Busy/retry: visible Stop; continued drafting; failures preserve original message/files/request identity.
- Saved Web on/off stays visible and accessible. Opt-in does not imply hosted-tool success.
- Group Talk/Conversation under a recognizable voice entry. Starting/listening/speaking/conversation has precise state and immediate Stop. Active selected-window context names target and retains Stop sharing. No automatic microphone/screen consent.

Learn, hints, walkthrough, guide, timer, notes/files, rename/export/Forget, read-aloud and all retained features have recognizable contextual/menu routes. Covered routes retain a stop for active work. Back restores the originating task. Native file/save/permission/updater dialogs and transient click-through pointing feedback keep their documented limited roles.

## Native grammar

SF via framework APIs and SF Symbols. Initial defaults: controls13, metadata12, message prose15, short empty heading20–22. Product hypotheses, not fixed HIG mandates. Remove excess padding before shrinking type. Long titles wrap/truncate purposefully with full accessible values. Tiny text is not density.

Use semantic system colors, native selection/accent and familiar control feedback. Custom starting surfaces retain warm light and charcoal dark: canvas#f7f6f2/#18191d, navigation#eeede8/#141519, input#ffffff/#22242a, text#252629/#f0f0ed, secondary#67686b/#b0b1b8, divider#ddddd6/#363840. No stacked shadow/border furniture or card around every action. Custom shapes6–10pt, native window/control shapes where provided; spacing4/8/12/16/24.

Controls need accurate disabled/pressed/hover/keyboard focus without layout movement. Accent is functional. Focus belongs only to the actually focused visible editor. Warning/recording states use words/symbols as well as color. Verify light/dark/increased contrast and native caret/text colors. Reduce Motion removes optional transitions; Reduce Transparency gives solid legible surfaces. No idle animation or launch choreography.

## Acceptance

Inspect complete native windows at minimum/default/wide and both appearances with realistic content/title/history and important combinations. Content-only raster cannot establish chrome; full-frame in-process render is explicitly labeled and does not establish compositor or physical input. Genuine provider/hardware/feed/publication/laptop installation are separate. A fresh critic compares the integrated result with the owner rejection and actual task, and may reject composition. Follow the bounded native pipeline and Factory repair rounds.

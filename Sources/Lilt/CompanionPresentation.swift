import AppKit

/// The physical panel always keeps its top-right anchor as its content changes.
/// Secondary tasks borrow this panel and return to the same mounted composer.
@MainActor enum CompanionPresentation {
    static let idleSize = NSSize(width: 300, height: 45)
    static let askWidth: CGFloat = 320
    static let replyWidth: CGFloat = 350
    static let maximumReplyHeight: CGFloat = 320
    static let headerHeight: CGFloat = 40
    static let toolsHeight: CGFloat = 43
    static let composerBottomInset: CGFloat = 8

    static func connectionMessage(for account: ChatGPTAccount) -> String {
        account.isSigningIn ? "Finish connecting in your browser." : account.needsIdentityValidation ? "Verify your ChatGPT connection to send." : "Connect ChatGPT to send. Your draft stays here."
    }

    private static func connectionHeight(for model: AppModel) -> CGFloat {
        let account = model.provider.account
        guard !account.permitsPlanUsage else { return 0 }
        let width = (hasReply(for: model) ? replyWidth : askWidth) - 34
        let font = NSFont.systemFont(ofSize: 11)
        let line = ceil(NSLayoutManager().defaultLineHeight(for: font))
        func textHeight(_ text: String) -> CGFloat {
            max(line, ceil((text as NSString).boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]).height))
        }
        // Match the visible sentence, optional three-line error and padding;
        // a one-line notice must not reserve a multirow empty region.
        return textHeight(connectionMessage(for: account)) + 10 +
            (account.error.map { 4 + min(line * 3, textHeight($0)) } ?? 0)
    }

    static func targetSize(for model: AppModel) -> NSSize {
        if model.workspaceRoute == .settings { return NSSize(width: 380, height: 520) }
        if model.compactHistoryVisible { return NSSize(width: 400, height: 500) }
        if model.inspector != nil { return NSSize(width: 460, height: 540) }
        guard model.companionExpanded else { return idleSize }
        let hasReply = hasReply(for: model)
        let height = nonReplyHeight(for: model) + (hasReply ? replyViewportHeight(for: model) + 8 : 0)
        return NSSize(width: hasReply ? replyWidth : askWidth, height: min(650, height))
    }
    static func hasReply(for model: AppModel) -> Bool {
        model.active?.messages.isEmpty == false || model.busy || model.active?.guide != nil
    }
    static func replyViewportHeight(for model: AppModel, availableHeight: CGFloat = 650) -> CGFloat {
        let wanted = min(maximumReplyHeight, max(50, model.companionReplyHeight))
        return max(40, min(wanted, min(650, availableHeight) - nonReplyHeight(for: model) - 8))
    }
    private static func nonReplyHeight(for model: AppModel) -> CGFloat {
        let inlineReply = hasReply(for: model) && model.provider.account.permitsPlanUsage
        let editorHeight = max(inlineReply ? 36 : CompanionEditorMetrics.expandedHeight, min(110, model.companionInputHeight))
        var height: CGFloat = headerHeight + editorHeight + composerBottomInset + (inlineReply ? 0 : toolsHeight)
        if model.context.hasSelection { height += 38 }
        else if model.workContext.enabled { height += 35 }
        if !model.pendingFiles.isEmpty { height += 36 }
        if model.importStatus != nil { height += 27 }
        if model.error != nil { height += 90 }
        if model.shortcutWarning != nil { height += 40 }
        if model.canRetry { height += 28 }
        if model.paused { height += 27 }
        if model.voice.starting || model.voice.listening || model.voice.speaking || model.conversation { height += 29 }
        height += connectionHeight(for: model)
        if model.active?.mode == .learn { height += 30 }
        return height
    }
}

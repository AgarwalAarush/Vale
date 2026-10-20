import AppKit

/// The physical panel always keeps its top-right anchor as its content changes.
/// Secondary tasks borrow this panel and return to the same mounted composer.
@MainActor enum CompanionPresentation {
    static let idleSize = NSSize(width: 300, height: 45)
    static let askWidth: CGFloat = 320
    static let replyWidth: CGFloat = 350
    static let maximumReplyHeight: CGFloat = 320

    static func targetSize(for model: AppModel) -> NSSize {
        if model.workspaceRoute == .settings { return NSSize(width: 520, height: 610) }
        if model.compactHistoryVisible { return NSSize(width: 400, height: 500) }
        if model.inspector != nil { return NSSize(width: 460, height: 540) }
        guard model.companionExpanded else { return idleSize }
        let hasReply = hasReply(for: model)
        let height = nonReplyHeight(for: model) + (hasReply ? replyViewportHeight(for: model) + 8 : 0)
        return NSSize(width: hasReply ? replyWidth : askWidth, height: min(650, max(188, height)))
    }
    static func hasReply(for model: AppModel) -> Bool {
        model.active?.messages.isEmpty == false || model.busy || model.active?.guide != nil
    }
    static func replyViewportHeight(for model: AppModel, availableHeight: CGFloat = 650) -> CGFloat {
        let wanted = min(maximumReplyHeight, max(50, model.companionReplyHeight))
        return max(40, min(wanted, min(650, availableHeight) - nonReplyHeight(for: model) - 8))
    }
    private static func nonReplyHeight(for model: AppModel) -> CGFloat {
        var height: CGFloat = 43 + max(hasReply(for: model) ? 36 : 70, min(110, model.companionInputHeight)) + 51
        if model.context.hasSelection { height += 38 }
        if !model.pendingFiles.isEmpty { height += 36 }
        if model.importing { height += 27 }
        if model.error != nil { height += 90 }
        if model.shortcutWarning != nil { height += 40 }
        if model.canRetry { height += 28 }
        if model.paused { height += 27 }
        if model.voice.starting || model.voice.listening || model.voice.speaking || model.conversation { height += 29 }
        if !model.provider.account.permitsPlanUsage { height += model.provider.account.error == nil ? 64 : 92 }
        if model.active?.mode == .learn { height += 30 }
        return height
    }
}

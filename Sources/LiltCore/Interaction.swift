import Foundation
import CoreGraphics

public struct GuidePlan: Codable,Equatable,Sendable {
    public var title:String
    public var steps:[String]
    public init(title:String,steps:[String]){self.title=title;self.steps=steps}
    public var isValid:Bool{
        let name=title.trimmingCharacters(in:.whitespacesAndNewlines)
        return !name.isEmpty && name.count<=400 && (2...8).contains(steps.count) && steps.allSatisfy{let step=$0.trimmingCharacters(in:.whitespacesAndNewlines);return !step.isEmpty && step.count<=4_000}
    }
}
public struct GuideProgress:Codable,Equatable,Sendable {
    public var plan:GuidePlan
    public var index:Int
    public init(plan:GuidePlan,index:Int=0){self.plan=plan;self.index=max(0,min(index,plan.steps.count-1))}
    private enum CodingKeys:String,CodingKey{case plan,index}
    public init(from decoder:Decoder)throws{let c=try decoder.container(keyedBy:CodingKeys.self);self.init(plan:try c.decode(GuidePlan.self,forKey:.plan),index:try c.decode(Int.self,forKey:.index))}
    public var current:String{plan.steps.indices.contains(index) ? plan.steps[index] : ""}
    /// The whole plan, for history and search. The coach card still shows only the current step.
    public var savedSteps:String{
        let lines=plan.steps.enumerated().map{offset,step in "\(offset+1). \(step)"+(offset==index ? " (current)" : "")}
        return ([plan.title]+lines).joined(separator:"\n")
    }
}
public struct ConversationWindow {
    public let text:String
    public let omitted:Int
    public let excerpted:Bool
    public var limited:Bool{omitted>0 || excerpted}
    public init(messages:[Message]){
        var selected:[String]=[];var budget=48_000;var clipped=false
        for message in messages.suffix(18).reversed(){
            guard budget>0 else{break}
            let count=min(8_000,budget);let piece=MessageExcerpt.keepingEnds(message.text,limit:count)
            let truncated=piece.truncated;clipped = clipped || truncated
            let hidden=message.highlightUnavailable ? "\n[Highlight unavailable. The place could not be shown on the selected window.]" : ""
            let stale=message.screenChanged ? "\n[The shared window changed while this answer was prepared. It may not match the current window.]" : ""
            selected.append("\(message.role == "user" ? "USER" : "ASSISTANT"): \(piece.text)" + (truncated ? "\n[Message excerpt; remaining text omitted.]" : "") + hidden + stale);budget-=piece.text.count
        }
        omitted=messages.count-selected.count;excerpted=clipped;text=selected.reversed().joined(separator:"\n\n")
    }
}
public struct ScreenEvidence:Equatable {
    public var generation:UUID
    public var windowID:UInt32?
    public var frame:CGRect?
    public var fingerprint:Data
    public var capturedAt:Date
    public init(generation:UUID,windowID:UInt32?,frame:CGRect?,fingerprint:Data,capturedAt:Date){self.generation=generation;self.windowID=windowID;self.frame=frame;self.fingerprint=fingerprint;self.capturedAt=capturedAt}
    public func reflectsSameView(_ current:Self,now:Date=Date())->Bool{generation==current.generation && windowID==current.windowID && frame==current.frame && fingerprint==current.fingerprint && now.timeIntervalSince(current.capturedAt)>=0 && now.timeIntervalSince(current.capturedAt)<=5}
    public func matches(_ current:Self,now:Date=Date())->Bool{
        guard let bounds=frame,bounds.origin.x.isFinite,bounds.origin.y.isFinite,bounds.width.isFinite,bounds.height.isFinite,bounds.width>1,bounds.height>1 else{return false}
        return generation==current.generation && windowID != nil && windowID==current.windowID && frame != nil && frame==current.frame && fingerprint==current.fingerprint && now.timeIntervalSince(capturedAt)>=0 && now.timeIntervalSince(capturedAt)<=45 && now.timeIntervalSince(current.capturedAt)>=0 && now.timeIntervalSince(current.capturedAt)<=5
    }
}

public struct PointWindow {
    public var id:UInt32
    public var bounds:CGRect?
    public var opacity:Double
    public init(id:UInt32,bounds:CGRect?,opacity:Double=1){self.id=id;self.bounds=bounds;self.opacity=opacity}
}
public enum PointVisibility {
    public static func isVisible(targetID:UInt32,box:CGRect,frontToBack:[PointWindow])->Bool{
        guard box.origin.x.isFinite,box.origin.y.isFinite,box.width.isFinite,box.height.isFinite,box.width>0,box.height>0 else{return false}
        for window in frontToBack{
            if window.id==targetID{
                guard window.opacity.isFinite,window.opacity>0.01,let bounds=window.bounds,bounds.origin.x.isFinite,bounds.origin.y.isFinite,bounds.width.isFinite,bounds.height.isFinite,bounds.width>1,bounds.height>1 else{return false}
                return bounds.contains(box)
            }
            guard window.opacity.isFinite else{return false}
            if window.opacity<=0.01{continue}
            guard let bounds=window.bounds else{return false}
            if bounds.intersects(box){return false}
        }
        return false
    }
}

public enum GuideStart {
    public static func needsConfirmation(draft: String, attachmentCount: Int) -> Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachmentCount > 0
    }
}

public enum ConversationOptIn {
    public static func startsListeningNow(busy: Bool, speaking: Bool) -> Bool { !busy && !speaking }
}

public enum ReplyRetry {
    public static func isAvailable(busy: Bool, hasFailedQuestion: Bool, lastRole: String?) -> Bool {
        !busy && hasFailedQuestion && lastRole == "user"
    }
}

public enum ModeChange {
    public static let keepsInFlightReply = true
}

public enum ComposerFocus {
    public static let attempts = 8
    public static func shouldRetry(found: Bool, attemptsLeft: Int) -> Bool {
        !found && attemptsLeft > 0
    }
    /// After a question leaves the field, the keyboard returns there.
    public static func returns(afterSending sent: Bool) -> Bool { sent }
}

public enum TranscriptReveal {
    public static let showsStartOfNewestMessage = true
}

public enum SharedWindowLabel {
    public static func text(windowTitle: String?, applicationName: String?) -> String {
        let title = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !title.isEmpty { return String(title.prefix(120)) }
        let app = applicationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !app.isEmpty { return "\(app) window" }
        return "Selected window"
    }
}

public enum CommandPrompt {
    public static func keepsComposerDraft(sendsOwnPrompt: Bool) -> Bool { sendsOwnPrompt }
}

public enum CapsuleFailure {
    public static let label = "Couldn't answer"
    public static func text(hasError: Bool) -> String? { hasError ? label : nil }
}

public enum ShortcutNotice {
    public static func text(_ warning: String?) -> String? {
        guard let warning else { return nil }
        let trimmed = warning.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum GuideStepText {
    public static func visible(_ step: String) -> String { step }
}

public struct SharedWindowSelection: Equatable, Sendable {
    public var id: UInt32
    public var title: String
    public var live: Bool
    public init(id: UInt32, title: String, live: Bool) {
        self.id=id; self.title=title; self.live=live
    }
}

public enum SharingPickerOutcome: Equatable, Sendable {
    case cancelled
    case failedToOpen
    case chose(SharedWindowSelection)
}

public enum SharingPicker {
    public static func selection(after outcome: SharingPickerOutcome, keeping current: SharedWindowSelection?) -> SharedWindowSelection? {
        switch outcome {
        case .cancelled, .failedToOpen: return current
        case .chose(let chosen): return chosen
        }
    }
    public static func failureMessage(keeping selection: SharedWindowSelection?) -> String {
        selection == nil
            ? "Couldn’t open window sharing. Keep typing or attach an image."
            : "Couldn’t open window sharing. The window you already chose is still shared."
    }
}

public enum PointHighlight {
    public static func shouldClear(windowUnchanged: Bool, visible: Bool) -> Bool {
        !windowUnchanged || !visible
    }
}

public enum MessageExcerpt {
    public static func keepingEnds(_ text: String, limit: Int) -> (text: String, truncated: Bool) {
        guard limit > 1 else { return (String(text.prefix(max(0, limit))), text.count > limit) }
        guard text.count > limit else { return (text, false) }
        let tailCount = limit / 2
        let headCount = limit - tailCount - 1
        return (String(text.prefix(headCount)) + "\n" + String(text.suffix(tailCount)), true)
    }
}

public enum CaptureAge {
    public static func shows(live: Bool, hasCapture: Bool) -> Bool { live && hasCapture }
}

public struct DisplayFrame: Equatable, Sendable {
    public var x: CGFloat
    public var y: CGFloat
    public var width: CGFloat
    public var height: CGFloat
    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x=x; self.y=y; self.width=width; self.height=height
    }
}

public enum HighlightPlacement {
    /// The main display is the one that contains the AppKit origin. Its height flips CGWindow top-left bounds.
    public static func primaryHeight(_ frames: [DisplayFrame]) -> CGFloat? {
        frames.first { $0.x <= 0 && $0.y <= 0 && $0.x + $0.width > 0 && $0.y + $0.height > 0 }?.height
    }
    public static func appKitOriginY(cgMinY: CGFloat, cgHeight: CGFloat, primaryHeight: CGFloat) -> CGFloat {
        primaryHeight - cgMinY - cgHeight
    }
}

public struct DisplayRect: Equatable, Sendable {
    public var x: CGFloat
    public var y: CGFloat
    public var width: CGFloat
    public var height: CGFloat
    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x=x; self.y=y; self.width=width; self.height=height
    }
}

public enum WindowPlacement {
    /// A restored history window is on screen when a meaningful part of it intersects a display.
    public static func isVisible(_ window: DisplayRect, on screens: [DisplayRect]) -> Bool {
        if screens.isEmpty { return true }
        return screens.contains { screen in
            let overlapW=min(window.x+window.width, screen.x+screen.width)-max(window.x, screen.x)
            let overlapH=min(window.y+window.height, screen.y+screen.height)-max(window.y, screen.y)
            return overlapW>=80 && overlapH>=80
        }
    }
}

public enum PreviewRoom {
    public enum Kind: Equatable { case file, screen }
    /// Older shared-window preview to close before opening another. An open file stays.
    public static func indexToClose(existing: [Kind], adding: Kind, limit: Int = 3) -> Int? {
        guard adding == .screen, existing.count >= limit else { return nil }
        return existing.firstIndex(of: .screen)
    }
}

public enum GuideRequest {
    /// A typed request for steps is explicit, the same as the guide button.
    public static func explicit(_ question: String) -> Bool {
        let q=question.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        return q.contains("step by step") || q.contains("step-by-step") || q.contains("guide me")
    }
}

public enum GuideStep {
    /// The saved step stays put when the question does not start.
    public static func indexToSave(current: Int, requested: Int, questionStarts: Bool) -> Int {
        questionStarts ? requested : current
    }
}

public enum GuideInstall {
    /// A plan is saved only for the guide that is still current, and only when the window has not changed.
    public static func shouldInstall(requested: Bool, windowChanged: Bool, stillCurrent: Bool) -> Bool {
        requested && !windowChanged && stillCurrent
    }
}

public enum PointRequest {
    public static let prompt = "Point out the relevant part of the shared window, with one short explanation."
    public static func wasPointing(_ question: String) -> Bool { question == prompt }
}

public enum ReadableLine {
    /// Lets a long unbroken line wrap. Every original character stays, in order.
    public static func display(_ text: String, limit: Int = 40) -> String {
        guard limit > 0 else { return text }
        var result = ""
        var token = ""
        func flush() {
            if token.contains("://") || token.count <= limit {
                result += token
            } else {
                var count = 0
                for character in token {
                    if count == limit {
                        result.append("\u{200B}")
                        count = 0
                    }
                    result.append(character)
                    count += 1
                }
            }
            token = ""
        }
        for character in text {
            if character.isWhitespace {
                flush()
                result.append(character)
            } else {
                token.append(character)
            }
        }
        flush()
        return result
    }
}

public enum DraftEcho {
    /// The composer reports its own text again after dictation writes the draft. That is not typing.
    public static func isTyping(_ edited: String, stored: String) -> Bool {
        edited != stored
    }
}

public enum DroppedLink {
    /// A web address dropped on the coach. File URLs stay on the file import path.
    public static func text(from urls: [URL]) -> String? {
        let links=urls.compactMap{url->String? in
            guard !url.isFileURL, let scheme=url.scheme?.lowercased(), scheme=="http" || scheme=="https" else { return nil }
            let text=url.absoluteString
            return text.isEmpty ? nil : text
        }
        guard !links.isEmpty else { return nil }
        return links.joined(separator: "\n")
    }
    /// The address is added to what is already written. It does not replace it.
    public static func inserted(into draft: String, links: String) -> String {
        if draft.isEmpty { return links }
        if draft.hasSuffix("\n") { return draft + links }
        return draft + "\n" + links
    }
}

public enum DraftCaret {
    /// When the caret was at the end of the previous draft, keep it at the end after that draft is shown again.
    public static func location(previousUTF16: Int, nextUTF16: Int, caret: Int) -> Int {
        let next = max(nextUTF16, 0)
        if caret >= max(previousUTF16, 0) { return next }
        return min(max(caret, 0), next)
    }
}

public enum CaptureSize {
    /// A capture pixel size must be a positive even number. An odd size is refused and the window never arrives.
    public static func even(_ length: Double) -> Int {
        guard length.isFinite, length > 0 else { return 2 }
        let raw = max(2, Int(length))
        return raw.isMultiple(of: 2) ? raw : raw - 1
    }
}

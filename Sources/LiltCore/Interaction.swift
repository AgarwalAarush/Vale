import Foundation
import CoreGraphics

/// Voice opt-in must not discard an answer that is already on the way.
public enum ConversationOptIn {
    public static func startsListeningNow(busy: Bool, speaking: Bool) -> Bool { !busy && !speaking }
}

public struct GuidePlan: Codable,Equatable,Sendable {
    public var title:String
    public var steps:[String]
    public init(title:String,steps:[String]){self.title=title;self.steps=steps}
    public var isValid:Bool{!title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && title.count<=120 && (2...8).contains(steps.count) && steps.allSatisfy{!$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && $0.count<=300}}
}
public struct GuideProgress:Codable,Equatable,Sendable {
    public var plan:GuidePlan
    public var index:Int
    public init(plan:GuidePlan,index:Int=0){self.plan=plan;self.index=max(0,min(index,plan.steps.count-1))}
    private enum CodingKeys:String,CodingKey{case plan,index}
    public init(from decoder:Decoder)throws{let c=try decoder.container(keyedBy:CodingKeys.self);self.init(plan:try c.decode(GuidePlan.self,forKey:.plan),index:try c.decode(Int.self,forKey:.index))}
    public var current:String{plan.steps.indices.contains(index) ? plan.steps[index] : ""}
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
            let count=min(8_000,budget);let fragment=String(message.text.prefix(count))
            let truncated=fragment.count<message.text.count;clipped = clipped || truncated
            selected.append("\(message.role == "user" ? "USER" : "ASSISTANT"): \(fragment)" + (truncated ? "\n[Message excerpt; remaining text omitted.]" : ""));budget-=fragment.count
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

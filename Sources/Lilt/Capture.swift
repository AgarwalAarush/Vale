import AppKit
@preconcurrency import ScreenCaptureKit
import CryptoKit
import LiltCore

struct ContextSnapshot {
    var data:Data
    var image:NSImage
    var windowID:CGWindowID?
    var frame:CGRect?
    var generation:UUID
    var capturedAt:Date
    var evidence:ScreenEvidence{ScreenEvidence(generation:generation,windowID:windowID,frame:frame,fingerprint:Data(SHA256.hash(data:data)),capturedAt:capturedAt)}
}

@MainActor private final class CaptureDeadline {
    var continuation:CheckedContinuation<ContextSnapshot,Error>?
    var worker:Task<Void,Never>?
    var timeout:Task<Void,Never>?
    func finish(_ result:Result<ContextSnapshot,Error>){
        guard let continuation else{return};self.continuation=nil;worker?.cancel();timeout?.cancel();worker=nil;timeout=nil;continuation.resume(with:result)
    }
}
@MainActor private func boundedCapture(seconds:Double,operation:@escaping @MainActor ()async throws->ContextSnapshot)async throws->ContextSnapshot{
    let gate=CaptureDeadline()
    return try await withTaskCancellationHandler(operation:{
        try await withCheckedThrowingContinuation{continuation in
            gate.continuation=continuation
            gate.worker=Task{do{try Task.checkCancellation();gate.finish(.success(try await operation()))}catch{gate.finish(.failure(error))}}
            gate.timeout=Task{try? await Task.sleep(nanoseconds:UInt64(seconds*1_000_000_000));guard !Task.isCancelled else{return};gate.finish(.failure(AppError("The selected window took too long to respond. Stop sharing and choose it again.")))}
        }
    },onCancel:{Task{@MainActor in gate.finish(.failure(CancellationError()))}})
}

@MainActor final class WindowContext:NSObject,ObservableObject,SCContentSharingPickerObserver {
    @Published private(set) var title:String?
    @Published private(set) var lastCapture:Date?
    @Published private(set) var live=false
    @Published private(set) var capturing=false
    @Published private(set) var latest:ContextSnapshot?
    private(set) var filter:SCContentFilter?
    private(set) var generation=UUID()
    private(set) var windowID:CGWindowID?
    private var liveTask:Task<Void,Never>?
    private var inFlight:Task<ContextSnapshot,Error>?
    private var captureID=UUID()
    private var requestedLive=false
    private var fixtureSource:(()async throws->ContextSnapshot)?
    private var fixtureFrame:CGRect?
    private var captureTimeout=6.0
    private var fixtureOnScreen=true
    private var fixturePointVisible=true
    var changed:(()->Void)?
    var failed:((String)->Void)?
    var hasSelection:Bool{filter != nil || fixtureSource != nil}
    private var sharedSelection:SharedWindowSelection?{hasSelection ? SharedWindowSelection(id:windowID ?? 0,title:title ?? "Selected window",live:live) : nil}
    var preview:NSImage?{latest?.image}
    override init(){super.init();SCContentSharingPicker.shared.add(self)}
    func choose(live:Bool=false){
        requestedLive=live
        var config=SCContentSharingPickerConfiguration();config.allowedPickerModes=[.singleWindow]
        config.excludedBundleIDs=[Bundle.main.bundleIdentifier ?? "local.lilt.companion"]
        SCContentSharingPicker.shared.defaultConfiguration=config;SCContentSharingPicker.shared.isActive=true;SCContentSharingPicker.shared.present()
    }
    func startLive(){
        guard hasSelection else{choose(live:true);return}
        stopLive();live=true
        liveTask=Task{[weak self] in
            while !Task.isCancelled{
                guard let self,self.live,self.hasSelection else{return}
                do{_=try await self.capture()}catch{
                    guard !Task.isCancelled,self.live else{return}
                    self.stop();self.failed?("Live sharing stopped because the selected window is unavailable. Choose it again; your chat is saved.");return
                }
                try? await Task.sleep(nanoseconds:2_000_000_000)
            }
        }
    }
    func stopLive(){liveTask?.cancel();liveTask=nil;live=false;latest=nil;lastCapture=nil}
    /// Stop local work without forgetting the explicitly chosen window. A late
    /// capture can no longer satisfy a question or recreate a preview/overlay.
    func suspendCapture(){
        stopLive();inFlight?.cancel();inFlight=nil;captureID=UUID();generation=UUID();capturing=false;requestedLive=false
        SCContentSharingPicker.shared.isActive=false
    }
    func stop(){
        suspendCapture()
        filter=nil;fixtureSource=nil;fixtureFrame=nil;captureTimeout=6;title=nil;windowID=nil
        changed?()
    }
    nonisolated func contentSharingPicker(_ picker:SCContentSharingPicker,didCancelFor stream:SCStream?){DispatchQueue.main.async{self.requestedLive=false}}
    nonisolated func contentSharingPickerStartDidFailWithError(_ error:Error){
        DispatchQueue.main.async{
            let kept=SharingPicker.selection(after:.failedToOpen,keeping:self.sharedSelection)
            self.requestedLive=false
            SCContentSharingPicker.shared.isActive=false
            self.failed?(SharingPicker.failureMessage(keeping:kept))
        }
    }
    nonisolated func contentSharingPicker(_ picker:SCContentSharingPicker,didUpdateWith filter:SCContentFilter,for stream:SCStream?){
        DispatchQueue.main.async{
            let wantsLive=self.requestedLive
            self.stopLive();self.inFlight?.cancel();self.inFlight=nil;self.captureID=UUID();self.capturing=false
            self.filter=filter;self.generation=UUID();self.latest=nil;self.lastCapture=nil
            if #available(macOS 15.2,*),let window=filter.includedWindows.first{self.windowID=window.windowID;self.title=SharedWindowLabel.text(windowTitle:window.title,applicationName:window.owningApplication?.applicationName)}
            else{self.windowID=nil;self.title="Selected window"}
            self.requestedLive=false;self.changed?();if wantsLive{self.startLive()}
        }
    }
    func capture()async throws->ContextSnapshot{
        guard hasSelection else{throw AppError("Choose a window to share first.")}
        if let task=inFlight{return try await task.value}
        let expected=generation;let selectedID=windowID;let filter=self.filter;let source=fixtureSource;let token=UUID();let timeout=captureTimeout;captureID=token;capturing=true
        let task=Task{[weak self] () async throws->ContextSnapshot in
            try await boundedCapture(seconds:timeout){[weak self]in
            guard let self else{throw CancellationError()}
            guard selectedID==nil || self.currentFrame() != nil else{throw AppError("The selected window is hidden or unavailable. Bring it into view or choose it again.")}
            var result:ContextSnapshot
            if let source{result=try await source()}
            else{
                guard let filter else{throw AppError("Choose a window to share first.")}
                let rect=filter.contentRect;guard rect.width>1,rect.height>1 else{throw AppError("The selected window is unavailable.")}
                let config=SCStreamConfiguration();let scale=min(2.0,1600.0/max(rect.width,rect.height))
                config.width=CaptureSize.even(rect.width*scale);config.height=CaptureSize.even(rect.height*scale);config.showsCursor=false;config.ignoreShadowsSingleWindow=true
                let image=try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:config)
                guard let data=windowPNG(image) else{throw AppError("Couldn’t read the selected window.")}
                let shown=NSImage(data:data) ?? NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height))
                result=ContextSnapshot(data:data,image:shown,windowID:selectedID,frame:self.currentFrame(),generation:expected,capturedAt:Date())
            }
            guard !Task.isCancelled,self.generation==expected,result.windowID==selectedID,(selectedID==nil || self.currentFrame() != nil) else{throw AppError("Sharing changed. Ask again with the selected window.")}
            result.generation=expected;result.capturedAt=Date();return result
            }
        }
        inFlight=task
        defer{if captureID==token{inFlight=nil;capturing=false}}
        let result=try await task.value
        guard generation==expected,!Task.isCancelled else{throw CancellationError()}
        latest=live ? result : nil;lastCapture=result.capturedAt
        if fixtureSource != nil{fixtureFrame=result.frame}
        return result
    }
    func captureForQuestion()async throws->ContextSnapshot{
        var waits=0
        while let existing=inFlight,!RequestCapture.useFrame(joinedExisting:true,waitsSoFar:waits){
            let token=captureID
            _ = try? await existing.value
            try Task.checkCancellation()
            if captureID==token{inFlight=nil;capturing=false}
            waits+=1
        }
        return try await capture()
    }
    func currentFrame()->CGRect?{
        if fixtureSource != nil{return fixtureOnScreen ? fixtureFrame : nil}
        guard let windowID,let entries=CGWindowListCopyWindowInfo(.optionIncludingWindow,windowID) as? [[String:Any]],let row=entries.first,row[kCGWindowIsOnscreen as String] as? Bool == true,let bounds=row[kCGWindowBounds as String] as? [String:Any],let frame=CGRect(dictionaryRepresentation:bounds as CFDictionary),frame.width>0,frame.height>0 else{return nil};return frame
    }
    func pointIsVisible(_ point:PointTarget,frame:CGRect,windowID:CGWindowID?,ignoring:CGWindowID?=nil)->Bool{
        guard point.isValid,let windowID,self.windowID==windowID,currentFrame()==frame else{return false}
        if fixtureSource != nil{return fixtureOnScreen && fixturePointVisible}
        guard let rows=CGWindowListCopyWindowInfo(.optionOnScreenOnly,kCGNullWindowID) as? [[String:Any]] else{return false}
        let windows=rows.compactMap{row->PointWindow? in
            let id=(row[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
            if id==ignoring{return nil}
            let bounds=(row[kCGWindowBounds as String] as? [String:Any]).flatMap{CGRect(dictionaryRepresentation:$0 as CFDictionary)}
            return PointWindow(id:id,bounds:bounds,opacity:(row[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1)
        }
        let box=CGRect(x:frame.minX+point.x*frame.width,y:frame.minY+point.y*frame.height,width:point.width*frame.width,height:point.height*frame.height).intersection(frame)
        return PointVisibility.isVisible(targetID:windowID,box:box,frontToBack:windows)
    }
    private func windowPNG(_ image:CGImage)->Data?{
        let primary=NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:])
        if let data=WindowImage.png(primary:primary,flattened:nil){return data}
        let width=image.width,height=image.height
        guard width>0,height>0,let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{return nil}
        context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
        guard let flattened=context.makeImage() else{return nil}
        return WindowImage.png(primary:nil,flattened:NSBitmapImageRep(cgImage:flattened).representation(using:.png,properties:[:]))
    }
    // App-owned generated fixtures only; unavailable in normal launches.
    func installFixture(windowID:CGWindowID=42,frame:CGRect=CGRect(x:100,y:100,width:400,height:260),timeout:Double=6,onScreen:Bool=true,pointVisible:Bool=true,source:@escaping ()async throws->ContextSnapshot){
        guard CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--integration-test") else{return}
        stop();self.windowID=windowID;fixtureFrame=frame;captureTimeout=max(0.05,min(6,timeout));fixtureOnScreen=onScreen;fixturePointVisible=pointVisible;fixtureSource=source;title="Synthetic fixture window";changed?()
    }
}

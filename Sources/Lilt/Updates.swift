import Foundation
import Combine
import Sparkle
import LiltCore

@MainActor final class UpdateController: NSObject,ObservableObject,SPUUpdaterDelegate {
    @Published private(set) var status="Updates aren’t configured for this build."
    @Published private var started=false
    @Published private var backendCanCheck=false
    private(set) var configuration:UpdateConfiguration?
    private var controller:SPUStandardUpdaterController?
    private var observation:AnyCancellable?
    var canCheck:Bool{configuration != nil && (!started || backendCanCheck)}
    override init(){
        super.init()
        let info=Bundle.main.infoDictionary ?? [:]
        guard let feed=info["SUFeedURL"] as? String,let key=info["SUPublicEDKey"] as? String else{return}
        do{
            configuration=try UpdateConfiguration(feed:feed,publicKey:key,requiresSignedFeed:info["SURequireSignedFeed"] as? Bool == true,verifiesBeforeExtraction:info["SUVerifyUpdateBeforeExtraction"] as? Bool == true)
            let controller=SPUStandardUpdaterController(startingUpdater:false,updaterDelegate:self,userDriverDelegate:nil)
            self.controller=controller
            observation=controller.updater.publisher(for:\.canCheckForUpdates).receive(on:DispatchQueue.main).sink{[weak self]in self?.backendCanCheck=$0}
            status="Signed updates are available when you choose to check."
        }catch{status="The update source isn’t configured securely. Updates are disabled."}
    }
    func check(){
        guard canCheck,let controller else{return}
        if !started{started=true;controller.startUpdater();controller.updater.automaticallyChecksForUpdates=false;controller.updater.automaticallyDownloadsUpdates=false}
        controller.checkForUpdates(nil)
    }
    nonisolated func updater(_ updater:SPUUpdater,shouldProceedWithUpdate updateItem:SUAppcastItem,updateCheck:SPUUpdateCheck) throws {
        let permitted=MainActor.assumeIsolated { updateItem.fileURL.map {configuration?.permitsRelease($0) == true} ?? false }
        guard permitted else {throw NSError(domain:"ValeUpdates",code:1,userInfo:[NSLocalizedDescriptionKey:"The update archive is outside the configured HTTPS release source."])}
    }
    nonisolated func feedURLString(for updater:SPUUpdater)->String?{MainActor.assumeIsolated{configuration?.feed.absoluteString}}
}

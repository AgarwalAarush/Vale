import Foundation
import Combine
import Sparkle
import LiltCore

@MainActor final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var status = "Updates aren’t configured for this build."
    @Published private(set) var canCheck = false
    @Published private(set) var isConfigured = false
    @Published private(set) var automaticallyChecks = false
    @Published private(set) var automaticallyDownloads = false
    @Published private(set) var lastCheckDate: Date?
    /// A transport/verification cycle receipt from Sparkle, independent of displayed text.
    @Published private(set) var lastCompletedCheckSucceeded: Bool?
    private(set) var configuration: UpdateConfiguration?
    private var controller: SPUStandardUpdaterController?
    private var observations = Set<AnyCancellable>()
    private var readyToInstall = false

    override convenience init() {
        // Native harnesses must never schedule a production check or write its preferences.
        let permitted = UpdateRuntimePolicy.permitsProductionUpdates(arguments: CommandLine.arguments)
        self.init(info: permitted ? Bundle.main.infoDictionary ?? [:] : [:], automaticStart: permitted)
    }

    /// An explicit metadata fixture with automaticStart:false validates configuration without
    /// creating a backend, contacting a feed, or touching Sparkle's main-bundle preferences.
    init(info: [String: Any], automaticStart: Bool) {
        super.init()
        do {
            guard let configuration = try UpdateConfiguration.read(from: info) else { return }
            self.configuration = configuration
            isConfigured = true
            guard automaticStart else {
                status = "Update configuration is valid. The test updater is inactive."
                return
            }
            let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
            self.controller = controller
            let updater = controller.updater
            updater.publisher(for: \.canCheckForUpdates).receive(on: DispatchQueue.main)
                .sink { [weak self] value in self?.canCheck = value }.store(in: &observations)
            updater.publisher(for: \.automaticallyChecksForUpdates).receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.refreshPreferences() }.store(in: &observations)
            updater.publisher(for: \.automaticallyDownloadsUpdates).receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.refreshPreferences() }.store(in: &observations)
            updater.publisher(for: \.lastUpdateCheckDate).receive(on: DispatchQueue.main)
                .sink { [weak self] date in self?.lastCheckDate = date }.store(in: &observations)
            // Defaults live in Info.plist. Runtime setters would persist over the user's choice.
            try updater.start()
            canCheck = updater.canCheckForUpdates
            refreshPreferences()
        } catch {
            controller = nil
            observations.removeAll()
            canCheck = false
            status = isConfigured
                ? "The updater couldn’t start. Check the app’s update configuration."
                : "The update source isn’t configured securely. Updates are disabled."
        }
    }

    func check(background: Bool = false) {
        guard canCheck, let controller else { return }
        lastCompletedCheckSucceeded = nil
        status = "Checking for updates…"
        if background { controller.updater.checkForUpdatesInBackground() }
        else { controller.checkForUpdates(nil) }
    }

    func setAutomaticChecks(_ enabled: Bool) {
        guard let updater = controller?.updater else { return }
        updater.automaticallyChecksForUpdates = enabled
        refreshPreferences()
    }

    func setAutomaticDownloads(_ enabled: Bool) {
        guard let updater = controller?.updater else { return }
        updater.automaticallyDownloadsUpdates = enabled
        refreshPreferences()
    }

    private func refreshPreferences() {
        guard let updater = controller?.updater else { return }
        automaticallyChecks = updater.automaticallyChecksForUpdates
        automaticallyDownloads = updater.automaticallyDownloadsUpdates
        lastCheckDate = updater.lastUpdateCheckDate
        guard !readyToInstall else { return }
        guard !updater.sessionInProgress else {
            status = "An update check is in progress…"
            return
        }
        if !automaticallyChecks {
            status = "Automatic checks are off. You can check manually."
        } else if automaticallyDownloads {
            status = "Updates download automatically and install when Vale quits."
        } else {
            status = "Vale checks automatically. Downloads need your approval."
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        let permitted = MainActor.assumeIsolated { self.permits(updateItem) }
        guard permitted else {
            throw NSError(domain: "ValeUpdates", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "The update archive is outside the configured HTTPS release source."
            ])
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        let permitted = MainActor.assumeIsolated {
            guard let target = request.url, configuration?.permitsRelease(target) == true else { return false }
            return item.fileURL.map { configuration?.permitsRelease($0) == true } ?? true
        }
        // Sparkle aborts a download whose scheme is missing before it opens a connection.
        if !permitted { request.url = nil }
    }

    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        MainActor.assumeIsolated { configuration?.feed.absoluteString }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        MainActor.assumeIsolated { status = "An update is available." }
    }

    nonisolated func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        MainActor.assumeIsolated { status = "Update downloaded. Verifying…" }
    }

    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock: @escaping () -> Void) -> Bool {
        MainActor.assumeIsolated {
            readyToInstall = true
            status = "An update is ready. It will install when Vale quits."
        }
        // Keep normal Sparkle scheduling; never force an active conversation to quit.
        return false
    }

    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        MainActor.assumeIsolated { status = "Installing update…" }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        MainActor.assumeIsolated { show(error: error as NSError) }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        MainActor.assumeIsolated {
            lastCheckDate = updater.lastUpdateCheckDate
            let sdkError = error as NSError?
            lastCompletedCheckSucceeded = sdkError == nil ||
                (sdkError?.domain == SUSparkleErrorDomain && sdkError?.code == Int(SUError.noUpdateError.rawValue))
            if let error { show(error: error as NSError) }
            else if !readyToInstall { status = "Update check finished." }
        }
    }

    private func show(error: NSError) {
        // Keep untrusted server/error text out of the UI.
        if error.domain == SUSparkleErrorDomain, error.code == Int(SUError.noUpdateError.rawValue) {
            status = "Vale is up to date."
        } else if error.domain == SUSparkleErrorDomain,
                  [SUError.appcastParseError, .signatureError, .validationError].contains(where: { Int($0.rawValue) == error.code }) {
            status = "The update couldn’t be verified or read. Nothing was installed."
        } else if error.domain == SUSparkleErrorDomain, error.code == Int(SUError.installationCanceledError.rawValue) {
            status = "Update installation was canceled. You can check again."
        } else {
            status = "Couldn’t complete the update check. Try again."
        }
    }

    private func permits(_ item: SUAppcastItem) -> Bool {
        guard let primary = item.fileURL else { return false }
        var urls = [primary]
        if let deltas = item.deltaUpdates {
            for delta in deltas.values {
                guard let url = delta.fileURL else { return false }
                urls.append(url)
            }
        }
        return configuration?.permitsReleases(urls) == true
    }
}

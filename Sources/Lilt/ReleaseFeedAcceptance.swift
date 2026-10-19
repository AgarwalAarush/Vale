import AppKit
import Foundation
import LiltCore

/// Runs only inside a nonce-identified disposable copy, never the installed Vale domain.
struct ReleaseFeedAcceptanceContext {
    let output: URL
    let preferenceOnly: Bool

    static func read() -> Self? {
        guard CommandLine.arguments.contains("--verify-release-feed"),
              let identifier = Bundle.main.bundleIdentifier,
              identifier.hasPrefix("local.vale.releasecheck."),
              Bundle.main.object(forInfoDictionaryKey: "SUDefaultsDomain") == nil,
              let argument = CommandLine.arguments.last else { return nil }
        let output = URL(fileURLWithPath: argument).resolvingSymlinksInPath()
        let root = output.deletingLastPathComponent()
        guard output.lastPathComponent == "evidence",
              root.lastPathComponent.hasPrefix("vale-release-check."),
              ["/tmp", "/private/tmp"].contains(root.deletingLastPathComponent().path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: root.path),
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o077 == 0,
              let data = try? Data(contentsOf: root.appendingPathComponent("request.json")),
              let request = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              request["bundleID"] == identifier else { return nil }
        return Self(output: output, preferenceOnly: CommandLine.arguments.contains("--preferences-off"))
    }
}

extension AppController {
    func runReleaseFeedAcceptance(_ context: ReleaseFeedAcceptanceContext) async {
        do {
            try FileManager.default.createDirectory(at: context.output, withIntermediateDirectories: true)
            let updates = model.updates
            let checksAtStartup = updates.automaticallyChecks
            let downloadsAtStartup = updates.automaticallyDownloads
            var checks: [String: Bool] = ["configuredBackend": updates.isConfigured && updates.canCheck]
            model.prepareChat()
            model.draft = "Generated release-feed verification draft."
            model.openSettings()
            await settle()
            var completedCheckStatus = "Not checked in this phase."
            if context.preferenceOnly {
                // Sparkle disallows the download setter while checks are off.
                updates.setAutomaticDownloads(false)
                updates.setAutomaticChecks(false)
                checks["automaticChecksCanBeDisabled"] = !updates.automaticallyChecks
                checks["automaticDownloadsCanBeDisabled"] = !updates.automaticallyDownloads
            } else {
                checks["savedAutomaticCheckChoiceSurvivesRelaunch"] = !checksAtStartup
                checks["savedAutomaticDownloadChoiceSurvivesRelaunch"] = !downloadsAtStartup
                updates.check(background: true)
                let deadline = Date().addingTimeInterval(90)
                while updates.lastCompletedCheckSucceeded == nil && Date() < deadline {
                    try await Task.sleep(nanoseconds: 200_000_000)
                }
                checks["realSDKCompletedProductionFeedCheck"] = updates.lastCompletedCheckSucceeded == true
                completedCheckStatus = updates.status
                checks["generatedDraftRetained"] = model.draft == "Generated release-feed verification draft."
                updates.setAutomaticChecks(true)
                updates.setAutomaticDownloads(true)
                checks["automaticChoicesCanBeReenabled"] = updates.automaticallyChecks && updates.automaticallyDownloads
            }
            if Bundle.main.bundleIdentifier?.hasPrefix("local.vale.releasecheck.") == true {
                // The reidentified main bundle already provides a unique standard domain.
                let suite = UserDefaults.standard
                checks["noncePreferenceDomainSynchronized"] = suite.synchronize()
                if context.preferenceOnly {
                    checks["checksOffStoredInNonceSuite"] = suite.object(forKey: "SUEnableAutomaticChecks") as? Bool == false
                    checks["downloadsOffStoredInNonceSuite"] = suite.object(forKey: "SUAutomaticallyUpdate") as? Bool == false
                }
            }
            await settle()
            let phase = context.preferenceOnly ? "preferences-off" : "production-feed"
            try snapshot(workspace, to: context.output.appendingPathComponent(phase + ".png"))
            let receipt: [String: Any] = [
                "phase": phase,
                "bundleID": Bundle.main.bundleIdentifier ?? "",
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "",
                "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "",
                "feed": updates.configuration?.feed.absoluteString ?? "",
                "automaticChecksAtStartup": checksAtStartup,
                "automaticDownloadsAtStartup": downloadsAtStartup,
                "status": updates.status,
                "completedCheckStatus": completedCheckStatus,
                "checks": checks,
                "passed": checks.values.allSatisfy { $0 },
                "boundary": "Actual Vale UpdateController and Sparkle in a disposable reidentified candidate; no installed app or personal data touched. This checks the live feed and stored preferences, not an installed upgrade."
            ]
            let data = try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: context.output.appendingPathComponent(phase + ".json"), options: .atomic)
            model.suspend()
            NSApp.terminate(nil)
        } catch {
            // Only a fixed message: no arbitrary network/body or local account details.
            print("Release-feed acceptance could not finish; inspect its isolated receipts.")
            exit(2)
        }
    }
}

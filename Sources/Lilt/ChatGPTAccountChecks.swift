import Foundation
import LiltCore

/// Disposable protocol checks. These never open a browser or touch the production credential store.
@MainActor enum ChatGPTAccountChecks {
    static func run() async -> [String: Bool] {
        guard CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--integration-test") else { return [:] }
        var results: [String: Bool] = [:]
        do {
            let store = ChatGPTCredentialStore(memoryOnly: true)
            var vault = try store.load()
            let host = vault.hostID
            let response = try JSONDecoder().decode(ChatGPTTokenResponse.self, from: Data(#"{"access_token":"generated-access-do-not-send","refresh_token":"generated-refresh-do-not-send","id_token":"generated-id-do-not-send","token_type":"Bearer","expires_in":3600,"scope":"openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"}"#.utf8))
            let credentials = try response.credentials()
            vault.registrations = [ChatGPTRegistration(clientID: "oaiapp_generated_1", label: "Generated connection 1", tokens: credentials), ChatGPTRegistration(clientID: "oaiapp_generated_2", label: "Generated connection 2", tokens: credentials)]
            vault.activeID = "oaiapp_generated_1"; try store.save(vault)
            let restored = try store.load()
            results["chatGPTFixtureVaultPreservesHostAndSeparateRegistrations"] = restored.hostID == host && restored.registrations.count == 2 && restored.activeID == "oaiapp_generated_1"
            try store.setSignedOut("oaiapp_generated_1", true)
            let signedOut = try store.load()
            let pendingRevocation = try store.load(includeSignedOutTokens: true)
            results["chatGPTFixtureDurableSignOutExcludesTokensButRetainsRevocationRecord"] = signedOut.registrations[0].tokens == nil && signedOut.registrations[1].tokens != nil && pendingRevocation.registrations[0].tokens?.refreshToken == credentials.refreshToken && signedOut.registrations[0].id == "oaiapp_generated_1"
            try store.setSignedOut("oaiapp_generated_1", false)
            results["chatGPTFixtureValidatedReauthorizationCanRestoreConnection"] = try store.load().registrations[0].tokens != nil
            let renewal = try JSONDecoder().decode(ChatGPTTokenResponse.self, from: Data(#"{"access_token":"generated-replacement-do-not-send","refresh_token":"generated-rotated-do-not-send","token_type":"Bearer","expires_in":3600}"#.utf8))
            let replacement = try renewal.credentials(previous: credentials)
            results["chatGPTFixtureRefreshReplacesRotationAndRetainsOmittedGrant"] = replacement.refreshToken == "generated-rotated-do-not-send" && replacement.idToken == credentials.idToken && replacement.scopes == credentials.scopes && replacement.permitsPlanUsage
            let missingGrant = try JSONDecoder().decode(ChatGPTTokenResponse.self, from: Data(#"{"access_token":"generated-access-do-not-send","id_token":"generated-id-do-not-send","token_type":"Bearer","expires_in":3600,"scope":"openid email"}"#.utf8))
            results["chatGPTFixtureIdentityAloneDoesNotAuthorizePlanUsage"] = try !missingGrant.credentials().permitsPlanUsage
        } catch { results["chatGPTFixtureCredentialChecksCompleted"] = false }
        do {
            let listener = ChatGPTCallbackListener()
            defer { listener.cancel() }
            let base = try await listener.start()
            let authorization = try ChatGPTAuthorization(redirectURI: base)
            listener.validatesCallback = { url in
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                return items.filter { $0.name == "state" }.count == 1 && items.first { $0.name == "state" }?.value == authorization.state
            }
            let callback = Task { try await listener.waitForCallback() }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil; configuration.timeoutIntervalForRequest = 5
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let (_, wrongResponse) = try await session.data(from: URL(string: base.absoluteString + "?state=incorrect&code=generated&client_id=oaiapp_generated")!)
            let valid = URL(string: base.absoluteString + "?state=\(authorization.state)&code=generated&client_id=oaiapp_generated")!
            let (_, rightResponse) = try await session.data(from: valid)
            let received = try await callback.value
            let verified = try authorization.callback(received)
            results["chatGPTLoopbackListenerBindsOnly127AndKeepsAttemptAfterWrongState"] = base.host == "127.0.0.1" && (wrongResponse as? HTTPURLResponse)?.statusCode == 400 && (rightResponse as? HTTPURLResponse)?.statusCode == 200 && verified.clientID == "oaiapp_generated"
        } catch { results["chatGPTLoopbackListenerBindsOnly127AndKeepsAttemptAfterWrongState"] = false }
        do {
            let listener = ChatGPTCallbackListener(); _ = try await listener.start(); listener.cancel()
            do { _ = try await listener.waitForCallback(); results["chatGPTLoopbackCancellationEndsAttempt"] = false }
            catch { results["chatGPTLoopbackCancellationEndsAttempt"] = true }
        } catch { results["chatGPTLoopbackCancellationEndsAttempt"] = false }
        return results
    }
}

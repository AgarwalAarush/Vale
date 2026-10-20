import Foundation
import LiltCore

/// Exercises real account tasks against a shared disposable store and a transport with no sockets.
@MainActor enum ChatGPTLifecycleChecks {
    static func makeSettingsFixture(planGranted: Bool, identityPending: Bool = false) async throws -> ChatGPTAccount {
        guard CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--integration-test") else { throw ChatGPTError("Generated account views are restricted to the native harness.") }
        let (store, http) = try fixture(expiring: false)
        if !planGranted {
            _ = try await store.update { vault in
                for index in vault.registrations.indices { vault.registrations[index].tokens?.scopes = ["openid", "profile", "email"] }
            }
        }
        if identityPending {
            _ = try await store.update { vault in
                for index in vault.registrations.indices { vault.registrations[index].tokens?.identityValidationPending = true }
            }
        }
        let account = try ChatGPTAccount(testingStore: store, testingTransport: http)
        if planGranted && !identityPending { account.refreshModels(); try await wait { account.models.count == 2 } }
        return account
    }
    static func run() async -> [String: Bool] {
        guard CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--integration-test") else { return [:] }
        var results: [String: Bool] = [:]
        await check("chatGPTLifecycleTwoCopiesKeepAliceRoutingAndRevokeAfterBobModelMutation", results: &results) { try await selectionIsolation() }
        await check("chatGPTLifecycleOtherCopySignOutShowsDisconnectedWithoutAdoptingAccount", results: &results) { try await externalSignOut() }
        await check("chatGPTLifecycleTwoCopiesSerializeActualRotatingRefresh", results: &results) { try await competingRefreshes() }
        await check("chatGPTLifecycleJWKS503RetainsPendingRotationAndRecoversWithNewRefresh", results: &results) { try await transientRecovery(ChatGPTError("Generated JWKS 503", status: 503)) }
        await check("chatGPTLifecycleJWKSTimeoutRetainsPendingRotationAndRecoversWithNewRefresh", results: &results) { try await transientRecovery(URLError(.timedOut)) }
        await check("chatGPTLifecycleRetryConnectionVerifiesNarrowedGrantAfterJWKS503WithoutCatalogOrSession", results: &results) { try await narrowedGrantRecovery(ChatGPTError("Generated JWKS 503", status: 503)) }
        await check("chatGPTLifecycleRetryConnectionVerifiesNarrowedGrantAfterJWKSTimeoutWithoutCatalogOrSession", results: &results) { try await narrowedGrantRecovery(URLError(.timedOut)) }
        await check("chatGPTLifecycleTerminalIdentityMismatchClearsAndKeepsDistinctError", results: &results) { try await terminalIdentityFailure(mismatch: true) }
        await check("chatGPTLifecycleTerminalSignatureFailureClearsPendingCredentials", results: &results) { try await terminalIdentityFailure(mismatch: false) }
        await check("chatGPTLifecycleCallerCancellationRetainsCompletedRotation", results: &results) { try await callerRace(switchAccount: false) }
        await check("chatGPTLifecycleAccountSwitchRejectsOldDeliveryAndRetainsRotation", results: &results) { try await callerRace(switchAccount: true) }
        await check("chatGPTLifecycleSignOutDuringVerificationRevokesNewestRefresh", results: &results) { try await signOutRace(identityFails: false) }
        await check("chatGPTLifecycleSignOutAfterTransientJWKSFailureRevokesPendingRefresh", results: &results) { try await signOutRace(identityFails: true) }
        return results
    }
    private static func check(_ name: String, results: inout [String: Bool], action: () async throws -> Bool) async {
        do { results[name] = try await action() } catch { results[name] = false }
    }
    private static func wait(_ condition: () throws -> Bool) async throws {
        for _ in 0..<200 {
            if try condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw ChatGPTError("Generated lifecycle fixture timed out.")
    }
    private static func fixture(expiring: Bool = true) throws -> (ChatGPTCredentialStore, ChatGPTFixtureTransport) {
        let store = ChatGPTCredentialStore(memoryOnly: true)
        let transport = ChatGPTFixtureTransport()
        var vault = try store.load()
        vault.activeID = "alice"
        vault.registrations = try ["alice", "bob"].map { id in
            let identity = try transport.generatedIdentity(id)
            let tokens = ChatGPTTokens(accessToken: "fixture-access-\(id)-old", refreshToken: "fixture-refresh-\(id)-old", idToken: "fixture-id-\(id)-old", scopes: ChatGPTOAuth.scopes.split(separator: " ").map(String.init), expiresAt: Date().addingTimeInterval(id == "alice" && expiring ? -60 : 3600))
            return ChatGPTRegistration(clientID: id, identity: identity, label: "Generated \(id)", tokens: tokens)
        }
        try store.save(vault)
        return (store, transport)
    }
    private static func selectionIsolation() async throws -> Bool {
        let (store, http) = try fixture(expiring: false)
        let alice = try ChatGPTAccount(testingStore: store, testingTransport: http)
        let otherCopy = try ChatGPTAccount(testingStore: store, testingTransport: http)
        let originalEpoch = alice.requestEpoch
        otherCopy.selectAccount("bob")
        try await wait { try store.load().activeID == "bob" }
        alice.refreshModels(); try await wait { alice.models.count == 2 }
        alice.selectModel("fixture-model-2")
        try await wait { try store.load().registrations.first { $0.id == "alice" }?.selectedModel == "fixture-model-2" }
        let ordinary = try await alice.usableSession()
        let sharedPreference = try store.load().activeID
        let metadataStayedLocal = alice.activeAccountID == "alice" && alice.accountDisplayName == "Generated Alice" && alice.requestEpoch == originalEpoch && ordinary.clientID == "alice" && ordinary.accessToken == "fixture-access-alice-old" && sharedPreference == "bob"
        _ = try await store.update { latest in
            let index = latest.registrations.firstIndex { $0.id == "alice" }!
            latest.registrations[index].tokens?.expiresAt = Date().addingTimeInterval(-60)
        }
        let renewed = try await alice.usableSession()
        alice.signOut(); try await wait { !alice.isSigningOut }
        let after = try store.load(includeSignedOutTokens: true)
        return metadataStayedLocal && renewed.clientID == "alice" && renewed.accessToken == "fixture-access-alice-r1" && alice.activeAccountID == "alice" && otherCopy.activeAccountID == "bob" && http.tokenCalls.map(\.clientID) == ["alice"] && http.revokeCalls.map(\.clientID) == ["alice"] && http.revokeCalls.first?.refresh == "fixture-refresh-alice-r1" && after.registrations.first { $0.id == "alice" }?.tokens == nil && after.registrations.first { $0.id == "bob" }?.tokens != nil && http.modelCalls.contains("fixture-access-alice-old")
    }
    private static func competingRefreshes() async throws -> Bool {
        let (store, http) = try fixture()
        let first = try ChatGPTAccount(testingStore: store, testingTransport: http)
        let second = try ChatGPTAccount(testingStore: store, testingTransport: http)
        let gate = ChatGPTFixtureGate(); http.identityGate = gate; defer { gate.release() }
        let one = Task { try await first.usableSession() }
        try await wait { gate.reached }
        let two = Task { try await second.usableSession() }
        await Task.yield(); gate.release()
        let a = try await one.value; let b = try await two.value
        return a.accessToken == "fixture-access-alice-r1" && b.accessToken == a.accessToken && http.tokenCalls.count == 1 && first.activeAccountID == "alice" && second.activeAccountID == "alice"
    }
    private static func externalSignOut() async throws -> Bool {
        let (store, http) = try fixture(expiring: false)
        let first = try ChatGPTAccount(testingStore: store, testingTransport: http)
        let second = try ChatGPTAccount(testingStore: store, testingTransport: http)
        first.signOut(); try await wait { !first.isSigningOut }
        var rejected = false
        do { _ = try await second.usableSession() } catch { rejected = true }
        return rejected && !second.isSignedIn && second.activeAccountID == "alice" && !second.status.hasPrefix("Connected") && second.status.contains("Continue with ChatGPT") && http.revokeCalls.map(\.clientID) == ["alice"]
    }
    private static func transientRecovery(_ failure: Error) async throws -> Bool {
        let (store, http) = try fixture()
        let account = try ChatGPTAccount(testingStore: store, testingTransport: http)
        let gate = ChatGPTFixtureGate(); http.identityGate = gate; http.identityFailures = [failure]; defer { gate.release() }
        let attempt = Task { try await account.usableSession() }
        try await wait { gate.reached }
        let protected = try store.load(includeSignedOutTokens: true).registrations.first { $0.id == "alice" }!.tokens!
        let pendingBeforeFailure = protected.identityValidationPending == true && protected.refreshToken == "fixture-refresh-alice-r1" && !protected.permitsPlanUsage && account.needsIdentityValidation && !account.permitsPlanUsage
        let overlapping = Task { try await account.usableSession() }
        await Task.yield(); gate.release()
        let firstFailed: Bool
        do { _ = try await attempt.value; firstFailed = false } catch { firstFailed = (error as? ChatGPTError)?.invalidatesSession != true }
        let secondFailed: Bool
        do { _ = try await overlapping.value; secondFailed = false } catch { secondFailed = true }
        let retained = try store.load(includeSignedOutTokens: true).registrations.first { $0.id == "alice" }!.tokens
        http.identityGate = nil
        _ = try await store.update { latest in
            let index = latest.registrations.firstIndex { $0.id == "alice" }!
            latest.registrations[index].tokens?.expiresAt = Date().addingTimeInterval(-60)
        }
        let recovered = try await account.usableSession()
        let saved = try store.load().registrations.first { $0.id == "alice" }!.tokens!
        return pendingBeforeFailure && firstFailed && secondFailed && retained?.identityValidationPending == true && retained?.refreshToken == "fixture-refresh-alice-r1" && http.tokenCalls.map(\.refresh) == ["fixture-refresh-alice-old", "fixture-refresh-alice-r1"] && recovered.accessToken == "fixture-access-alice-r2" && saved.identityValidationPending == false && saved.refreshToken == "fixture-refresh-alice-r2" && account.permitsPlanUsage
    }
    private static func terminalIdentityFailure(mismatch: Bool) async throws -> Bool {
        let (store, http) = try fixture()
        let account = try ChatGPTAccount(testingStore: store, testingTransport: http)
        if mismatch { http.identityOverride = try http.generatedIdentity("bob") }
        else { http.identityFailures = [ChatGPTError("Generated invalid signature", code: "invalid_id_token")] }
        var code: String?
        do { _ = try await account.usableSession() } catch { code = (error as? ChatGPTError)?.code }
        let cleared = try store.load(includeSignedOutTokens: true).registrations.first { $0.id == "alice" }?.tokens == nil
        return cleared && !account.isSignedIn && !account.permitsPlanUsage && account.activeAccountID == "alice" && code == (mismatch ? "identity_mismatch" : "invalid_id_token") && http.tokenCalls.count == 1
    }
    private static func narrowedGrantRecovery(_ failure: Error) async throws -> Bool {
        let (store, http) = try fixture()
        http.returnedScopes = "openid profile email"
        let account = try ChatGPTAccount(testingStore: store, testingTransport: http)
        let epoch = account.requestEpoch
        let gate = ChatGPTFixtureGate(); http.identityGate = gate; http.identityFailures = [failure]; defer { gate.release() }
        account.refreshModels()
        try await wait { gate.reached }
        let pending = try store.load().registrations.first { $0.id == "alice" }!.tokens!
        let retryWasDisplayed = account.isSignedIn && account.needsIdentityValidation && !account.permitsPlanUsage && account.status.contains("Retry connection")
        gate.release()
        try await wait { account.error != nil }
        let retained = try store.load().registrations.first { $0.id == "alice" }!.tokens!
        let failedSafely = retained.identityValidationPending == true && retained.refreshToken == pending.refreshToken && http.modelCalls.isEmpty
        http.identityGate = nil
        // This is the exact action displayed by Settings for the pending connection.
        account.refreshModels()
        try await wait { !account.needsIdentityValidation }
        try await wait { account.error?.contains("Enable it in Settings") == true }
        let saved = try store.load().registrations.first { $0.id == "alice" }!.tokens!
        let consentIsActionable = account.isSignedIn && !account.permitsPlanUsage && account.status.contains("Enable ChatGPT plan usage")
        var sessionRejected = false
        do { _ = try await account.usableSession() }
        catch { sessionRejected = (error as? ChatGPTError)?.message.contains("Enable ChatGPT plan usage") == true }
        let narrowedRotation = pending.identityValidationPending == true && !pending.hasPlanGrant && pending.idToken == "fixture-id-alice-r1"
        let savedRotation = saved.identityValidationPending == false && !saved.hasPlanGrant && saved.refreshToken == "fixture-refresh-alice-r1" && saved.idToken == pending.idToken
        let retriedSavedIdentity = http.tokenCalls.map(\.refresh) == ["fixture-refresh-alice-old"]
            && http.identityCalls.map(\.token) == ["fixture-id-alice-r1", "fixture-id-alice-r1"] && http.identityCalls.allSatisfy { $0.clientID == "alice" }
        let stayedLocal = http.modelCalls.isEmpty && account.models.isEmpty && account.activeAccountID == "alice" && account.requestEpoch == epoch
        return retryWasDisplayed && failedSafely && consentIsActionable && sessionRejected && narrowedRotation && savedRotation && retriedSavedIdentity && stayedLocal
    }
    private static func callerRace(switchAccount: Bool) async throws -> Bool {
        let (store, http) = try fixture()
        let account = try ChatGPTAccount(testingStore: store, testingTransport: http)
        let gate = ChatGPTFixtureGate(); http.identityGate = gate; defer { gate.release() }
        let attempt = Task { try await account.usableSession() }
        try await wait { gate.reached }
        if switchAccount { account.selectAccount("bob") } else { attempt.cancel() }
        gate.release()
        var rejected = false
        do { _ = try await attempt.value } catch { rejected = error is CancellationError }
        try await wait { try store.load().registrations.first { $0.id == "alice" }?.tokens?.identityValidationPending == false }
        if switchAccount { try await wait { try store.load().activeID == "bob" } }
        let next = try await account.usableSession()
        let retained = try store.load(includeSignedOutTokens: true).registrations.first { $0.id == "alice" }?.tokens
        return rejected && retained?.refreshToken == "fixture-refresh-alice-r1" && next.clientID == (switchAccount ? "bob" : "alice") && account.activeAccountID == next.clientID && http.tokenCalls.map(\.clientID) == ["alice"]
    }
    private static func signOutRace(identityFails: Bool) async throws -> Bool {
        let (store, http) = try fixture()
        let account = try ChatGPTAccount(testingStore: store, testingTransport: http)
        let gate = ChatGPTFixtureGate(); http.identityGate = gate; defer { gate.release() }
        if identityFails { http.identityFailures = [ChatGPTError("Generated JWKS unavailable", status: 503)] }
        let attempt = Task { try await account.usableSession() }
        try await wait { gate.reached }
        account.signOut()
        let maskedImmediately = try store.load().registrations.first { $0.id == "alice" }?.tokens == nil
        let pending = try store.load(includeSignedOutTokens: true).registrations.first { $0.id == "alice" }?.tokens?.refreshToken
        gate.release()
        var noDelivery = false
        do { _ = try await attempt.value } catch { noDelivery = true }
        try await wait { !account.isSigningOut }
        let after = try store.load(includeSignedOutTokens: true)
        return maskedImmediately && pending == "fixture-refresh-alice-r1" && noDelivery && account.activeAccountID == "alice" && !account.isSignedIn && http.revokeCalls.count == 1 && http.revokeCalls[0].clientID == "alice" && http.revokeCalls[0].refresh == "fixture-refresh-alice-r1" && after.registrations.first { $0.id == "alice" }?.tokens == nil && after.registrations.first { $0.id == "bob" }?.tokens != nil
    }
}

@MainActor private final class ChatGPTFixtureGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var open = false
    private(set) var reached = false
    func wait() async {
        reached = true
        if open { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { open = true; continuation?.resume(); continuation = nil }
}

@MainActor private final class ChatGPTFixtureTransport: ChatGPTAccountTransport {
    let isFixture = true
    var tokenCalls: [(clientID: String, refresh: String)] = []
    var revokeCalls: [(clientID: String, refresh: String)] = []
    var modelCalls: [String] = []
    var identityCalls: [(token: String, clientID: String)] = []
    var returnedScopes: String?
    var identityGate: ChatGPTFixtureGate?
    var identityFailures: [Error] = []
    var identityOverride: ChatGPTIdentity?
    func generatedIdentity(_ clientID: String) throws -> ChatGPTIdentity {
        let data = try JSONSerialization.data(withJSONObject: ["issuer": ChatGPTOAuth.issuer, "subject": "fixture-subject-" + clientID, "name": "Generated " + clientID.capitalized, "email": clientID + "@example.invalid"])
        return try JSONDecoder().decode(ChatGPTIdentity.self, from: data)
    }
    func discovery() async throws -> ChatGPTDiscovery { throw ChatGPTError("Browser/discovery requests are disabled in disposable lifecycle fixtures.") }
    func identity(_ token: String, clientID: String, nonce: String?) async throws -> ChatGPTIdentity {
        identityCalls.append((token, clientID))
        if let identityGate { await identityGate.wait() }
        if !identityFailures.isEmpty { throw identityFailures.removeFirst() }
        return try identityOverride ?? generatedIdentity(clientID)
    }
    func token(_ values: [String: String]) async throws -> ChatGPTTokenResponse {
        guard values["grant_type"] == "refresh_token", let id = values["client_id"], let refresh = values["refresh_token"], refresh.hasPrefix("fixture-") else { throw ChatGPTError("Unexpected generated token request.") }
        tokenCalls.append((id, refresh))
        let rotation = tokenCalls.filter { $0.clientID == id }.count
        var response: [String: Any] = ["access_token": "fixture-access-\(id)-r\(rotation)", "refresh_token": "fixture-refresh-\(id)-r\(rotation)", "id_token": "fixture-id-\(id)-r\(rotation)", "token_type": "Bearer", "expires_in": 3600]
        if let returnedScopes { response["scope"] = returnedScopes }
        let data = try JSONSerialization.data(withJSONObject: response)
        return try JSONDecoder().decode(ChatGPTTokenResponse.self, from: data)
    }
    func revoke(_ tokens: ChatGPTTokens, clientID: String) async throws {
        guard let refresh = tokens.refreshToken, refresh.hasPrefix("fixture-") else { throw ChatGPTError("Unexpected generated revoke request.") }
        revokeCalls.append((clientID, refresh))
    }
    func models(accessToken: String) async throws -> [ChatGPTModel] {
        guard accessToken.hasPrefix("fixture-") else { throw ChatGPTError("Unexpected generated model request.") }
        modelCalls.append(accessToken)
        return try ChatGPTModel.catalog(Data(#"{"models":[{"slug":"fixture-model-1","display_name":"Generated model 1","visibility":"list"},{"slug":"fixture-model-2","display_name":"Generated model 2","visibility":"list"}]}"#.utf8))
    }
}

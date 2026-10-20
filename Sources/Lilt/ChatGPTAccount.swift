import Foundation
import AppKit
import Combine
import LiltCore

struct ChatGPTAccountSummary: Identifiable {
    let id: String
    let name: String
    let label: String
    let isConnected: Bool
}

struct ChatGPTAuthorizedSession {
    let accessToken: String
    let clientID: String
    let epoch: UUID
}

@MainActor final class ChatGPTAccount: ObservableObject {
    static let shared = ChatGPTAccount()
    static let connectionWillChange = Notification.Name("ValeChatGPTConnectionWillChange")
    @Published private(set) var status = "Continue with ChatGPT to use your eligible plan in Vale."
    @Published private(set) var error: String?
    @Published private(set) var isSigningIn = false
    @Published private(set) var isSigningOut = false
    @Published private(set) var needsSignOutRetry = false
    @Published private(set) var models: [ChatGPTModel] = []
    @Published private(set) var selectedModelID = ""
    @Published private(set) var accounts: [ChatGPTAccountSummary] = []
    @Published private(set) var activeAccountID: String?
    @Published private(set) var isSignedIn = false
    @Published private(set) var permitsPlanUsage = false
    private(set) var requestEpoch = UUID()
    private let store: ChatGPTCredentialStore
    private let fixtureMode: Bool
    private var vault = ChatGPTCredentialVault()
    private var authTask: Task<Void, Never>?
    private var refreshTasks: [String: Task<ChatGPTTokens, Error>] = [:]
    private var catalogTask: Task<Void, Never>?
    private var signOutTask: Task<Void, Never>?
    private var listener: ChatGPTCallbackListener?
    private var attemptID = UUID()
    private var activeRegistration: ChatGPTRegistration? { vault.registrations.first { $0.id == vault.activeID } }
    var accountDisplayName: String { activeRegistration?.displayName ?? "ChatGPT" }
    var selectedModel: ChatGPTModel? { models.first { $0.id == selectedModelID } }

    init(memoryOnly: Bool = CommandLine.arguments.contains("--self-test")) {
        fixtureMode = memoryOnly; store = ChatGPTCredentialStore(memoryOnly: memoryOnly)
        do {
            vault = try store.load(); publish()
            if let activeID = vault.activeID, store.isSignedOut(activeID) {
                let pending = try store.load(includeSignedOutTokens: true)
                needsSignOutRetry = pending.registrations.first(where: { $0.id == activeID })?.tokens != nil
                if needsSignOutRetry { status = "Signed out locally. Retry sign-out to finish disconnecting the saved session, or manage access in ChatGPT Settings → Usage." }
            }
        }
        catch { self.error = error.localizedDescription; status = "Reconnect ChatGPT in Settings." }
    }
    private func publish() {
        activeAccountID = vault.activeID
        accounts = vault.registrations.map { ChatGPTAccountSummary(id: $0.id, name: $0.displayName, label: $0.label, isConnected: $0.tokens != nil) }
        isSignedIn = activeRegistration?.tokens != nil
        permitsPlanUsage = activeRegistration?.tokens?.permitsPlanUsage == true
        selectedModelID = activeRegistration?.selectedModel ?? ""
        if isSignedIn { status = permitsPlanUsage ? "Connected to ChatGPT. Requests use your ChatGPT plan and app limits." : "Signed in. Enable ChatGPT plan usage to send a question." }
    }
    private func invalidateRequests() {
        requestEpoch = UUID()
        NotificationCenter.default.post(name: Self.connectionWillChange, object: self)
        catalogTask?.cancel(); catalogTask = nil; models = []
    }
    /// Called only by an explicit Continue with ChatGPT action.
    func signIn() { beginSignIn(registration: activeRegistration ?? vault.registrations.first(where: { $0.identity == nil }), requestConsent: false) }
    func addAccount() { beginSignIn(registration: nil, requestConsent: false) }
    func enablePlanUsage() { beginSignIn(registration: activeRegistration, requestConsent: true) }
    func signIn(accountID: String) { beginSignIn(registration: vault.registrations.first { $0.id == accountID }, requestConsent: false) }
    private func beginSignIn(registration: ChatGPTRegistration?, requestConsent: Bool, canRetryCode: Bool = true) {
        guard !fixtureMode else { status = "Generated account fixture. Browser sign-in is disabled during self-test."; return }
        guard !isSigningOut else { return }
        cancelSignIn(); error = nil; isSigningIn = true; status = "Complete sign-in in your browser, then return to Vale."
        let id = UUID(); attemptID = id
        authTask = Task { [weak self] in
            guard let self else { return }
            let listener = ChatGPTCallbackListener(); self.listener = listener
            var issuedRegistration = registration
            do {
                // Save this host's ID before starting its first authorization, including canceled attempts.
                self.vault = try await self.store.update { _ in }
                try self.checkAttempt(id)
                let config = try await ChatGPTHTTP.shared.discovery()
                try self.checkAttempt(id)
                let redirect = try await listener.start()
                try self.checkAttempt(id)
                let transaction = try ChatGPTAuthorization(redirectURI: redirect, clientID: registration?.clientID ?? ChatGPTOAuth.registrationClient)
                listener.validatesCallback = { url in
                    guard Date() < transaction.expiresAt,
                          let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                          items.filter({ $0.name == "state" }).count == 1,
                          items.first(where: { $0.name == "state" })?.value == transaction.state else { return false }
                    return true
                }
                let url = try transaction.authorizationURL(endpoint: config.authorization_endpoint, hostID: self.vault.hostID, idTokenHint: registration?.tokens?.idToken, emailHint: registration?.identity?.email, requestConsent: requestConsent)
                guard NSWorkspace.shared.open(url) else { throw ChatGPTError("Vale couldn’t open your browser. Choose Continue with ChatGPT to try again.") }
                let callback = try await listener.waitForCallback()
                try self.checkAttempt(id)
                let result = try transaction.callback(callback)
                // Retain an issued registration even if its single-use code has expired.
                self.vault = try await self.store.update { latest in
                    try self.checkAttempt(id)
                    if !latest.registrations.contains(where: { $0.id == result.clientID }) {
                        latest.registrations.append(ChatGPTRegistration(clientID: result.clientID, label: "Connection \(latest.registrations.count + 1)"))
                    }
                }
                try self.checkAttempt(id)
                issuedRegistration = self.vault.registrations.first { $0.id == result.clientID }
                let response = try await ChatGPTHTTP.shared.token(["grant_type": "authorization_code", "client_id": result.clientID, "code": result.code, "code_verifier": transaction.verifier, "redirect_uri": transaction.redirectURI.absoluteString, "resource": ChatGPTOAuth.resource])
                try self.checkAttempt(id)
                let tokens = try response.credentials()
                let identity = try await ChatGPTHTTP.shared.identity(tokens.idToken, clientID: result.clientID, nonce: transaction.nonce)
                try self.checkAttempt(id)
                if let previous = registration?.identity, previous.subject != identity.subject || previous.issuer != identity.issuer { throw ChatGPTError("That ChatGPT account differs from the selected connection. Use Add account to connect it separately.") }
                self.vault = try await self.store.update { latest in
                    try self.checkAttempt(id)
                    guard let index = latest.registrations.firstIndex(where: { $0.id == result.clientID }) else { throw ChatGPTError("The ChatGPT registration couldn’t be saved. Try again.") }
                    latest.registrations[index].identity = identity; latest.registrations[index].tokens = tokens; latest.activeID = result.clientID
                }
                try self.checkAttempt(id)
                try self.store.setSignedOut(result.clientID, false)
                self.vault = try self.store.load()
                self.invalidateRequests(); self.publish(); self.error = nil
                if !tokens.permitsPlanUsage { self.status = "Signed in. ChatGPT plan usage wasn’t granted. Enable it here to send questions." }
                self.isSigningIn = false; self.authTask = nil; self.listener = nil
                NSApp.activate(ignoringOtherApps: true)
                if tokens.permitsPlanUsage { self.refreshModels() }
            } catch {
                guard self.attemptID == id else { return }
                listener.cancel(); self.listener = nil; self.authTask = nil; self.isSigningIn = false
                if (error as? ChatGPTError)?.code == "invalid_grant", canRetryCode, let issuedRegistration {
                    self.beginSignIn(registration: issuedRegistration, requestConsent: requestConsent, canRetryCode: false)
                    return
                }
                if error is CancellationError { self.status = self.isSignedIn ? "Connected to ChatGPT." : "Sign-in canceled. Continue with ChatGPT whenever you’re ready." }
                else { self.error = self.safeMessage(error); self.status = "ChatGPT sign-in needs attention." }
            }
        }
    }
    private func checkAttempt(_ id: UUID) throws { try Task.checkCancellation(); guard attemptID == id else { throw CancellationError() } }
    func cancelSignIn() {
        attemptID = UUID(); authTask?.cancel(); authTask = nil; listener?.cancel(); listener = nil
        if isSigningIn { status = isSignedIn ? "Connected to ChatGPT." : "Sign-in canceled. Continue with ChatGPT whenever you’re ready." }
        isSigningIn = false
    }
    func selectAccount(_ id: String) {
        guard !isSigningOut, id != vault.activeID, vault.registrations.contains(where: { $0.id == id }) else { return }
        cancelSignIn(); invalidateRequests()
        let epoch = requestEpoch
        Task { [weak self] in
            guard let self else { return }
            do {
                let updated = try await self.store.update { latest in guard self.requestEpoch == epoch else { throw CancellationError() }; latest.activeID = id }
                guard self.requestEpoch == epoch else { return }
                self.vault = updated; self.error = nil; self.publish()
                if self.permitsPlanUsage { self.refreshModels() } else if !self.isSignedIn { self.status = "Continue with ChatGPT to reconnect this account." }
            } catch { if self.requestEpoch == epoch { self.error = self.safeMessage(error) } }
        }
    }
    func selectModel(_ id: String) {
        guard !isSigningOut, models.contains(where: { $0.id == id }), let activeID = vault.activeID else { return }
        selectedModelID = id
        let epoch = requestEpoch
        Task { [weak self] in
            guard let self else { return }
            do {
                let updated = try await self.store.update { latest in
                    guard self.requestEpoch == epoch, let index = latest.registrations.firstIndex(where: { $0.id == activeID }) else { throw CancellationError() }
                    latest.registrations[index].selectedModel = id
                }
                if self.requestEpoch == epoch { self.vault = updated }
            } catch { if self.requestEpoch == epoch { self.error = self.safeMessage(error) } }
        }
    }
    func refreshModels() {
        catalogTask?.cancel()
        guard permitsPlanUsage, !fixtureMode else { return }
        let epoch = requestEpoch
        catalogTask = Task { [weak self] in
            guard let self else { return }
            do {
                let session = try await self.usableSession()
                let catalog = try await ChatGPTHTTP.shared.models(accessToken: session.accessToken)
                try Task.checkCancellation(); guard self.requestEpoch == epoch else { return }
                self.models = catalog
                if !catalog.contains(where: { $0.id == self.selectedModelID }), let first = catalog.first { self.selectModel(first.id) }
                self.error = nil
                self.status = catalog.isEmpty ? "No eligible ChatGPT models are available for this connection. Check the account and workspace." : "Connected to ChatGPT. Requests use your ChatGPT plan and app limits."
            } catch {
                guard !Task.isCancelled, self.requestEpoch == epoch else { return }
                self.error = self.safeMessage(error)
            }
        }
    }
    func usableSession() async throws -> ChatGPTAuthorizedSession {
        guard !fixtureMode else { throw ChatGPTError("Generated account fixtures cannot make ChatGPT requests.") }
        let epoch = requestEpoch
        guard !isSigningOut, let registration = activeRegistration, !store.isSignedOut(registration.id), let tokens = registration.tokens else { throw ChatGPTError("Continue with ChatGPT in Settings to send your question.") }
        guard tokens.permitsPlanUsage else { throw ChatGPTError("Enable ChatGPT plan usage in Settings to send your question.") }
        var current = tokens
        if tokens.expiresAt.timeIntervalSinceNow < 90 {
            if let refreshTask = refreshTasks[registration.id] { current = try await refreshTask.value }
            else {
                let task = Task { [weak self] () throws -> ChatGPTTokens in
                    guard let self else { throw CancellationError() }
                    let lock = ChatGPTRefreshLock(); try await lock.acquire()
                    defer { withExtendedLifetime(lock) {} }
                    // Re-read under the cross-process lock to avoid using an already-rotated refresh token.
                    var latest = try self.store.load(includeSignedOutTokens: true)
                    guard !self.store.isSignedOut(registration.id), let index = latest.registrations.firstIndex(where: { $0.id == registration.id }), let stored = latest.registrations[index].tokens else { throw CancellationError() }
                    if stored.expiresAt.timeIntervalSinceNow >= 90 { if self.requestEpoch == epoch { self.vault = try self.store.load(); self.publish() }; return stored }
                    if let earliest = stored.earliestRefreshAt, earliest > Date() { throw ChatGPTError("ChatGPT isn’t ready to renew this connection yet. Try again shortly.") }
                    guard let refresh = stored.refreshToken else { throw ChatGPTError("Reconnect ChatGPT in Settings to renew this session.", code: "invalid_refresh_token") }
                    let response: ChatGPTTokenResponse
                    do { response = try await ChatGPTHTTP.shared.token(["grant_type": "refresh_token", "client_id": registration.clientID, "refresh_token": refresh, "resource": ChatGPTOAuth.resource]) }
                    catch {
                        if (error as? ChatGPTError)?.invalidatesSession == true {
                            latest.registrations[index].tokens = nil; try self.store.save(latest)
                            if self.vault.activeID == registration.id { self.invalidateRequests(); self.vault = try self.store.load(); self.publish(); self.status = "Your ChatGPT connection ended. Continue with ChatGPT to reconnect." }
                        }
                        throw error
                    }
                    let replacement = try response.credentials(previous: stored)
                    guard response.refresh_token?.isEmpty == false else { throw ChatGPTError("ChatGPT didn’t return a renewable replacement session. Reconnect in Settings.", code: "invalid_refresh_token") }
                    if let idToken = response.id_token {
                        do {
                            let identity = try await ChatGPTHTTP.shared.identity(idToken, clientID: registration.clientID, nonce: nil)
                            guard identity.subject == registration.identity?.subject, identity.issuer == registration.identity?.issuer else { throw ChatGPTError("ChatGPT returned a different account during renewal. Reconnect in Settings.", code: "invalid_refresh_token") }
                        } catch {
                            latest.registrations[index].tokens = nil; try self.store.save(latest)
                            throw ChatGPTError("ChatGPT’s renewed identity couldn’t be verified. Reconnect in Settings.", code: "invalid_refresh_token")
                        }
                    }
                    // Commit a server rotation even when its original caller switched accounts. A durable
                    // sign-out marker prevents reuse; sign-out then revokes this newest token under this lock.
                    latest.registrations[index].tokens = replacement
                    try self.store.save(latest)
                    if self.requestEpoch == epoch { self.vault = try self.store.load(); self.publish() }
                    return replacement
                }
                refreshTasks[registration.id] = task
                do { current = try await task.value; refreshTasks[registration.id] = nil }
                catch {
                    refreshTasks[registration.id] = nil
                    if requestEpoch == epoch, (error as? ChatGPTError)?.invalidatesSession == true {
                        let updated = try await store.update { latest in
                            if let index = latest.registrations.firstIndex(where: { $0.id == registration.id }) { latest.registrations[index].tokens = nil }
                        }
                        invalidateRequests(); vault = updated; publish(); status = "Your ChatGPT connection ended. Continue with ChatGPT to reconnect."
                    }
                    throw error
                }
            }
        }
        try Task.checkCancellation(); guard epoch == requestEpoch, activeAccountID == registration.id else { throw CancellationError() }
        guard current.permitsPlanUsage else { throw ChatGPTError("ChatGPT plan usage wasn’t granted for the renewed session. Enable it in Settings.") }
        return ChatGPTAuthorizedSession(accessToken: current.accessToken, clientID: registration.clientID, epoch: epoch)
    }
    func signOut() {
        guard !isSigningOut, let registration = activeRegistration else { return }
        cancelSignIn(); invalidateRequests(); isSigningOut = true; needsSignOutRetry = false; error = nil; status = "Signing out of ChatGPT…"
        if let index = vault.registrations.firstIndex(where: { $0.id == registration.id }) { vault.registrations[index].tokens = nil }
        publish()
        do { try store.setSignedOut(registration.id, true) }
        catch { self.error = "Vale couldn’t save the signed-out state in Keychain. This window stopped using ChatGPT. Unlock Keychain and retry sign-out before quitting."; needsSignOutRetry = true; isSigningOut = false; return }
        // Remove credentials from the active in-memory account immediately; the captured copy is used only for revocation.
        signOutTask = Task { [weak self] in
            guard let self else { return }
            var remoteConfirmed = true
            do {
                let lock = ChatGPTRefreshLock(); try await lock.acquire(); defer { withExtendedLifetime(lock) {} }
                var latest = try self.store.load(includeSignedOutTokens: true)
                if let index = latest.registrations.firstIndex(where: { $0.id == registration.id }) {
                    if let tokens = latest.registrations[index].tokens {
                        do { try await ChatGPTHTTP.shared.revoke(tokens, clientID: registration.clientID) } catch { remoteConfirmed = false }
                    }
                    latest.registrations[index].tokens = nil
                }
                try self.store.save(latest); self.vault = try self.store.load()
            }
            catch { self.error = "Vale couldn’t remove the saved ChatGPT session from Keychain. Unlock Keychain and retry sign-out."; self.needsSignOutRetry = true }
            self.isSigningOut = false; self.signOutTask = nil; self.publish()
            self.status = remoteConfirmed ? "Signed out of ChatGPT. Your local chats are saved." : "Signed out locally. Remote revocation wasn’t confirmed; disconnect Vale in ChatGPT Settings → Usage."
        }
    }
    private func safeMessage(_ error: Error) -> String {
        if let error = error as? ChatGPTError { return error.message }
        if error is CancellationError { return "The ChatGPT request was canceled." }
        return "The ChatGPT connection stopped. Check your internet connection and try again."
    }
}

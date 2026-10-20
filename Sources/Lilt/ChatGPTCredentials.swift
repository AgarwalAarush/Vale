import Foundation
import Security
import LiltCore
import Darwin

struct ChatGPTTokens: Codable {
    var accessToken: String
    var refreshToken: String?
    var idToken: String
    var scopes: [String]
    var expiresAt: Date
    var earliestRefreshAt: Date?
    var permitsPlanUsage: Bool { scopes.contains("chatgpt.tokens.use.direct") && scopes.contains("resource.invoke") }
}

struct ChatGPTRegistration: Codable, Identifiable {
    var clientID: String
    var identity: ChatGPTIdentity?
    var label: String
    var tokens: ChatGPTTokens?
    var selectedModel: String?
    var id: String { clientID }
    var displayName: String { identity?.name ?? identity?.email ?? label }
}

struct ChatGPTCredentialVault: Codable {
    var hostID = "urn:uuid:" + UUID().uuidString.lowercased()
    var registrations: [ChatGPTRegistration] = []
    var activeID: String?
}

/// This namespace is intentionally independent of legacy Lilt settings and Codex credentials.
@MainActor final class ChatGPTCredentialStore {
    private let service = "local.lilt.companion.chatgpt.oauth.v1"
    private let memoryOnly: Bool
    private var memory = ChatGPTCredentialVault()
    private var blockedMemory = Set<String>()
    init(memoryOnly: Bool) { self.memoryOnly = memoryOnly }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "account-vault", kSecAttrSynchronizable as String: false]
    }
    func load(includeSignedOutTokens: Bool = false) throws -> ChatGPTCredentialVault {
        if memoryOnly { return filtered(memory, includeSignedOutTokens: includeSignedOutTokens) }
        var request = query; request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return ChatGPTCredentialVault() }
        guard status == errSecSuccess, let data = result as? Data else { throw ChatGPTError("Vale couldn’t read its ChatGPT connection from Keychain. Unlock your login Keychain and try again.") }
        do { return filtered(try JSONDecoder().decode(ChatGPTCredentialVault.self, from: data), includeSignedOutTokens: includeSignedOutTokens) }
        catch { throw ChatGPTError("Vale’s ChatGPT connection couldn’t be read. Your chats are safe. Reconnect ChatGPT in Settings.") }
    }
    private func filtered(_ value: ChatGPTCredentialVault, includeSignedOutTokens: Bool) -> ChatGPTCredentialVault {
        guard !includeSignedOutTokens else { return value }
        var vault = value
        for index in vault.registrations.indices where isSignedOut(vault.registrations[index].id) { vault.registrations[index].tokens = nil }
        return vault
    }
    func isSignedOut(_ clientID: String) -> Bool {
        if memoryOnly { return blockedMemory.contains(clientID) }
        var request = query; request[kSecAttrAccount as String] = "signed-out-" + clientID
        let status = SecItemCopyMatching(request as CFDictionary, nil)
        // A Keychain error must not silently reactivate a connection with uncertain sign-out state.
        return status != errSecItemNotFound
    }
    func setSignedOut(_ clientID: String, _ signedOut: Bool) throws {
        if memoryOnly { if signedOut { blockedMemory.insert(clientID) } else { blockedMemory.remove(clientID) }; return }
        var request = query; request[kSecAttrAccount as String] = "signed-out-" + clientID
        if signedOut {
            request[kSecValueData as String] = Data([1]); request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let status = SecItemAdd(request as CFDictionary, nil)
            guard status == errSecSuccess || status == errSecDuplicateItem else { throw saveError() }
        } else {
            let status = SecItemDelete(request as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw saveError() }
        }
    }
    func save(_ vault: ChatGPTCredentialVault) throws {
        if memoryOnly { memory = vault; return }
        let data = try JSONEncoder().encode(vault)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var request = query; request[kSecValueData as String] = data
            request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(request as CFDictionary, nil) == errSecSuccess else { throw saveError() }
        } else if status != errSecSuccess { throw saveError() }
    }
    func update(_ mutation: (inout ChatGPTCredentialVault) throws -> Void) async throws -> ChatGPTCredentialVault {
        let lock = ChatGPTRefreshLock()
        if !memoryOnly { try await lock.acquire() }
        defer { withExtendedLifetime(lock) {} }
        var latest = try load(includeSignedOutTokens: true)
        try mutation(&latest); try save(latest)
        return try load()
    }
    private func saveError() -> ChatGPTError { ChatGPTError("Vale couldn’t save its ChatGPT connection securely in Keychain. Unlock your login Keychain and try again.") }
}

/// Serialize rotating refreshes across running Vale copies, without sharing tokens through disk.
final class ChatGPTRefreshLock {
    private var descriptor: Int32 = -1
    func acquire() async throws {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Lilt/ChatGPT", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let path = folder.appendingPathComponent("refresh.lock").path
        descriptor = open(path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw ChatGPTError("Vale couldn’t protect the ChatGPT session refresh. Try again.") }
        for _ in 0..<100 {
            try Task.checkCancellation()
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return }
            guard errno == EWOULDBLOCK else { throw ChatGPTError("Vale couldn’t protect the ChatGPT session refresh. Try again.") }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw ChatGPTError("Another Vale window is renewing ChatGPT. Wait a moment and try again.")
    }
    deinit { if descriptor >= 0 { _ = flock(descriptor, LOCK_UN); close(descriptor) } }
}

struct ChatGPTTokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let id_token: String?
    let token_type: String
    let expires_in: TimeInterval
    let scope: String?
    let earliest_refresh_at: TimeInterval?
    func credentials(previous: ChatGPTTokens? = nil, now: Date = Date()) throws -> ChatGPTTokens {
        guard token_type.lowercased() == "bearer", !access_token.isEmpty, expires_in > 0, expires_in <= 86_400,
              let idToken = id_token ?? previous?.idToken, !idToken.isEmpty else { throw ChatGPTError("ChatGPT returned an incomplete connection. Try signing in again.") }
        return ChatGPTTokens(accessToken: access_token, refreshToken: refresh_token ?? previous?.refreshToken, idToken: idToken, scopes: scope.map { $0.split(whereSeparator: \.isWhitespace).map(String.init) } ?? previous?.scopes ?? [], expiresAt: now.addingTimeInterval(expires_in), earliestRefreshAt: earliest_refresh_at.map { Date(timeIntervalSince1970: $0) })
    }
}

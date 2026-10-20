import Foundation
import LiltCore

private final class ChatGPTNoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct ChatGPTDiscovery: Decodable {
    let issuer: String
    let authorization_endpoint: URL
    let token_endpoint: URL
    let revocation_endpoint: URL
    let jwks_uri: URL
    func validate() throws {
        let endpoints = [authorization_endpoint, token_endpoint, revocation_endpoint, jwks_uri]
        guard issuer == ChatGPTOAuth.issuer, endpoints.allSatisfy(Self.isTrusted) else { throw ChatGPTError("OpenAI’s sign-in configuration couldn’t be verified. Try again later.") }
    }
    private static func isTrusted(_ url: URL) -> Bool {
        guard url.scheme == "https", url.host == "auth.openai.com", url.port == nil else { return false }
        return url.user == nil && url.password == nil && url.fragment == nil && url.query == nil
    }
}

@MainActor final class ChatGPTHTTP {
    static let shared = ChatGPTHTTP()
    let session: URLSession
    private var discoveryCache: ChatGPTDiscovery?
    private var keysCache: (data: Data, date: Date)?
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 150; configuration.timeoutIntervalForResource = 180
        session = URLSession(configuration: configuration, delegate: ChatGPTNoRedirects(), delegateQueue: nil)
    }
    func discovery() async throws -> ChatGPTDiscovery {
        if let discoveryCache { return discoveryCache }
        let data = try await data(URLRequest(url: URL(string: "https://auth.openai.com/.well-known/openid-configuration")!))
        let result = try JSONDecoder().decode(ChatGPTDiscovery.self, from: data)
        try result.validate(); discoveryCache = result; return result
    }
    func identity(_ token: String, clientID: String, nonce: String?) async throws -> ChatGPTIdentity {
        let config = try await discovery()
        var keys: Data
        if let cache = keysCache, Date().timeIntervalSince(cache.date) < 3600 { keys = cache.data }
        else { keys = try await data(URLRequest(url: config.jwks_uri)); keysCache = (keys, Date()) }
        do { return try ChatGPTIdentityValidator.validate(token, jwks: keys, clientID: clientID, nonce: nonce) }
        catch {
            // A rotated or unfamiliar kid must get one fresh JWKS attempt, never unverified claims.
            keys = try await data(URLRequest(url: config.jwks_uri)); keysCache = (keys, Date())
            return try ChatGPTIdentityValidator.validate(token, jwks: keys, clientID: clientID, nonce: nonce)
        }
    }
    func token(_ values: [String: String]) async throws -> ChatGPTTokenResponse {
        let config = try await discovery()
        let response = try await data(formRequest(config.token_endpoint, values: values))
        do { return try JSONDecoder().decode(ChatGPTTokenResponse.self, from: response) }
        catch { throw ChatGPTError("ChatGPT returned an unreadable connection. Try signing in again.") }
    }
    func revoke(_ tokens: ChatGPTTokens, clientID: String) async throws {
        guard let refresh = tokens.refreshToken else { return }
        let config = try await discovery()
        let request = formRequest(config.revocation_endpoint, values: ["token": refresh, "token_type_hint": "refresh_token", "client_id": clientID])
        for attempt in 0..<3 {
            do { _ = try await data(request); return }
            catch {
                let status = (error as? ChatGPTError)?.status
                if attempt == 2 || (status != nil && status! < 500) || Task.isCancelled { throw error }
                try await Task.sleep(for: .milliseconds(250 * (1 << attempt)))
            }
        }
    }
    func models(accessToken: String) async throws -> [ChatGPTModel] {
        var request = URLRequest(url: URL(string: ChatGPTOAuth.resource + "/models")!)
        request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization")
        return try ChatGPTModel.catalog(await data(request))
    }
    private func formRequest(_ url: URL, values: [String: String]) -> URLRequest {
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.httpBody = ChatGPTOAuth.form(values)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"); return request
    }
    func data(_ request: URLRequest) async throws -> Data {
        var request = request; request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ChatGPTError("ChatGPT’s connection couldn’t be verified. Try again.") }
        guard (200..<300).contains(http.statusCode) else { throw Self.failure(http, data: data) }
        guard data.count <= 4_194_304 else { throw ChatGPTError("ChatGPT returned an oversized connection response. Try again.") }; return data
    }
    static func failure(_ response: HTTPURLResponse, data: Data) -> ChatGPTError {
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let nested = root?["error"] as? [String: Any]
        let code = nested?["code"] as? String ?? root?["error"] as? String
        let requestID = response.value(forHTTPHeaderField: "x-request-id") ?? response.value(forHTTPHeaderField: "openai-request-id")
        let message: String
        if let code, ["invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired", "refresh_token_invalidated", "refresh_token_reused"].contains(code) {
            message = "Your ChatGPT connection expired or was disconnected. Continue with ChatGPT in Settings."
        } else if code == "invalid_client" { message = "ChatGPT didn’t recognize this app registration. Reconnect the selected account in Settings." }
        else if code?.hasPrefix("subscription_sharing_") == true || code?.hasPrefix("chatpass_") == true { message = ChatGPTResponseStream.failureMessage(code) }
        else {
            switch response.statusCode {
            case 401: message = "ChatGPT didn’t accept this connection’s identity or plan permission. Check your account in Settings."
            case 403: message = "ChatGPT restricted this request for the selected account, workspace, or region. Check access in ChatGPT Settings."
            case 429: message = "ChatGPT is limiting requests. Review usage in ChatGPT Settings, then try again later."
            case 503: message = "ChatGPT is temporarily unavailable. Your question is saved; try again later."
            default: message = "ChatGPT couldn’t complete the request (HTTP \(response.statusCode)). Your question is saved; try again."
            }
        }
        let shape = nested != nil ? "error-object" : root?["error"] is String ? "oauth-error" : root?["detail"] != nil ? "detail" : root != nil ? "json-object" : "non-json"
        return ChatGPTError(message, code: code, status: response.statusCode, requestID: requestID, responseBodyShape: shape, parameter: nested?["param"] as? String)
    }
}

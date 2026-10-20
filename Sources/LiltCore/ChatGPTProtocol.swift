import Foundation
import CryptoKit
import Security

public struct ChatGPTError: LocalizedError {
    public let message: String
    public let code: String?
    public let status: Int?
    public let requestID: String?
    public let responseBodyShape: String?
    public let parameter: String?
    public init(_ message: String, code: String? = nil, status: Int? = nil, requestID: String? = nil, responseBodyShape: String? = nil, parameter: String? = nil) {
        self.message = message; self.code = code; self.status = status; self.requestID = requestID
        self.responseBodyShape = responseBodyShape; self.parameter = parameter
    }
    public var errorDescription: String? { message }
    public var invalidatesSession: Bool {
        ["invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired", "refresh_token_invalidated", "refresh_token_reused"].contains(code ?? "")
    }
}

public enum ChatGPTOAuth {
    public static let issuer = "https://auth.openai.com"
    public static let resource = "https://api.openai.com/v1"
    public static let scopes = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    public static let registrationClient = "dynamic_agent_client"
    public static func randomValue(bytes: Int = 32) throws -> String {
        var value = Data(count: bytes)
        let result = value.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        guard result == errSecSuccess else { throw ChatGPTError("A secure sign-in request couldn’t be created. Try again.") }
        return base64URL(value)
    }
    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    public static func decodeBase64URL(_ text: String) -> Data? {
        guard text.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
        let raw = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        return Data(base64Encoded: raw + String(repeating: "=", count: (4 - raw.count % 4) % 4))
    }
    public static func form(_ values: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return Data(values.keys.sorted().map { key in
            "\(key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\(values[key]!.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").utf8)
    }
}

public struct ChatGPTAuthorization {
    public let state: String
    public let nonce: String
    public let verifier: String
    public let redirectURI: URL
    public let clientID: String
    public let expiresAt: Date
    public init(redirectURI: URL, clientID: String = ChatGPTOAuth.registrationClient, now: Date = Date()) throws {
        guard redirectURI.scheme == "http", redirectURI.host == "127.0.0.1", redirectURI.port != nil, redirectURI.path == "/auth/callback", redirectURI.query == nil else { throw ChatGPTError("The local sign-in callback is invalid.") }
        self.redirectURI = redirectURI; self.clientID = clientID
        state = try ChatGPTOAuth.randomValue(); nonce = try ChatGPTOAuth.randomValue(); verifier = try ChatGPTOAuth.randomValue(bytes: 64)
        expiresAt = now.addingTimeInterval(600)
    }
    public var challenge: String { ChatGPTOAuth.base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))) }
    public func authorizationURL(endpoint: URL, hostID: String, idTokenHint: String? = nil, emailHint: String? = nil, requestConsent: Bool = false) throws -> URL {
        guard endpoint.scheme == "https", endpoint.host == "auth.openai.com" else { throw ChatGPTError("OpenAI’s sign-in address couldn’t be verified.") }
        var parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        var query = ["client_id": clientID, "ext_agent_host_id": hostID, "response_type": "code", "redirect_uri": redirectURI.absoluteString, "scope": ChatGPTOAuth.scopes, "resource": ChatGPTOAuth.resource, "state": state, "nonce": nonce, "code_challenge_method": "S256", "code_challenge": challenge]
        if clientID == ChatGPTOAuth.registrationClient { query["agent_name_hint"] = "Vale" }
        else { query["id_token_hint"] = idTokenHint; query["login_hint"] = emailHint }
        if requestConsent { query["prompt"] = "consent" }
        parts.queryItems = query.keys.sorted().map { URLQueryItem(name: $0, value: query[$0]) }
        guard let url = parts.url else { throw ChatGPTError("The sign-in address couldn’t be prepared.") }; return url
    }
    public func callback(_ url: URL, now: Date = Date()) throws -> (code: String, clientID: String) {
        guard now < expiresAt, url.scheme == redirectURI.scheme, url.host == redirectURI.host, url.port == redirectURI.port, url.path == redirectURI.path,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { throw ChatGPTError("This sign-in request expired or returned to an unexpected address. Try again.") }
        var values: [String: String] = [:]
        for item in items {
            guard values[item.name] == nil, let value = item.value else { throw ChatGPTError("The sign-in callback couldn’t be verified. Try again.") }
            values[item.name] = value
        }
        guard values["state"] == state else { throw ChatGPTError("The sign-in callback couldn’t be verified. Try again.") }
        if let error = values["error"] { throw ChatGPTError(error == "access_denied" ? "Sign-in was canceled. You can continue with ChatGPT whenever you’re ready." : "ChatGPT couldn’t complete sign-in. Try again.", code: error) }
        let issued = values["client_id"] ?? clientID
        guard !issued.isEmpty, issued != ChatGPTOAuth.registrationClient, clientID == ChatGPTOAuth.registrationClient || issued == clientID,
              let code = values["code"], !code.isEmpty else { throw ChatGPTError("ChatGPT didn’t return a complete registration. Try signing in again.") }
        return (code, issued)
    }
}

public struct ChatGPTModel: Codable, Identifiable, Equatable {
    public let slug: String
    public let displayName: String
    public var id: String { slug }
    public let supportsStructuredOutputs: Bool
    public let supportsImages: Bool?
    public let supportsWebSearch: Bool?
    public static func catalog(_ data: Data) throws -> [Self] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let rows = root["models"] as? [[String: Any]] else { throw ChatGPTError("ChatGPT returned an unreadable model list. Try refreshing the connection.") }
        var seen = Set<String>()
        return rows.compactMap { row in
            guard row["visibility"] as? String == "list", let slug = row["slug"] as? String, !slug.isEmpty, let name = row["display_name"] as? String, !name.isEmpty, seen.insert(slug).inserted else { return nil }
            // Optional capabilities are honored only when the catalog explicitly advertises them.
            return Self(slug: slug, displayName: name, supportsStructuredOutputs: row["supports_structured_outputs"] as? Bool == true, supportsImages: row["supports_images"] as? Bool, supportsWebSearch: row["supports_web_search"] as? Bool)
        }
    }
}

public enum ChatGPTResponses {
    public static func request(model: ChatGPTModel, instructions: String, prompt: String, images: [Data], search: Bool, schema: Data) throws -> Data {
        guard images.isEmpty || model.supportsImages != false else { throw ChatGPTError("The selected ChatGPT model doesn’t accept images. Choose another model in Settings.") }
        guard !search || model.supportsWebSearch != false else { throw ChatGPTError("Web search isn’t available for this model. Choose another model or turn off Web.") }
        var content: [[String: Any]] = [["type": "input_text", "text": prompt]]
        content += images.map { ["type": "input_image", "image_url": "data:image/png;base64,\($0.base64EncodedString())"] }
        var body: [String: Any] = ["model": model.slug, "instructions": instructions + "\nReturn only one JSON object with text (string), point (null or a normalized rectangle with x,y,width,height,label), and guide (null or {title,steps}). Never wrap the JSON in Markdown.", "input": [["role": "user", "content": content]], "store": false, "stream": true]
        if model.supportsStructuredOutputs {
            body["text"] = ["format": ["type": "json_schema", "name": "vale_reply", "strict": true, "schema": try JSONSerialization.jsonObject(with: schema)]]
        }
        // The sole permitted hosted tool. Account/workspace restrictions remain server authoritative.
        if search { body["tools"] = [["type": "web_search"]] }
        return try JSONSerialization.data(withJSONObject: body)
    }
}

/// Incremental SSE parser. A partial answer is never promoted to a successful reply.
public struct ChatGPTResponseStream {
    private var eventLines: [String] = []
    private var text = ""
    private var completed = false
    private var reply: TutorReply?
    public private(set) var usedWebSearch = false
    public init() {}
    public mutating func consume(line: String) throws {
        guard line.utf8.count <= 2_097_152 else { throw ChatGPTError("The response exceeded the safe reading limit. Try a shorter question.") }
        if line.isEmpty { try dispatch(); return }
        if line.hasPrefix("data:") {
            var value = String(line.dropFirst(5)); if value.first == " " { value.removeFirst() }
            eventLines.append(value)
            guard eventLines.reduce(0, { $0 + $1.utf8.count }) <= 4_194_304 else { throw ChatGPTError("The response exceeded the safe reading limit.") }
        }
    }
    private mutating func dispatch() throws {
        guard !eventLines.isEmpty else { return }; let raw = eventLines.joined(separator: "\n"); eventLines.removeAll(keepingCapacity: true)
        if raw == "[DONE]" { return }
        guard let data = raw.data(using: .utf8), let event = try JSONSerialization.jsonObject(with: data) as? [String: Any], let type = event["type"] as? String else { throw ChatGPTError("The ChatGPT stream couldn’t be read. Your question is saved; try again.") }
        switch type {
        case "response.output_text.delta":
            guard !completed else { return }; text += event["delta"] as? String ?? ""
            guard text.utf8.count <= 4_194_304 else { throw ChatGPTError("The answer exceeded the safe reading limit.") }
        case "response.completed":
            guard !completed, let response = event["response"] as? [String: Any], response["status"] as? String == "completed", response["error"] == nil || response["error"] is NSNull else { throw ChatGPTError("ChatGPT didn’t complete the response. Your question is saved; try again.") }
            let output = response["output"] as? [[String: Any]] ?? []
            let final = output.filter { $0["type"] as? String == "message" }.flatMap { $0["content"] as? [[String: Any]] ?? [] }.filter { $0["type"] as? String == "output_text" }.compactMap { $0["text"] as? String }.joined()
            usedWebSearch = output.contains { $0["type"] as? String == "web_search_call" && $0["status"] as? String == "completed" }
            do { reply = try TutorReply.decode(Data((final.isEmpty ? text : final).utf8)) }
            catch { throw ChatGPTError("ChatGPT returned an unreadable reply. Your question is saved; try again.") }
            completed = true
        case "response.failed", "response.incomplete", "error":
            let response = event["response"] as? [String: Any]
            let details = response?["error"] as? [String: Any] ?? event["error"] as? [String: Any] ?? event
            let code = details["code"] as? String
            throw ChatGPTError(Self.failureMessage(code), code: code, responseBodyShape: type, parameter: details["param"] as? String)
        default: break
        }
    }
    public mutating func finish() throws -> TutorReply {
        try dispatch()
        guard completed, let reply else { throw ChatGPTError("The connection ended before ChatGPT completed its answer. Your question is saved; try again.") }; return reply
    }
    public static func failureMessage(_ code: String?) -> String {
        switch code {
        case "subscription_sharing_usage_limit_exceeded": return "ChatGPT’s usage limit for this request was reached. Review app access and limits in ChatGPT Settings → Usage, then retry when available."
        case "subscription_sharing_user_not_eligible": return "ChatGPT plan usage isn’t available for this account or workspace. Check the selected account in Settings."
        case "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable": return "ChatGPT plan usage is temporarily unavailable. Your question is saved; try again later."
        case "subscription_sharing_unsupported_capability": return "The selected ChatGPT model or workspace doesn’t support this request’s inputs or web search. Adjust the request or model in Settings."
        case "chatpass_v2_scope_not_authorized", "chatpass_v2_invalid_authorization_context": return "ChatGPT didn’t authorize plan usage for this connection. Enable ChatGPT plan usage in Settings."
        default: return "ChatGPT couldn’t complete the answer. Your question is saved; try again."
        }
    }
}

import Foundation
import Security

public struct ChatGPTIdentity: Equatable, Codable {
    public let issuer: String
    public let subject: String
    public let email: String?
    public let name: String?
}

public enum ChatGPTIdentityValidator {
    /// RS256 is the sole signing algorithm in OpenAI's production discovery document.
    public static func validate(_ token: String, jwks: Data, clientID: String, nonce: String?, now: Date = Date()) throws -> ChatGPTIdentity {
        let pieces = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard pieces.count == 3, token.utf8.count < 131_072,
              let headerData = ChatGPTOAuth.decodeBase64URL(pieces[0]), let payloadData = ChatGPTOAuth.decodeBase64URL(pieces[1]), let signature = ChatGPTOAuth.decodeBase64URL(pieces[2]),
              let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any], header["alg"] as? String == "RS256", header["crit"] == nil,
              let kid = header["kid"] as? String, !kid.isEmpty,
              let set = try JSONSerialization.jsonObject(with: jwks) as? [String: Any], let keys = set["keys"] as? [[String: Any]] else { throw invalid() }
        let matches = keys.filter { $0["kid"] as? String == kid && $0["kty"] as? String == "RSA" && ($0["alg"] == nil || $0["alg"] as? String == "RS256") && ($0["use"] == nil || $0["use"] as? String == "sig") }
        guard matches.count == 1, let key = matches.first, let n = key["n"] as? String, let e = key["e"] as? String,
              let modulus = ChatGPTOAuth.decodeBase64URL(n), let exponent = ChatGPTOAuth.decodeBase64URL(e), modulus.count >= 256, modulus.count <= 1024, !exponent.isEmpty,
              let publicKey = SecKeyCreateWithData(rsaDER(modulus: modulus, exponent: exponent) as CFData, [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic] as CFDictionary, nil),
              SecKeyIsAlgorithmSupported(publicKey, .verify, .rsaSignatureMessagePKCS1v15SHA256),
              SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256, Data((pieces[0] + "." + pieces[1]).utf8) as CFData, signature as CFData, nil),
              let claims = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any], claims["iss"] as? String == ChatGPTOAuth.issuer,
              let subject = claims["sub"] as? String, !subject.isEmpty,
              let expiry = claims["exp"] as? Double, expiry > now.timeIntervalSince1970 - 5,
              let issued = claims["iat"] as? Double, issued <= now.timeIntervalSince1970 + 5 else { throw invalid() }
        let audience = (claims["aud"] as? String).map { [$0] } ?? claims["aud"] as? [String] ?? []
        guard audience.contains(clientID), audience.count == 1 || claims["azp"] as? String == clientID else { throw invalid() }
        if let authorized = claims["azp"] as? String, authorized != clientID { throw invalid() }
        if let notBefore = claims["nbf"] as? Double, notBefore > now.timeIntervalSince1970 + 5 { throw invalid() }
        if let nonce, claims["nonce"] as? String != nonce { throw invalid() }
        return ChatGPTIdentity(issuer: ChatGPTOAuth.issuer, subject: subject, email: claims["email"] as? String, name: claims["name"] as? String)
    }
    private static func invalid() -> ChatGPTError { ChatGPTError("ChatGPT’s identity couldn’t be verified. No account was changed. Try signing in again.", code: "invalid_id_token") }
    private static func length(_ count: Int) -> Data {
        if count < 128 { return Data([UInt8(count)]) }
        var remaining = count; var bytes: [UInt8] = []
        while remaining > 0 { bytes.insert(UInt8(remaining & 255), at: 0); remaining >>= 8 }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }
    private static func integer(_ value: Data) -> Data {
        var bytes = value
        while bytes.count > 1, bytes.first == 0 { bytes.removeFirst() }
        if let first = bytes.first, first & 0x80 != 0 { bytes.insert(0, at: 0) }
        return Data([0x02]) + length(bytes.count) + bytes
    }
    private static func rsaDER(modulus: Data, exponent: Data) -> Data {
        let body = integer(modulus) + integer(exponent)
        return Data([0x30]) + length(body.count) + body
    }
}

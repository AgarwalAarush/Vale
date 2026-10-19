import Foundation

public struct UpdateConfiguration: Equatable {
    public let feed: URL
    public let publicKey: String
    public init(feed: String, publicKey: String, requiresSignedFeed: Bool, verifiesBeforeExtraction: Bool, signedFeedFailureExpirationInterval: TimeInterval = 0) throws {
        guard !feed.contains(where: \.isWhitespace),let url=URL(string:feed),url.scheme?.lowercased()=="https",let host=url.host,!host.isEmpty,url.user==nil,url.password==nil,url.fragment==nil,(url.port ?? 443)>0 else{throw UpdateConfigurationError.insecureFeed}
        guard let key=Data(base64Encoded:publicKey),key.count==32 else{throw UpdateConfigurationError.invalidKey}
        guard requiresSignedFeed,verifiesBeforeExtraction,signedFeedFailureExpirationInterval == 0 else{throw UpdateConfigurationError.incompleteVerification}
        self.feed=url;self.publicKey=publicKey
    }
    public static func read(from info: [String: Any]) throws -> UpdateConfiguration? {
        guard info["SUFeedURL"] != nil || info["SUPublicEDKey"] != nil else { return nil }
        guard let feed = info["SUFeedURL"] as? String,
              let publicKey = info["SUPublicEDKey"] as? String,
              let expiration = info["SUSignedFeedFailureExpirationInterval"] as? NSNumber else {
            throw UpdateConfigurationError.incompleteVerification
        }
        return try UpdateConfiguration(
            feed: feed,
            publicKey: publicKey,
            requiresSignedFeed: info["SURequireSignedFeed"] as? Bool == true,
            verifiesBeforeExtraction: info["SUVerifyUpdateBeforeExtraction"] as? Bool == true,
            signedFeedFailureExpirationInterval: expiration.doubleValue
        )
    }
    public func permitsRelease(_ url:URL)->Bool{
        url.scheme?.lowercased()=="https" && url.host?.lowercased()==feed.host?.lowercased() && (url.port ?? 443)==(feed.port ?? 443) && url.user==nil && url.password==nil && url.fragment==nil
    }
    public func permitsReleases(_ urls:[URL])->Bool {
        !urls.isEmpty && urls.allSatisfy(permitsRelease)
    }
}
public enum UpdateConfigurationError: Error {case insecureFeed,invalidKey,incompleteVerification}

public enum UpdateRuntimePolicy {
    /// Native fixture runs must not contact the production updater or mutate its preferences.
    public static func permitsProductionUpdates(arguments: [String]) -> Bool {
        !arguments.contains("--self-test") && !arguments.contains("--integration-test")
    }
}

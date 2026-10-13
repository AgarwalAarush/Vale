import Foundation

public struct UpdateConfiguration: Equatable {
    public let feed: URL
    public let publicKey: String
    public init(feed: String, publicKey: String, requiresSignedFeed: Bool, verifiesBeforeExtraction: Bool) throws {
        guard let url=URL(string:feed),url.scheme?.lowercased()=="https",let host=url.host,!host.isEmpty,url.user==nil,url.password==nil,url.fragment==nil else{throw UpdateConfigurationError.insecureFeed}
        guard let key=Data(base64Encoded:publicKey),key.count==32 else{throw UpdateConfigurationError.invalidKey}
        guard requiresSignedFeed,verifiesBeforeExtraction else{throw UpdateConfigurationError.incompleteVerification}
        self.feed=url;self.publicKey=publicKey
    }
    public func permitsRelease(_ url:URL)->Bool{
        url.scheme?.lowercased()=="https" && url.host?.lowercased()==feed.host?.lowercased() && (url.port ?? 443)==(feed.port ?? 443) && url.user==nil && url.password==nil
    }
}
public enum UpdateConfigurationError: Error {case insecureFeed,invalidKey,incompleteVerification}

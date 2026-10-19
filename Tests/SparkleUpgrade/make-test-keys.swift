import Foundation
import CryptoKit

// Preparation only: invoked explicitly by prototype.py after its authorization flag.
guard CommandLine.arguments.count == 3,
      CommandLine.arguments[1] == "--generate-ephemeral-files" else {
    fatalError("Explicit --generate-ephemeral-files RUN_ROOT is required")
}
let root = URL(fileURLWithPath: CommandLine.arguments[2]).resolvingSymlinksInPath()
guard root.lastPathComponent.hasPrefix("vale-sparkle-fixture."),
      ["/tmp", "/private/tmp"].contains(root.deletingLastPathComponent().path) else {
    fatalError("Refusing a root outside the dedicated temporary fixture directory")
}
let seedURL = root.appendingPathComponent("test-seed.base64")
let publicURL = root.appendingPathComponent("test-public.base64")
guard !FileManager.default.fileExists(atPath: seedURL.path),
      !FileManager.default.fileExists(atPath: publicURL.path) else {
    fatalError("Refusing to overwrite fixture keys")
}
let key = Curve25519.Signing.PrivateKey()
try (key.rawRepresentation.base64EncodedString() + "\n").write(to: seedURL, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: seedURL.path)
try (key.publicKey.rawRepresentation.base64EncodedString() + "\n").write(to: publicURL, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: publicURL.path)
// No private or public key content is printed.

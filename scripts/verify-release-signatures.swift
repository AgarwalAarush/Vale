// Public-key-only verification. Never load an Ed25519 signing seed or Keychain item.
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 4, let publicBytes = Data(base64Encoded: args[2]), publicBytes.count == 32,
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicBytes),
      let data = try? Data(contentsOf: URL(fileURLWithPath: args[3])) else {
    fail("Usage: verifier archive PUBLIC_KEY FILE SIGNATURE | feed PUBLIC_KEY FILE")
}
let signed: Data
let signature: Data
switch args[1] {
case "archive":
    guard args.count == 5, let decoded = Data(base64Encoded: args[4]), decoded.count == 64 else {
        fail("Invalid archive signature encoding")
    }
    signed = data
    signature = decoded
case "feed":
    let prefix = Data("<!-- sparkle-signatures:\n".utf8)
    guard args.count == 4, let range = data.range(of: prefix, options: .backwards),
          let suffix = data.range(of: Data("-->".utf8), in: range.upperBound..<data.endIndex),
          data[suffix.upperBound...].allSatisfy({ [9, 10, 13, 32].contains($0) }),
          data[..<range.lowerBound].range(of: prefix) == nil,
          let footer = String(data: data[range.upperBound..<suffix.lowerBound], encoding: .utf8) else {
        fail("Missing or malformed Sparkle signature footer")
    }
    let lines = footer.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    let signatures = lines.filter { $0.hasPrefix("edSignature:") }
    let lengths = lines.filter { $0.hasPrefix("length:") }
    guard signatures.count == 1, lengths.count == 1,
          let decoded = Data(base64Encoded: String(signatures[0].dropFirst(12)).trimmingCharacters(in: .whitespaces)),
          decoded.count == 64,
          let length = Int(String(lengths[0].dropFirst(7)).trimmingCharacters(in: .whitespaces)),
          length == range.lowerBound else { fail("Invalid Sparkle signature length or encoding") }
    signed = Data(data[..<range.lowerBound])
    signature = decoded
default:
    fail("Unknown verification mode")
}
guard key.isValidSignature(signature, for: signed) else { fail("Ed25519 public-key verification failed") }
print("Verified \(args[1]) Ed25519 signature")

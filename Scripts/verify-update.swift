import Foundation
import CryptoKit

// Verify the final bytes with the public key shipped in Levels, without Keychain access.
final class Feed: NSObject, XMLParserDelegate {
    var enclosures: [[String: String]] = []
    func parser(_ parser: XMLParser, didStartElement name: String,
                namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if name == "enclosure" { enclosures.append(attributes) }
    }
}

do {
    guard CommandLine.arguments.count == 4 else {
        throw NSError(domain: "Levels", code: 1, userInfo: [NSLocalizedDescriptionKey: "Pass archive, appcast, and app Info.plist paths."])
    }
    let archive = URL(fileURLWithPath: CommandLine.arguments[1])
    let bytes = try Data(contentsOf: archive)
    let info = try PropertyListSerialization.propertyList(
        from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3])), format: nil) as! [String: Any]
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: info["SUPublicEDKey"] as! String)!)
    let feed = Feed()
    let parser = XMLParser(data: try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
    parser.delegate = feed
    guard parser.parse(), let entry = feed.enclosures.first(where: {
        URL(string: $0["url"] ?? "")?.lastPathComponent == archive.lastPathComponent
    }), let address = URL(string: entry["url"] ?? ""), address.scheme == "https",
        address.user == nil, address.password == nil,
        Int(entry["length"] ?? "") == bytes.count,
        let signature = Data(base64Encoded: entry["sparkle:edSignature"] ?? ""),
        key.isValidSignature(signature, for: bytes) else {
        throw NSError(domain: "Levels", code: 2, userInfo: [NSLocalizedDescriptionKey: "Archive signature, length, or feed URL is invalid."])
    }
    var damaged = bytes
    guard !damaged.isEmpty else { throw NSError(domain: "Levels", code: 3) }
    damaged[0] ^= 1
    guard !key.isValidSignature(signature, for: damaged) else { throw NSError(domain: "Levels", code: 4) }
    print("Verified archive length and Ed25519 signature with the bundled public key; altered bytes rejected.")
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}

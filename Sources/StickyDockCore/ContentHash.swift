import CryptoKit
import Foundation

/// Content hashing, the thing that stops the sync looping.
///
/// A push to Apple Notes bumps that note's modification date, so a timestamp
/// comparison would read our own write as a remote change on the very next
/// poll, push it back, and never settle. Hashes do not have that problem: after
/// a push, both sides hash the same, so there is nothing to do.
public enum ContentHash {
    public static func of(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(RemoteNote.normalise(text).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

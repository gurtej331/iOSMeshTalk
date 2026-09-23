import Foundation
import CryptoKit

/// Byte-for-byte compatible with com.example.crypto.SimpleCrypto:
/// key = SHA-256("MeshTalk_Shared_Passphrase_V1"), AES-256-GCM, 12-byte
/// nonce prepended to ciphertext+tag, whole thing Base64-encoded.
///
/// Same caveat as the Android side: shared passphrase, not per-user
/// end-to-end encryption. Anyone running this app build can decrypt.
enum SimpleCrypto {
    private static let sharedPassphrase = "MeshTalk_Shared_Passphrase_V1"

    private static let key: SymmetricKey = {
        let digest = SHA256.hash(data: Data(sharedPassphrase.utf8))
        return SymmetricKey(data: Data(digest))
    }()

    static func encrypt(_ plaintext: String) -> String {
        guard let data = plaintext.data(using: .utf8) else { return "" }
        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            // .combined is nonce + ciphertext + tag, in that order -- the
            // same layout the Android side builds by hand (iv + cipherText,
            // where Java's GCM cipherText already has the tag appended).
            guard let combined = sealedBox.combined else { return "" }
            return combined.base64EncodedString()
        } catch {
            return ""
        }
    }

    static func decrypt(_ encryptedBase64: String) -> String {
        guard let combined = Data(base64Encoded: encryptedBase64) else { return "" }
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: combined)
            let plainData = try AES.GCM.open(sealedBox, using: key)
            return String(data: plainData, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}

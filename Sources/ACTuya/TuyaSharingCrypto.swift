import CryptoKit
import Foundation

/// Criptografia das requisições do SDK de compartilhamento da Tuya
/// (port de `tuya_sharing/customerapi.py`, licença MIT).
enum TuyaSharingCrypto {
    /// Cada requisição deriva sua chave do próprio `requestID` e do refresh token.
    static func keys(requestID: String, refreshToken: String) -> (hashKey: String, secret: String) {
        let hashKey = Insecure.MD5.hash(data: Data((requestID + refreshToken).utf8)).hexString
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data(hashKey.utf8),
            using: SymmetricKey(data: Data(requestID.utf8))
        )
        return (hashKey, String(Data(mac).hexString.prefix(16)))
    }

    /// Parâmetros cifrados: base64(nonce) + base64(cifrado + tag), como o SDK envia.
    static func encrypt(_ json: String, secret: String, nonce: [UInt8]) throws -> String {
        let box = try AES.GCM.seal(
            Data(json.utf8),
            using: SymmetricKey(data: Data(secret.utf8)),
            nonce: AES.GCM.Nonce(data: nonce)
        )
        return Data(nonce).base64EncodedString() + (box.ciphertext + box.tag).base64EncodedString()
    }

    /// Resposta do servidor: base64(nonce + cifrado + tag).
    static func decrypt(_ base64: String, secret: String) throws -> Data {
        guard let combined = Data(base64Encoded: base64) else { throw TuyaSharingError.invalidResponse }
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: SymmetricKey(data: Data(secret.utf8)))
    }

    /// Assinatura: cabeçalhos não vazios em "chave=valor" unidos por "||", mais os dados cifrados.
    static func sign(hashKey: String, headers: [(String, String)], queryEncdata: String, bodyEncdata: String) -> String {
        let headerString = headers
            .filter { !$0.1.isEmpty }
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "||")
        let message = headerString + queryEncdata + bodyEncdata
        let mac = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: SymmetricKey(data: Data(hashKey.utf8)))
        return Data(mac).hexString
    }

    /// Nonce de 12 caracteres do mesmo alfabeto usado pelo SDK.
    static func randomNonce() -> [UInt8] {
        let alphabet = Array("ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678".utf8)
        return (0..<12).map { _ in alphabet.randomElement()! }
    }
}

extension Sequence where Element == UInt8 {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

extension Digest {
    var hexString: String { Array(self).hexString }
}

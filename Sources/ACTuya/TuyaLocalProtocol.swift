import CommonCrypto
import CryptoKit
import Foundation

// Protocolo local Tuya 3.3 (porte do tinytuya, licença MIT): mensagens 0x55AA com
// CRC32 e conteúdo cifrado em AES-128-ECB com a chave local do aparelho.

public enum TuyaCommand: UInt32, Sendable {
    case control = 0x07
    case status = 0x08
    case heartbeat = 0x09
    case dpQuery = 0x0a
    case controlNew = 0x0d
    case udpNew = 0x13

    /// Comandos enviados sem o cabeçalho "3.3" + 12 zeros.
    var omitsVersionHeader: Bool {
        self == .dpQuery || self == .heartbeat
    }
}

public enum TuyaProtocolError: Error, Equatable {
    case badChecksum
    case frameTooLarge
    case decryptionFailed
}

/// Mensagem recebida do aparelho (sempre com código de retorno).
public struct TuyaFrame: Equatable, Sendable {
    public let sequence: UInt32
    public let command: UInt32
    public let returnCode: UInt32
    public let payload: Data
}

private let prefix: UInt32 = 0x0000_55AA
private let suffix: UInt32 = 0x0000_AA55
private let versionHeader = Data("3.3".utf8) + Data(repeating: 0, count: 12)

/// Junta os bytes que chegam pelo TCP e entrega mensagens inteiras, uma de cada vez.
public struct TuyaFrameBuffer: Sendable {
    private var data = Data()

    public init() {}

    public mutating func append(_ bytes: Data) {
        data.append(bytes)
    }

    public mutating func nextFrame() throws -> TuyaFrame? {
        // Descarta lixo antes do início de uma mensagem.
        while data.count >= 4, data.uint32(at: 0) != prefix {
            data.removeFirst()
        }
        guard data.count >= 16 else { return nil }
        let length = Int(data.uint32(at: 12))
        guard length <= 0x10000 else {
            data.removeAll()
            throw TuyaProtocolError.frameTooLarge
        }
        let total = 16 + length
        guard data.count >= total else { return nil }
        let frameData = Data(data.prefix(total))
        data.removeFirst(total)

        guard length >= 12, frameData.uint32(at: total - 8) == crc32(frameData.prefix(total - 8)) else {
            throw TuyaProtocolError.badChecksum
        }
        return TuyaFrame(
            sequence: frameData.uint32(at: 4),
            command: frameData.uint32(at: 8),
            returnCode: frameData.uint32(at: 16),
            payload: frameData.subdata(in: 20..<(total - 8))
        )
    }
}

public struct TuyaLocalCodec: Sendable {
    private let localKey: Data

    public init(localKey: Data) {
        self.localKey = localKey
    }

    /// JSON compacto com chaves em ordem (o aparelho aceita qualquer ordem).
    public static func json(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
    }

    public func encode(command: TuyaCommand, payload: Data, sequence: UInt32) -> Data {
        var body = aes(payload, operation: kCCEncrypt) ?? Data()
        if !command.omitsVersionHeader {
            body = versionHeader + body
        }
        var frame = Data()
        frame.appendUInt32(prefix)
        frame.appendUInt32(sequence)
        frame.appendUInt32(command.rawValue)
        frame.appendUInt32(UInt32(body.count + 8))
        frame.append(body)
        frame.appendUInt32(crc32(frame))
        frame.appendUInt32(suffix)
        return frame
    }

    /// Conteúdo decifrado; vazio para confirmações sem dados.
    public func decrypt(_ frame: TuyaFrame) throws -> Data {
        var body = frame.payload
        if body.starts(with: Data("3.3".utf8)) || body.count % 16 != 0 {
            body = body.dropFirst(min(versionHeader.count, body.count))
        }
        guard !body.isEmpty else { return Data() }
        guard let plain = aes(Data(body), operation: kCCDecrypt) else { throw TuyaProtocolError.decryptionFailed }
        return plain
    }

    private func aes(_ input: Data, operation: Int) -> Data? {
        Self.aesECB(input, key: localKey, operation: operation)
    }

    static func aesECB(_ input: Data, key: Data, operation: Int) -> Data? {
        var output = Data(count: input.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var produced = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            input.withUnsafeBytes { inputBytes in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        CCOperation(operation), CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                        keyBytes.baseAddress, key.count, nil,
                        inputBytes.baseAddress, input.count,
                        outputBytes.baseAddress, outputCapacity, &produced
                    )
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return output.prefix(produced)
    }
}

/// Aparelho que se anunciou na rede.
public struct TuyaDiscoveredDevice: Equatable, Sendable {
    public let id: String
    public let ip: String
    public let version: String
    public let productKey: String
}

public enum TuyaDiscovery {
    /// Porta dos anúncios cifrados (protocolo 3.3).
    public static let port: UInt16 = 6667
    private static let key = Data(Insecure.MD5.hash(data: Data("yGAdlopoPVldABfn".utf8)))

    public static func decode(_ datagram: Data) -> TuyaDiscoveredDevice? {
        var buffer = TuyaFrameBuffer()
        buffer.append(datagram)
        guard let frame = try? buffer.nextFrame() else { return nil }
        let plain = frame.payload.first == UInt8(ascii: "{")
            ? frame.payload
            : TuyaLocalCodec.aesECB(frame.payload, key: key, operation: kCCDecrypt)
        guard let plain,
              let json = try? JSONSerialization.jsonObject(with: plain) as? [String: Any],
              let id = json["gwId"] as? String,
              let ip = json["ip"] as? String
        else { return nil }
        return TuyaDiscoveredDevice(
            id: id,
            ip: ip,
            version: json["version"] as? String ?? "3.3",
            productKey: json["productKey"] as? String ?? ""
        )
    }
}

// MARK: Auxiliares binários

private extension Data {
    func uint32(at offset: Int) -> UInt32 {
        let start = startIndex + offset
        return self[start..<start + 4].reduce(0) { ($0 << 8) | UInt32($1) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(contentsOf: [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
    }
}

private let crcTable: [UInt32] = (0..<256).map { index in
    (0..<8).reduce(UInt32(index)) { crc, _ in crc & 1 == 1 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1 }
}

/// CRC-32 (o mesmo do zlib), usado no fim de cada mensagem.
func crc32(_ data: Data) -> UInt32 {
    ~data.reduce(~UInt32(0)) { crc, byte in crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
}

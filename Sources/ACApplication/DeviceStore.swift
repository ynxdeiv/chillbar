import Foundation
import Security

/// Aparelho configurado. `secret` (chave local) dá controle total do aparelho.
public struct SavedDevice: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let model: String
    public let secret: String
    /// Ausente em aparelhos salvos por versões antigas.
    public let productID: String?

    public init(id: String, name: String, model: String, secret: String, productID: String? = nil) {
        self.id = id
        self.name = name
        self.model = model
        self.secret = secret
        self.productID = productID
    }
}

public protocol DeviceStore: Sendable {
    func load() throws -> SavedDevice?
    func save(_ device: SavedDevice) throws
    func delete() throws
}

public struct KeychainError: Error, Equatable {
    public let status: OSStatus
}

/// Guarda o aparelho no Keychain do Mac, acessível só neste Mac e após o primeiro desbloqueio.
public struct KeychainDeviceStore: DeviceStore {
    private let service: String
    private let account = "device"

    public init(service: String = "io.github.ynxdeiv.Chillbar") {
        self.service = service
    }

    public func load() throws -> SavedDevice? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        return try JSONDecoder().decode(SavedDevice.self, from: data)
    }

    public func save(_ device: SavedDevice) throws {
        let data = try JSONEncoder().encode(device)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = baseQuery
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            item[kSecAttrLabel as String] = "Chillbar – \(device.name)"
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

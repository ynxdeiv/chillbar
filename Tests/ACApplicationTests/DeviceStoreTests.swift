import Foundation
import Testing
@testable import ACApplication

private let device = SavedDevice(
    id: "dev-ac", name: "ac quarto", model: "Smart air conditioner", secret: "chave-ficticia"
)

/// Serviço exclusivo por teste, para não tocar no Keychain do app. Apague com `delete()`.
private func temporaryStore() -> KeychainDeviceStore {
    KeychainDeviceStore(service: "io.github.ynxdeiv.Chillbar.tests.\(UUID().uuidString)")
}

@Suite("Aparelho salvo no Keychain", .serialized)
struct DeviceStoreTests {
    @Test("sem nada salvo, não há aparelho")
    func emptyByDefault() throws {
        let store = temporaryStore()
        defer { try? store.delete() }
        #expect(try store.load() == nil)
    }

    @Test("salva e lê o aparelho com a chave")
    func roundTrip() throws {
        let store = temporaryStore()
        defer { try? store.delete() }
        try store.save(device)
        #expect(try store.load() == device)
    }

    @Test("salvar de novo substitui o anterior")
    func overwrites() throws {
        let store = temporaryStore()
        defer { try? store.delete() }
        try store.save(device)
        let renamed = SavedDevice(id: device.id, name: "sala", model: device.model, secret: "nova-chave")
        try store.save(renamed)
        #expect(try store.load() == renamed)
    }

    @Test("apagar remove o aparelho")
    func deletes() throws {
        let store = temporaryStore()
        try store.save(device)
        try store.delete()
        #expect(try store.load() == nil)
    }
}

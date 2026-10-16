import Foundation
import Testing
@testable import ACApplication

private let airConditioner = SetupDevice(
    id: "dev-ac", name: "ac quarto", model: "Smart air conditioner",
    isOnline: true, isAirConditioner: true, secret: "chave-ficticia"
)
private let plug = SetupDevice(
    id: "dev-plug", name: "tomada", model: "Smart plug",
    isOnline: true, isAirConditioner: false, secret: "outra-chave"
)

/// Conta falsa: o QR só é "confirmado" depois de `confirmAfter` consultas.
private actor FakeAccount: AccountLinking {
    var confirmAfter = 1
    var devices = [airConditioner, plug]
    var failure: SetupError?
    private(set) var polls = 0
    private(set) var requestedCodes: [String] = []

    func setFailure(_ error: SetupError?) { failure = error }
    func setDevices(_ list: [SetupDevice]) { devices = list }

    func requestQRCode(userCode: String) async throws -> SetupQRCode {
        requestedCodes.append(userCode)
        if let failure { throw failure }
        return SetupQRCode(content: "tuyaSmart--qrLogin?token=qr", token: "qr")
    }

    func devicesIfConfirmed(qrCode: SetupQRCode, userCode: String) async throws -> [SetupDevice]? {
        polls += 1
        return polls > confirmAfter ? devices : nil
    }
}

@MainActor
@Suite("Assistente de configuração")
struct SetupFlowTests {
    @Test("começa nas boas-vindas e avança para o código de usuário")
    func startsAtWelcome() {
        let flow = SetupFlow(account: FakeAccount(), store: MemoryStore())
        #expect(flow.step == .welcome)
        flow.continueFromWelcome()
        #expect(flow.step == .userCode)
    }

    @Test("código vazio ou só espaços não avança")
    func rejectsEmptyUserCode() async {
        let account = FakeAccount()
        let flow = SetupFlow(account: account, store: MemoryStore())
        flow.continueFromWelcome()
        flow.userCode = "   "

        await flow.submitUserCode()

        #expect(flow.step == .userCode)
        #expect(await account.requestedCodes.isEmpty)
    }

    @Test("com o código, mostra o QR (sem espaços extras no código)")
    func showsQRCode() async {
        let account = FakeAccount()
        let flow = SetupFlow(account: account, store: MemoryStore())
        flow.continueFromWelcome()
        flow.userCode = "  codigo123 \n"

        await flow.submitUserCode()

        #expect(flow.step == .scan)
        #expect(flow.qrCode?.content == "tuyaSmart--qrLogin?token=qr")
        #expect(await account.requestedCodes == ["codigo123"])
    }

    @Test("erro da conta fica no passo do código, com mensagem")
    func accountErrorStaysOnUserCode() async {
        let account = FakeAccount()
        await account.setFailure(.account(message: "invalid user code"))
        let flow = SetupFlow(account: account, store: MemoryStore())
        flow.continueFromWelcome()
        flow.userCode = "errado"

        await flow.submitUserCode()

        #expect(flow.step == .userCode)
        #expect(flow.error == .account(message: "invalid user code"))
    }

    @Test("aguarda a confirmação no celular; com um único ar-condicionado, salva sozinho")
    func waitsForConfirmationThenSavesSingleAirConditioner() async {
        let store = MemoryStore()
        let flow = SetupFlow(account: FakeAccount(), store: store)
        flow.continueFromWelcome()
        flow.userCode = "codigo123"
        await flow.submitUserCode()

        await flow.pollOnce()
        #expect(flow.step == .scan)

        await flow.pollOnce()
        #expect(flow.step == .saved)
        #expect(flow.selectedDevice == airConditioner)
        #expect(store.saved?.id == "dev-ac")
    }

    @Test("com vários ares-condicionados, pede para escolher")
    func asksToChooseAmongSeveral() async {
        let account = FakeAccount()
        let second = SetupDevice(id: "dev-ac2", name: "sala", model: "Smart air conditioner", isOnline: false, isAirConditioner: true, secret: "k2")
        await account.setDevices([airConditioner, plug, second])
        let store = MemoryStore()
        let flow = SetupFlow(account: account, store: store)
        flow.continueFromWelcome()
        flow.userCode = "codigo123"
        await flow.submitUserCode()
        await flow.pollOnce()
        await flow.pollOnce()

        #expect(flow.step == .chooseDevice)
        #expect(flow.devices == [airConditioner, second])
        #expect(flow.selectedDevice == nil)
        #expect(store.saved == nil)
    }

    @Test("conta sem ar-condicionado mostra o aviso em vez de uma lista vazia")
    func noAirConditioner() async {
        let account = FakeAccount()
        await account.setDevices([plug])
        let flow = SetupFlow(account: account, store: MemoryStore())
        flow.continueFromWelcome()
        flow.userCode = "codigo123"
        await flow.submitUserCode()
        await flow.pollOnce()
        await flow.pollOnce()

        #expect(flow.step == .chooseDevice)
        #expect(flow.devices.isEmpty)
        #expect(flow.error == .noAirConditioner)
    }

    @Test("voltar do QR permite trocar o código")
    func backFromScan() async {
        let flow = SetupFlow(account: FakeAccount(), store: MemoryStore())
        flow.continueFromWelcome()
        flow.userCode = "codigo123"
        await flow.submitUserCode()

        flow.back()

        #expect(flow.step == .userCode)
        #expect(flow.qrCode == nil)
    }
}

/// Armazenamento em memória para os testes do fluxo.
private final class MemoryStore: DeviceStore, @unchecked Sendable {
    var saved: SavedDevice?
    func load() throws -> SavedDevice? { saved }
    func save(_ device: SavedDevice) throws { saved = device }
    func delete() throws { saved = nil }
}

@MainActor
@Suite("Assistente: salvar")
struct SetupFlowSaveTests {
    @Test("salvar guarda o aparelho escolhido e conclui")
    func savesSelectedDevice() async throws {
        let account = FakeAccount()
        let second = SetupDevice(id: "dev-ac2", name: "sala", model: "Smart air conditioner", isOnline: true, isAirConditioner: true, secret: "k2")
        await account.setDevices([airConditioner, second])
        let store = MemoryStore()
        let flow = SetupFlow(account: account, store: store)
        flow.continueFromWelcome()
        flow.userCode = "codigo123"
        await flow.submitUserCode()
        await flow.pollOnce()
        await flow.pollOnce()

        flow.selectedDevice = second
        flow.saveSelectedDevice()

        #expect(flow.step == .saved)
        #expect(store.saved == SavedDevice(id: "dev-ac2", name: "sala", model: "Smart air conditioner", secret: "k2"))
    }

    @Test("sem aparelho escolhido não salva")
    func requiresSelection() async {
        let store = MemoryStore()
        let flow = SetupFlow(account: FakeAccount(), store: store)

        flow.saveSelectedDevice()

        #expect(flow.step == .welcome)
        #expect(store.saved == nil)
    }
}

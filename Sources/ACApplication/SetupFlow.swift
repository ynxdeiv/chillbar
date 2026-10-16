import Foundation
import Observation

/// QR code mostrado na configuração; o app do fabricante lê `content`.
public struct SetupQRCode: Sendable, Equatable {
    public let content: String
    public let token: String

    public init(content: String, token: String) {
        self.content = content
        self.token = token
    }
}

/// Aparelho encontrado na conta do usuário. `secret` dá controle do aparelho: nunca exibir.
public struct SetupDevice: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let model: String
    public let isOnline: Bool
    public let isAirConditioner: Bool
    public let secret: String
    /// Identificador do modelo no fabricante, para escolher o perfil de botões.
    public let productID: String

    public init(id: String, name: String, model: String, isOnline: Bool, isAirConditioner: Bool, secret: String, productID: String = "") {
        self.id = id
        self.name = name
        self.model = model
        self.isOnline = isOnline
        self.isAirConditioner = isAirConditioner
        self.secret = secret
        self.productID = productID
    }
}

public enum SetupError: Error, Equatable, Sendable {
    case account(message: String)
    case network
    case qrExpired
    case noAirConditioner
    case saveFailed
}

/// Vinculação com a conta do app do fabricante (ex.: Smart Life) para buscar as chaves.
public protocol AccountLinking: Sendable {
    func requestQRCode(userCode: String) async throws -> SetupQRCode
    /// `nil` enquanto o usuário não confirmou o QR no celular.
    func devicesIfConfirmed(qrCode: SetupQRCode, userCode: String) async throws -> [SetupDevice]?
}

/// Passos do assistente de configuração, sem dependência de interface.
@MainActor
@Observable
public final class SetupFlow {
    public enum Step: Equatable, Sendable {
        case welcome, userCode, scan, chooseDevice, saved
    }

    public private(set) var step: Step = .welcome
    public var userCode = ""
    public private(set) var qrCode: SetupQRCode?
    public private(set) var devices: [SetupDevice] = []
    public var selectedDevice: SetupDevice?
    public private(set) var error: SetupError?
    public private(set) var isWorking = false

    @ObservationIgnored private let account: any AccountLinking
    @ObservationIgnored private let store: any DeviceStore
    @ObservationIgnored private var pollingTask: Task<Void, Never>?

    public init(account: any AccountLinking, store: any DeviceStore) {
        self.account = account
        self.store = store
    }

    public func continueFromWelcome() {
        step = .userCode
    }

    public func submitUserCode() async {
        let code = userCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        userCode = code
        error = nil
        isWorking = true
        defer { isWorking = false }
        do {
            qrCode = try await account.requestQRCode(userCode: code)
            step = .scan
        } catch {
            self.error = Self.setupError(error)
        }
    }

    /// Consulta uma vez se o usuário já confirmou o QR no celular.
    public func pollOnce() async {
        guard step == .scan, let qrCode else { return }
        do {
            guard let found = try await account.devicesIfConfirmed(qrCode: qrCode, userCode: userCode) else { return }
            devices = found.filter(\.isAirConditioner)
            selectedDevice = devices.count == 1 ? devices.first : nil
            error = devices.isEmpty ? .noAirConditioner : nil
            step = .chooseDevice
            // Um único ar-condicionado: nada para escolher, salva direto.
            if devices.count == 1 { saveSelectedDevice() }
        } catch {
            self.error = Self.setupError(error)
        }
    }

    /// Consulta a cada 2 s até a confirmação ou até o QR expirar (~3 min).
    public func startWaitingForConfirmation() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            for _ in 0..<90 {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled, self.step == .scan else { return }
                await self.pollOnce()
            }
            if let self, self.step == .scan { self.error = .qrExpired }
        }
    }

    /// Guarda o aparelho escolhido (com a chave) no armazenamento seguro.
    public func saveSelectedDevice() {
        guard let device = selectedDevice else { return }
        do {
            try store.save(SavedDevice(id: device.id, name: device.name, model: device.model, secret: device.secret, productID: device.productID.isEmpty ? nil : device.productID))
            error = nil
            step = .saved
        } catch {
            self.error = .saveFailed
        }
    }

    public func back() {
        pollingTask?.cancel()
        error = nil
        switch step {
        case .welcome, .saved: break
        case .userCode: step = .welcome
        case .scan:
            qrCode = nil
            step = .userCode
        case .chooseDevice:
            devices = []
            selectedDevice = nil
            qrCode = nil
            step = .userCode
        }
    }

    private static func setupError(_ error: any Error) -> SetupError {
        if let error = error as? SetupError { return error }
        if error is URLError { return .network }
        return .account(message: error.localizedDescription)
    }
}

import ACCore
import Foundation
import Observation

public enum StatusHeadline: Equatable, Sendable {
    case connecting
    case disconnected
    case sending
    case notConfirmed
    case sendFailed
    case unsupported
    case unavailableInMode
    case stale(since: Date)
    case off
    case synced(at: Date)
}

/// Coordena a interface com um adaptador: valida, envia, acompanha a confirmação
/// e mantém o estado de conexão.
@MainActor
@Observable
public final class ClimateController {
    public enum Connection: Equatable, Sendable {
        case connecting
        case connected
        case disconnected(String)
    }

    public enum Alert: Equatable, Sendable {
        case unsupported
        case unavailableInMode
        case sendFailed
        case notConfirmed(ClimateCommand)
    }

    public let deviceName: String
    public let sourceName: String
    public let capabilities: ClimateCapabilities
    public private(set) var connection: Connection = .connecting
    public private(set) var alert: Alert?
    private var reconciler: ClimateReconciler
    private var usage: UsageTracker
    @ObservationIgnored private let saveUsage: (@MainActor (UsageTracker) -> Void)?
    @ObservationIgnored private let adapter: any ClimateDeviceAdapter
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private let retryDelay: Duration

    /// - Parameters:
    ///   - usage: contagem de tempo ligado restaurada de uma execução anterior.
    ///   - saveUsage: chamado quando a contagem muda, para persistir.
    public init(
        deviceName: String,
        sourceName: String = "",
        adapter: any ClimateDeviceAdapter,
        confirmationTimeout: TimeInterval = 10,
        retryDelay: Duration = .seconds(2),
        usage: UsageTracker = UsageTracker(),
        saveUsage: (@MainActor (UsageTracker) -> Void)? = nil
    ) {
        self.deviceName = deviceName
        self.sourceName = sourceName
        self.adapter = adapter
        self.capabilities = adapter.capabilities
        self.reconciler = ClimateReconciler(confirmationTimeout: confirmationTimeout)
        self.usage = usage
        self.saveUsage = saveUsage
        self.retryDelay = retryDelay
    }

    /// Período ligado atual, se o aparelho estiver ligado.
    public var usageSession: UsageSession? { usage.session }

    /// Estado exibido: o reportado pelo aparelho com os comandos pendentes por cima.
    public var state: ClimateState { reconciler.displayed }
    public var lastUpdate: Date? { reconciler.lastReportAt }

    public func status(of field: ClimateField) -> FieldStatus {
        reconciler.status(of: field)
    }

    public func freshness(now: Date, staleAfter: TimeInterval) -> Freshness {
        reconciler.freshness(now: now, staleAfter: staleAfter)
    }

    /// A mensagem de status mais importante no momento, em ordem de prioridade.
    public func headline(now: Date, staleAfter: TimeInterval = 300) -> StatusHeadline {
        switch alert {
        case .notConfirmed: return .notConfirmed
        case .sendFailed: return .sendFailed
        case .unsupported: return .unsupported
        case .unavailableInMode: return .unavailableInMode
        case nil: break
        }
        switch connection {
        case .connecting: return .connecting
        case .disconnected: return .disconnected
        case .connected: break
        }
        let fields: [ClimateField] = [.power, .setpoint, .mode, .fanSpeed, .verticalSwing]
            + capabilities.features.map { .feature($0) }
        if fields.contains(where: { if case .pending = status(of: $0) { true } else { false } }) {
            return .sending
        }
        if case .stale(let since) = freshness(now: now, staleAfter: staleAfter) {
            return .stale(since: since)
        }
        if state.isOn == false { return .off }
        return .synced(at: lastUpdate ?? now)
    }

    /// Lê o estado e passa a ouvir as mudanças. Se a conexão cair, tenta de novo sozinho,
    /// com espera crescente (até 30 s) entre as tentativas.
    public func start() async {
        updatesTask?.cancel()
        let firstUpdates = adapter.stateUpdates()
        updatesTask = Task { [weak self, retryDelay] in
            var updates = firstUpdates
            var delay = retryDelay
            while !Task.isCancelled {
                do {
                    for try await snapshot in updates {
                        self?.receive(snapshot)
                        delay = retryDelay
                    }
                } catch {
                    self?.connection = .disconnected(error.localizedDescription)
                }
                try? await Task.sleep(for: delay)
                delay = min(delay * 2, .seconds(30))
                guard let self, !Task.isCancelled else { return }
                updates = adapter.stateUpdates()
                await refresh()
            }
        }
        await refresh()
    }

    public func stop() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    public func refresh() async {
        do {
            receive(try await adapter.refresh())
        } catch {
            connection = .disconnected(error.localizedDescription)
        }
    }

    public func send(_ command: ClimateCommand) async {
        do {
            try capabilities.validate(command, in: state.mode)
        } catch {
            alert = error == .unavailableInMode ? .unavailableInMode : .unsupported
            return
        }
        alert = nil
        // Nada a mudar (ou o mesmo pedido já pendente): o aparelho não mandaria aviso,
        // e a espera pela confirmação viraria um falso "não confirmou".
        guard !command.isSatisfied(by: state) else { return }
        reconciler.didSend(command, at: Date())
        do {
            try await adapter.send(command)
        } catch {
            reconciler.cancelPending(command.field)
            alert = .sendFailed
            return
        }
        scheduleExpiry()
    }

    public func stepSetpoint(by steps: Int) async {
        guard let current = state.setpoint else { return }
        let target = Temperature(
            tenthsOfCelsius: current.tenthsOfCelsius + steps * capabilities.setpointStep.tenthsOfCelsius
        )
        guard capabilities.setpointRange.contains(target) else { return }
        await send(.setSetpoint(target))
    }

    public func togglePower() async {
        await send(.setPower(!(state.isOn ?? false)))
    }

    public func expirePending(now: Date) {
        if let failed = reconciler.expire(now: now).last {
            alert = .notConfirmed(failed)
        }
    }

    public func dismissAlert() {
        alert = nil
    }

    private func receive(_ snapshot: ClimateSnapshot) {
        reconciler.apply(snapshot)
        connection = .connected
        if let isOn = snapshot.state.isOn {
            let previous = usage
            usage.observe(isOn: isOn, at: snapshot.observedAt)
            if usage != previous { saveUsage?(usage) }
        }
    }

    private func scheduleExpiry() {
        let timeout = reconciler.confirmationTimeout
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            self?.expirePending(now: Date())
        }
    }
}

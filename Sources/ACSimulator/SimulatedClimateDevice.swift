import ACCore
import Foundation

/// Aparelho simulado: aplica comandos após uma latência e reporta só o campo alterado,
/// como o Elgin faz na rede local. Usado em testes e no modo demonstração.
public actor SimulatedClimateDevice: ClimateDeviceAdapter {
    public nonisolated let capabilities: ClimateCapabilities
    public private(set) var receivedCommands: [ClimateCommand] = []
    private var state: ClimateState
    private let latency: Duration
    private var ignoresCommands = false
    private var subscribers: [UUID: AsyncThrowingStream<ClimateSnapshot, Error>.Continuation] = [:]

    public init(capabilities: ClimateCapabilities, initialState: ClimateState, latency: Duration = .milliseconds(450)) {
        self.capabilities = capabilities
        self.state = initialState
        self.latency = latency
    }

    /// Simula um aparelho que recebe o comando mas nunca confirma.
    public func setIgnoresCommands(_ value: Bool) {
        ignoresCommands = value
    }

    public nonisolated func stateUpdates() -> AsyncThrowingStream<ClimateSnapshot, Error> {
        let (stream, continuation) = AsyncThrowingStream<ClimateSnapshot, Error>.makeStream()
        let id = UUID()
        Task { await self.subscribe(id, continuation) }
        continuation.onTermination = { _ in Task { await self.unsubscribe(id) } }
        return stream
    }

    public func refresh() async throws -> ClimateSnapshot {
        ClimateSnapshot(state: state, observedAt: Date())
    }

    public func send(_ command: ClimateCommand) async throws {
        receivedCommands.append(command)
        guard !ignoresCommands else { return }
        Task {
            try? await Task.sleep(for: latency)
            report(command)
        }
    }

    private func report(_ command: ClimateCommand) {
        var partial = ClimateState()
        switch command {
        case .setPower(let value): state.isOn = value; partial.isOn = value
        case .setSetpoint(let value): state.setpoint = value; partial.setpoint = value
        case .setMode(let value): state.mode = value; partial.mode = value
        case .setFanSpeed(let value): state.fanSpeed = value; partial.fanSpeed = value
        case .setVerticalSwing(let value): state.verticalSwing = value; partial.verticalSwing = value
        case .setFeature(let feature, let value): state.features[feature] = value; partial.features[feature] = value
        }
        let snapshot = ClimateSnapshot(state: partial, observedAt: Date())
        for continuation in subscribers.values { continuation.yield(snapshot) }
    }

    private func subscribe(_ id: UUID, _ continuation: AsyncThrowingStream<ClimateSnapshot, Error>.Continuation) {
        subscribers[id] = continuation
    }

    private func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
    }
}

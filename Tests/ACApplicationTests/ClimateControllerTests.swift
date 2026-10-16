import Foundation
import Testing
import ACCore
import ACSimulator
@testable import ACApplication

private let capabilities = ClimateCapabilities(
    modes: [.cool, .dry, .fanOnly, .auto],
    fanSpeeds: [.auto, .low, .medium, .high],
    setpointRange: Temperature(celsius: 16)...Temperature(celsius: 30),
    setpointStep: Temperature(celsius: 1),
    reportsRoomTemperature: true,
    supportsVerticalSwing: true,
    features: [.sleep]
)

private let initialState = ClimateState(
    isOn: true,
    setpoint: Temperature(celsius: 25),
    roomTemperature: Temperature(celsius: 23),
    mode: .cool,
    fanSpeed: .auto,
    verticalSwing: false,
    features: [.sleep: false]
)

private struct OfflineDevice: ClimateDeviceAdapter {
    let capabilities: ClimateCapabilities
    func stateUpdates() -> AsyncThrowingStream<ClimateSnapshot, Error> { AsyncThrowingStream { $0.finish() } }
    func refresh() async throws -> ClimateSnapshot { throw URLError(.cannotConnectToHost) }
    func send(_ command: ClimateCommand) async throws { throw URLError(.cannotConnectToHost) }
}

/// Aparelho cuja primeira conexão cai logo de cara; as seguintes funcionam.
private actor FlakyDevice: ClimateDeviceAdapter {
    nonisolated let capabilities: ClimateCapabilities
    private var subscriptions = 0

    init(capabilities: ClimateCapabilities) {
        self.capabilities = capabilities
    }

    nonisolated func stateUpdates() -> AsyncThrowingStream<ClimateSnapshot, Error> {
        let (stream, continuation) = AsyncThrowingStream<ClimateSnapshot, Error>.makeStream()
        Task { await self.attach(continuation) }
        return stream
    }

    private func attach(_ continuation: AsyncThrowingStream<ClimateSnapshot, Error>.Continuation) {
        subscriptions += 1
        if subscriptions == 1 { continuation.finish(throwing: URLError(.networkConnectionLost)) }
    }

    func refresh() async throws -> ClimateSnapshot {
        ClimateSnapshot(state: initialState, observedAt: Date())
    }

    func send(_ command: ClimateCommand) async throws {}

    var subscriptionCount: Int { subscriptions }
}

/// Espera uma condição que depende de tarefas assíncronas do simulador.
@MainActor
private func eventually(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<200 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
}

@MainActor
private func startedController(device: SimulatedClimateDevice) async -> ClimateController {
    let controller = ClimateController(deviceName: "ac quarto", adapter: device, confirmationTimeout: 10)
    await controller.start()
    return controller
}

@MainActor
@Suite("Controlador da interface")
struct ClimateControllerTests {
    @Test("ao iniciar, mostra o estado lido do aparelho e fica conectado")
    func startLoadsState() async {
        let device = SimulatedClimateDevice(capabilities: capabilities, initialState: initialState, latency: .zero)
        let controller = await startedController(device: device)

        #expect(controller.connection == .connected)
        #expect(controller.state.setpoint == Temperature(celsius: 25))
        #expect(controller.state.roomTemperature == Temperature(celsius: 23))
    }

    @Test("aparelho inacessível deixa o controlador desconectado")
    func startOffline() async {
        let controller = ClimateController(
            deviceName: "ac quarto",
            adapter: OfflineDevice(capabilities: capabilities),
            confirmationTimeout: 10
        )
        await controller.start()

        guard case .disconnected = controller.connection else {
            Issue.record("esperava desconectado, veio \(controller.connection)")
            return
        }
    }

    @Test("comando enviado fica pendente e é confirmado pelo relatório do aparelho")
    func sendConfirms() async {
        let device = SimulatedClimateDevice(capabilities: capabilities, initialState: initialState, latency: .milliseconds(50))
        let controller = await startedController(device: device)

        await controller.send(.setSetpoint(Temperature(celsius: 26)))
        guard case .pending = controller.status(of: .setpoint) else {
            Issue.record("esperava pendente logo após o envio")
            return
        }
        #expect(controller.state.setpoint == Temperature(celsius: 26))
        #expect(await eventually { controller.status(of: .setpoint) == .synced })
        #expect(await device.receivedCommands == [.setSetpoint(Temperature(celsius: 26))])
    }

    @Test("comando que o aparelho não suporta não é enviado")
    func rejectsUnsupportedCommand() async {
        let device = SimulatedClimateDevice(capabilities: capabilities, initialState: initialState, latency: .zero)
        let controller = await startedController(device: device)

        await controller.send(.setMode(.heat))

        #expect(await device.receivedCommands.isEmpty)
        #expect(controller.alert == .unsupported)
        #expect(controller.state.mode == .cool)
    }

    @Test("sem confirmação no prazo, mostra alerta e volta ao valor real")
    func unconfirmedCommandFails() async {
        let device = SimulatedClimateDevice(capabilities: capabilities, initialState: initialState, latency: .zero)
        await device.setIgnoresCommands(true)
        let controller = await startedController(device: device)

        await controller.send(.setSetpoint(Temperature(celsius: 27)))
        controller.expirePending(now: Date().addingTimeInterval(11))

        #expect(controller.alert == .notConfirmed(.setSetpoint(Temperature(celsius: 27))))
        #expect(controller.state.setpoint == Temperature(celsius: 25))
    }

    @Test("falha de envio vira alerta e não deixa comando pendente")
    func sendFailure() async {
        let controller = ClimateController(
            deviceName: "ac quarto",
            adapter: OfflineDevice(capabilities: capabilities),
            confirmationTimeout: 10
        )
        await controller.send(.setPower(false))

        #expect(controller.alert == .sendFailed)
        #expect(controller.status(of: .power) == .synced)
    }

    @Test("▲▼ ajusta um passo e respeita os limites", arguments: [
        (25.0, 1, [26.0]),
        (25.0, -1, [24.0]),
        (30.0, 1, []),
        (16.0, -1, []),
    ])
    func stepSetpoint(start: Double, steps: Int, expectedSent: [Double]) async {
        var state = initialState
        state.setpoint = Temperature(celsius: start)
        let device = SimulatedClimateDevice(capabilities: capabilities, initialState: state, latency: .zero)
        let controller = await startedController(device: device)

        await controller.stepSetpoint(by: steps)

        #expect(await device.receivedCommands == expectedSent.map { .setSetpoint(Temperature(celsius: $0)) })
    }

    @Test("status: sincronizado → enviando → sem confirmação")
    func headlineFollowsCommandLifecycle() async {
        let device = SimulatedClimateDevice(capabilities: capabilities, initialState: initialState, latency: .zero)
        await device.setIgnoresCommands(true)
        let controller = await startedController(device: device)
        let lastUpdate = try! #require(controller.lastUpdate)

        #expect(controller.headline(now: lastUpdate) == .synced(at: lastUpdate))
        await controller.send(.setSetpoint(Temperature(celsius: 26)))
        #expect(controller.headline(now: lastUpdate) == .sending)
        controller.expirePending(now: Date().addingTimeInterval(11))
        #expect(controller.headline(now: lastUpdate) == .notConfirmed)
    }

    @Test("status: desconectado tem prioridade sobre o resto")
    func headlineDisconnected() async {
        let controller = ClimateController(
            deviceName: "ac quarto",
            adapter: OfflineDevice(capabilities: capabilities),
            confirmationTimeout: 10
        )
        await controller.start()
        #expect(controller.headline(now: Date()) == .disconnected)
    }

    @Test("status: desatualizado quando o último relatório é antigo")
    func headlineStale() async {
        let device = SimulatedClimateDevice(capabilities: capabilities, initialState: initialState, latency: .zero)
        let controller = await startedController(device: device)
        let lastUpdate = try! #require(controller.lastUpdate)

        #expect(controller.headline(now: lastUpdate + 301, staleAfter: 300) == .stale(since: lastUpdate))
    }

    @Test("status: desligado quando o aparelho reporta desligado")
    func headlineOff() async {
        var state = initialState
        state.isOn = false
        let device = SimulatedClimateDevice(capabilities: capabilities, initialState: state, latency: .zero)
        let controller = await startedController(device: device)

        #expect(controller.headline(now: Date()) == .off)
    }

    @Test("conta o tempo ligado a partir dos estados reportados e salva a cada mudança")
    func tracksUsage() async {
        let device = SimulatedClimateDevice(capabilities: capabilities, initialState: initialState, latency: .zero)
        var saved: [UsageTracker] = []
        let controller = ClimateController(
            deviceName: "ac quarto",
            adapter: device,
            confirmationTimeout: 10,
            usage: UsageTracker(),
            saveUsage: { saved.append($0) }
        )
        await controller.start()

        #expect(controller.usageSession?.startIsExact == false)
        await controller.togglePower()
        #expect(await eventually { controller.usageSession == nil })
        #expect(saved.last?.session == nil)
    }

    @Test("se a conexão cair, reconecta sozinho e volta a ficar conectado")
    func reconnectsAfterDrop() async {
        let device = FlakyDevice(capabilities: capabilities)
        let controller = ClimateController(
            deviceName: "ac quarto", adapter: device, confirmationTimeout: 10, retryDelay: .milliseconds(20)
        )
        await controller.start()

        #expect(await eventually { await device.subscriptionCount >= 2 })
        #expect(await eventually { controller.connection == .connected })
    }

    @Test("comando travado no modo atual não é enviado e explica o motivo")
    func rejectsCommandLockedByMode() async {
        var state = initialState
        state.mode = .auto
        var autoLocked = capabilities
        autoLocked.modeRules = [.auto: ModeRule(allowsSetpoint: false, fanSpeeds: [])]
        let device = SimulatedClimateDevice(capabilities: autoLocked, initialState: state, latency: .zero)
        let controller = await startedController(device: device)

        await controller.send(.setFanSpeed(.low))

        #expect(await device.receivedCommands.isEmpty)
        #expect(controller.alert == .unavailableInMode)
    }

    @Test("comando que não muda nada não é enviado (o aparelho não confirmaria e daria falso alarme)")
    func skipsNoOpCommand() async {
        let device = SimulatedClimateDevice(capabilities: capabilities, initialState: initialState, latency: .zero)
        await device.setIgnoresCommands(true)
        let controller = await startedController(device: device)

        await controller.send(.setMode(.cool))
        controller.expirePending(now: Date().addingTimeInterval(11))

        #expect(await device.receivedCommands.isEmpty)
        #expect(controller.status(of: .mode) == .synced)
        #expect(controller.alert == nil)
    }

    @Test("voltar ao valor real enquanto outro pedido está pendente ainda é enviado")
    func sendsWhenOverridingPending() async {
        let device = SimulatedClimateDevice(capabilities: capabilities, initialState: initialState, latency: .zero)
        await device.setIgnoresCommands(true)
        let controller = await startedController(device: device)

        await controller.send(.setMode(.dry))
        await controller.send(.setMode(.cool))

        #expect(await device.receivedCommands == [.setMode(.dry), .setMode(.cool)])
    }

    @Test("botão liga/desliga envia o oposto do estado atual")
    func togglePower() async {
        let device = SimulatedClimateDevice(capabilities: capabilities, initialState: initialState, latency: .zero)
        let controller = await startedController(device: device)

        await controller.togglePower()

        #expect(await device.receivedCommands == [.setPower(false)])
    }
}

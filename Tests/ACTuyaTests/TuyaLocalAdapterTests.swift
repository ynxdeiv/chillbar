import ACCore
import CommonCrypto
import Foundation
import Network
import Testing
@testable import ACTuya

private let key = "0123456789abcdef"
private let deviceID = "testdevice22charsxxxxx"

/// Estado completo que o Elgin reportou na prova de conceito.
private var elginDPS: [String: Any] { [
    "1": true, "2": 250, "3": 230, "4": "cold", "5": "auto", "13": true, "102": false,
    "103": false, "104": false, "105": false, "106": true,
] }

/// Aparelho Tuya falso em localhost: decifra o que recebe e responde como o Elgin.
private final class FakeTuyaDevice: @unchecked Sendable {
    enum Mode { case normal, requiresAlternateQuery }

    let mode: Mode
    private let listener: NWListener
    private let queue = DispatchQueue(label: "fake-tuya-device")
    private let lock = NSLock()
    private var received: [(command: UInt32, json: [String: Any])] = []
    private var client: NWConnection?
    private let codec = TuyaLocalCodec(localKey: Data(key.utf8))

    init(mode: Mode = .normal) throws {
        self.mode = mode
        listener = try NWListener(using: .tcp, on: .any)
    }

    func start() async throws -> UInt16 {
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            lock.withLock { client = connection }
            connection.start(queue: queue)
            read(connection, buffer: Data())
        }
        let ready = ResumeOnce()
        return try await withCheckedThrowingContinuation { resume in
            listener.stateUpdateHandler = { [listener] state in
                if case .ready = state, ready.claim() { resume.resume(returning: listener.port!.rawValue) }
                if case .failed(let error) = state, ready.claim() { resume.resume(throwing: error) }
            }
            listener.start(queue: queue)
        }
    }

    var commands: [(command: UInt32, json: [String: Any])] { lock.withLock { received } }

    /// Envia um aviso de mudança (comando 8), como o aparelho faz ao mudar o setpoint.
    func push(_ dps: [String: Any]) {
        let frame = deviceFrame(command: 8, json: ["dps": dps, "t": 1], header: true)
        lock.withLock { client }?.send(content: frame, completion: .idempotent)
    }

    func disconnect() {
        lock.withLock { client }?.cancel()
    }

    func stop() {
        listener.cancel()
        disconnect()
    }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self, error == nil, !isComplete else { return }
            var pending = buffer + (data ?? Data())
            while pending.count >= 16 {
                // `Data` perde o índice 0 depois de `removeFirst`: lê relativo ao início.
                let header = Array(pending.prefix(16))
                let length = Int(header[12]) << 24 | Int(header[13]) << 16 | Int(header[14]) << 8 | Int(header[15])
                guard pending.count >= 16 + length else { break }
                let frame = Data(pending.prefix(16 + length))
                pending.removeFirst(16 + length)
                handle(frame, on: connection)
            }
            read(connection, buffer: pending)
        }
    }

    private func handle(_ frame: Data, on connection: NWConnection) {
        let command = UInt32(frame[11])
        var body = frame.subdata(in: 16..<(frame.count - 8))
        if body.starts(with: Data("3.3".utf8)) { body = body.dropFirst(15) }
        let plain = TuyaLocalCodec.aesECB(Data(body), key: Data(key.utf8), operation: kCCDecrypt) ?? Data()
        let json = (try? JSONSerialization.jsonObject(with: plain) as? [String: Any]) ?? [:]
        lock.withLock { received.append((command, json)) }

        let reply: Data?
        switch (command, mode) {
        case (0x0a, .normal):
            reply = deviceFrame(command: 0x0a, json: ["devId": deviceID, "dps": elginDPS], header: false)
        case (0x0a, .requiresAlternateQuery):
            reply = deviceFrame(command: 0x0a, raw: Data("json obj data unvalid".utf8), header: false, returnCode: 1)
        case (0x0d, _):
            reply = deviceFrame(command: 0x08, json: ["dps": elginDPS, "t": 1], header: true)
        case (0x07, _):
            reply = deviceFrame(command: 0x07, raw: Data(), header: false)
        default:
            reply = nil
        }
        if let reply { connection.send(content: reply, completion: .idempotent) }
    }

    private func deviceFrame(command: UInt32, json: [String: Any], header: Bool) -> Data {
        deviceFrame(command: command, raw: TuyaLocalCodec.json(json), header: header)
    }

    /// Mensagem do aparelho para o app: código de retorno + [cabeçalho 3.3] + AES.
    private func deviceFrame(command: UInt32, raw: Data, header: Bool, returnCode: UInt32 = 0) -> Data {
        var body = Data(be(returnCode))
        if !raw.isEmpty {
            if header { body += Data("3.3".utf8) + Data(repeating: 0, count: 12) }
            body += TuyaLocalCodec.aesECB(raw, key: Data(key.utf8), operation: kCCEncrypt)!
        }
        var frame = Data(be(0x55AA)) + Data(be(1)) + Data(be(command)) + Data(be(UInt32(body.count + 8))) + body
        frame += Data(be(crc32(frame))) + Data(be(0xAA55))
        return frame
    }

    private func be(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }
}

private func elginProfile() throws -> TuyaDeviceProfile {
    try #require(TuyaDeviceProfile.bundled(category: "kt", productID: "gncaqbnuk4cj2etp"))
}

private func adapter(port: UInt16) throws -> TuyaLocalAdapter {
    TuyaLocalAdapter(
        deviceID: deviceID, localKey: key, host: "127.0.0.1", port: port,
        profile: try elginProfile(), locate: { nil }
    )
}

@Suite("Adaptador local Tuya (aparelho falso em localhost)", .serialized)
struct TuyaLocalAdapterTests {
    @Test("lê o estado completo pela rede local")
    func refreshReadsState() async throws {
        let device = try FakeTuyaDevice()
        defer { device.stop() }
        let adapter = try adapter(port: try await device.start())

        let snapshot = try await adapter.refresh()

        #expect(snapshot.state.isOn == true)
        #expect(snapshot.state.setpoint == Temperature(celsius: 25))
        #expect(snapshot.state.roomTemperature == Temperature(celsius: 23))
        #expect(snapshot.state.mode == .cool)
        #expect(device.commands.first?.command == 0x0a)
    }

    @Test("aparelho que responde 'data unvalid' é consultado do jeito alternativo")
    func fallsBackToAlternateQuery() async throws {
        let device = try FakeTuyaDevice(mode: .requiresAlternateQuery)
        defer { device.stop() }
        let adapter = try adapter(port: try await device.start())

        let snapshot = try await adapter.refresh()

        #expect(snapshot.state.setpoint == Temperature(celsius: 25))
        #expect(device.commands.map(\.command).contains(0x0d))
    }

    @Test("comando vira um CONTROL com o DP certo")
    func sendsControl() async throws {
        let device = try FakeTuyaDevice()
        defer { device.stop() }
        let adapter = try adapter(port: try await device.start())
        _ = try await adapter.refresh()

        try await adapter.send(.setSetpoint(Temperature(celsius: 26)))
        try await Task.sleep(for: .milliseconds(200))

        let control = try #require(device.commands.last { $0.command == 0x07 })
        #expect(control.json["dps"] as? [String: Int] == ["2": 260])
        #expect(control.json["devId"] as? String == deviceID)
    }

    @Test("aviso de mudança do aparelho chega como atualização parcial")
    func pushBecomesUpdate() async throws {
        let device = try FakeTuyaDevice()
        defer { device.stop() }
        let adapter = try adapter(port: try await device.start())
        let updates = adapter.stateUpdates()
        _ = try await adapter.refresh()

        device.push(["2": 260])

        var iterator = updates.makeAsyncIterator()
        var received: ClimateState?
        while let snapshot = try await iterator.next() {
            if snapshot.state.setpoint == Temperature(celsius: 26) {
                received = snapshot.state
                break
            }
        }
        #expect(received == ClimateState(setpoint: Temperature(celsius: 26)))
    }

    @Test("queda da conexão encerra as atualizações com erro")
    func disconnectEndsUpdates() async throws {
        let device = try FakeTuyaDevice()
        defer { device.stop() }
        let adapter = try adapter(port: try await device.start())
        let updates = adapter.stateUpdates()
        _ = try await adapter.refresh()

        device.disconnect()

        await #expect(throws: (any Error).self) {
            for try await _ in updates {}
        }
    }

    @Test("sem endereço e sem descoberta, avisa que não achou o aparelho")
    func notFound() async throws {
        let adapter = TuyaLocalAdapter(
            deviceID: deviceID, localKey: key, host: nil,
            profile: try elginProfile(), locate: { nil }
        )
        await #expect(throws: TuyaLocalError.deviceNotFound) { try await adapter.refresh() }
    }
}

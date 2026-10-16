import Foundation
import Network
import Testing
@testable import ACTuya

/// Anúncio de descoberta (vetor do tinytuya) do aparelho fictício `testdevice22charsxxxxx`.
private let announcement: Data = {
    let hex = "000055aa0000000000000013000000ac000000003147c936e9a73aeeff2f4dab0b33499fc76c5adcce3ca655eb2a7e021c57ee1914ccdc69da6f52716f1f7d23a35bb1208b0c6f93a44b789d48244758ebb814f7e37e2491786d8b6efd633e04a61168de172030a98473512a8e23a0d37ed26e6132e8ef8621f63a363795b5e3cdc7ec536c9477537a0b433d14905a23fea05de2beeb735778176a1e477255d1f238a3ca384363dcd0f0705ae4cac595bbf496252bbef0600000aa55"
    var data = Data()
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2)
        data.append(UInt8(hex[index..<next], radix: 16)!)
        index = next
    }
    return data
}()

/// Envia o anúncio de uma porta de origem fixa (como o aparelho faz) a cada 300 ms.
private final class FakeBroadcaster: @unchecked Sendable {
    private let connection: NWConnection
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "fake-broadcaster")

    init(toPort port: UInt16, fromPort source: UInt16) {
        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: source)!)
        connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: parameters)
    }

    func start() {
        connection.start(queue: queue)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(300))
        timer.setEventHandler { [connection] in
            connection.send(content: announcement, completion: .idempotent)
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        connection.cancel()
    }
}

@Suite("Regressões de rede (bug de 16/10: sem conexão após permissão de Rede Local)", .serialized)
struct TuyaConnectionRegressionTests {
    @Test("a descoberta funciona de novo na segunda vez (não deixa conexão presa)")
    func discoveryWorksRepeatedly() async throws {
        let port = UInt16.random(in: 40_000...49_000)
        let broadcaster = FakeBroadcaster(toPort: port, fromPort: port + 1)
        broadcaster.start()
        defer { broadcaster.stop() }

        let first = await TuyaNetworkDiscovery.find(deviceID: "testdevice22charsxxxxx", timeout: .seconds(3), port: port)
        let second = await TuyaNetworkDiscovery.find(deviceID: "testdevice22charsxxxxx", timeout: .seconds(3), port: port)

        #expect(first?.ip == "192.168.1.50")
        #expect(second?.ip == "192.168.1.50")
    }

    @Test("'aguardando' (ex.: pedido de permissão de Rede Local) não é falha", arguments: [
        (TuyaLocalConnection.Outcome.ready, NWConnection.State.ready),
        (.keepWaiting, .waiting(.posix(.ENETUNREACH))),
        (.keepWaiting, .preparing),
        (.fail, .failed(.posix(.ECONNRESET))),
        (.fail, .cancelled),
    ])
    func waitingIsNotFatal(expected: TuyaLocalConnection.Outcome, state: NWConnection.State) {
        #expect(TuyaLocalConnection.outcome(for: state) == expected)
    }

    @Test("o IP encontrado pela descoberta é guardado mesmo se a conexão TCP falhar")
    func cachesDiscoveredHostBeforeConnecting() async throws {
        let found = FoundHost()
        let profile = try #require(TuyaDeviceProfile.bundled(category: "kt", productID: "gncaqbnuk4cj2etp"))
        let adapter = TuyaLocalAdapter(
            deviceID: "testdevice22charsxxxxx", localKey: "0123456789abcdef", host: nil,
            port: 9, // porta fechada: a conexão TCP falha
            profile: profile,
            locate: { "127.0.0.1" },
            onHostFound: { host in found.set(host) }
        )

        await #expect(throws: (any Error).self) { try await adapter.refresh() }
        #expect(found.value == "127.0.0.1")
    }
}

private final class FoundHost: @unchecked Sendable {
    private let lock = NSLock()
    private var host: String?
    var value: String? { lock.withLock { host } }
    func set(_ host: String) { lock.withLock { self.host = host } }
}

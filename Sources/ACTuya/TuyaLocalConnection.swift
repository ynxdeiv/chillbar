import Foundation
import Network

public enum TuyaLocalError: Error, Equatable {
    case deviceNotFound
    case timeout
    case disconnected
}

/// Garante que uma continuação seja retomada uma única vez entre callbacks concorrentes.
final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.withLock {
            if done { return false }
            done = true
            return true
        }
    }
}

/// Conexão TCP com o aparelho (porta 6668). Entrega as mensagens recebidas, em ordem, em `frames`.
final class TuyaLocalConnection: @unchecked Sendable {
    enum Outcome: Equatable {
        case ready, keepWaiting, fail
    }

    /// O que fazer em cada estado da conexão durante a abertura. "Aguardando" não é falha:
    /// acontece, por exemplo, enquanto o macOS pede a permissão de Rede Local; quem
    /// desiste é o tempo limite.
    static func outcome(for state: NWConnection.State) -> Outcome {
        switch state {
        case .ready: .ready
        case .failed, .cancelled: .fail
        default: .keepWaiting
        }
    }

    let frames: AsyncThrowingStream<TuyaFrame, Error>
    private let continuation: AsyncThrowingStream<TuyaFrame, Error>.Continuation
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "io.github.ynxdeiv.Chillbar.tuya")
    /// Só são acessados na `queue`.
    private var buffer = TuyaFrameBuffer()
    private var isOpen = false

    init(host: String, port: UInt16 = 6668) {
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        (frames, continuation) = AsyncThrowingStream.makeStream()
    }

    func start(timeout: Duration = .seconds(5)) async throws {
        let once = ResumeOnce()
        try await withCheckedThrowingContinuation { (resume: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch Self.outcome(for: state) {
                case .ready:
                    isOpen = true
                    if once.claim() { resume.resume() }
                    receive()
                case .keepWaiting:
                    // Já aberta e voltou a aguardar: a rede caiu; quem usa reconecta.
                    if isOpen, case .waiting(let error) = state {
                        continuation.finish(throwing: error)
                        connection.cancel()
                    }
                case .fail:
                    let error: Error = if case .failed(let error) = state { error } else { TuyaLocalError.disconnected }
                    if once.claim() { resume.resume(throwing: error) }
                    continuation.finish(throwing: error)
                    connection.cancel()
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout.timeInterval) { [weak self] in
                if once.claim() {
                    resume.resume(throwing: TuyaLocalError.timeout)
                    self?.connection.cancel()
                }
            }
        }
    }

    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (resume: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { resume.resume(throwing: error) } else { resume.resume() }
            })
        }
    }

    func cancel() {
        connection.cancel()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                buffer.append(data)
                do {
                    while let frame = try buffer.nextFrame() {
                        continuation.yield(frame)
                    }
                } catch {
                    // Mensagem corrompida: descarta e segue lendo as próximas.
                }
            }
            if let error {
                continuation.finish(throwing: error)
            } else if isComplete {
                continuation.finish(throwing: TuyaLocalError.disconnected)
            } else {
                receive()
            }
        }
    }
}

/// Escuta os anúncios UDP dos aparelhos Tuya até achar o aparelho pedido.
public enum TuyaNetworkDiscovery {
    public static func find(
        deviceID: String,
        timeout: Duration = .seconds(10),
        port: UInt16 = TuyaDiscovery.port
    ) async -> TuyaDiscoveredDevice? {
        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!) else {
            return nil
        }
        let queue = DispatchQueue(label: "io.github.ynxdeiv.Chillbar.discovery")
        let once = ResumeOnce()
        let inbound = InboundConnections()

        return await withCheckedContinuation { (resume: CheckedContinuation<TuyaDiscoveredDevice?, Never>) in
            @Sendable func finish(_ device: TuyaDiscoveredDevice?) {
                if once.claim() {
                    listener.cancel()
                    // Sem isto, o fluxo do aparelho fica preso e a próxima descoberta falha
                    // ("File exists" no NECP).
                    inbound.cancelAll()
                    resume.resume(returning: device)
                }
            }
            listener.newConnectionHandler = { connection in
                inbound.add(connection)
                connection.start(queue: queue)
                @Sendable func read() {
                    connection.receiveMessage { data, _, _, error in
                        if let data, let device = TuyaDiscovery.decode(data), device.id == deviceID {
                            finish(device)
                        } else if error == nil {
                            read()
                        }
                    }
                }
                read()
            }
            listener.stateUpdateHandler = { state in
                if case .failed = state { finish(nil) }
            }
            listener.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout.timeInterval) { finish(nil) }
        }
    }
}

/// Conexões UDP recebidas pela descoberta, para fechá-las ao terminar.
private final class InboundConnections: @unchecked Sendable {
    private let lock = NSLock()
    private var connections: [NWConnection] = []

    func add(_ connection: NWConnection) {
        lock.withLock { connections.append(connection) }
    }

    func cancelAll() {
        lock.withLock {
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}

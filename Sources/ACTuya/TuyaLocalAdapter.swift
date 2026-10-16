import ACCore
import Foundation

/// Controla um aparelho Tuya 3.3 direto pela rede local, sem nuvem.
///
/// Conecta sob demanda, mantém a conexão viva com batimentos e repassa os avisos de
/// mudança do aparelho. Se a conexão cair, `stateUpdates()` termina com erro; a próxima
/// chamada reconecta.
public actor TuyaLocalAdapter: ClimateDeviceAdapter {
    public nonisolated let capabilities: ClimateCapabilities
    private let deviceID: String
    private let codec: TuyaLocalCodec
    private let mapper: TuyaClimateMapper
    private let port: UInt16
    private let locate: @Sendable () async -> String?
    private let onHostFound: @Sendable (String) -> Void

    private var host: String?
    private var connection: TuyaLocalConnection?
    private var connecting: Task<TuyaLocalConnection, Error>?
    private var readTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var sequence: UInt32 = 1
    /// Aparelhos com ID de 22 caracteres podem exigir a consulta alternativa (CONTROL_NEW).
    private var usesAlternateQuery = false
    private var lastDPS: [String: TuyaValue] = [:]
    private var pendingQuery: CheckedContinuation<Void, Error>?
    private var pendingQueryToken = 0
    private var subscribers: [UUID: AsyncThrowingStream<ClimateSnapshot, Error>.Continuation] = [:]

    /// - Parameters:
    ///   - host: IP conhecido (cache); se falhar, usa `locate` para procurar de novo.
    ///   - locate: descoberta na rede (ex.: `TuyaNetworkDiscovery.find`).
    ///   - onHostFound: avisado quando um IP novo é encontrado, para guardar em cache.
    public init(
        deviceID: String,
        localKey: String,
        host: String?,
        port: UInt16 = 6668,
        profile: TuyaDeviceProfile,
        locate: @escaping @Sendable () async -> String?,
        onHostFound: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.deviceID = deviceID
        self.codec = TuyaLocalCodec(localKey: Data(localKey.utf8))
        self.mapper = TuyaClimateMapper(profile: profile)
        self.capabilities = profile.capabilities
        self.host = host
        self.port = port
        self.locate = locate
        self.onHostFound = onHostFound
    }

    // MARK: ClimateDeviceAdapter

    public nonisolated func stateUpdates() -> AsyncThrowingStream<ClimateSnapshot, Error> {
        let (stream, continuation) = AsyncThrowingStream<ClimateSnapshot, Error>.makeStream()
        let id = UUID()
        continuation.onTermination = { _ in Task { await self.unsubscribe(id) } }
        Task { await self.subscribe(id, continuation) }
        return stream
    }

    public func refresh() async throws -> ClimateSnapshot {
        try await query()
        return ClimateSnapshot(state: mapper.state(from: lastDPS), observedAt: Date())
    }

    public func send(_ command: ClimateCommand) async throws {
        let dps = try mapper.dps(for: command).mapValues(\.jsonValue)
        try await write(.control, ["devId": deviceID, "uid": deviceID, "t": timestamp, "dps": dps])
    }

    // MARK: Consulta

    /// Pede o estado completo e espera a resposta (até 5 s). A espera é registrada antes
    /// do envio, para não perder uma resposta rápida.
    private func query() async throws {
        _ = try await connect()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pendingQuery?.resume(throwing: TuyaLocalError.timeout)
            pendingQuery = continuation
            pendingQueryToken += 1
            let token = pendingQueryToken
            Task {
                do {
                    try await self.sendQuery()
                } catch {
                    self.failPendingQuery(token: token, with: error)
                }
            }
            Task {
                try? await Task.sleep(for: .seconds(5))
                self.failPendingQuery(token: token, with: TuyaLocalError.timeout)
            }
        }
    }

    private func sendQuery() async throws {
        if usesAlternateQuery {
            let requested = Dictionary(uniqueKeysWithValues: queryDPs.map { ($0, NSNull() as Any) })
            try await write(.controlNew, ["devId": deviceID, "uid": deviceID, "t": timestamp, "dps": requested])
        } else {
            try await write(.dpQuery, ["gwId": deviceID, "devId": deviceID, "uid": deviceID, "t": timestamp])
        }
    }

    private func completePendingQuery() {
        pendingQuery?.resume()
        pendingQuery = nil
    }

    private func failPendingQuery(with error: Error) {
        pendingQuery?.resume(throwing: error)
        pendingQuery = nil
    }

    private func failPendingQuery(token: Int, with error: Error) {
        guard token == pendingQueryToken else { return }
        failPendingQuery(with: error)
    }

    /// DPs pedidos na consulta alternativa: todos os que o perfil conhece.
    private var queryDPs: [String] {
        let profile = mapper.profile
        let ids = [profile.power?.dp, profile.setpoint?.dp, profile.roomTemperature?.dp, profile.mode?.dp,
                   profile.fanSpeed?.dp, profile.verticalSwing?.dp].compactMap { $0 }
            + (profile.features.map { Array($0.values) } ?? [])
        return Array(Set(ids)).sorted()
    }

    // MARK: Conexão

    private func write(_ command: TuyaCommand, _ payload: [String: Any]) async throws {
        let connection = try await connect()
        let frame = codec.encode(command: command, payload: TuyaLocalCodec.json(payload), sequence: sequence)
        sequence &+= 1
        try await connection.send(frame)
    }

    private func connect() async throws -> TuyaLocalConnection {
        if let connection { return connection }
        if let connecting { return try await connecting.value }
        let task = Task { try await self.openConnection() }
        connecting = task
        defer { connecting = nil }
        let connection = try await task.value
        self.connection = connection
        startReading(connection)
        startHeartbeat()
        return connection
    }

    private func openConnection() async throws -> TuyaLocalConnection {
        if let host, let connection = try? await open(host) { return connection }
        guard let found = await locate() else { throw TuyaLocalError.deviceNotFound }
        // Guarda já: se o TCP falhar agora (ex.: permissão pendente), a próxima tentativa
        // vai direto ao IP, sem depender de outra descoberta.
        host = found
        onHostFound(found)
        return try await open(found)
    }

    private func open(_ host: String) async throws -> TuyaLocalConnection {
        let connection = TuyaLocalConnection(host: host, port: port)
        try await connection.start()
        return connection
    }

    private func startReading(_ connection: TuyaLocalConnection) {
        readTask = Task {
            do {
                for try await frame in connection.frames {
                    self.handle(frame)
                }
                self.connectionEnded(TuyaLocalError.disconnected)
            } catch {
                self.connectionEnded(error)
            }
        }
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                try? await self.write(.heartbeat, ["gwId": self.deviceID, "devId": self.deviceID])
            }
        }
    }

    private func connectionEnded(_ error: Error) {
        connection?.cancel()
        connection = nil
        heartbeatTask?.cancel()
        failPendingQuery(with: error)
        for continuation in subscribers.values { continuation.finish(throwing: error) }
        subscribers.removeAll()
    }

    // MARK: Mensagens recebidas

    private func handle(_ frame: TuyaFrame) {
        guard let plain = try? codec.decrypt(frame), !plain.isEmpty else { return }
        if String(decoding: plain, as: UTF8.self).contains("data unvalid") {
            usesAlternateQuery = true
            if pendingQuery != nil {
                let token = pendingQueryToken
                Task {
                    do {
                        try await self.sendQuery()
                    } catch {
                        self.failPendingQuery(token: token, with: error)
                    }
                }
            }
            return
        }
        guard let json = try? JSONSerialization.jsonObject(with: plain) as? [String: Any],
              let raw = json["dps"] as? [String: Any]
        else { return }
        let dps = raw.compactMapValues(TuyaValue.init(json:))
        lastDPS.merge(dps) { _, new in new }
        completePendingQuery()
        let snapshot = ClimateSnapshot(state: mapper.state(from: dps), observedAt: Date())
        for continuation in subscribers.values { continuation.yield(snapshot) }
    }

    // MARK: Assinantes

    private func subscribe(_ id: UUID, _ continuation: AsyncThrowingStream<ClimateSnapshot, Error>.Continuation) async {
        subscribers[id] = continuation
        do {
            _ = try await connect()
        } catch {
            subscribers[id] = nil
            continuation.finish(throwing: error)
        }
    }

    private func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
    }

    private var timestamp: String {
        String(Int(Date().timeIntervalSince1970))
    }
}

extension TuyaValue {
    /// Converte um valor vindo do JSON do aparelho, distinguindo booleano de número.
    init?(json value: Any) {
        switch value {
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
            self = .bool(number.boolValue)
        case let number as NSNumber:
            self = .int(number.intValue)
        case let string as String:
            self = .string(string)
        default:
            return nil
        }
    }

    var jsonValue: Any {
        switch self {
        case .bool(let value): value
        case .int(let value): value
        case .string(let value): value
        }
    }
}

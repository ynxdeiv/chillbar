import Foundation

public enum ClimateField: Hashable, Sendable {
    case power, setpoint, mode, fanSpeed, verticalSwing
    case feature(ClimateFeature)
}

public enum FieldStatus: Equatable, Sendable {
    case synced
    case pending(since: Date)
    case failed(ClimateCommand)
}

public enum Freshness: Equatable, Sendable {
    case unknown
    case fresh
    case stale(since: Date)
}

/// Separa o que o usuário pediu do que o aparelho confirmou.
///
/// Um comando enviado fica pendente até o aparelho reportar o mesmo valor; se o
/// prazo vencer, vira falha e a interface volta a mostrar o último valor reportado.
public struct ClimateReconciler: Sendable {
    public let confirmationTimeout: TimeInterval
    public private(set) var reported = ClimateState()
    public private(set) var lastReportAt: Date?
    private var pending: [ClimateField: (command: ClimateCommand, sentAt: Date)] = [:]
    private var failures: [ClimateField: ClimateCommand] = [:]

    public init(confirmationTimeout: TimeInterval) {
        self.confirmationTimeout = confirmationTimeout
    }

    public var displayed: ClimateState {
        pending.values.reduce(into: reported) { state, entry in entry.command.apply(to: &state) }
    }

    public func status(of field: ClimateField) -> FieldStatus {
        if let entry = pending[field] { return .pending(since: entry.sentAt) }
        if let command = failures[field] { return .failed(command) }
        return .synced
    }

    public mutating func didSend(_ command: ClimateCommand, at date: Date) {
        failures[command.field] = nil
        pending[command.field] = (command, date)
    }

    /// Descarta um comando que nem chegou a sair (falha de envio).
    public mutating func cancelPending(_ field: ClimateField) {
        pending[field] = nil
    }

    public mutating func apply(_ snapshot: ClimateSnapshot) {
        reported.merge(snapshot.state)
        lastReportAt = snapshot.observedAt
        for (field, entry) in pending where entry.command.isSatisfied(by: reported) {
            pending[field] = nil
        }
    }

    /// Converte em falha os comandos sem confirmação dentro do prazo e os devolve.
    public mutating func expire(now: Date) -> [ClimateCommand] {
        let expired = pending.filter { now.timeIntervalSince($0.value.sentAt) >= confirmationTimeout }
        for (field, entry) in expired {
            pending[field] = nil
            failures[field] = entry.command
        }
        return expired.map(\.value.command)
    }

    public func freshness(now: Date, staleAfter: TimeInterval) -> Freshness {
        guard let lastReportAt else { return .unknown }
        return now.timeIntervalSince(lastReportAt) < staleAfter ? .fresh : .stale(since: lastReportAt)
    }
}

extension ClimateCommand {
    public var field: ClimateField {
        switch self {
        case .setPower: .power
        case .setSetpoint: .setpoint
        case .setMode: .mode
        case .setFanSpeed: .fanSpeed
        case .setVerticalSwing: .verticalSwing
        case .setFeature(let feature, _): .feature(feature)
        }
    }

    func apply(to state: inout ClimateState) {
        switch self {
        case .setPower(let value): state.isOn = value
        case .setSetpoint(let value): state.setpoint = value
        case .setMode(let value): state.mode = value
        case .setFanSpeed(let value): state.fanSpeed = value
        case .setVerticalSwing(let value): state.verticalSwing = value
        case .setFeature(let feature, let value): state.features[feature] = value
        }
    }

    /// `true` se o estado já tem o valor que este comando pede.
    public func isSatisfied(by state: ClimateState) -> Bool {
        var expected = state
        apply(to: &expected)
        return expected == state
    }
}

extension ClimateState {
    /// Sobrepõe apenas os campos presentes em `other`.
    mutating func merge(_ other: ClimateState) {
        isOn = other.isOn ?? isOn
        setpoint = other.setpoint ?? setpoint
        roomTemperature = other.roomTemperature ?? roomTemperature
        mode = other.mode ?? mode
        fanSpeed = other.fanSpeed ?? fanSpeed
        verticalSwing = other.verticalSwing ?? verticalSwing
        features.merge(other.features) { _, new in new }
    }
}

import Foundation

/// Período contínuo com o aparelho ligado.
public struct UsageSession: Equatable, Sendable, Codable {
    public let start: Date
    /// `false` quando o app encontrou o aparelho já ligado: o início real é anterior.
    public let startIsExact: Bool

    public init(start: Date, startIsExact: Bool) {
        self.start = start
        self.startIsExact = startIsExact
    }

    public func duration(now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(start))
    }

    /// kWh estimados a partir de uma potência média (não é medição).
    public func estimatedEnergy(now: Date, averageWatts: Double) -> Double {
        duration(now: now) / 3_600 * averageWatts / 1_000
    }
}

/// Acompanha há quanto tempo o aparelho está ligado, a partir dos estados reportados.
public struct UsageTracker: Equatable, Sendable, Codable {
    public private(set) var session: UsageSession?
    private var lastIsOn: Bool?

    public init() {}

    public mutating func observe(isOn: Bool, at date: Date) {
        switch (lastIsOn, isOn) {
        case (_, false):
            session = nil
        case (false?, true):
            session = UsageSession(start: date, startIsExact: true)
        case (nil, true):
            session = UsageSession(start: date, startIsExact: false)
        case (true?, true):
            break
        }
        lastIsOn = isOn
    }
}

import Foundation

/// Estado normalizado, independente do fabricante. `nil` significa "desconhecido"
/// (nunca reportado), nunca um valor padrão.
public struct ClimateState: Sendable, Equatable {
    public var isOn: Bool?
    public var setpoint: Temperature?
    public var roomTemperature: Temperature?
    public var mode: HVACMode?
    public var fanSpeed: FanSpeed?
    public var verticalSwing: Bool?
    public var features: [ClimateFeature: Bool]

    public init(
        isOn: Bool? = nil,
        setpoint: Temperature? = nil,
        roomTemperature: Temperature? = nil,
        mode: HVACMode? = nil,
        fanSpeed: FanSpeed? = nil,
        verticalSwing: Bool? = nil,
        features: [ClimateFeature: Bool] = [:]
    ) {
        self.isOn = isOn
        self.setpoint = setpoint
        self.roomTemperature = roomTemperature
        self.mode = mode
        self.fanSpeed = fanSpeed
        self.verticalSwing = verticalSwing
        self.features = features
    }
}

/// Estado observado em um instante. Pode ser parcial: aparelhos costumam reportar
/// só o que mudou.
public struct ClimateSnapshot: Sendable, Equatable {
    public var state: ClimateState
    public var observedAt: Date

    public init(state: ClimateState, observedAt: Date) {
        self.state = state
        self.observedAt = observedAt
    }
}

public enum ClimateCommand: Sendable, Equatable {
    case setPower(Bool)
    case setSetpoint(Temperature)
    case setMode(HVACMode)
    case setFanSpeed(FanSpeed)
    case setVerticalSwing(Bool)
    case setFeature(ClimateFeature, Bool)
}

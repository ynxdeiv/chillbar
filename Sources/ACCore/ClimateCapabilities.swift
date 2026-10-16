public enum HVACMode: String, Sendable, Codable, CaseIterable {
    case cool, heat, dry, fanOnly, auto
}

public enum FanSpeed: String, Sendable, Codable, CaseIterable {
    case auto, quiet, low, medium, high, turbo
}

/// Funções extras que alguns aparelhos expõem como liga/desliga.
public enum ClimateFeature: String, Sendable, Codable, CaseIterable {
    case display, sleep, ionizer, clean, antiMould, eco
}

/// O que cada modo deixa ajustar. `nil` = tudo o que o aparelho suporta.
/// Ex.: no Auto do Elgin a temperatura fica fixa e a ventilação é automática.
public struct ModeRule: Sendable, Equatable, Codable {
    public var allowsSetpoint: Bool
    /// Velocidades permitidas; vazio = ventilação automática (não ajustável).
    public var fanSpeeds: [FanSpeed]?
    /// Funções extras permitidas.
    public var features: [ClimateFeature]?

    public init(allowsSetpoint: Bool = true, fanSpeeds: [FanSpeed]? = nil, features: [ClimateFeature]? = nil) {
        self.allowsSetpoint = allowsSetpoint
        self.fanSpeeds = fanSpeeds
        self.features = features
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        allowsSetpoint = try container.decodeIfPresent(Bool.self, forKey: .allowsSetpoint) ?? true
        fanSpeeds = try container.decodeIfPresent([FanSpeed].self, forKey: .fanSpeeds)
        features = try container.decodeIfPresent([ClimateFeature].self, forKey: .features)
    }
}

/// O que o aparelho conectado suporta. A interface só mostra o que estiver aqui.
public struct ClimateCapabilities: Sendable, Equatable {
    public var modes: [HVACMode]
    public var fanSpeeds: [FanSpeed]
    public var setpointRange: ClosedRange<Temperature>
    public var setpointStep: Temperature
    public var reportsRoomTemperature: Bool
    public var supportsVerticalSwing: Bool
    public var features: [ClimateFeature]
    /// Potência média estimada enquanto ligado (W), para estimar consumo. Não é medição.
    public var estimatedAverageWatts: Double?
    /// Restrições por modo (modos sem regra liberam tudo).
    public var modeRules: [HVACMode: ModeRule]

    public init(
        modes: [HVACMode],
        fanSpeeds: [FanSpeed],
        setpointRange: ClosedRange<Temperature>,
        setpointStep: Temperature,
        reportsRoomTemperature: Bool,
        supportsVerticalSwing: Bool,
        features: [ClimateFeature],
        estimatedAverageWatts: Double? = nil,
        modeRules: [HVACMode: ModeRule] = [:]
    ) {
        self.modes = modes
        self.fanSpeeds = fanSpeeds
        self.setpointRange = setpointRange
        self.setpointStep = setpointStep
        self.reportsRoomTemperature = reportsRoomTemperature
        self.supportsVerticalSwing = supportsVerticalSwing
        self.features = features
        self.estimatedAverageWatts = estimatedAverageWatts
        self.modeRules = modeRules
    }

    public func rule(for mode: HVACMode?) -> ModeRule {
        mode.flatMap { modeRules[$0] } ?? ModeRule()
    }

    /// Velocidades ajustáveis no modo (na ordem do aparelho).
    public func fanSpeeds(in mode: HVACMode?) -> [FanSpeed] {
        guard let allowed = rule(for: mode).fanSpeeds else { return fanSpeeds }
        return fanSpeeds.filter(allowed.contains)
    }

    /// Funções extras disponíveis no modo (na ordem do aparelho).
    public func features(in mode: HVACMode?) -> [ClimateFeature] {
        guard let allowed = rule(for: mode).features else { return features }
        return features.filter(allowed.contains)
    }
}

public enum CommandValidationError: Error, Equatable {
    case setpointOutOfRange
    case setpointOffStep
    case unsupportedMode
    case unsupportedFanSpeed
    case unsupportedVerticalSwing
    case unsupportedFeature
    case unavailableInMode
}

extension ClimateCapabilities {
    /// Rejeita comandos que o aparelho não suporta antes de enviá-los.
    public func validate(_ command: ClimateCommand) throws(CommandValidationError) {
        switch command {
        case .setPower:
            return
        case .setSetpoint(let target):
            guard setpointRange.contains(target) else { throw .setpointOutOfRange }
            let offset = target.tenthsOfCelsius - setpointRange.lowerBound.tenthsOfCelsius
            guard offset % setpointStep.tenthsOfCelsius == 0 else { throw .setpointOffStep }
        case .setMode(let mode):
            guard modes.contains(mode) else { throw .unsupportedMode }
        case .setFanSpeed(let speed):
            guard fanSpeeds.contains(speed) else { throw .unsupportedFanSpeed }
        case .setVerticalSwing:
            guard supportsVerticalSwing else { throw .unsupportedVerticalSwing }
        case .setFeature(let feature, _):
            guard features.contains(feature) else { throw .unsupportedFeature }
        }
    }

    /// Como `validate(_:)`, mais as restrições do modo em que o aparelho está.
    public func validate(_ command: ClimateCommand, in mode: HVACMode?) throws(CommandValidationError) {
        try validate(command)
        switch command {
        case .setSetpoint:
            guard rule(for: mode).allowsSetpoint else { throw .unavailableInMode }
        case .setFanSpeed(let speed):
            guard fanSpeeds(in: mode).contains(speed) else { throw .unavailableInMode }
        case .setFeature(let feature, _):
            guard features(in: mode).contains(feature) else { throw .unavailableInMode }
        case .setPower, .setMode, .setVerticalSwing:
            return
        }
    }
}

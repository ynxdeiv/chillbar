import ACCore

public enum TuyaMappingError: Error, Equatable {
    /// O perfil não tem DP para este comando.
    case unsupported
}

/// Traduz DPs ↔ modelo normalizado usando um `TuyaDeviceProfile`.
public struct TuyaClimateMapper: Sendable {
    public let profile: TuyaDeviceProfile

    public init(profile: TuyaDeviceProfile) {
        self.profile = profile
    }

    /// Converte um relatório (completo ou parcial). DPs ausentes ou com valor
    /// desconhecido ficam `nil`.
    public func state(from dps: [String: TuyaValue]) -> ClimateState {
        var state = ClimateState()
        state.isOn = profile.power.flatMap { dps[$0.dp]?.boolValue }
        state.setpoint = profile.setpoint.flatMap { temperature(dps[$0.dp], spec: $0) }
        state.roomTemperature = profile.roomTemperature.flatMap { temperature(dps[$0.dp], spec: $0) }
        state.mode = profile.mode.flatMap { enumValue(dps[$0.dp], spec: $0) }
        state.fanSpeed = profile.fanSpeed.flatMap { enumValue(dps[$0.dp], spec: $0) }
        state.verticalSwing = profile.verticalSwing.flatMap { dps[$0.dp]?.boolValue }
        for (name, dp) in profile.features ?? [:] {
            if let feature = ClimateFeature(rawValue: name), let value = dps[dp]?.boolValue {
                state.features[feature] = value
            }
        }
        return state
    }

    public func dps(for command: ClimateCommand) throws(TuyaMappingError) -> [String: TuyaValue] {
        switch command {
        case .setPower(let value):
            guard let spec = profile.power else { throw .unsupported }
            return [spec.dp: .bool(value)]
        case .setSetpoint(let value):
            guard let spec = profile.setpoint else { throw .unsupported }
            return [spec.dp: .int(value.tenthsOfCelsius * spec.unitsPerDegree / 10)]
        case .setMode(let mode):
            guard let spec = profile.mode, let raw = spec.values[mode.rawValue] else { throw .unsupported }
            return [spec.dp: .string(raw)]
        case .setFanSpeed(let speed):
            guard let spec = profile.fanSpeed, let raw = spec.values[speed.rawValue] else { throw .unsupported }
            return [spec.dp: .string(raw)]
        case .setVerticalSwing(let value):
            guard let spec = profile.verticalSwing else { throw .unsupported }
            return [spec.dp: .bool(value)]
        case .setFeature(let feature, let value):
            guard let dp = profile.features?[feature.rawValue] else { throw .unsupported }
            return [dp: .bool(value)]
        }
    }

    private func temperature(_ value: TuyaValue?, spec: TuyaDeviceProfile.Temperature) -> Temperature? {
        guard case .int(let units)? = value else { return nil }
        return Temperature(tenthsOfCelsius: units * 10 / spec.unitsPerDegree)
    }

    private func enumValue<Value: RawRepresentable<String>>(
        _ value: TuyaValue?,
        spec: TuyaDeviceProfile.Enumeration<Value>
    ) -> Value? {
        guard case .string(let raw)? = value,
              let name = spec.values.first(where: { $0.value == raw })?.key
        else { return nil }
        return Value(rawValue: name)
    }
}

extension TuyaValue {
    var boolValue: Bool? {
        if case .bool(let value) = self { value } else { nil }
    }
}

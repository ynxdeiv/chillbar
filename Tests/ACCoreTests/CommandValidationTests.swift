import Testing
@testable import ACCore

/// Aparelho só frio, 16–32 °C em passos de 1 °C, sem oscilação.
private let coolOnly = ClimateCapabilities(
    modes: [.cool, .dry, .fanOnly, .auto],
    fanSpeeds: [.auto, .low, .medium, .high],
    setpointRange: Temperature(celsius: 16)...Temperature(celsius: 32),
    setpointStep: Temperature(celsius: 1),
    reportsRoomTemperature: true,
    supportsVerticalSwing: false,
    features: [.display, .sleep]
)

@Suite("Validação de comandos")
struct CommandValidationTests {
    @Test("aceita setpoint dentro da faixa e no passo")
    func acceptsValidSetpoint() throws {
        try coolOnly.validate(.setSetpoint(Temperature(celsius: 24)))
        try coolOnly.validate(.setSetpoint(Temperature(celsius: 16)))
        try coolOnly.validate(.setSetpoint(Temperature(celsius: 32)))
    }

    @Test("rejeita setpoint fora da faixa", arguments: [15.0, 33.0])
    func rejectsSetpointOutOfRange(celsius: Double) {
        #expect(throws: CommandValidationError.setpointOutOfRange) {
            try coolOnly.validate(.setSetpoint(Temperature(celsius: celsius)))
        }
    }

    @Test("rejeita setpoint fora do passo")
    func rejectsSetpointOffStep() {
        #expect(throws: CommandValidationError.setpointOffStep) {
            try coolOnly.validate(.setSetpoint(Temperature(celsius: 24.5)))
        }
    }

    @Test("rejeita aquecer em aparelho só frio")
    func rejectsHeatOnCoolOnly() {
        #expect(throws: CommandValidationError.unsupportedMode) {
            try coolOnly.validate(.setMode(.heat))
        }
        #expect(throws: Never.self) { try coolOnly.validate(.setMode(.dry)) }
    }

    @Test("rejeita velocidade de ventilação não suportada")
    func rejectsUnsupportedFanSpeed() {
        #expect(throws: CommandValidationError.unsupportedFanSpeed) {
            try coolOnly.validate(.setFanSpeed(.turbo))
        }
    }

    @Test("rejeita oscilação quando o aparelho não oscila")
    func rejectsSwingWhenUnsupported() {
        #expect(throws: CommandValidationError.unsupportedVerticalSwing) {
            try coolOnly.validate(.setVerticalSwing(true))
        }
    }

    @Test("rejeita função extra não suportada e aceita a suportada")
    func validatesFeatures() {
        #expect(throws: CommandValidationError.unsupportedFeature) {
            try coolOnly.validate(.setFeature(.ionizer, true))
        }
        #expect(throws: Never.self) { try coolOnly.validate(.setFeature(.sleep, true)) }
    }
}

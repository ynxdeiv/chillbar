import Testing
@testable import ACCore

/// Regras do manual do Elgin Eco Inverter III (HJ): Auto fixa 25 °C e ventilação;
/// Desumidificar fixa a ventilação; Ventilar não usa temperatura; Turbo só no Frio;
/// Dormir só em Frio e Desumidificar.
private let elgin = ClimateCapabilities(
    modes: [.cool, .dry, .fanOnly, .auto],
    fanSpeeds: [.auto, .low, .medium, .high, .turbo],
    setpointRange: Temperature(celsius: 16)...Temperature(celsius: 30),
    setpointStep: Temperature(celsius: 1),
    reportsRoomTemperature: true,
    supportsVerticalSwing: true,
    features: [.display, .sleep, .ionizer, .clean, .antiMould],
    modeRules: [
        .auto: ModeRule(allowsSetpoint: false, fanSpeeds: [], features: [.display, .ionizer, .clean, .antiMould]),
        .dry: ModeRule(fanSpeeds: []),
        .fanOnly: ModeRule(allowsSetpoint: false, fanSpeeds: [.auto, .low, .medium, .high], features: [.display, .ionizer, .clean, .antiMould]),
    ]
)

@Suite("Regras por modo")
struct ModeRuleTests {
    @Test("no Auto, temperatura, ventilação, Turbo e Dormir ficam travados", arguments: [
        ClimateCommand.setSetpoint(Temperature(celsius: 24)),
        .setFanSpeed(.low),
        .setFanSpeed(.turbo),
        .setFeature(.sleep, true),
    ])
    func autoLocks(command: ClimateCommand) {
        #expect(throws: CommandValidationError.unavailableInMode) { try elgin.validate(command, in: .auto) }
    }

    @Test("no Auto, ligar/desligar, trocar de modo, oscilar e funções permitidas continuam", arguments: [
        ClimateCommand.setPower(false),
        .setMode(.cool),
        .setVerticalSwing(true),
        .setFeature(.display, false),
        .setFeature(.ionizer, true),
    ])
    func autoAllows(command: ClimateCommand) {
        #expect(throws: Never.self) { try elgin.validate(command, in: .auto) }
    }

    @Test("Desumidificar trava só a ventilação")
    func dryLocksFanOnly() {
        #expect(throws: CommandValidationError.unavailableInMode) { try elgin.validate(.setFanSpeed(.high), in: .dry) }
        #expect(throws: Never.self) { try elgin.validate(.setSetpoint(Temperature(celsius: 22)), in: .dry) }
        #expect(throws: Never.self) { try elgin.validate(.setFeature(.sleep, true), in: .dry) }
    }

    @Test("Ventilar não usa temperatura nem Turbo, mas aceita as velocidades")
    func fanOnlyRules() {
        #expect(throws: CommandValidationError.unavailableInMode) { try elgin.validate(.setSetpoint(Temperature(celsius: 22)), in: .fanOnly) }
        #expect(throws: CommandValidationError.unavailableInMode) { try elgin.validate(.setFanSpeed(.turbo), in: .fanOnly) }
        #expect(throws: Never.self) { try elgin.validate(.setFanSpeed(.medium), in: .fanOnly) }
    }

    @Test("Frio (sem regra) libera tudo, inclusive Turbo")
    func coolAllowsEverything() {
        #expect(throws: Never.self) { try elgin.validate(.setFanSpeed(.turbo), in: .cool) }
        #expect(throws: Never.self) { try elgin.validate(.setSetpoint(Temperature(celsius: 18)), in: .cool) }
    }

    @Test("modo desconhecido não trava nada")
    func unknownModeAllows() {
        #expect(throws: Never.self) { try elgin.validate(.setFanSpeed(.low), in: nil) }
    }

    @Test("a regra efetiva informa o que a interface pode mostrar")
    func effectiveRule() {
        let auto = elgin.rule(for: .auto)
        #expect(auto.allowsSetpoint == false)
        #expect(elgin.fanSpeeds(in: .auto) == [])
        #expect(elgin.fanSpeeds(in: .fanOnly) == [.auto, .low, .medium, .high])
        #expect(elgin.fanSpeeds(in: .cool) == [.auto, .low, .medium, .high, .turbo])
        #expect(elgin.features(in: .auto) == [.display, .ionizer, .clean, .antiMould])
        #expect(elgin.features(in: .dry) == [.display, .sleep, .ionizer, .clean, .antiMould])
    }
}

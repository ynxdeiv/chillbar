import Foundation
import Testing
import ACCore
@testable import ACTuya

/// DPs lidos do Elgin 45HJFI12C2WF na prova de conceito (16/10/2026), sem alterações.
private let elginReportJSON = """
{"1": true, "2": 250, "3": 230, "4": "cold", "5": "auto", "8": false, "12": false, "13": true,
 "14": false, "19": "C", "28": 0, "33": false, "102": false, "103": false, "104": false,
 "105": false, "106": true, "107": 0, "108": 6, "109": false, "110": false, "111": 0,
 "112": 0, "114": false}
"""

private func decodeDPs(_ json: String) throws -> [String: TuyaValue] {
    try JSONDecoder().decode([String: TuyaValue].self, from: Data(json.utf8))
}

private func elginMapper() throws -> TuyaClimateMapper {
    let profile = try #require(TuyaDeviceProfile.bundled(category: "kt", productID: "gncaqbnuk4cj2etp"))
    return TuyaClimateMapper(profile: profile)
}

@Suite("Perfil e mapeamento Tuya")
struct TuyaClimateMapperTests {
    @Test("valores JSON mantêm o tipo: booleano, inteiro e texto")
    func decodesTypedValues() throws {
        let dps = try decodeDPs(#"{"1": true, "2": 250, "4": "cold"}"#)
        #expect(dps == ["1": .bool(true), "2": .int(250), "4": .string("cold")])
    }

    @Test("encontra o perfil do Elgin pelo product_id e ignora produtos desconhecidos")
    func findsBundledProfile() {
        #expect(TuyaDeviceProfile.bundled(category: "kt", productID: "gncaqbnuk4cj2etp") != nil)
        #expect(TuyaDeviceProfile.bundled(category: "kt", productID: "desconhecido") == nil)
        #expect(TuyaDeviceProfile.bundled(category: "dj", productID: "gncaqbnuk4cj2etp") == nil)
    }

    @Test("o perfil do Elgin só frio não oferece aquecimento")
    func elginProfileIsCoolOnly() throws {
        let capabilities = try elginMapper().profile.capabilities
        #expect(capabilities.modes == [.cool, .dry, .fanOnly, .auto])
        #expect(capabilities.setpointStep == Temperature(celsius: 1))
    }

    @Test("perfil do Elgin segue o manual: Auto trava temperatura e ventilação; sem tecla Silêncio")
    func elginModeRules() throws {
        let capabilities = try elginMapper().profile.capabilities
        #expect(capabilities.rule(for: .auto).allowsSetpoint == false)
        #expect(capabilities.fanSpeeds(in: .auto) == [])
        #expect(capabilities.fanSpeeds(in: .dry) == [])
        #expect(capabilities.rule(for: .fanOnly).allowsSetpoint == false)
        #expect(capabilities.fanSpeeds(in: .cool).contains(.turbo))
        #expect(!capabilities.fanSpeeds.contains(.quiet))
        #expect(!capabilities.features(in: .auto).contains(.sleep))
    }

    @Test("potência média estimada vem da etiqueta INMETRO do perfil (406 kWh/ano ÷ 2.080 h)")
    func elginEstimatedPower() throws {
        let watts = try #require(try elginMapper().profile.capabilities.estimatedAverageWatts)
        #expect(abs(watts - 195.19) < 0.01)
    }

    @Test("converte o relatório real do Elgin para o estado normalizado")
    func mapsRealReport() throws {
        let state = try elginMapper().state(from: decodeDPs(elginReportJSON))
        #expect(state == ClimateState(
            isOn: true,
            setpoint: Temperature(celsius: 25),
            roomTemperature: Temperature(celsius: 23),
            mode: .cool,
            fanSpeed: .auto,
            verticalSwing: false,
            features: [.display: true, .sleep: false, .clean: false, .antiMould: false, .ionizer: true]
        ))
    }

    @Test("relatório parcial gera estado parcial")
    func mapsPartialReport() throws {
        let state = try elginMapper().state(from: ["2": .int(260)])
        #expect(state == ClimateState(setpoint: Temperature(celsius: 26)))
    }

    @Test("valor de enum fora do perfil vira desconhecido, não um modo errado")
    func unknownEnumBecomesNil() throws {
        let state = try elginMapper().state(from: ["4": .string("hot"), "5": .string("hurricane")])
        #expect(state.mode == nil)
        #expect(state.fanSpeed == nil)
    }

    @Test("comandos viram os DPs do Elgin", arguments: [
        (ClimateCommand.setPower(false), ["1": TuyaValue.bool(false)]),
        (.setSetpoint(Temperature(celsius: 26)), ["2": .int(260)]),
        (.setMode(.dry), ["4": .string("wet")]),
        (.setMode(.fanOnly), ["4": .string("wind")]),
        (.setFanSpeed(.medium), ["5": .string("mid")]),
        (.setFanSpeed(.turbo), ["5": .string("strength")]),
        (.setVerticalSwing(true), ["105": .bool(true)]),
        (.setFeature(.ionizer, false), ["106": .bool(false)]),
    ])
    func mapsCommands(command: ClimateCommand, expected: [String: TuyaValue]) throws {
        #expect(try elginMapper().dps(for: command) == expected)
    }

    @Test("comando sem DP no perfil é rejeitado")
    func rejectsUnmappedCommand() throws {
        let mapper = try elginMapper()
        #expect(throws: TuyaMappingError.unsupported) { try mapper.dps(for: .setMode(.heat)) }
        #expect(throws: TuyaMappingError.unsupported) { try mapper.dps(for: .setFeature(.eco, true)) }
    }

    @Test("respeita a escala do perfil (aparelho em graus inteiros)")
    func appliesScale() throws {
        let json = #"""
        {"id": "teste", "name": "Teste", "category": "kt", "productIDs": ["x"], "protocolVersion": "3.3",
         "setpoint": {"dp": "2", "unitsPerDegree": 1, "min": 16, "max": 30, "step": 1}}
        """#
        let profile = try JSONDecoder().decode(TuyaDeviceProfile.self, from: Data(json.utf8))
        let mapper = TuyaClimateMapper(profile: profile)

        #expect(mapper.state(from: ["2": .int(24)]).setpoint == Temperature(celsius: 24))
        #expect(try mapper.dps(for: .setSetpoint(Temperature(celsius: 26))) == ["2": .int(26)])
    }
}

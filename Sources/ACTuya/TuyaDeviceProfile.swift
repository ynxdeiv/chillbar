import ACCore
import Foundation

/// Descreve, em dados, como os DPs de um modelo Tuya se traduzem no modelo normalizado.
/// Novos aparelhos entram como um JSON em `Profiles/`, sem mudar código.
public struct TuyaDeviceProfile: Codable, Sendable, Equatable {
    public struct Switch: Codable, Sendable, Equatable {
        public var dp: String
    }

    public struct Temperature: Codable, Sendable, Equatable {
        public var dp: String
        /// Unidades do aparelho por grau Celsius (10 quando o aparelho reporta 250 para 25,0 °C).
        public var unitsPerDegree: Int
        public var min: Double?
        public var max: Double?
        public var step: Double?
    }

    /// Consumo declarado na etiqueta de eficiência, usado só para estimativas.
    public struct Energy: Codable, Sendable, Equatable {
        public var annualKWh: Double
        public var annualHours: Double
        public var source: String?
    }

    public struct Enumeration<Value: Hashable & Codable & Sendable>: Codable, Sendable, Equatable {
        public var dp: String
        /// Valor normalizado → texto usado pelo aparelho.
        public var values: [String: String]
    }

    public var id: String
    public var name: String
    public var category: String
    public var productIDs: [String]
    public var protocolVersion: String
    public var notes: String?
    public var power: Switch?
    public var setpoint: Temperature?
    public var roomTemperature: Temperature?
    public var mode: Enumeration<HVACMode>?
    public var fanSpeed: Enumeration<FanSpeed>?
    public var verticalSwing: Switch?
    /// Função extra → DP.
    public var features: [String: String]?
    public var energy: Energy?
    /// Restrições por modo, chaveadas pelo nome do modo normalizado ("auto", "dry"…).
    public var modeRules: [String: ModeRule]?
}

extension TuyaDeviceProfile {
    public static func bundled(category: String, productID: String) -> TuyaDeviceProfile? {
        allBundled.first { $0.category == category && $0.productIDs.contains(productID) }
    }

    /// Perfil para um modelo; sem correspondência exata, o primeiro da mesma categoria.
    public static func bestMatch(category: String, productID: String?) -> TuyaDeviceProfile? {
        bundled(category: category, productID: productID ?? "") ?? allBundled.first { $0.category == category }
    }

    static let allBundled: [TuyaDeviceProfile] = {
        let urls = resourceBundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        return urls.compactMap { url in
            try? JSONDecoder().decode(TuyaDeviceProfile.self, from: Data(contentsOf: url))
        }
    }()

    /// No .app os recursos ficam em Contents/Resources; em testes e `swift run`, `Bundle.module` resolve.
    private static var resourceBundle: Bundle {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Chillbar_ACTuya.bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }

    public var capabilities: ClimateCapabilities {
        let range = setpoint.map { ACCore.Temperature(celsius: $0.min ?? 16)...ACCore.Temperature(celsius: $0.max ?? 30) }
        return ClimateCapabilities(
            modes: HVACMode.allCases.filter { mode?.values[$0.rawValue] != nil },
            fanSpeeds: FanSpeed.allCases.filter { fanSpeed?.values[$0.rawValue] != nil },
            setpointRange: range ?? ACCore.Temperature(celsius: 0)...ACCore.Temperature(celsius: 0),
            setpointStep: ACCore.Temperature(celsius: setpoint?.step ?? 1),
            reportsRoomTemperature: roomTemperature != nil,
            supportsVerticalSwing: verticalSwing != nil,
            features: ClimateFeature.allCases.filter { features?[$0.rawValue] != nil },
            estimatedAverageWatts: energy.map { $0.annualKWh * 1_000 / $0.annualHours },
            modeRules: Dictionary(uniqueKeysWithValues: (modeRules ?? [:]).compactMap { name, rule in
                HVACMode(rawValue: name).map { ($0, rule) }
            })
        )
    }
}

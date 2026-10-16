import ACApplication
import ACCore
import ACInterface
import ACSimulator
import ACTuya
import Foundation
import Observation

/// Decide qual aparelho o pop-up controla: o real (salvo no Keychain) ou o simulado.
@MainActor
@Observable
final class AppModel {
    private(set) var controller: ClimateController

    init() {
        controller = Self.makeController()
        start()
    }

    /// Chamado depois do assistente: troca para o aparelho recém-salvo sem reiniciar o app.
    func reloadDevice() {
        controller.stop()
        controller = Self.makeController()
        start()
    }

    private func start() {
        let controller = controller
        Task { await controller.start() }
    }

    private static func makeController() -> ClimateController {
        let usageKey = "usageTracker"
        let savedUsage = UserDefaults.standard.data(forKey: usageKey)
            .flatMap { try? JSONDecoder().decode(UsageTracker.self, from: $0) }
        let saveUsage: @MainActor (UsageTracker) -> Void = { tracker in
            UserDefaults.standard.set(try? JSONEncoder().encode(tracker), forKey: usageKey)
        }

        if let device = try? KeychainDeviceStore().load(),
           let profile = TuyaDeviceProfile.bestMatch(category: "kt", productID: device.productID) {
            // O IP muda de vez em quando (DHCP): guardamos o último e procuramos de novo se falhar.
            let hostKey = "deviceHost.\(device.id)"
            let adapter = TuyaLocalAdapter(
                deviceID: device.id,
                localKey: device.secret,
                host: UserDefaults.standard.string(forKey: hostKey),
                profile: profile,
                locate: { await TuyaNetworkDiscovery.find(deviceID: device.id)?.ip },
                onHostFound: { host in UserDefaults.standard.set(host, forKey: hostKey) }
            )
            return ClimateController(
                deviceName: device.name,
                sourceName: InterfaceText.localNetwork,
                adapter: adapter,
                usage: savedUsage ?? UsageTracker(),
                saveUsage: saveUsage
            )
        }

        let fallback = TuyaDeviceProfile.bestMatch(category: "kt", productID: nil)
        let simulator = SimulatedClimateDevice(
            capabilities: fallback?.capabilities ?? ClimateCapabilities(
                modes: [.cool], fanSpeeds: [.auto],
                setpointRange: Temperature(celsius: 16)...Temperature(celsius: 30),
                setpointStep: Temperature(celsius: 1),
                reportsRoomTemperature: true, supportsVerticalSwing: false, features: []
            ),
            initialState: DemoDevice.initialState
        )
        return ClimateController(
            deviceName: "Chillbar",
            sourceName: InterfaceText.simulation,
            adapter: simulator,
            usage: savedUsage ?? UsageTracker(),
            saveUsage: saveUsage
        )
    }
}

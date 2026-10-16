import ACApplication
import ACInterface
import AppKit
import SwiftUI

@main
struct ChillbarApp: App {
    @State private var model: AppModel

    init() {
        // Utilitário de barra de menus: sem ícone no Dock nem janela principal.
        NSApplication.shared.setActivationPolicy(.accessory)
        let model = AppModel()
        _model = State(initialValue: model)
        SetupWindowController.shared.onDeviceSaved = { model.reloadDevice() }

        // Primeira abertura sem aparelho configurado: abre o assistente uma vez.
        let promptedKey = "setupPrompted"
        if (try? KeychainDeviceStore().load()) == nil, !UserDefaults.standard.bool(forKey: promptedKey) {
            UserDefaults.standard.set(true, forKey: promptedKey)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                SetupWindowController.shared.show()
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            ClimatePopover(controller: model.controller) {
                SetupWindowController.shared.show()
            }
            .id(ObjectIdentifier(model.controller))
        } label: {
            MenuBarLabel(controller: model.controller)
        }
        .menuBarExtraStyle(.window)
    }
}

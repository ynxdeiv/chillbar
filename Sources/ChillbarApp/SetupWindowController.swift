import ACApplication
import ACInterface
import AppKit
import SwiftUI

/// Janela do assistente de configuração. Uma só instância; reabrir traz para a frente.
@MainActor
final class SetupWindowController {
    static let shared = SetupWindowController()
    /// Avisado quando o assistente salva um aparelho, para o pop-up passar a usá-lo.
    var onDeviceSaved: (() -> Void)?
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let flow = SetupFlow(account: SmartLifeAccount(), store: KeychainDeviceStore())
        let view = SetupView(flow: flow) { [weak self] in
            self?.window?.close()
            self?.onDeviceSaved?()
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Chillbar"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.window = nil }
        }
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

// Gera PNGs do popover e do ícone em vários estados, para revisar o visual
// sem abrir a barra de menus. Uso: swift run ACSnapshots <pasta-de-saída>
import ACApplication
import ACCore
import ACInterface
import ACSimulator
import ACTuya
import AppKit
import SwiftUI

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/snapshots")
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

guard let profile = TuyaDeviceProfile.bundled(category: "kt", productID: "gncaqbnuk4cj2etp") else {
    fatalError("Perfil do Elgin não encontrado")
}

struct OfflineDevice: ClimateDeviceAdapter {
    let capabilities: ClimateCapabilities
    func stateUpdates() -> AsyncThrowingStream<ClimateSnapshot, Error> { AsyncThrowingStream { $0.finish() } }
    func refresh() async throws -> ClimateSnapshot { throw URLError(.cannotConnectToHost) }
    func send(_ command: ClimateCommand) async throws { throw URLError(.cannotConnectToHost) }
}

@MainActor
func controller(
    state: ClimateState = DemoDevice.initialState,
    ignoring: Bool = false,
    offline: Bool = false
) async -> (ClimateController, SimulatedClimateDevice) {
    let device = SimulatedClimateDevice(capabilities: profile.capabilities, initialState: state, latency: .zero)
    await device.setIgnoresCommands(ignoring)
    let adapter: any ClimateDeviceAdapter = offline ? OfflineDevice(capabilities: profile.capabilities) : device
    let controller = ClimateController(deviceName: "Bedroom AC", sourceName: InterfaceText.localNetwork, adapter: adapter)
    await controller.start()
    try? await Task.sleep(for: .milliseconds(50))
    return (controller, device)
}

@MainActor
func save(_ view: some View, name: String) {
    for scheme in [ColorScheme.light, .dark] {
        let content = view
            .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.95))
            .environment(\.colorScheme, scheme)
            .environment(\.isStaticRendering, true)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.cgImage else { continue }
        let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        let suffix = scheme == .dark ? "escuro" : "claro"
        try? data?.write(to: outputDirectory.appendingPathComponent("\(name)-\(suffix).png"))
    }
}

var dryTurbo = DemoDevice.initialState
dryTurbo.mode = .dry
dryTurbo.fanSpeed = .turbo
dryTurbo.verticalSwing = true
dryTurbo.features[.sleep] = true

var off = DemoDevice.initialState
off.isOn = false

save(ClimatePopover(controller: await controller().0), name: "1-ligado-frio")
save(ClimatePopover(controller: await controller(state: dryTurbo).0), name: "2-desumidificar-turbo")

let (sending, _) = await controller(ignoring: true)
await sending.send(.setSetpoint(Temperature(celsius: 22)))
save(ClimatePopover(controller: sending), name: "3-enviando")
sending.expirePending(now: Date().addingTimeInterval(11))
save(ClimatePopover(controller: sending), name: "4-nao-confirmado")

save(ClimatePopover(controller: await controller(state: off).0), name: "5-desligado")

var autoMode = DemoDevice.initialState
autoMode.mode = .auto
save(ClimatePopover(controller: await controller(state: autoMode).0), name: "7-modo-auto")
save(ClimatePopover(controller: await controller(offline: true).0), name: "6-sem-conexao")

let icons = HStack(spacing: 28) {
    ForEach([MenuBarIcon.Style.on, .off, .disconnected], id: \.self) { style in
        Image(nsImage: MenuBarIcon.image(style))
            .renderingMode(.template)
            .resizable()
            .interpolation(.none)
            .frame(width: 80, height: 72)
    }
}
.foregroundStyle(.primary)
.padding(24)
save(icons, name: "0-icones")

print("Snapshots em \(outputDirectory.path)")

// MARK: Assistente de configuração

struct SnapshotAccount: AccountLinking {
    func requestQRCode(userCode: String) async throws -> SetupQRCode {
        SetupQRCode(content: "tuyaSmart--qrLogin?token=snapshot", token: "snapshot")
    }
    func devicesIfConfirmed(qrCode: SetupQRCode, userCode: String) async throws -> [SetupDevice]? {
        [SetupDevice(id: "d", name: "Bedroom AC", model: "Smart air conditioner", isOnline: true, isAirConditioner: true, secret: "s")]
    }
}

final class SnapshotStore: DeviceStore, @unchecked Sendable {
    func load() throws -> SavedDevice? { nil }
    func save(_ device: SavedDevice) throws {}
    func delete() throws {}
}

@MainActor
func setupFlow(_ step: SetupFlow.Step) async -> SetupFlow {
    let flow = SetupFlow(account: SnapshotAccount(), store: SnapshotStore())
    if step == .welcome { return flow }
    flow.continueFromWelcome()
    flow.userCode = step == .userCode ? "" : "abc123"
    if step == .userCode { return flow }
    await flow.submitUserCode()
    if step == .scan { return flow }
    await flow.pollOnce()
    return flow
}

for step in [SetupFlow.Step.welcome, .userCode, .scan, .saved] {
    save(SetupView(flow: await setupFlow(step), onClose: {}), name: "setup-\(step)")
}

// MARK: Imagens do README e do vídeo (--docs <pasta>)

/// Janela/pop-up "de verdade": cantos arredondados, sombra e fundo suave.
@MainActor
func saveFramed(_ view: some View, name: String, scheme: ColorScheme, corner: CGFloat = 22, directory: URL) {
    let window = view
        .background(scheme == .dark ? Color(white: 0.15) : Color(white: 0.965))
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 30, y: 16)
        .padding(56)
        .environment(\.colorScheme, scheme)
        .environment(\.isStaticRendering, true)
    let renderer = ImageRenderer(content: window)
    renderer.scale = 2
    guard let image = renderer.cgImage,
          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
    try? data.write(to: directory.appendingPathComponent("\(name).png"))
}

if let index = CommandLine.arguments.firstIndex(of: "--docs"), CommandLine.arguments.count > index + 1 {
    let docs = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)

    var cool = DemoDevice.initialState
    cool.setpoint = Temperature(celsius: 23)
    let (popoverCool, _) = await controller(state: cool)
    saveFramed(ClimatePopover(controller: popoverCool), name: "popover-light", scheme: .light, directory: docs)
    saveFramed(ClimatePopover(controller: popoverCool), name: "popover-dark", scheme: .dark, directory: docs)

    var dry = DemoDevice.initialState
    dry.mode = .dry
    dry.verticalSwing = true
    saveFramed(ClimatePopover(controller: await controller(state: dry).0), name: "popover-dry-dark", scheme: .dark, directory: docs)

    var auto = DemoDevice.initialState
    auto.mode = .auto
    saveFramed(ClimatePopover(controller: await controller(state: auto).0), name: "popover-auto-light", scheme: .light, directory: docs)

    var offState = DemoDevice.initialState
    offState.isOn = false
    saveFramed(ClimatePopover(controller: await controller(state: offState).0), name: "popover-off-light", scheme: .light, directory: docs)

    for step in [SetupFlow.Step.welcome, .userCode, .scan, .saved] {
        saveFramed(SetupView(flow: await setupFlow(step), onClose: {}), name: "setup-\(step)", scheme: .light, corner: 16, directory: docs)
    }
    print("Imagens do README em \(docs.path)")
}

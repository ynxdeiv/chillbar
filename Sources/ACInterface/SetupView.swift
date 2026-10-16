import ACApplication
import ACCore
import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Assistente de configuração (janela própria: o usuário vai e volta do celular).
/// Cada passo mostra no desenho do celular exatamente onde tocar.
public struct SetupView: View {
    @Bindable var flow: SetupFlow
    let onClose: () -> Void
    @AppStorage(AppLanguage.defaultsKey) private var language = AppLanguage.english.rawValue
    @Environment(\.isStaticRendering) private var isStaticRendering

    public init(flow: SetupFlow, onClose: @escaping () -> Void) {
        self.flow = flow
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                StepDots(current: stepIndex, total: 4)
                Spacer()
                if isStaticRendering {
                    staticLanguagePicker
                } else {
                    Picker(L("Language"), selection: $language) {
                        ForEach(AppLanguage.allCases) { option in
                            Text(option.shortName).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            buttons
        }
        .padding(.horizontal, 30)
        .padding(.top, 34)
        .padding(.bottom, 26)
        .frame(width: 520, height: 660)
        .animation(.easeInOut(duration: 0.2), value: flow.step)
        .id(language)
        .environment(\.locale, AppLanguage(rawValue: language)?.locale ?? .current)
    }

    private var stepIndex: Int {
        switch flow.step {
        case .welcome: 0
        case .userCode: 1
        case .scan, .chooseDevice: 2
        case .saved: 3
        }
    }

    @ViewBuilder
    private var content: some View {
        switch flow.step {
        case .welcome: welcome
        case .userCode: userCode
        case .scan: scan
        case .chooseDevice: chooseDevice
        case .saved: saved
        }
    }

    // MARK: Passos

    private var welcome: some View {
        let name = macUserFirstName
        return VStack(alignment: .leading, spacing: 16) {
            ChillMascot(width: 230)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)
            title(name.isEmpty ? L("Hi!") : L("Hi, \(name)!"))
            Text(L("I’m Chill. I put your air conditioner right in your Mac’s menu bar."))
                .font(.system(size: 15))
            Text(L("It takes about two minutes. Keep your phone nearby."))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                requirement("iphone", L("Your air conditioner already works in the Smart Life app")) {
                    if isStaticRendering {
                        Text(L("Don’t have Smart Life? Get it"))
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Link(L("Don’t have Smart Life? Get it"), destination: URL(string: "https://apps.apple.com/app/smart-life-smart-living/id1115101477")!)
                            .font(.system(size: 12))
                    }
                }
                requirement("wifi", L("This Mac is on the same Wi-Fi as the air conditioner")) { EmptyView() }
            }
            Spacer(minLength: 0)
            CreatorCard()
        }
    }

    private var userCode: some View {
        VStack(alignment: .leading, spacing: 18) {
            title(L("Get your code from Smart Life"))
            Text(L("On your phone, open Smart Life and follow the pictures:"))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 0) {
                phoneStep(1, .meTab, L("Tap Me"))
                arrow
                phoneStep(2, .gear, L("Tap the gear"))
                arrow
                phoneStep(3, .userCode, L("Account and Security, then User Code"))
            }
            .frame(maxWidth: .infinity)
            MascotTip(text: L("Tip: with an iPhone on the same Apple ID, copy the code there and click Paste here."))
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Type or paste the code here:"))
                    .font(.system(size: 13, weight: .medium))
                HStack {
                    if isStaticRendering {
                        Text(flow.userCode.isEmpty ? L("User code") : flow.userCode)
                            .foregroundStyle(flow.userCode.isEmpty ? .tertiary : .primary)
                            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                            .padding(.horizontal, 8)
                            .background(RoundedRectangle(cornerRadius: 7).strokeBorder(.quaternary))
                    } else {
                        TextField(L("User code"), text: $flow.userCode)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.large)
                            .onSubmit { submitUserCode() }
                    }
                    Button(L("Paste")) {
                        if let text = NSPasteboard.general.string(forType: .string) {
                            flow.userCode = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    .controlSize(.large)
                }
                errorText
            }
        }
    }

    private var scan: some View {
        VStack(alignment: .leading, spacing: 18) {
            title(L("Scan this code with Smart Life"))
            HStack(alignment: .center, spacing: 22) {
                if let qrCode = flow.qrCode, let image = Self.qrImage(qrCode.content) {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 200, height: 200)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white))
                        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
                        .accessibilityLabel(L("QR code"))
                }
                VStack(spacing: 10) {
                    PhoneMockup(screen: .scan)
                    Text(L("On the Me tab, tap the scan icon"))
                        .font(.system(size: 12))
                        .multilineTextAlignment(.center)
                        .frame(width: 150)
                }
            }
            .frame(maxWidth: .infinity)
            if flow.error == .qrExpired {
                HStack {
                    errorText
                    Spacer()
                    Button(L("New QR Code")) { submitUserCode() }
                }
            } else {
                HStack(spacing: 10) {
                    if isStaticRendering {
                        Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text(L("Then tap Confirm on your phone. This screen moves on by itself."))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                MascotTip(text: L("I’ll notice as soon as you confirm on your phone."))
            }
        }
        .onAppear { flow.startWaitingForConfirmation() }
    }

    private var chooseDevice: some View {
        VStack(alignment: .leading, spacing: 16) {
            title(L("Which air conditioner?"))
            if flow.devices.isEmpty {
                errorText
            } else {
                VStack(spacing: 8) {
                    ForEach(flow.devices) { device in
                        deviceRow(device)
                    }
                }
            }
        }
    }

    private var saved: some View {
        let name = flow.selectedDevice?.name ?? ""
        return ZStack(alignment: .top) {
            VStack(spacing: 14) {
                ChillMascot(width: 200, mood: .excited)
                title(L("All set!"))
                Text(L("Chillbar is connected to “\(name)”."))
                    .font(.system(size: 15))
                HStack(spacing: 8) {
                    Image(nsImage: MenuBarIcon.image(.on))
                    Text(L("Click this icon in your menu bar to control it."))
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule().fill(.quaternary.opacity(0.6)))
                Spacer(minLength: 0)
                CreatorCard(isProminent: true)
            }
            .frame(maxWidth: .infinity)
            SnowfallCelebration()
        }
    }

    // MARK: Botões

    private var buttons: some View {
        HStack {
            if flow.step == .userCode || flow.step == .scan || flow.step == .chooseDevice {
                Button(L("Back")) { flow.back() }
                    .buttonStyle(.bordered)
            }
            Spacer()
            switch flow.step {
            case .welcome:
                Button(L("Start")) { flow.continueFromWelcome() }
                    .keyboardShortcut(.defaultAction)
            case .userCode:
                Button(L("Continue")) { submitUserCode() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(flow.userCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || flow.isWorking)
            case .scan:
                EmptyView()
            case .chooseDevice:
                Button(L("Connect")) { flow.saveSelectedDevice() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(flow.selectedDevice == nil)
            case .saved:
                Button(L("Done"), action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
    }

    // MARK: Peças

    private var staticLanguagePicker: some View {
        HStack(spacing: 0) {
            ForEach(AppLanguage.allCases) { option in
                Text(option.shortName)
                    .font(.system(size: 12, weight: option.rawValue == language ? .semibold : .regular))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(option.rawValue == language ? AnyShapeStyle(.background) : AnyShapeStyle(.clear)))
            }
        }
        .padding(2)
        .background(Capsule().fill(.quaternary))
    }

    private func title(_ text: String) -> some View {
        Text(text).font(.system(size: 22, weight: .bold))
    }

    private func requirement(_ symbol: String, _ text: String, @ViewBuilder accessory: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.cool.ink)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.cool.solid.opacity(0.12)))
            VStack(alignment: .leading, spacing: 3) {
                Text(text).font(.system(size: 14))
                accessory()
            }
        }
    }

    private func phoneStep(_ number: Int, _ screen: PhoneMockup.Screen, _ caption: String) -> some View {
        VStack(spacing: 8) {
            PhoneMockup(screen: screen)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(number)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 17, height: 17)
                    .background(Circle().fill(Theme.cool.solid))
                Text(caption)
                    .font(.system(size: 11.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 128)
        }
    }

    private var arrow: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.top, 88)
    }

    private func deviceRow(_ device: SetupDevice) -> some View {
        let isSelected = flow.selectedDevice == device
        return Button {
            flow.selectedDevice = device
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Theme.cool.solid : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name).font(.system(size: 14, weight: .semibold))
                    Text(device.model).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(device.isOnline ? Color.green : Color.secondary).frame(width: 6, height: 6)
                    Text(device.isOnline ? L("Online") : L("Offline"))
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(isSelected ? 0.9 : 0.5)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var errorText: some View {
        if let message = errorMessage {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.system(size: 12))
                .foregroundStyle(Theme.amber)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var errorMessage: String? {
        switch flow.error {
        case .account(let message)?:
            message.isEmpty ? L("Check the user code and try again.") : L("Check the user code and try again. Smart Life said: \(message)")
        case .network?: L("Couldn’t reach Smart Life. Check your internet connection.")
        case .qrExpired?: L("This QR code expired.")
        case .noAirConditioner?: L("No air conditioner found in this Smart Life account. Make sure it’s added in Smart Life, then try again.")
        case .saveFailed?: L("Couldn’t save to the Keychain.")
        case nil: nil
        }
    }

    private func submitUserCode() {
        Task { await flow.submitUserCode() }
    }

    static func qrImage(_ content: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(content.utf8)
        filter.correctionLevel = "Q"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let representation = NSCIImageRep(ciImage: output)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}

/// Bolinhas de progresso: preenchidas até o passo atual.
private struct StepDots: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? AnyShapeStyle(Theme.cool.solid) : AnyShapeStyle(.quaternary))
                    .frame(width: index == current ? 22 : 8, height: 8)
            }
        }
        .animation(.spring(duration: 0.3), value: current)
        .accessibilityHidden(true)
    }
}

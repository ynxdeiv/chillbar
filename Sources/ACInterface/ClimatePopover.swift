import ACApplication
import ACCore
import AppKit
import SwiftUI

/// Conteúdo do popover da barra de menus.
public struct ClimatePopover: View {
    let controller: ClimateController
    let onSetup: (() -> Void)?
    @State private var draftSetpoint: Temperature?
    @AppStorage(AppLanguage.defaultsKey) private var language = AppLanguage.english.rawValue
    @Environment(\.isStaticRendering) private var isStaticRendering

    public init(controller: ClimateController, onSetup: (() -> Void)? = nil) {
        self.controller = controller
        self.onSetup = onSetup
    }

    private var state: ClimateState { controller.state }
    private var capabilities: ClimateCapabilities { controller.capabilities }
    private var isOn: Bool { state.isOn == true }
    private var isReachable: Bool { controller.connection == .connected }
    private var isControllable: Bool { isOn && isReachable }
    private var palette: ModePalette { Theme.palette(for: state.mode, isOn: isOn) }
    private var setpointLocked: Bool { !capabilities.rule(for: state.mode).allowsSetpoint }
    private var fanLocked: Bool { capabilities.fanSpeeds(in: state.mode).isEmpty }
    /// "Travado no modo Auto": explica por que um controle está apagado.
    private var lockedText: String {
        let mode = state.mode?.title ?? ""
        return L("Locked in \(mode) mode")
    }

    public var body: some View {
        VStack(spacing: 18) {
            header
            AirConditionerIllustration(
                setpoint: draftSetpoint ?? state.setpoint,
                mode: state.mode,
                isOn: isOn,
                palette: palette,
                isPending: isPending(.setpoint)
            )
            temperatureControls
            if StatusLine.isNoteworthy(controller.headline(now: .now)) {
                StatusLine(controller: controller)
            }
            VStack(spacing: 10) {
                modes
                fanSpeeds
                functionKeys
            }
            .disabled(!isControllable)
            .opacity(isControllable ? 1 : 0.4)
            footer
        }
        .padding(16)
        .frame(width: 296)
        .animation(.easeInOut(duration: 0.25), value: palette)
        // Trocar o idioma redesenha tudo com os novos textos e formatos.
        .id(language)
        .environment(\.locale, AppLanguage(rawValue: language)?.locale ?? .current)
        .hoverHintBubbles()
    }

    // MARK: Seções

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.deviceName)
                    .font(.system(size: 13, weight: .semibold))
                ConnectionLabel(connection: controller.connection, sourceName: controller.sourceName)
            }
            Spacer()
            GlassCircleButton(
                symbol: "power",
                label: isOn ? L("Turn off") : L("Turn on"),
                size: 32,
                tint: isOn ? palette.solid : nil,
                isPending: isPending(.power)
            ) {
                Task { await controller.togglePower() }
            }
            .disabled(!isReachable)
        }
    }

    private var temperatureControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                GlassCircleButton(symbol: "minus", label: L("Lower temperature"), size: 28, repeats: true) {
                    Task { await controller.stepSetpoint(by: -1) }
                }
                .keyboardShortcut(.downArrow, modifiers: [])
                SetpointSlider(
                    value: state.setpoint,
                    range: capabilities.setpointRange,
                    step: capabilities.setpointStep,
                    accent: palette.solid,
                    draft: $draftSetpoint
                ) { target in
                    send(.setSetpoint(target))
                }
                GlassCircleButton(symbol: "plus", label: L("Raise temperature"), size: 28, repeats: true) {
                    Task { await controller.stepSetpoint(by: 1) }
                }
                .keyboardShortcut(.upArrow, modifiers: [])
            }
            .disabled(!isControllable || setpointLocked)
            .opacity(isControllable && !setpointLocked ? 1 : 0.4)
            .hoverHint(setpointLocked ? lockedText : L("Target temperature"))
            if isControllable && setpointLocked {
                Label(lockedText, systemImage: "lock.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            UsageStats(
                roomTemperature: state.roomTemperature,
                session: isOn ? controller.usageSession : nil,
                averageWatts: capabilities.estimatedAverageWatts
            )
        }
    }

    private var modes: some View {
        Segmented(
            options: capabilities.modes.map { .init(item: $0, title: $0.title, symbol: $0.symbol) },
            selected: state.mode,
            palette: palette,
            accessibilityLabel: { L("\($0) mode") }
        ) { mode in
            send(.setMode(mode))
        }
    }

    @ViewBuilder
    private var fanSpeeds: some View {
        let speeds = capabilities.fanSpeeds.filter { $0 != .turbo && $0 != .quiet }
        if !speeds.isEmpty {
            Segmented(
                options: speeds.map { speed in
                    .init(item: speed, title: speed.title, level: Self.level(of: speed))
                },
                selected: state.fanSpeed,
                palette: palette,
                accessibilityLabel: { L("Fan speed \($0)") }
            ) { speed in
                send(.setFanSpeed(speed))
            }
            .disabled(fanLocked)
            .opacity(fanLocked ? 0.4 : 1)
            .hoverHint(fanLocked ? lockedText : L("Fan speed"))
        }
    }

    private var functionKeys: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.title) { key in
                GlassCircleButton(
                    symbol: key.symbol,
                    label: key.title,
                    size: 29,
                    tint: key.isActive ? palette.solid : nil,
                    isPending: isPending(key.field)
                ) {
                    send(key.command)
                }
                .accessibilityValue(key.isActive ? L("on") : L("off"))
                .disabled(!key.isAvailable)
                .opacity(key.isAvailable ? 1 : 0.35)
                // A dica fica fora do botão desativado para continuar aparecendo.
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .hoverHint(key.isAvailable ? key.title : "\(key.title): \(lockedText)")
            }
        }
    }

    private var footer: some View {
        HStack {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(updatedText(now: context.date))
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
            Spacer()
            if isStaticRendering {
                Text(verbatim: "@\(ProjectInfo.author)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
            } else {
                footerLinkAndMenu
            }
        }
    }

    private var footerLinkAndMenu: some View {
        HStack {
            Link(destination: ProjectInfo.authorURL) {
                Text(verbatim: "@\(ProjectInfo.author)")
                    .font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .hoverHint(L("Open GitHub profile"))
            Menu {
                Button(L("Refresh now")) { Task { await controller.refresh() } }
                if let onSetup {
                    Button(L("Set Up Air Conditioner…"), action: onSetup)
                }
                Picker(L("Language"), selection: $language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
                Divider()
                Button(L("Quit")) { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.secondary)
            .accessibilityLabel(L("More options"))
        }
    }

    // MARK: Teclas do controle

    private struct KeySpec {
        let title: String
        let symbol: String
        let isActive: Bool
        let isAvailable: Bool
        let field: ClimateField
        let command: ClimateCommand
    }

    private var keys: [KeySpec] {
        var keys: [KeySpec] = []
        if capabilities.supportsVerticalSwing {
            let active = state.verticalSwing == true
            keys.append(KeySpec(title: L("Swing"), symbol: "arrow.up.and.down", isActive: active, isAvailable: true,
                                field: .verticalSwing, command: .setVerticalSwing(!active)))
        }
        let speedsInMode = capabilities.fanSpeeds(in: state.mode)
        for (speed, symbol) in [(FanSpeed.turbo, "hare"), (.quiet, "speaker.slash")]
        where capabilities.fanSpeeds.contains(speed) {
            let active = state.fanSpeed == speed
            keys.append(KeySpec(title: speed.title, symbol: symbol, isActive: active, isAvailable: speedsInMode.contains(speed),
                                field: .fanSpeed, command: .setFanSpeed(active ? .auto : speed)))
        }
        let features: [(ClimateFeature, String, String)] = [
            (.sleep, L("Sleep"), "moon.zzz"),
            (.ionizer, L("IonAir"), "sparkles"),
            (.display, L("Display"), "lightbulb"),
            (.clean, L("Clean"), "bubbles.and.sparkles"),
            (.antiMould, L("Anti-mold"), "allergens"),
            (.eco, L("Eco"), "leaf"),
        ]
        let featuresInMode = capabilities.features(in: state.mode)
        for (feature, title, symbol) in features where capabilities.features.contains(feature) {
            let active = state.features[feature] == true
            keys.append(KeySpec(title: title, symbol: symbol, isActive: active, isAvailable: featuresInMode.contains(feature),
                                field: .feature(feature), command: .setFeature(feature, !active)))
        }
        return keys
    }

    // MARK: Auxiliares

    private static func level(of speed: FanSpeed) -> Int? {
        switch speed {
        case .low: 1
        case .medium: 2
        case .high: 3
        default: nil
        }
    }

    private func send(_ command: ClimateCommand) {
        Task { await controller.send(command) }
    }

    private func isPending(_ field: ClimateField) -> Bool {
        if case .pending = controller.status(of: field) { true } else { false }
    }

    private func updatedText(now: Date) -> String {
        guard let lastUpdate = controller.lastUpdate else { return L("No reading from the device yet") }
        if now.timeIntervalSince(lastUpdate) < 60 { return L("Updated just now") }
        let relative = lastUpdate.formatted(.relative(presentation: .named).locale(appLocale))
        return L("Updated \(relative)")
    }
}

private struct ConnectionLabel: View {
    let connection: ClimateController.Connection
    let sourceName: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch connection {
        case .connected: .green
        case .connecting: Theme.amber
        case .disconnected: .red
        }
    }

    private var text: String {
        switch connection {
        case .connected: sourceName.isEmpty ? L("Connected") : sourceName
        case .connecting: L("Connecting…")
        case .disconnected: L("Offline")
        }
    }
}

/// Uma linha que diz o que está acontecendo e, em caso de problema, o que fazer.
private struct StatusLine: View {
    let controller: ClimateController

    /// Sincronizado ou desligado não precisam de mensagem: a ilustração já diz.
    static func isNoteworthy(_ headline: StatusHeadline) -> Bool {
        switch headline {
        case .synced, .off: false
        default: true
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let headline = controller.headline(now: context.date)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: symbol(headline))
                VStack(alignment: .leading, spacing: 4) {
                    Text(text(headline))
                        .fixedSize(horizontal: false, vertical: true)
                    if isProblem(headline) {
                        Button(headline == .unsupported || headline == .unavailableInMode ? L("OK") : L("Try again")) {
                            controller.dismissAlert()
                            Task { await controller.refresh() }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                    }
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 11.5))
            .foregroundStyle(isProblem(headline) ? Theme.amber : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassSurface(
                in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                tint: isProblem(headline) ? Theme.amber.opacity(0.18) : nil
            )
        }
        .accessibilityElement(children: .combine)
    }

    private func staleText(since: Date) -> String {
        let time = since.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(appLocale))
        return L("No updates from the device since \(time).")
    }

    private func isProblem(_ headline: StatusHeadline) -> Bool {
        switch headline {
        case .notConfirmed, .sendFailed, .unsupported, .unavailableInMode, .disconnected, .stale: true
        default: false
        }
    }

    private func symbol(_ headline: StatusHeadline) -> String {
        switch headline {
        case .connecting, .sending: "arrow.triangle.2.circlepath"
        case .synced: "checkmark.circle"
        case .off: "power"
        case .stale: "clock.badge.exclamationmark"
        case .disconnected: "wifi.exclamationmark"
        case .notConfirmed, .sendFailed, .unsupported: "exclamationmark.triangle"
        case .unavailableInMode: "lock"
        }
    }

    private func text(_ headline: StatusHeadline) -> String {
        switch headline {
        case .connecting: L("Connecting to the device…")
        case .disconnected: L("Can’t reach the device. Check that it’s plugged in and on Wi-Fi.")
        case .sending: L("Sending to the device…")
        case .notConfirmed: L("The device didn’t confirm the last command.")
        case .sendFailed: L("Couldn’t send the command.")
        case .unsupported: L("This device doesn’t support that.")
        case .unavailableInMode: L("Not available in this mode.")
        case .stale(let since):
            staleText(since: since)
        case .off: L("Off")
        case .synced: L("In sync with the device")
        }
    }
}

/// Rótulo da barra de menus: o ar desenhado e, ligado, a temperatura desejada.
public struct MenuBarLabel: View {
    let controller: ClimateController
    @AppStorage(AppLanguage.defaultsKey) private var language = AppLanguage.english.rawValue

    public init(controller: ClimateController) {
        self.controller = controller
    }

    public var body: some View {
        let state = controller.state
        let style: MenuBarIcon.Style = switch controller.connection {
        case .disconnected: .disconnected
        default: state.isOn == true ? .on : .off
        }
        HStack(spacing: 3) {
            Image(nsImage: MenuBarIcon.image(style))
            if state.isOn == true, let setpoint = state.setpoint, controller.connection == .connected {
                Text("\(setpoint.formatted)°")
                    .monospacedDigit()
            }
        }
        .id(language)
    }
}

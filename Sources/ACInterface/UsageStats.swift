import ACCore
import SwiftUI

/// Linha discreta com temperatura ambiente, tempo ligado e consumo estimado.
struct UsageStats: View {
    let roomTemperature: Temperature?
    let session: UsageSession?
    let averageWatts: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 14) {
                if let roomTemperature {
                    stat("thermometer.medium", "\(roomTemperature.formatted)°")
                        .hoverHint(L("Room temperature"))
                        .accessibilityLabel(L("Room temperature"))
                        .accessibilityValue("\(roomTemperature.formatted) °C")
                }
                if let session {
                    let seconds = session.duration(now: context.date)
                    let duration = Self.durationText(seconds)
                    // Início desconhecido: o tempo real é "pelo menos" o observado.
                    let shown = session.startIsExact || seconds < 60 ? duration : "≥ \(duration)"
                    stat("clock", shown)
                        .hoverHint(sinceText(session))
                        .accessibilityLabel(L("Time on"))
                        .accessibilityValue(duration)
                    if let averageWatts {
                        let energy = session.estimatedEnergy(now: context.date, averageWatts: averageWatts)
                        let watts = averageWatts.formatted(.number.precision(.fractionLength(0)).locale(appLocale))
                        stat("bolt", "≈ \(energy.formatted(.number.precision(.fractionLength(2)).locale(appLocale))) kWh")
                            .hoverHint(L("Estimate: \(watts) W average while on"))
                            .accessibilityLabel(L("Estimated energy"))
                    }
                }
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
        }
    }

    private func stat(_ symbol: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).imageScale(.small)
            Text(value).monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
    }

    private func sinceText(_ session: UsageSession) -> String {
        let time = session.start.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(appLocale))
        return session.startIsExact ? L("On since \(time)") : L("On since at least \(time)")
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        guard seconds >= 60 else { return L("< 1 min") }
        return Duration.seconds(seconds).formatted(
            .units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2).locale(appLocale)
        )
    }
}

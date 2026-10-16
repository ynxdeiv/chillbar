import ACCore
import SwiftUI

/// A evaporadora desenhada, branca e sólida como a de verdade: o visor mostra o
/// modo e a temperatura desejada, e o vento sai na cor do modo. É o único elemento animado.
struct AirConditionerIllustration: View {
    let setpoint: Temperature?
    let mode: HVACMode?
    let isOn: Bool
    let palette: ModePalette
    let isPending: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            unitBody
            Airflow(color: palette.ink, isActive: isOn)
                .frame(height: 30)
                .padding(.horizontal, 48)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var unitBody: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(
                    // No modo escuro o aparelho fica um pouco mais apagado para não ofuscar.
                    colors: colorScheme == .dark
                        ? [Color(white: 0.90), Color(white: 0.78)]
                        : [Color(white: 1.0), Color(white: 0.92)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.22), radius: 10, y: 5)

            display
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 14)
                .padding(.bottom, 10)

            louver
        }
        .frame(height: 68)
    }

    private var display: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.displayGlass.opacity(0.92))
            if isOn, let setpoint {
                HStack(alignment: .center, spacing: 6) {
                    if let mode {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 10, weight: .semibold))
                            .opacity(0.8)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(setpoint.formatted)
                            .font(.system(size: 26, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: setpoint.celsius))
                        Text("°")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                    }
                }
                .foregroundStyle(palette.glow)
                .shadow(color: palette.glow.opacity(0.6), radius: 5)
                .opacity(isPending ? 0.6 : 1)
            }
        }
        .frame(width: 92, height: 40)
    }

    /// A aleta abre quando o aparelho liga.
    private var louver: some View {
        Capsule()
            .fill(Color.black.opacity(isOn ? 0.5 : 0.15))
            .frame(height: isOn ? 4 : 2)
            .padding(.horizontal, 30)
            .padding(.bottom, 5)
            .animation(.spring(duration: 0.5), value: isOn)
    }

    private var accessibilityText: String {
        guard isOn, let setpoint else { return L("Air conditioner off") }
        let modeTitle = mode?.title ?? ""
        let degrees = setpoint.formatted
        return L("Air conditioner on, \(modeTitle), \(degrees) degrees")
    }
}

/// Rajadas de vento saindo da aleta. Param quando "Reduzir movimento" está ativo.
struct Airflow: View {
    let color: Color
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: !isActive || reduceMotion)) { context in
            Canvas { canvas, size in
                guard isActive else { return }
                let phase: CGFloat = reduceMotion ? 0 : CGFloat(context.date.timeIntervalSinceReferenceDate * 26)
                let count = 5
                for index in 0..<count {
                    // Rajadas abrem em leque, como o ar do aparelho.
                    let x = size.width * (CGFloat(index) + 0.5) / CGFloat(count)
                    let spread = (CGFloat(index) - CGFloat(count - 1) / 2) * 9
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addCurve(
                        to: CGPoint(x: x + spread, y: size.height),
                        control1: CGPoint(x: x + 10, y: size.height * 0.3),
                        control2: CGPoint(x: x + spread - 10, y: size.height * 0.65)
                    )
                    canvas.stroke(
                        path,
                        with: .color(color),
                        style: StrokeStyle(
                            lineWidth: 1.5,
                            lineCap: .round,
                            dash: [16, 11],
                            dashPhase: -phase - CGFloat(index) * 7
                        )
                    )
                }
            }
        }
        .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
        .opacity(isActive ? 0.85 : 0)
        .animation(.easeInOut(duration: 0.6), value: isActive)
    }
}

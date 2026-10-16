import ACCore
import SwiftUI

/// Botão redondo: liga/desliga, −/+ e teclas de função. Neutro é de vidro;
/// com `tint` (ativo), fica preenchido com a cor do modo e o ícone branco.
struct GlassCircleButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 30
    var tint: Color?
    var isPending = false
    var repeats = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
                .frame(width: size, height: size)
                .background {
                    // Ativo: cor sólida e nítida. Neutro: vidro que reage ao toque.
                    if let tint {
                        Circle().fill(tint)
                    } else {
                        Color.clear.glassSurface(in: Circle(), interactive: true)
                    }
                }
                .opacity(isPending ? 0.55 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(repeats ? .enabled : .disabled)
        .hoverHint(label)
        .accessibilityLabel(label)
    }
}

/// Slider desenhado em SwiftUI puro: o valor só é enviado ao soltar, para não
/// disparar um comando a cada grau arrastado.
struct SetpointSlider: View {
    /// `nil` enquanto o aparelho não informou a temperatura: mostra só o trilho.
    let value: Temperature?
    let range: ClosedRange<Temperature>
    let step: Temperature
    let accent: Color
    @Binding var draft: Temperature?
    let commit: (Temperature) -> Void

    private var shown: Temperature? { draft ?? value }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 4)
                if let shown {
                    let fraction = progress(of: shown)
                    Capsule().fill(accent).frame(width: max(4, width * fraction), height: 4)
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                        .frame(width: 16, height: 16)
                        .offset(x: (width - 16) * fraction)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in draft = temperature(at: gesture.location.x, width: width) }
                    .onEnded { gesture in
                        let target = temperature(at: gesture.location.x, width: width)
                        draft = nil
                        if target != value { commit(target) }
                    },
                isEnabled: value != nil
            )
        }
        .frame(height: 20)
        .hoverHint(L("Target temperature"))
        .accessibilityElement()
        .accessibilityLabel(L("Target temperature"))
        .accessibilityValue(shown.map { L("\($0.formatted) degrees") } ?? L("unknown"))
        .accessibilityAdjustableAction { direction in
            guard let value else { return }
            let delta = direction == .increment ? step.tenthsOfCelsius : -step.tenthsOfCelsius
            let target = Temperature(tenthsOfCelsius: value.tenthsOfCelsius + delta)
            if range.contains(target) { commit(target) }
        }
    }

    private func progress(of temperature: Temperature) -> CGFloat {
        let span = CGFloat(range.upperBound.tenthsOfCelsius - range.lowerBound.tenthsOfCelsius)
        guard span > 0 else { return 0 }
        return CGFloat(temperature.tenthsOfCelsius - range.lowerBound.tenthsOfCelsius) / span
    }

    private func temperature(at x: CGFloat, width: CGFloat) -> Temperature {
        let fraction = min(max(x / max(width, 1), 0), 1)
        let span = range.upperBound.tenthsOfCelsius - range.lowerBound.tenthsOfCelsius
        let raw = Double(span) * fraction
        let steps = (raw / Double(step.tenthsOfCelsius)).rounded()
        return Temperature(tenthsOfCelsius: range.lowerBound.tenthsOfCelsius + Int(steps) * step.tenthsOfCelsius)
    }
}

/// Seletor de vidro: a pílula colorida desliza até a opção escolhida.
struct Segmented<Item: Hashable>: View {
    struct Option {
        let item: Item
        let title: String
        var symbol: String?
        var level: Int?
    }

    let options: [Option]
    let selected: Item?
    let palette: ModePalette
    /// Formato do rótulo de acessibilidade, ex.: "Modo %@".
    let accessibilityLabel: (String) -> String
    let select: (Item) -> Void
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.item) { option in
                let isSelected = option.item == selected
                Button { select(option.item) } label: {
                    label(for: option)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(Color.primary.opacity(0.65)))
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(palette.solid)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .hoverHint(accessibilityLabel(option.title))
                .accessibilityLabel(accessibilityLabel(option.title))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .glassSurface(in: Capsule())
        .animation(.spring(duration: 0.35, bounce: 0.25), value: selected)
    }

    @ViewBuilder
    private func label(for option: Option) -> some View {
        if let symbol = option.symbol {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
        } else if let level = option.level {
            LevelBars(level: level)
        } else {
            Text(option.title).font(.system(size: 11, weight: .semibold))
        }
    }
}

/// Barrinhas de intensidade da ventilação (1 a 3).
struct LevelBars: View {
    let level: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...3, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 1)
                    .frame(width: 3, height: CGFloat(3 + bar * 3))
                    .opacity(bar <= level ? 1 : 0.35)
            }
        }
        .accessibilityHidden(true)
    }
}

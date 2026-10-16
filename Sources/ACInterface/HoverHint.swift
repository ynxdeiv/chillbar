import AppKit
import SwiftUI

/// Os balões de `.help` do macOS aparecem de forma inconsistente em pop-ups da barra
/// de menus (o app fica em segundo plano). Por isso desenhamos o nosso: o controle
/// sob o mouse publica sua posição e o pop-up mostra um balão acima dele.
private struct HoverHintValue {
    let text: String
    let anchor: Anchor<CGRect>
}

private struct HoverHintKey: PreferenceKey {
    static var defaultValue: HoverHintValue? { nil }

    static func reduce(value: inout HoverHintValue?, nextValue: () -> HoverHintValue?) {
        value = nextValue() ?? value
    }
}

private struct HoverHintModifier: ViewModifier {
    let text: String
    @State private var isShown = false
    @State private var showTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { isInside in
                showTask?.cancel()
                if isInside {
                    // Pequena espera para o balão não piscar ao atravessar os botões.
                    showTask = Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        if !Task.isCancelled { isShown = true }
                    }
                } else {
                    isShown = false
                }
            }
            .onDisappear { showTask?.cancel() }
            .anchorPreference(key: HoverHintKey.self, value: .bounds) { anchor in
                isShown ? HoverHintValue(text: text, anchor: anchor) : nil
            }
    }
}

extension View {
    /// Mostra `text` num balão enquanto o mouse está sobre a view.
    func hoverHint(_ text: String) -> some View {
        modifier(HoverHintModifier(text: text))
    }

    /// Camada que desenha o balão do controle sob o mouse. Aplicar na raiz do pop-up.
    func hoverHintBubbles() -> some View {
        overlayPreferenceValue(HoverHintKey.self) { value in
            GeometryReader { proxy in
                if let value {
                    HintBubble(text: value.text, target: proxy[value.anchor], container: proxy.size)
                        .transition(.opacity)
                }
            }
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.12), value: value?.text)
        }
    }
}

private struct HintBubble: View {
    let text: String
    let target: CGRect
    let container: CGSize

    private static let font = NSFont.systemFont(ofSize: 11, weight: .medium)
    private let height: CGFloat = 24
    private let gap: CGFloat = 6
    private let margin: CGFloat = 8
    private let horizontalPadding: CGFloat = 9

    var body: some View {
        // No topo não há espaço acima: o balão vai para baixo do controle.
        let showBelow = target.minY < height + gap + margin
        let y = showBelow ? target.maxY + gap : target.minY - gap - height
        // Centralizado no controle, mas sempre inteiro dentro do pop-up.
        let x = min(max(target.midX - width / 2, margin), container.width - margin - width)

        label
            .frame(width: width, height: height)
            .offset(x: max(margin, x), y: y)
            .frame(width: container.width, height: container.height, alignment: .topLeading)
    }

    /// Largura medida do texto, para saber se o balão cabe ao lado do controle.
    private var width: CGFloat {
        let textWidth = (text as NSString).size(withAttributes: [.font: Self.font]).width
        return min(ceil(textWidth) + horizontalPadding * 2, container.width - margin * 2)
    }

    private var label: some View {
        Text(text)
            .font(Font(Self.font))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
    }
}

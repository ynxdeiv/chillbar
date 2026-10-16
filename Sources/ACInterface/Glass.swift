import Foundation
import SwiftUI

extension View {
    /// Liquid Glass no macOS 26+; antes disso (ou em imagens estáticas), um preenchimento
    /// translúcido equivalente.
    func glassSurface(in shape: some Shape, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: AnyShape(shape), tint: tint, interactive: interactive))
    }
}

private struct GlassSurface: ViewModifier {
    let shape: AnyShape
    let tint: Color?
    let interactive: Bool
    @Environment(\.isStaticRendering) private var isStaticRendering

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !isStaticRendering {
            content.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            content.background(shape.fill(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.quaternary.opacity(0.7))))
        }
    }
}

private struct StaticRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// `true` ao gerar imagens (README, vídeo): troca vidro e controles nativos, que a
    /// renderização fora da tela não desenha, por equivalentes desenhados.
    public var isStaticRendering: Bool {
        get { self[StaticRenderingKey.self] }
        set { self[StaticRenderingKey.self] = newValue }
    }
}

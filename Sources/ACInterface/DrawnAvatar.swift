import SwiftUI

/// Avatar desenhado a partir de uma "semente" (nome), no espírito do DiceBear: a mesma
/// semente sempre gera o mesmo rosto. Feito em formas SwiftUI para poder piscar.
struct DrawnAvatar: View {
    let seed: String
    var size: CGFloat = 48
    var isAnimated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var traits: AvatarTraits { AvatarTraits(seed: seed) }

    var body: some View {
        TimelineView(.animation(paused: !isAnimated || reduceMotion)) { context in
            let blink = isAnimated && !reduceMotion ? Blink.amount(at: context.date, offset: traits.blinkOffset) : 0
            face(blink: blink)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func face(blink: CGFloat) -> some View {
        let t = traits
        let s = size
        return ZStack {
            Circle().fill(t.background)
            // Ombros
            Capsule()
                .fill(t.shirt)
                .frame(width: s * 0.78, height: s * 0.5)
                .offset(y: s * 0.42)
            // Pescoço e cabeça
            RoundedRectangle(cornerRadius: s * 0.04)
                .fill(t.skin.opacity(0.92))
                .frame(width: s * 0.16, height: s * 0.16)
                .offset(y: s * 0.2)
            hair(back: true)
            Ellipse()
                .fill(t.skin)
                .frame(width: s * 0.5, height: s * 0.56)
                .offset(y: -s * 0.02)
            // Bochechas
            HStack(spacing: s * 0.2) {
                Circle().fill(Color.pink.opacity(0.28)).frame(width: s * 0.09)
                Circle().fill(Color.pink.opacity(0.28)).frame(width: s * 0.09)
            }
            .offset(y: s * 0.07)
            // Olhos (fecham ao piscar)
            HStack(spacing: s * 0.14) {
                eye
                eye
            }
            .scaleEffect(x: 1, y: max(0.12, 1 - blink), anchor: .center)
            .offset(y: -s * 0.02)
            if t.hasGlasses {
                HStack(spacing: s * 0.04) {
                    Circle().strokeBorder(Color.black.opacity(0.75), lineWidth: s * 0.02).frame(width: s * 0.16)
                    Circle().strokeBorder(Color.black.opacity(0.75), lineWidth: s * 0.02).frame(width: s * 0.16)
                }
                .offset(y: -s * 0.02)
            }
            Smile(width: t.grin ? 0.16 : 0.12)
                .stroke(Color.black.opacity(0.7), style: StrokeStyle(lineWidth: s * 0.025, lineCap: .round))
                .frame(width: s, height: s)
                .offset(y: s * 0.11)
            hair(back: false)
        }
        .frame(width: s, height: s)
        .clipShape(Circle())
    }

    private var eye: some View {
        Capsule()
            .fill(Color.black.opacity(0.82))
            .frame(width: size * 0.05, height: size * 0.075)
    }

    @ViewBuilder
    private func hair(back: Bool) -> some View {
        let s = size
        let color = traits.hair
        switch traits.hairStyle {
        case .short:
            if !back {
                HairCap(depth: 0.42)
                    .fill(color)
                    .frame(width: s * 0.56, height: s * 0.34)
                    .offset(y: -s * 0.2)
            }
        case .long:
            if back {
                RoundedRectangle(cornerRadius: s * 0.2)
                    .fill(color)
                    .frame(width: s * 0.66, height: s * 0.72)
                    .offset(y: s * 0.04)
            } else {
                HairCap(depth: 0.5)
                    .fill(color)
                    .frame(width: s * 0.6, height: s * 0.36)
                    .offset(y: -s * 0.19)
            }
        case .curly:
            if !back {
                ZStack {
                    ForEach(0..<7, id: \.self) { index in
                        let angle = Double(index) / 6 * .pi
                        Circle()
                            .fill(color)
                            .frame(width: s * 0.2)
                            .offset(x: -cos(angle) * s * 0.23, y: -sin(angle) * s * 0.17 - s * 0.12)
                    }
                }
            }
        case .bun:
            if !back {
                ZStack {
                    Circle().fill(color).frame(width: s * 0.2).offset(y: -s * 0.36)
                    HairCap(depth: 0.38)
                        .fill(color)
                        .frame(width: s * 0.54, height: s * 0.3)
                        .offset(y: -s * 0.21)
                }
            }
        case .cap:
            if !back {
                ZStack {
                    Capsule().fill(color).frame(width: s * 0.5, height: s * 0.06).offset(x: s * 0.1, y: -s * 0.18)
                    HairCap(depth: 0.5)
                        .fill(color)
                        .frame(width: s * 0.54, height: s * 0.3)
                        .offset(y: -s * 0.22)
                }
            }
        }
    }
}

/// Traços sorteados de forma determinística a partir da semente.
struct AvatarTraits {
    enum HairStyle: CaseIterable { case short, long, curly, bun, cap }

    let background: Color
    let skin: Color
    let hair: Color
    let shirt: Color
    let hairStyle: HairStyle
    let hasGlasses: Bool
    let grin: Bool
    let blinkOffset: Double

    init(seed: String) {
        // FNV-1a: estável entre execuções (o `hashValue` do Swift muda a cada execução).
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        func pick<T>(_ options: [T], _ shift: UInt64) -> T {
            options[Int((hash >> shift) % UInt64(options.count))]
        }
        background = pick([Color(hex: 0xB6E3FF), Color(hex: 0xC9F2E5), Color(hex: 0xFFE3B3), Color(hex: 0xE6D9FF), Color(hex: 0xFFD1DC)], 0)
        skin = pick([Color(hex: 0xF9D7B8), Color(hex: 0xEDB98A), Color(hex: 0xD08B5B), Color(hex: 0xAE5D29), Color(hex: 0x6E3B1F)], 8)
        hair = pick([Color(hex: 0x2C1B10), Color(hex: 0x4A2C17), Color(hex: 0x8C5A2B), Color(hex: 0xE2B05A), Color(hex: 0x1F2A44)], 16)
        shirt = pick([Color(hex: 0x1570D6), Color(hex: 0x0B877A), Color(hex: 0x6D4FE0), Color(hex: 0xC2521A), Color(hex: 0x3A3F4B)], 24)
        hairStyle = pick(HairStyle.allCases, 32)
        hasGlasses = (hash >> 40) % 3 == 0
        grin = (hash >> 44) % 2 == 0
        blinkOffset = Double((hash >> 48) % 1000) / 1000 * 3
    }
}

/// Piscada curta a cada ~4 s.
enum Blink {
    static func amount(at date: Date, offset: Double) -> CGFloat {
        let period = 4.2
        let phase = (date.timeIntervalSinceReferenceDate + offset).truncatingRemainder(dividingBy: period)
        guard phase < 0.16 else { return 0 }
        return CGFloat(sin(phase / 0.16 * .pi))
    }
}

/// Topo de cabeça (cabelo): meia elipse com franja levemente curva.
private struct HairCap: Shape {
    let depth: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control1: CGPoint(x: rect.minX, y: rect.minY - rect.height * depth),
            control2: CGPoint(x: rect.maxX, y: rect.minY - rect.height * depth)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.35)
        )
        return path
    }
}

/// Sorriso: arco simples centrado, com largura relativa ao quadro.
struct Smile: Shape {
    let width: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let half = rect.width * width / 2
        path.move(to: CGPoint(x: rect.midX - half, y: rect.midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX + half, y: rect.midY),
            control: CGPoint(x: rect.midX, y: rect.midY + half * 0.9)
        )
        return path
    }
}

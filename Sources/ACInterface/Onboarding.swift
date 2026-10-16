import SwiftUI

/// "Chill": o ar-condicionado com carinha. Pisca, balança de leve e solta vento.
struct ChillMascot: View {
    enum Mood { case happy, excited }

    var width: CGFloat = 220
    var mood: Mood = .happy
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let bob = reduceMotion ? 0 : sin(time * 1.8) * width * 0.012
            let blink = reduceMotion ? 0 : Blink.amount(at: context.date, offset: 0.7)
            VStack(spacing: 0) {
                unit(blink: blink)
                Airflow(color: Theme.cool.ink, isActive: true)
                    .frame(height: width * 0.17)
                    .padding(.horizontal, width * 0.2)
            }
            .offset(y: bob)
        }
        .frame(width: width)
        .accessibilityElement()
        .accessibilityLabel(L("Chill, the Chillbar mascot"))
    }

    private func unit(blink: CGFloat) -> some View {
        let w = width
        let h = w * 0.34
        return ZStack {
            RoundedRectangle(cornerRadius: h * 0.32, style: .continuous)
                .fill(LinearGradient(colors: [.white, Color(white: 0.9)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: h * 0.32, style: .continuous).strokeBorder(Color.black.opacity(0.08)))
                .shadow(color: .black.opacity(0.2), radius: w * 0.04, y: w * 0.02)

            // Rosto
            ZStack {
                HStack(spacing: w * 0.12) {
                    eye(blink: blink)
                    eye(blink: blink)
                }
                .offset(y: -h * 0.1)
                HStack(spacing: w * 0.2) {
                    Circle().fill(Color.pink.opacity(0.3)).frame(width: w * 0.06)
                    Circle().fill(Color.pink.opacity(0.3)).frame(width: w * 0.06)
                }
                .offset(y: h * 0.1)
                mouth
                    .offset(y: h * 0.12)
            }
            .offset(x: -w * 0.1)

            // Visor com floquinho
            RoundedRectangle(cornerRadius: h * 0.12, style: .continuous)
                .fill(Theme.displayGlass)
                .frame(width: w * 0.17, height: h * 0.34)
                .overlay(
                    Image(systemName: "snowflake")
                        .font(.system(size: h * 0.18, weight: .semibold))
                        .foregroundStyle(Theme.cool.glow)
                        .shadow(color: Theme.cool.glow, radius: 4)
                )
                .offset(x: w * 0.32, y: -h * 0.12)

            Capsule()
                .fill(Color.black.opacity(0.45))
                .frame(width: w * 0.7, height: h * 0.07)
                .offset(y: h * 0.38)
        }
        .frame(width: w, height: h)
    }

    private func eye(blink: CGFloat) -> some View {
        Capsule()
            .fill(Color.black.opacity(0.82))
            .frame(width: width * 0.035, height: width * 0.06)
            .scaleEffect(x: 1, y: max(0.12, 1 - blink))
    }

    @ViewBuilder
    private var mouth: some View {
        switch mood {
        case .happy:
            Smile(width: 0.5)
                .stroke(Color.black.opacity(0.75), style: StrokeStyle(lineWidth: width * 0.012, lineCap: .round))
                .frame(width: width * 0.16, height: width * 0.08)
        case .excited:
            Capsule()
                .fill(Color.black.opacity(0.78))
                .frame(width: width * 0.07, height: width * 0.045)
                .overlay(alignment: .bottom) {
                    Capsule().fill(Color.pink.opacity(0.85)).frame(width: width * 0.04, height: width * 0.018).padding(.bottom, 1)
                }
        }
    }
}

/// O Chill pequenininho com um balão de fala: dicas ao longo dos passos.
struct MascotTip: View {
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ChillMascot(width: 58)
                .frame(height: 34, alignment: .top)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.quaternary.opacity(0.6))
                )
        }
    }
}

/// Créditos do criador: avatar desenhado e links para GitHub, LinkedIn e X.
struct CreatorCard: View {
    var isProminent = false

    var body: some View {
        HStack(spacing: 12) {
            DrawnAvatar(seed: ProjectInfo.author, size: isProminent ? 46 : 34)
            VStack(alignment: .leading, spacing: isProminent ? 8 : 4) {
                Text(L("Made by \(ProjectInfo.authorName)"))
                    .font(.system(size: isProminent ? 14 : 12, weight: .semibold))
                HStack(spacing: 6) {
                    ForEach(ProjectInfo.socialLinks) { link in
                        SocialButton(link: link, showsName: isProminent)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(isProminent ? 14 : 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quaternary.opacity(0.5)))
    }
}

/// Botão de rede social: só o símbolo (compacto) ou símbolo + nome.
private struct SocialButton: View {
    let link: SocialLink
    let showsName: Bool
    @Environment(\.isStaticRendering) private var isStaticRendering

    var body: some View {
        if isStaticRendering {
            label
        } else {
            Link(destination: link.url) { label }
                .buttonStyle(.plain)
                .hoverHint(link.address)
                .accessibilityLabel(L("Open \(link.name)"))
        }
    }

    private var label: some View {
            HStack(spacing: 5) {
                glyph
                    .frame(width: 16, height: 16)
                if showsName {
                    Text(verbatim: link.name)
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, showsName ? 10 : 6)
            .padding(.vertical, 5)
            .background(Capsule().fill(.quaternary.opacity(0.9)))
            .contentShape(Capsule())
    }

    @ViewBuilder
    private var glyph: some View {
        switch link.glyph {
        case .symbol(let name):
            Image(systemName: name).font(.system(size: 10, weight: .bold))
        case .text(let text):
            Text(verbatim: text).font(.system(size: 12, weight: .heavy, design: .rounded))
        }
    }
}

/// Flocos de neve caindo por alguns segundos para comemorar. Some com "Reduzir movimento".
struct SnowfallCelebration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation) { context in
                Canvas { canvas, size in
                    let elapsed = context.date.timeIntervalSince(start)
                    guard elapsed < 4 else { return }
                    let fade = elapsed > 3 ? 4 - elapsed : 1
                    for index in 0..<28 {
                        let seed = Double(index) * 37.7
                        let x = (seed.truncatingRemainder(dividingBy: 97) / 97) * size.width
                        let speed = 70 + (seed.truncatingRemainder(dividingBy: 53))
                        let delay = (seed.truncatingRemainder(dividingBy: 11)) / 11 * 0.8
                        let y = (elapsed - delay) * speed - 20
                        guard y > -20 else { continue }
                        let sway = sin(elapsed * 2 + seed) * 10
                        let flake = canvas.resolveSymbol(id: index % 2)!
                        canvas.opacity = fade * 0.9
                        canvas.draw(flake, at: CGPoint(x: x + sway, y: y))
                    }
                } symbols: {
                    Image(systemName: "snowflake").foregroundStyle(Theme.cool.solid).tag(0)
                    Image(systemName: "snowflake").font(.system(size: 9)).foregroundStyle(Theme.cool.glow).tag(1)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Primeiro nome do usuário do Mac, para o "Oi, …!".
var macUserFirstName: String {
    NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
}

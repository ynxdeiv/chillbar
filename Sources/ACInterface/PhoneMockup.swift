import SwiftUI

/// Celular desenhado mostrando onde tocar no app Smart Life, passo a passo.
struct PhoneMockup: View {
    enum Screen {
        /// Aba "Eu" na barra inferior.
        case meTab
        /// Engrenagem no canto superior direito da aba "Eu".
        case gear
        /// Conta e Segurança → Código de usuário.
        case userCode
        /// Ícone de escanear no canto superior direito da aba "Eu".
        case scan
    }

    let screen: Screen
    private let accent = Theme.cool.solid

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(white: 0.13))
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color(white: 0.97))
                .padding(5)
            content
                .padding(5)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .frame(width: 104, height: 196)
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        .environment(\.colorScheme, .light)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .meTab:
            VStack(spacing: 0) {
                placeholderRows(count: 5).padding(10)
                Spacer()
                tabBar
            }
        case .gear, .scan:
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    Image(systemName: "viewfinder")
                        .font(.system(size: 11))
                        .modifier(TapTarget(isActive: screen == .scan, accent: accent))
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                        .modifier(TapTarget(isActive: screen == .gear, accent: accent))
                }
                .padding(.horizontal, 8)
                .padding(.top, 12)
                HStack(spacing: 6) {
                    Circle().fill(Color(white: 0.8)).frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Capsule().fill(Color(white: 0.75)).frame(width: 38, height: 5)
                        Capsule().fill(Color(white: 0.85)).frame(width: 24, height: 4)
                    }
                }
                .padding(10)
                placeholderRows(count: 3).padding(.horizontal, 10)
                Spacer()
                tabBar
            }
        case .userCode:
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Account and Security"))
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.top, 14)
                    .padding(.horizontal, 8)
                row(width: 50)
                row(width: 40)
                HStack {
                    Text(L("User Code"))
                        .font(.system(size: 7.5, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 2)
                    Text(verbatim: "a1b2…")
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.black)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(accent.opacity(0.14)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(accent, lineWidth: 1.5))
                .overlay(alignment: .bottomTrailing) { tapHand.offset(x: 4, y: 12) }
                .padding(.horizontal, 6)
                row(width: 46)
                Spacer()
            }
        }
    }

    private var tabBar: some View {
        HStack {
            Image(systemName: "house.fill")
            Spacer()
            Image(systemName: "wand.and.stars")
            Spacer()
            Image(systemName: "person.fill")
                .modifier(TapTarget(isActive: screen == .meTab, accent: accent))
        }
        .font(.system(size: 11))
        .foregroundStyle(Color(white: 0.45))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color(white: 0.92))
    }

    private func placeholderRows(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(0..<count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(white: 0.86))
                    .frame(width: index.isMultiple(of: 2) ? 70 : 54, height: 9)
            }
        }
    }

    private func row(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(white: 0.87))
            .frame(width: width, height: 9)
            .padding(.horizontal, 8)
    }

    private var tapHand: some View {
        Image(systemName: "hand.point.up.left.fill")
            .font(.system(size: 14))
            .foregroundStyle(accent)
            .shadow(color: .white, radius: 1)
    }
}

/// Destaca o ponto onde tocar: anel colorido e a mãozinha.
private struct TapTarget: ViewModifier {
    let isActive: Bool
    let accent: Color

    func body(content: Content) -> some View {
        if isActive {
            content
                .foregroundStyle(accent)
                .padding(4)
                .background(Circle().fill(accent.opacity(0.15)))
                .overlay(Circle().strokeBorder(accent, lineWidth: 1.5))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(accent)
                        .shadow(color: .white, radius: 1)
                        .offset(x: 8, y: 12)
                }
        } else {
            content
        }
    }
}

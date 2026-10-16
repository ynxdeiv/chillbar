import ACCore
import AppKit
import SwiftUI

/// Tons de um modo. Cada um tem um papel, para manter contraste sobre o fundo
/// translúcido do popover em qualquer tema.
struct ModePalette: Equatable {
    /// Preenchimento com texto branco por cima (≥ 4,3:1).
    let solid: Color
    /// Texto e ícones sobre fundo neutro: escuro no tema claro, claro no escuro.
    let ink: Color
    /// Brilho do visor do aparelho, que é sempre escuro.
    let glow: Color
}

/// Cada modo tem a cor do ar que sai do aparelho; o resto da interface fica neutro.
enum Theme {
    static let amber = Color.adaptive(light: 0xA15C00, dark: 0xF5A524)
    static let displayGlass = Color(red: 0.06, green: 0.10, blue: 0.14)

    static func palette(for mode: HVACMode?, isOn: Bool?) -> ModePalette {
        guard isOn == true else { return off }
        switch mode {
        case .cool, nil: return cool
        case .dry: return dry
        case .fanOnly: return fan
        case .auto: return auto
        case .heat: return heat
        }
    }

    static let cool = ModePalette(
        solid: .adaptive(light: 0x1570D6, dark: 0x2479DD),
        ink: .adaptive(light: 0x0D5BB5, dark: 0x7DC3FF),
        glow: Color(hex: 0x4FB3FF)
    )
    static let dry = ModePalette(
        solid: .adaptive(light: 0x0B877A, dark: 0x0B877A),
        ink: .adaptive(light: 0x08756A, dark: 0x5FE0CF),
        glow: Color(hex: 0x3CC8B4)
    )
    static let fan = ModePalette(
        solid: .adaptive(light: 0x5B6878, dark: 0x687586),
        ink: .adaptive(light: 0x4A5563, dark: 0xB4C0CD),
        glow: Color(hex: 0x9AA7B8)
    )
    static let auto = ModePalette(
        solid: .adaptive(light: 0x6D4FE0, dark: 0x7B5EEA),
        ink: .adaptive(light: 0x5A3CCB, dark: 0xC2B0FF),
        glow: Color(hex: 0xA78BFA)
    )
    static let heat = ModePalette(
        solid: .adaptive(light: 0xC2521A, dark: 0xC2521A),
        ink: .adaptive(light: 0xA8441A, dark: 0xFFB089),
        glow: Color(hex: 0xFF8A4C)
    )
    static let off = ModePalette(
        solid: .adaptive(light: 0x6E6E73, dark: 0x636366),
        ink: .secondary,
        glow: Color(hex: 0x8E8E93)
    )
}

extension Color {
    init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension HVACMode {
    var title: String {
        switch self {
        case .cool: L("Cool")
        case .heat: L("Heat")
        case .dry: L("Dry")
        case .fanOnly: L("Fan")
        case .auto: L("Auto")
        }
    }

    var symbol: String {
        switch self {
        case .cool: "snowflake"
        case .heat: "sun.max"
        case .dry: "drop"
        case .fanOnly: "fan"
        case .auto: "a.circle"
        }
    }
}

extension FanSpeed {
    var title: String {
        switch self {
        case .auto: L("Auto")
        case .quiet: L("Quiet")
        case .low: L("Low")
        case .medium: L("Medium")
        case .high: L("High")
        case .turbo: L("Turbo")
        }
    }
}

extension Temperature {
    /// "25" ou "24,5", no formato do usuário.
    var formatted: String {
        celsius.formatted(.number.precision(.fractionLength(0...1)).locale(appLocale))
    }
}

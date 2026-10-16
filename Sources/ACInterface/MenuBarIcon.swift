import AppKit

/// Ícone da barra de menus: a evaporadora desenhada, com o vento saindo quando ligada.
/// Imagem "template" para seguir o tema claro/escuro da barra automaticamente.
public enum MenuBarIcon {
    public enum Style: Sendable {
        case off
        case on
        case disconnected
    }

    public static func image(_ style: Style) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: true) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let body = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 1.5, width: 17, height: 8), xRadius: 2.6, yRadius: 2.6)
            body.lineWidth = 1.4
            body.stroke()

            // Aleta: fechada dentro da carenagem quando desligado; aberta, pendurada
            // abaixo dela, quando ligado.
            let louver = NSBezierPath()
            louver.lineWidth = 1.2
            louver.lineCapStyle = .round
            if style == .on {
                louver.move(to: NSPoint(x: 4.5, y: 10.6))
                louver.line(to: NSPoint(x: 15.5, y: 11.6))
            } else {
                louver.move(to: NSPoint(x: 5, y: 7.4))
                louver.line(to: NSPoint(x: 15, y: 7.4))
            }
            louver.stroke()

            // Visor
            NSBezierPath(ovalIn: NSRect(x: 13.6, y: 3.6, width: 2, height: 2)).fill()

            switch style {
            case .on:
                for (x, lean) in [(5.5, -1.2), (10.0, 0.0), (14.5, 1.2)] {
                    let gust = NSBezierPath()
                    gust.lineWidth = 1.3
                    gust.lineCapStyle = .round
                    gust.move(to: NSPoint(x: x, y: 13.2))
                    gust.curve(
                        to: NSPoint(x: x + lean, y: 17.4),
                        controlPoint1: NSPoint(x: x + 1.5, y: 14.4),
                        controlPoint2: NSPoint(x: x - 1.5 + lean, y: 16.2)
                    )
                    gust.stroke()
                }
            case .disconnected:
                let slash = NSBezierPath()
                slash.lineWidth = 1.4
                slash.lineCapStyle = .round
                slash.move(to: NSPoint(x: 3, y: 16.5))
                slash.line(to: NSPoint(x: 17, y: 0.8))
                slash.stroke()
            case .off:
                break
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = switch style {
        case .on: L("Air conditioner on")
        case .off: L("Air conditioner off")
        case .disconnected: L("Air conditioner offline")
        }
        return image
    }
}

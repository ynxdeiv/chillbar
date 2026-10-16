// Gera o ícone do app (AppIcon.iconset) e o fundo do DMG a partir de desenho em código.
// Uso: swift run ChillbarAssets <pasta-de-saída> <versão>
import AppKit
import SwiftUI

let arguments = Array(CommandLine.arguments.dropFirst())
let output = URL(fileURLWithPath: arguments.first ?? "build/assets")
let version = arguments.dropFirst().first ?? "dev"
let iconset = output.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

private let sky = Color(red: 0.37, green: 0.78, blue: 1.00)
private let deep = Color(red: 0.08, green: 0.44, blue: 0.84)

/// Ícone: a evaporadora branca soprando ar sobre um azul-gelo, no formato padrão do macOS.
struct AppIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size.width
            // Grade da Apple: a forma ocupa ~80% da tela do ícone, com sombra em volta.
            let inset = size * 0.1
            let tile = size - inset * 2
            ZStack {
                RoundedRectangle(cornerRadius: tile * 0.2237, style: .continuous)
                    .fill(LinearGradient(colors: [sky, deep], startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: tile * 0.2237, style: .continuous)
                            .fill(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center))
                    )
                    .shadow(color: .black.opacity(0.28), radius: size * 0.02, y: size * 0.012)

                unit(width: tile * 0.68)
                    .offset(y: -tile * 0.1)

                airflow(width: tile * 0.5, height: tile * 0.24)
                    .offset(y: tile * 0.17)
            }
            .frame(width: tile, height: tile)
            .frame(width: size, height: size)
        }
    }

    private func unit(width: CGFloat) -> some View {
        let height = width * 0.34
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: height * 0.3, style: .continuous)
                .fill(LinearGradient(colors: [.white, Color(white: 0.9)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.25), radius: width * 0.03, y: width * 0.02)
            RoundedRectangle(cornerRadius: height * 0.1, style: .continuous)
                .fill(Color(red: 0.06, green: 0.10, blue: 0.14))
                .frame(width: width * 0.26, height: height * 0.36)
                .overlay(
                    Circle().fill(sky).frame(width: height * 0.12).shadow(color: sky, radius: height * 0.08)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, height * 0.18)
                .padding(.trailing, width * 0.08)
            Capsule()
                .fill(Color.black.opacity(0.45))
                .frame(width: width * 0.72, height: height * 0.08)
                .padding(.bottom, height * 0.12)
        }
        .frame(width: width, height: height)
    }

    private func airflow(width: CGFloat, height: CGFloat) -> some View {
        Canvas { context, size in
            for index in 0..<3 {
                let x = size.width * (CGFloat(index) + 0.5) / 3
                let lean = (CGFloat(index) - 1) * size.width * 0.12
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addCurve(
                    to: CGPoint(x: x + lean, y: size.height),
                    control1: CGPoint(x: x + size.width * 0.12, y: size.height * 0.33),
                    control2: CGPoint(x: x + lean - size.width * 0.12, y: size.height * 0.66)
                )
                context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: size.width * 0.055, lineCap: .round))
            }
        }
        .frame(width: width, height: height)
        .mask(LinearGradient(colors: [.black, .black.opacity(0.15)], startPoint: .top, endPoint: .bottom))
    }
}

/// Fundo da janela do DMG (600×400). Os ícones ficam em (150, 235) e (450, 235),
/// posições definidas em scripts/make-dmg.sh.
struct DMGBackground: View {
    let version: String

    private let night = Color(red: 0.05, green: 0.18, blue: 0.37)
    private let ocean = Color(red: 0.14, green: 0.35, blue: 0.60)
    // Sob os nomes dos ícones o azul fica com luminância ~0,18: o Finder escreve em
    // preto no modo claro e em branco no escuro, e os dois ficam legíveis (~4,5:1).
    private let shore = Color(red: 0.29, green: 0.49, blue: 0.75)

    var body: some View {
        ZStack {
            LinearGradient(stops: [
                .init(color: night, location: 0),
                .init(color: ocean, location: 0.5),
                .init(color: shore, location: 1),
            ], startPoint: .top, endPoint: .bottom)

            // Brilhos de luz azul-gelo
            Circle().fill(sky.opacity(0.45)).frame(width: 340).blur(radius: 80).offset(x: 230, y: -190)
            Circle().fill(Color(red: 0.24, green: 0.78, blue: 0.71).opacity(0.22)).frame(width: 300).blur(radius: 90).offset(x: -260, y: 170)

            breeze
            header
            slot(dashed: false).position(x: 150, y: 247)
            slot(dashed: true).position(x: 450, y: 247)
            arrow
            footer
        }
        .frame(width: 600, height: 400)
        .clipped()
    }

    /// Linhas de vento quase invisíveis atravessando o fundo, como no pop-up do app.
    private var breeze: some View {
        Canvas { context, size in
            for index in 0..<5 {
                let y = 120 + CGFloat(index) * 52
                var path = Path()
                path.move(to: CGPoint(x: -20, y: y))
                path.addCurve(
                    to: CGPoint(x: size.width + 20, y: y - 40),
                    control1: CGPoint(x: size.width * 0.3, y: y - 70),
                    control2: CGPoint(x: size.width * 0.6, y: y + 50)
                )
                context.stroke(path, with: .color(.white.opacity(0.05)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(verbatim: "Chillbar")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: sky.opacity(0.6), radius: 12)
            Text(verbatim: "Your air conditioner, right in the menu bar.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 36)
    }

    /// Área de vidro fosco sob cada ícone; a de Aplicativos tem borda tracejada (onde soltar).
    private func slot(dashed: Bool) -> some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(.white.opacity(0.07))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(.white.opacity(dashed ? 0.35 : 0.18), style: StrokeStyle(lineWidth: 1.2, dash: dashed ? [6, 5] : []))
            )
            .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
            .frame(width: 156, height: 172)
    }

    /// Seta curva pontilhada com brilho, do app até Aplicativos.
    private var arrow: some View {
        Canvas { context, _ in
            let start = CGPoint(x: 246, y: 232)
            let end = CGPoint(x: 352, y: 232)
            var arc = Path()
            arc.move(to: start)
            arc.addQuadCurve(to: end, control: CGPoint(x: 299, y: 196))
            context.stroke(arc, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [0.1, 9]))

            // Ponta alinhada à tangente da curva no fim (do ponto de controle até o fim).
            let control = CGPoint(x: 299, y: 196)
            let length = hypot(end.x - control.x, end.y - control.y)
            let direction = CGPoint(x: (end.x - control.x) / length, y: (end.y - control.y) / length)
            let normal = CGPoint(x: -direction.y, y: direction.x)
            var head = Path()
            head.move(to: CGPoint(x: end.x - direction.x * 12 + normal.x * 7, y: end.y - direction.y * 12 + normal.y * 7))
            head.addLine(to: end)
            head.addLine(to: CGPoint(x: end.x - direction.x * 12 - normal.x * 7, y: end.y - direction.y * 12 - normal.y * 7))
            context.stroke(head, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        .shadow(color: sky.opacity(0.9), radius: 6)
    }

    private var footer: some View {
        HStack {
            Text(verbatim: "Version \(version)")
            Spacer()
            Text(verbatim: "github.com/ynxdeiv")
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.white.opacity(0.5))
        .padding(.horizontal, 22)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 14)
    }
}

@MainActor
func writePNG(_ view: some View, size: CGSize, scale: CGFloat, to url: URL) throws {
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    renderer.scale = scale
    guard let image = renderer.cgImage,
          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else { throw CocoaError(.fileWriteUnknown) }
    try data.write(to: url)
}

for points in [16, 32, 128, 256, 512] {
    let size = CGSize(width: points, height: points)
    try writePNG(AppIcon(), size: size, scale: 1, to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try writePNG(AppIcon(), size: size, scale: 2, to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
try writePNG(DMGBackground(version: version), size: CGSize(width: 600, height: 400), scale: 1, to: output.appendingPathComponent("dmg-background.png"))
try writePNG(DMGBackground(version: version), size: CGSize(width: 600, height: 400), scale: 2, to: output.appendingPathComponent("dmg-background@2x.png"))
print("Assets em \(output.path)")

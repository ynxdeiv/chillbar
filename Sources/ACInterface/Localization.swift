import Foundation

/// Idioma da interface, escolhido no menu ⋯. Inglês é o idioma-base.
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case portuguese = "pt-BR"

    public static let defaultsKey = "appLanguage"

    public static func current(in defaults: UserDefaults = .standard) -> AppLanguage {
        defaults.string(forKey: defaultsKey).flatMap(AppLanguage.init(rawValue:)) ?? .english
    }

    public var id: String { rawValue }

    /// Nome do idioma nele mesmo, como nos menus do sistema.
    public var displayName: String {
        switch self {
        case .english: "English"
        case .portuguese: "Português (Brasil)"
        }
    }

    /// Rótulo curto para o seletor do assistente.
    public var shortName: String {
        switch self {
        case .english: "English"
        case .portuguese: "Português"
        }
    }

    /// Para datas, horas, durações e números no idioma escolhido.
    public var locale: Locale {
        Locale(identifier: rawValue)
    }

    fileprivate var bundle: Bundle {
        Self.bundles[self] ?? resourceBundle
    }

    private static let bundles: [AppLanguage: Bundle] = {
        let resources = resourceBundle
        var result: [AppLanguage: Bundle] = [:]
        for language in AppLanguage.allCases {
            // O SwiftPM grava "pt-BR.lproj" como "pt-br.lproj": compara sem diferenciar maiúsculas.
            let folder = resources.localizations.first { $0.caseInsensitiveCompare(language.rawValue) == .orderedSame }
            if let folder,
               let path = resources.path(forResource: folder, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                result[language] = bundle
            }
        }
        return result
    }()
}

/// Texto da interface no idioma escolhido. A chave é a frase em inglês.
func L(_ key: String.LocalizationValue) -> String {
    L(key, in: .current())
}

func L(_ key: String.LocalizationValue, in language: AppLanguage) -> String {
    String(localized: key, bundle: language.bundle)
}

/// Locale do idioma escolhido, para formatar valores na interface.
var appLocale: Locale { AppLanguage.current().locale }

/// No .app os recursos ficam em Contents/Resources; em `swift run` e testes, `Bundle.module` resolve.
private var resourceBundle: Bundle {
    if let url = Bundle.main.resourceURL?.appendingPathComponent("Chillbar_ACInterface.bundle"),
       let bundle = Bundle(url: url) {
        return bundle
    }
    return Bundle.module
}

/// Textos que o app (fora deste módulo) também exibe.
public enum InterfaceText {
    public static var simulation: String { L("Simulation") }
    public static var localNetwork: String { L("Wi-Fi") }
}

/// Autor e links do projeto, exibidos no rodapé do pop-up.
public enum ProjectInfo {
    public static let author = "ynxdeiv"
    public static let authorName = "deiv"
    public static let authorURL = URL(string: "https://github.com/ynxdeiv")!

    /// Redes do criador, na ordem em que aparecem nos créditos.
    static let socialLinks: [SocialLink] = [
        SocialLink(name: "GitHub", address: "github.com/ynxdeiv", url: authorURL, glyph: .symbol("chevron.left.forwardslash.chevron.right")),
        SocialLink(name: "LinkedIn", address: "linkedin.com/in/deivcst", url: URL(string: "https://www.linkedin.com/in/deivcst/")!, glyph: .text("in")),
        SocialLink(name: "X", address: "x.com/2003setembro", url: URL(string: "https://x.com/2003setembro")!, glyph: .text("𝕏")),
    ]
}

/// Link de rede social com um símbolo simples (sem logotipos de marca).
struct SocialLink: Identifiable, Sendable {
    enum Glyph: Sendable {
        case symbol(String)
        case text(String)
    }

    let name: String
    let address: String
    let url: URL
    let glyph: Glyph
    var id: String { name }
}

import Foundation
import Testing
@testable import ACInterface

private let sourcesDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("../../Sources/ACInterface")
    .standardizedFileURL

/// Chaves `L("…")` usadas no código, com interpolações no formato `%@`.
private func keysUsedInSources() throws -> Set<String> {
    let files = try FileManager.default.contentsOfDirectory(at: sourcesDirectory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "swift" }
    let call = try Regex(#"\bL\("((?:[^"\\]|\\\([^)]*\)|\\.)*)""#)
    var keys = Set<String>()
    for file in files {
        let source = try String(contentsOf: file, encoding: .utf8)
        for match in source.matches(of: call) {
            let literal = String(match.output[1].substring ?? "")
            keys.insert(literal.replacing(#/\\\([^)]*\)/#, with: "%@"))
        }
    }
    return keys
}

private func translations(_ language: String) throws -> [String: String] {
    let url = sourcesDirectory.appendingPathComponent("Resources/\(language).lproj/Localizable.strings")
    return try #require(NSDictionary(contentsOf: url) as? [String: String])
}

@Suite("Idiomas")
struct LocalizationTests {
    @Test("sem preferência salva, o app abre em inglês")
    func defaultsToEnglish() throws {
        let defaults = try #require(UserDefaults(suiteName: "LocalizationTests.\(UUID())"))
        #expect(AppLanguage.current(in: defaults) == .english)
    }

    @Test("a escolha de idioma do usuário é respeitada")
    func respectsStoredChoice() throws {
        let defaults = try #require(UserDefaults(suiteName: "LocalizationTests.\(UUID())"))
        defaults.set("pt-BR", forKey: AppLanguage.defaultsKey)
        #expect(AppLanguage.current(in: defaults) == .portuguese)
    }

    @Test("traduz para o idioma escolhido", arguments: [
        (AppLanguage.english, "Cool"),
        (.portuguese, "Frio"),
    ])
    func translates(language: AppLanguage, expected: String) {
        #expect(L("Cool", in: language) == expected)
    }

    @Test("interpolação é traduzida com o valor no lugar certo")
    func translatesInterpolation() {
        let time = "14:32"
        #expect(L("On since \(time)", in: .portuguese) == "Ligado desde 14:32")
        #expect(L("On since \(time)", in: .english) == "On since 14:32")
    }

    @Test("todo texto da interface tem tradução em português")
    func everyKeyHasPortuguese() throws {
        let used = try keysUsedInSources()
        let portuguese = try translations("pt-BR")
        #expect(!used.isEmpty)
        #expect(used.subtracting(portuguese.keys).sorted() == [])
    }

    @Test("o arquivo em português não tem traduções órfãs")
    func noOrphanTranslations() throws {
        let used = try keysUsedInSources()
        let portuguese = try translations("pt-BR")
        #expect(Set(portuguese.keys).subtracting(used).sorted() == [])
    }
}

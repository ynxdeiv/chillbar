/// Temperatura em décimos de grau Celsius, para evitar erros de ponto flutuante
/// em comparações de faixa e passo.
public struct Temperature: Hashable, Comparable, Sendable, Codable {
    public var tenthsOfCelsius: Int

    public init(tenthsOfCelsius: Int) {
        self.tenthsOfCelsius = tenthsOfCelsius
    }

    public init(celsius: Double) {
        tenthsOfCelsius = Int((celsius * 10).rounded())
    }

    public var celsius: Double { Double(tenthsOfCelsius) / 10 }

    public static func < (lhs: Temperature, rhs: Temperature) -> Bool {
        lhs.tenthsOfCelsius < rhs.tenthsOfCelsius
    }
}

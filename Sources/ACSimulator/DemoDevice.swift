import ACCore

/// Estado inicial do modo demonstração: o que o Elgin reportou na prova de conceito.
public enum DemoDevice {
    public static let initialState = ClimateState(
        isOn: true,
        setpoint: Temperature(celsius: 25),
        roomTemperature: Temperature(celsius: 23),
        mode: .cool,
        fanSpeed: .auto,
        verticalSwing: false,
        features: [.display: true, .sleep: false, .clean: false, .antiMould: false, .ionizer: true]
    )
}

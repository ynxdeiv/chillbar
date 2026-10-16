// Diagnóstico somente leitura: conecta ao aparelho pela rede local e mostra o estado.
// Uso: swift run ChillbarProbe <devices.json do tinytuya> [--discover] [--cycle]
// --cycle: desliga, liga, testa o modo Auto e devolve o aparelho ao estado inicial.
// --auto-rule: verifica se o Auto fixa 25 °C e se o aparelho aceita mudar a temperatura nele.
// Nunca imprime a chave local.
import ACCore
import ACTuya
import Foundation

let arguments = CommandLine.arguments.dropFirst()
guard let path = arguments.first,
      let data = FileManager.default.contents(atPath: path),
      let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
      let device = list.first,
      let id = device["id"] as? String,
      let key = device["key"] as? String
else {
    print("Uso: ChillbarProbe <devices.json> [--discover] [--cycle]")
    exit(1)
}

let productID = device["product_id"] as? String ?? ""
guard let profile = TuyaDeviceProfile.bundled(category: "kt", productID: productID) else {
    print("Sem perfil para o produto \(productID)")
    exit(1)
}

var host = device["ip"] as? String
if arguments.contains("--discover") {
    print("Procurando o aparelho na rede (até 15 s)…")
    let started = Date()
    if let found = await TuyaNetworkDiscovery.find(deviceID: id, timeout: .seconds(15)) {
        print("Encontrado em \(found.ip) (protocolo \(found.version)) após \(String(format: "%.1f", Date().timeIntervalSince(started))) s")
        host = found.ip
    } else {
        print("Não encontrado pela descoberta UDP.")
    }
}

let adapter = TuyaLocalAdapter(deviceID: id, localKey: key, host: host, profile: profile, locate: { nil })
let started = Date()
do {
    let snapshot = try await adapter.refresh()
    let state = snapshot.state
    print("Leitura em \(String(format: "%.2f", Date().timeIntervalSince(started))) s")
    print("  ligado: \(state.isOn.map { $0 ? "sim" : "não" } ?? "?")")
    print("  setpoint: \(state.setpoint.map { "\($0.celsius) °C" } ?? "?")")
    print("  ambiente: \(state.roomTemperature.map { "\($0.celsius) °C" } ?? "?")")
    print("  modo: \(state.mode?.rawValue ?? "?") | ventilação: \(state.fanSpeed?.rawValue ?? "?") | oscilação: \(state.verticalSwing.map { "\($0)" } ?? "?")")
    print("  funções: \(state.features.map { "\($0.key.rawValue)=\($0.value)" }.sorted().joined(separator: ", "))")
} catch {
    print("Falha: \(error)")
    exit(2)
}

// MARK: Roteiro --cycle (altera o aparelho e restaura no fim)

func describe(_ state: ClimateState) -> String {
    let power = state.isOn.map { $0 ? "ligado" : "desligado" } ?? "?"
    let setpoint = state.setpoint.map { "\($0.celsius) °C" } ?? "?"
    return "\(power), \(state.mode?.rawValue ?? "?"), setpoint \(setpoint), ventilação \(state.fanSpeed?.rawValue ?? "?")"
}

/// Envia o comando e espera o aparelho confirmar (aviso de mudança) até `timeout`.
func sendAndConfirm(
    _ command: ClimateCommand,
    until condition: @escaping @Sendable (ClimateState) -> Bool,
    label: String,
    timeout: Duration = .seconds(10)
) async -> Bool {
    let updates = adapter.stateUpdates()
    try? await Task.sleep(for: .milliseconds(300))
    let started = Date()
    do {
        try await adapter.send(command)
    } catch {
        print("  ✘ \(label): falha ao enviar (\(error))")
        return false
    }
    let confirmed = await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            var merged = ClimateState()
            do {
                for try await snapshot in updates {
                    if let value = snapshot.state.isOn { merged.isOn = value }
                    if let value = snapshot.state.setpoint { merged.setpoint = value }
                    if let value = snapshot.state.mode { merged.mode = value }
                    if let value = snapshot.state.fanSpeed { merged.fanSpeed = value }
                    if condition(merged) { return true }
                }
            } catch {}
            return false
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return false
        }
        let first = await group.next() ?? false
        group.cancelAll()
        return first
    }
    let elapsed = String(format: "%.2f", Date().timeIntervalSince(started))
    print(confirmed ? "  ✔ \(label): confirmado pelo aparelho em \(elapsed) s" : "  ✘ \(label): sem confirmação em \(timeout)")
    return confirmed
}

if arguments.contains("--cycle") {
    guard let initial = try? await adapter.refresh().state else {
        print("Não consegui ler o estado inicial.")
        exit(3)
    }
    print("\nEstado inicial: \(describe(initial))")
    var results: [Bool] = []

    print("\n1) Desligar e ligar")
    if initial.isOn == true {
        results.append(await sendAndConfirm(.setPower(false), until: { $0.isOn == false }, label: "desligar"))
        try? await Task.sleep(for: .seconds(5))
        results.append(await sendAndConfirm(.setPower(true), until: { $0.isOn == true }, label: "ligar"))
    } else {
        results.append(await sendAndConfirm(.setPower(true), until: { $0.isOn == true }, label: "ligar"))
        try? await Task.sleep(for: .seconds(5))
        results.append(await sendAndConfirm(.setPower(false), until: { $0.isOn == false }, label: "desligar"))
        try? await Task.sleep(for: .seconds(3))
        results.append(await sendAndConfirm(.setPower(true), until: { $0.isOn == true }, label: "ligar de novo (para o teste do Auto)"))
    }

    print("\n2) Modo Auto (manual: temperatura fixa em 25 °C)")
    try? await Task.sleep(for: .seconds(3))
    results.append(await sendAndConfirm(.setMode(.auto), until: { $0.mode == .auto }, label: "mudar para Auto"))
    try? await Task.sleep(for: .seconds(3))
    if let inAuto = try? await adapter.refresh().state {
        print("  No Auto o aparelho reporta: \(describe(inAuto))")
    }

    print("\n3) Restaurando o estado inicial")
    if let mode = initial.mode {
        results.append(await sendAndConfirm(.setMode(mode), until: { $0.mode == mode }, label: "voltar ao modo \(mode.rawValue)"))
    }
    try? await Task.sleep(for: .seconds(2))
    if let setpoint = initial.setpoint, let now = try? await adapter.refresh().state, now.setpoint != setpoint {
        results.append(await sendAndConfirm(.setSetpoint(setpoint), until: { $0.setpoint == setpoint }, label: "voltar a \(setpoint.celsius) °C"))
    }
    if initial.isOn == false {
        try? await Task.sleep(for: .seconds(2))
        results.append(await sendAndConfirm(.setPower(false), until: { $0.isOn == false }, label: "desligar (como estava)"))
    }
    if let final = try? await adapter.refresh().state {
        print("\nEstado final: \(describe(final))")
    }
    print(results.allSatisfy { $0 } ? "\nResultado: tudo confirmado ✔" : "\nResultado: houve passos sem confirmação ✘")
}

if arguments.contains("--auto-rule") {
    guard let initial = try? await adapter.refresh().state, initial.isOn == true else {
        print("O aparelho precisa estar ligado para este teste.")
        exit(3)
    }
    print("\nEstado inicial: \(describe(initial))")
    let probeTemperature = Temperature(celsius: 23)

    print("\n1) Frio a 23 °C")
    _ = await sendAndConfirm(.setMode(.cool), until: { $0.mode == .cool }, label: "modo Frio", timeout: .seconds(4))
    _ = await sendAndConfirm(.setSetpoint(probeTemperature), until: { $0.setpoint == probeTemperature }, label: "23 °C")

    print("\n2) Auto: o aparelho muda a temperatura sozinho?")
    try? await Task.sleep(for: .seconds(2))
    _ = await sendAndConfirm(.setMode(.auto), until: { $0.mode == .auto }, label: "modo Auto")
    try? await Task.sleep(for: .seconds(3))
    if let state = try? await adapter.refresh().state {
        print("  No Auto: setpoint \(state.setpoint.map { "\($0.celsius) °C" } ?? "?"), ventilação \(state.fanSpeed?.rawValue ?? "?")")
    }

    print("\n3) Ainda no Auto: o aparelho aceita 27 °C?")
    let attempt = Temperature(celsius: 27)
    let accepted = await sendAndConfirm(.setSetpoint(attempt), until: { $0.setpoint == attempt }, label: "pedir 27 °C no Auto", timeout: .seconds(6))
    try? await Task.sleep(for: .seconds(1))
    if let state = try? await adapter.refresh().state {
        print("  Depois do pedido: setpoint \(state.setpoint.map { "\($0.celsius) °C" } ?? "?") (\(accepted ? "aceitou" : "recusou/ignorou"))")
    }

    print("\n4) Restaurando")
    if let mode = initial.mode {
        _ = await sendAndConfirm(.setMode(mode), until: { $0.mode == mode }, label: "voltar ao modo \(mode.rawValue)")
    }
    try? await Task.sleep(for: .seconds(2))
    if let setpoint = initial.setpoint, let now = try? await adapter.refresh().state, now.setpoint != setpoint {
        _ = await sendAndConfirm(.setSetpoint(setpoint), until: { $0.setpoint == setpoint }, label: "voltar a \(setpoint.celsius) °C")
    }
    if let final = try? await adapter.refresh().state {
        print("\nEstado final: \(describe(final))")
    }
}

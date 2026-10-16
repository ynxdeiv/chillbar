import Foundation
import Testing
@testable import ACCore

private let t0 = Date(timeIntervalSince1970: 2_000_000)

@Suite("Tempo ligado e consumo estimado")
struct UsageTrackerTests {
    @Test("ligar enquanto o app observa marca o início exato")
    func exactStartWhenObservedTurningOn() {
        var tracker = UsageTracker()
        tracker.observe(isOn: false, at: t0)
        tracker.observe(isOn: true, at: t0 + 60)

        #expect(tracker.session == UsageSession(start: t0 + 60, startIsExact: true))
    }

    @Test("aparelho já ligado quando o app o vê pela primeira vez: início aproximado")
    func approximateStartWhenFirstSeenOn() {
        var tracker = UsageTracker()
        tracker.observe(isOn: true, at: t0)

        #expect(tracker.session == UsageSession(start: t0, startIsExact: false))
    }

    @Test("continuar ligado mantém o início original")
    func stayingOnKeepsStart() {
        var tracker = UsageTracker()
        tracker.observe(isOn: false, at: t0)
        tracker.observe(isOn: true, at: t0 + 10)
        tracker.observe(isOn: true, at: t0 + 3_600)

        #expect(tracker.session?.start == t0 + 10)
    }

    @Test("desligar encerra a sessão")
    func turningOffClearsSession() {
        var tracker = UsageTracker()
        tracker.observe(isOn: true, at: t0)
        tracker.observe(isOn: false, at: t0 + 60)

        #expect(tracker.session == nil)
    }

    @Test("duração e energia estimada pela potência média", arguments: [
        (7_200.0, 195.0, 0.39),
        (1_800.0, 200.0, 0.1),
        (0.0, 195.0, 0.0),
    ])
    func durationAndEnergy(seconds: Double, watts: Double, expectedKWh: Double) {
        let session = UsageSession(start: t0, startIsExact: true)

        #expect(session.duration(now: t0 + seconds) == seconds)
        #expect(abs(session.estimatedEnergy(now: t0 + seconds, averageWatts: watts) - expectedKWh) < 0.000_1)
    }

    @Test("sobrevive a reiniciar o app: a sessão salva continua se o aparelho segue ligado")
    func persistsAcrossRestart() throws {
        var tracker = UsageTracker()
        tracker.observe(isOn: false, at: t0)
        tracker.observe(isOn: true, at: t0 + 30)

        let data = try JSONEncoder().encode(tracker)
        var restored = try JSONDecoder().decode(UsageTracker.self, from: data)
        restored.observe(isOn: true, at: t0 + 600)

        #expect(restored.session == UsageSession(start: t0 + 30, startIsExact: true))
    }
}

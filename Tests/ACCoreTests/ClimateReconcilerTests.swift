import Foundation
import Testing
@testable import ACCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func snapshot(_ state: ClimateState, at date: Date = t0) -> ClimateSnapshot {
    ClimateSnapshot(state: state, observedAt: date)
}

/// Reconciliador com o aparelho reportando ligado, 25 °C, frio.
private func reconcilerAt25() -> ClimateReconciler {
    var reconciler = ClimateReconciler(confirmationTimeout: 10)
    reconciler.apply(snapshot(ClimateState(isOn: true, setpoint: Temperature(celsius: 25), mode: .cool)))
    return reconciler
}

@Suite("Reconciliação: desejado × confirmado")
struct ClimateReconcilerTests {
    @Test("enquanto pendente, exibe o valor desejado sem alterar o reportado")
    func pendingShowsDesiredValue() {
        var reconciler = reconcilerAt25()
        reconciler.didSend(.setSetpoint(Temperature(celsius: 26)), at: t0)

        #expect(reconciler.displayed.setpoint == Temperature(celsius: 26))
        #expect(reconciler.reported.setpoint == Temperature(celsius: 25))
        #expect(reconciler.status(of: .setpoint) == .pending(since: t0))
    }

    @Test("confirma quando o aparelho reporta o valor desejado")
    func confirmsOnMatchingReport() {
        var reconciler = reconcilerAt25()
        reconciler.didSend(.setSetpoint(Temperature(celsius: 26)), at: t0)
        reconciler.apply(snapshot(ClimateState(setpoint: Temperature(celsius: 26)), at: t0 + 0.5))

        #expect(reconciler.status(of: .setpoint) == .synced)
        #expect(reconciler.reported.setpoint == Temperature(celsius: 26))
    }

    @Test("relatório com outro valor não confirma o comando")
    func otherValueKeepsPending() {
        var reconciler = reconcilerAt25()
        reconciler.didSend(.setSetpoint(Temperature(celsius: 26)), at: t0)
        reconciler.apply(snapshot(ClimateState(setpoint: Temperature(celsius: 25)), at: t0 + 1))

        #expect(reconciler.status(of: .setpoint) == .pending(since: t0))
        #expect(reconciler.displayed.setpoint == Temperature(celsius: 26))
    }

    @Test("sem confirmação no prazo, falha e volta a exibir o último valor reportado")
    func expiresToFailure() {
        var reconciler = reconcilerAt25()
        reconciler.didSend(.setSetpoint(Temperature(celsius: 26)), at: t0)

        #expect(reconciler.expire(now: t0 + 9.9).isEmpty)
        #expect(reconciler.expire(now: t0 + 10) == [.setSetpoint(Temperature(celsius: 26))])
        #expect(reconciler.status(of: .setpoint) == .failed(.setSetpoint(Temperature(celsius: 26))))
        #expect(reconciler.displayed.setpoint == Temperature(celsius: 25))
    }

    @Test("o comando mais recente do mesmo campo substitui o anterior")
    func latestCommandWins() {
        var reconciler = reconcilerAt25()
        reconciler.didSend(.setSetpoint(Temperature(celsius: 26)), at: t0)
        reconciler.didSend(.setSetpoint(Temperature(celsius: 27)), at: t0 + 1)
        reconciler.apply(snapshot(ClimateState(setpoint: Temperature(celsius: 26)), at: t0 + 1.5))

        #expect(reconciler.status(of: .setpoint) == .pending(since: t0 + 1))
        #expect(reconciler.displayed.setpoint == Temperature(celsius: 27))
    }

    @Test("um novo comando limpa a falha anterior do campo")
    func newCommandClearsFailure() {
        var reconciler = reconcilerAt25()
        reconciler.didSend(.setSetpoint(Temperature(celsius: 26)), at: t0)
        _ = reconciler.expire(now: t0 + 10)
        reconciler.didSend(.setSetpoint(Temperature(celsius: 24)), at: t0 + 20)

        #expect(reconciler.status(of: .setpoint) == .pending(since: t0 + 20))
    }

    @Test("cancelar um envio que falhou descarta o pendente sem registrar falha de confirmação")
    func cancelPending() {
        var reconciler = reconcilerAt25()
        reconciler.didSend(.setSetpoint(Temperature(celsius: 26)), at: t0)
        reconciler.cancelPending(.setpoint)

        #expect(reconciler.status(of: .setpoint) == .synced)
        #expect(reconciler.displayed.setpoint == Temperature(celsius: 25))
        #expect(reconciler.expire(now: t0 + 60).isEmpty)
    }

    @Test("relatório parcial preserva os campos não reportados")
    func partialReportMerges() {
        var reconciler = reconcilerAt25()
        reconciler.apply(snapshot(ClimateState(roomTemperature: Temperature(celsius: 23)), at: t0 + 5))

        #expect(reconciler.reported == ClimateState(
            isOn: true,
            setpoint: Temperature(celsius: 25),
            roomTemperature: Temperature(celsius: 23),
            mode: .cool
        ))
    }

    @Test("funções extras são confirmadas individualmente")
    func featureConfirmation() {
        var reconciler = reconcilerAt25()
        reconciler.didSend(.setFeature(.sleep, true), at: t0)
        #expect(reconciler.displayed.features[.sleep] == true)
        #expect(reconciler.status(of: .feature(.display)) == .synced)

        reconciler.apply(snapshot(ClimateState(features: [.sleep: true]), at: t0 + 1))
        #expect(reconciler.status(of: .feature(.sleep)) == .synced)
    }

    @Test("frescor: desconhecido sem relatório, recente dentro do limite, desatualizado depois")
    func freshness() {
        let empty = ClimateReconciler(confirmationTimeout: 10)
        #expect(empty.freshness(now: t0, staleAfter: 60) == .unknown)

        let reconciler = reconcilerAt25()
        #expect(reconciler.freshness(now: t0 + 59, staleAfter: 60) == .fresh)
        #expect(reconciler.freshness(now: t0 + 60, staleAfter: 60) == .stale(since: t0))
    }
}

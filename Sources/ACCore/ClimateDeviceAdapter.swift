import Foundation

/// Contrato que toda integração (Tuya local, Home Assistant, nuvem…) implementa.
///
/// `send` só garante que o comando saiu; a confirmação chega por `stateUpdates()`
/// quando o aparelho reporta o novo valor.
public protocol ClimateDeviceAdapter: Sendable {
    var capabilities: ClimateCapabilities { get }
    func stateUpdates() -> AsyncThrowingStream<ClimateSnapshot, Error>
    func refresh() async throws -> ClimateSnapshot
    func send(_ command: ClimateCommand) async throws
}

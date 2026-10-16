import ACApplication
import ACTuya

/// Liga o assistente (genérico) ao login por QR do Smart Life.
struct SmartLifeAccount: AccountLinking {
    private let client = TuyaSharingClient()

    func requestQRCode(userCode: String) async throws -> SetupQRCode {
        do {
            let login = try await client.requestQRCode(userCode: userCode)
            return SetupQRCode(content: login.qrContent, token: login.token)
        } catch TuyaSharingError.api(_, let message) {
            throw SetupError.account(message: message)
        }
    }

    func devicesIfConfirmed(qrCode: SetupQRCode, userCode: String) async throws -> [SetupDevice]? {
        guard let session = try await client.session(for: TuyaQRLogin(token: qrCode.token), userCode: userCode) else {
            return nil
        }
        return try await client.devices(session: session).map { device in
            SetupDevice(
                id: device.id,
                name: device.name,
                model: device.productName,
                isOnline: device.isOnline,
                isAirConditioner: device.isAirConditioner,
                secret: device.localKey,
                productID: device.productID
            )
        }
    }
}

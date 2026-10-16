import CryptoKit
import Foundation
import Testing
@testable import ACTuya

/// Operações do lado do servidor, usadas só pelo servidor falso dos testes.
private extension TuyaSharingCrypto {
    /// `encdata` da requisição: base64(nonce) (16 caracteres) + base64(cifrado+tag).
    static func decryptRequest(_ encdata: String, secret: String) throws -> Data {
        let nonce = try #require(Data(base64Encoded: String(encdata.prefix(16))))
        let sealed = try #require(Data(base64Encoded: String(encdata.dropFirst(16))))
        let box = try AES.GCM.SealedBox(combined: nonce + sealed)
        return try AES.GCM.open(box, using: SymmetricKey(data: Data(secret.utf8)))
    }

    /// Resposta do servidor: base64(nonce + cifrado + tag).
    static func sealForTesting(_ plain: Data, secret: String, nonce: [UInt8]) throws -> String {
        let box = try AES.GCM.seal(plain, using: SymmetricKey(data: Data(secret.utf8)), nonce: AES.GCM.Nonce(data: nonce))
        return try #require(box.combined).base64EncodedString()
    }
}

// Vetores gerados com o SDK oficial (Python `cryptography`) e valores fictícios.
private let requestID = "11111111-2222-4333-8444-555555555555"
private let refreshToken = "refresh-token-ficticio"

@Suite("Login por QR do Smart Life: criptografia")
struct TuyaSharingCryptoTests {
    @Test("deriva a chave da requisição como o SDK")
    func derivesKeys() {
        let keys = TuyaSharingCrypto.keys(requestID: requestID, refreshToken: refreshToken)
        #expect(keys.hashKey == "91c772b1f4f6c7bef7d2c6c6a7b1942f")
        #expect(keys.secret == "6ed4dc779d9ede46")
    }

    @Test("cifra os parâmetros como o SDK (nonce fixo)")
    func encryptsQuery() throws {
        let encdata = try TuyaSharingCrypto.encrypt(#"{"homeId":"123456"}"#, secret: "6ed4dc779d9ede46", nonce: Array("ABCDEFGHJKMN".utf8))
        #expect(encdata == "QUJDREVGR0hKS01OWYN20KGwKtvJIzBqRHhZ6eZ9pkmQJM5rMy7zZF2STVvsgkM=")
    }

    @Test("assina cabeçalhos e parâmetros como o SDK")
    func signs() {
        let signature = TuyaSharingCrypto.sign(
            hashKey: "91c772b1f4f6c7bef7d2c6c6a7b1942f",
            headers: [
                ("X-appKey", "HA_3y9q4ak7g4ephrvke"),
                ("X-requestId", requestID),
                ("X-sid", ""),
                ("X-time", "1700000000000"),
                ("X-token", "access-token-ficticio"),
            ],
            queryEncdata: "QUJDREVGR0hKS01OWYN20KGwKtvJIzBqRHhZ6eZ9pkmQJM5rMy7zZF2STVvsgkM=",
            bodyEncdata: ""
        )
        #expect(signature == "e27882418bfc8b938ec792bf0272aa98320eadc08ae7ffa21ccb3f96d9509106")
    }

    @Test("decifra a resposta do servidor")
    func decryptsResponse() throws {
        let plain = try TuyaSharingCrypto.decrypt(
            "UFFSU1RXWFlaYWJjcv8Dihh6Jdu5o4zqKeDvmhyGBSMDMocXXtje60LJC6/QW1qzVXyoZgHLSjNGOwc=",
            secret: "6ed4dc779d9ede46"
        )
        #expect(String(decoding: plain, as: UTF8.self) == #"[{"ownerId":987,"name":"Casa"}]"#)
    }

    @Test("resposta adulterada é rejeitada")
    func rejectsTamperedResponse() {
        #expect(throws: (any Error).self) {
            try TuyaSharingCrypto.decrypt(
                "UFFSU1RXWFlaYWJjcv8Dihh6Jdu5o4zqKeDvmhyGBSMDMocXXtje60LJC6/QW1qzVXyoZgHLSjNGOwA=",
                secret: "6ed4dc779d9ede46"
            )
        }
    }
}

/// Servidor falso que responde como a Tuya: login por QR em texto e o resto cifrado
/// com a chave derivada do `X-requestId` de cada requisição.
private final class FakeTuyaServer: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    var loginConfirmed = false
    var requests: [URLRequest] { lock.withLock { _requests } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { _requests.append(request) }
        let url = try #require(request.url)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let path = url.path

        if path == "/v1.0/m/life/home-assistant/qrcode/tokens" {
            return (Data(#"{"success":true,"t":1,"result":{"qrcode":"qr-ficticio"}}"#.utf8), response)
        }
        if path == "/v1.0/m/life/home-assistant/qrcode/tokens/qr-ficticio" {
            let body = loginConfirmed
                ? #"{"success":true,"t":1700000000000,"result":{"access_token":"access-ficticio","refresh_token":"refresh-ficticio","expire_time":7200,"uid":"uid-ficticio","endpoint":"https://apigw.tuyaus.com","terminal_id":"terminal-ficticio","username":"x"}}"#
                : #"{"success":false,"code":1,"msg":"not scanned"}"#
            return (Data(body.utf8), response)
        }

        let requestID = request.value(forHTTPHeaderField: "X-requestId") ?? ""
        let secret = TuyaSharingCrypto.keys(requestID: requestID, refreshToken: "refresh-ficticio").secret
        let plain: String
        switch path {
        case "/v1.0/m/life/users/homes":
            plain = #"[{"ownerId":987,"name":"Casa"}]"#
        case "/v1.0/m/life/ha/home/devices":
            let encdata = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "encdata" }?.value)
            let query = String(decoding: try TuyaSharingCrypto.decryptRequest(encdata, secret: secret), as: UTF8.self)
            #expect(query == #"{"homeId":"987"}"#)
            plain = #"[{"id":"dev-ficticio","name":"ac quarto","local_key":"chave-ficticia","category":"kt","product_id":"gncaqbnuk4cj2etp","product_name":"Smart air conditioner","online":true,"sub":false,"uuid":"u","asset_id":"a","icon":"i","ip":"1.2.3.4","time_zone":"-03:00","active_time":1,"create_time":1,"update_time":1,"status":[]}]"#
        default:
            Issue.record("rota inesperada: \(path)")
            plain = "[]"
        }
        let nonce = Array("PQRSTWXYZabc".utf8)
        let sealed = try TuyaSharingCrypto.sealForTesting(Data(plain.utf8), secret: secret, nonce: nonce)
        let body = #"{"success":true,"t":1,"result":"\#(sealed)"}"#
        return (Data(body.utf8), response)
    }
}

@Suite("Login por QR do Smart Life: fluxo")
struct TuyaSharingClientTests {
    @Test("pede o QR com o código de usuário e monta o conteúdo que o Smart Life lê")
    func requestsQRCode() async throws {
        let server = FakeTuyaServer()
        let login = try await TuyaSharingClient(transport: server).requestQRCode(userCode: "codigo123")

        #expect(login.qrContent == "tuyaSmart--qrLogin?token=qr-ficticio")
        let request = try #require(server.requests.first)
        #expect(request.httpMethod == "POST")
        let query = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "usercode", value: "codigo123")))
        #expect(query.contains(URLQueryItem(name: "schema", value: "haauthorize")))
    }

    @Test("enquanto o QR não é confirmado no celular, o login ainda não existe")
    func loginPendingUntilConfirmed() async throws {
        let server = FakeTuyaServer()
        let client = TuyaSharingClient(transport: server)
        let login = try await client.requestQRCode(userCode: "codigo123")

        #expect(try await client.session(for: login, userCode: "codigo123") == nil)
        server.loginConfirmed = true
        let session = try #require(try await client.session(for: login, userCode: "codigo123"))
        #expect(session.endpoint == "https://apigw.tuyaus.com")
        #expect(session.refreshToken == "refresh-ficticio")
    }

    @Test("lista os aparelhos de todas as casas, com a chave local")
    func listsDevicesWithLocalKey() async throws {
        let server = FakeTuyaServer()
        server.loginConfirmed = true
        let client = TuyaSharingClient(transport: server)
        let login = try await client.requestQRCode(userCode: "codigo123")
        let session = try #require(try await client.session(for: login, userCode: "codigo123"))

        let devices = try await client.devices(session: session)

        #expect(devices == [TuyaCloudDevice(
            id: "dev-ficticio",
            name: "ac quarto",
            localKey: "chave-ficticia",
            category: "kt",
            productID: "gncaqbnuk4cj2etp",
            productName: "Smart air conditioner",
            isOnline: true
        )])
        let devicesRequest = try #require(server.requests.last)
        #expect(devicesRequest.value(forHTTPHeaderField: "X-token") == "access-ficticio")
        #expect(devicesRequest.value(forHTTPHeaderField: "X-sign")?.count == 64)
    }
}

@Suite("Aparelhos da conta")
struct TuyaCloudDeviceTests {
    @Test("categorias de ar-condicionado da Tuya são reconhecidas", arguments: [
        ("kt", true),
        ("ktkzq", true),
        ("cz", false),
        ("dj", false),
    ])
    func recognizesAirConditioners(category: String, expected: Bool) {
        let device = TuyaCloudDevice(id: "d", name: "n", localKey: "k", category: category, productID: "p", productName: "x", isOnline: true)
        #expect(device.isAirConditioner == expected)
    }
}

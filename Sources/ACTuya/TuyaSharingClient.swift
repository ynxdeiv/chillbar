import Foundation

/// QR code de login: o Smart Life lê `qrContent` e o usuário confirma no celular.
public struct TuyaQRLogin: Sendable, Equatable {
    public let token: String

    public init(token: String) {
        self.token = token
    }
    public var qrContent: String { "tuyaSmart--qrLogin?token=\(token)" }
}

/// Sessão obtida após o usuário confirmar o QR. Usada só durante a configuração.
public struct TuyaSharingSession: Sendable, Equatable, Codable {
    public let accessToken: String
    public let refreshToken: String
    public let uid: String
    public let endpoint: String
    public let terminalID: String
}

/// Aparelho da conta Smart Life, com a chave para controle local.
public struct TuyaCloudDevice: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let localKey: String
    public let category: String
    public let productID: String
    public let productName: String
    public let isOnline: Bool

    public init(id: String, name: String, localKey: String, category: String, productID: String, productName: String, isOnline: Bool) {
        self.id = id
        self.name = name
        self.localKey = localKey
        self.category = category
        self.productID = productID
        self.productName = productName
        self.isOnline = isOnline
    }
}

public enum TuyaSharingError: Error, Equatable {
    case api(code: Int, message: String)
    case invalidResponse
}

/// Login por QR do Smart Life e leitura das chaves locais, sem conta de desenvolvedor.
///
/// Usa o SDK oficial de compartilhamento da Tuya (`tuya-device-sharing-sdk`, MIT) com o
/// cadastro público do Home Assistant, como outras ferramentas open source. Se a Tuya
/// restringir esse cadastro, a configuração avançada (Access ID/Secret) continua disponível.
public struct TuyaSharingClient: Sendable {
    static let loginHost = "https://apigw.iotbing.com"
    static let clientID = "HA_3y9q4ak7g4ephrvke"
    static let schema = "haauthorize"

    private let transport: any HTTPTransport
    private let now: @Sendable () -> Date

    public init(transport: any HTTPTransport = URLSessionTransport(), now: @escaping @Sendable () -> Date = Date.init) {
        self.transport = transport
        self.now = now
    }

    public func requestQRCode(userCode: String) async throws -> TuyaQRLogin {
        let url = try Self.url(
            Self.loginHost + "/v1.0/m/life/home-assistant/qrcode/tokens",
            query: [("clientid", Self.clientID), ("usercode", userCode), ("schema", Self.schema)]
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let json = try await sendJSON(request)
        guard let result = json["result"] as? [String: Any], let token = result["qrcode"] as? String else {
            throw Self.error(from: json)
        }
        return TuyaQRLogin(token: token)
    }

    /// `nil` enquanto o usuário ainda não confirmou no celular.
    public func session(for login: TuyaQRLogin, userCode: String) async throws -> TuyaSharingSession? {
        let url = try Self.url(
            Self.loginHost + "/v1.0/m/life/home-assistant/qrcode/tokens/\(login.token)",
            query: [("clientid", Self.clientID), ("usercode", userCode)]
        )
        let json = try await sendJSON(URLRequest(url: url))
        guard json["success"] as? Bool == true else { return nil }
        guard let result = json["result"] as? [String: Any],
              let accessToken = result["access_token"] as? String,
              let refreshToken = result["refresh_token"] as? String,
              let endpoint = result["endpoint"] as? String
        else { throw TuyaSharingError.invalidResponse }
        return TuyaSharingSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            uid: result["uid"] as? String ?? "",
            endpoint: endpoint,
            terminalID: result["terminal_id"] as? String ?? ""
        )
    }

    /// Todos os aparelhos de todas as casas da conta.
    public func devices(session: TuyaSharingSession) async throws -> [TuyaCloudDevice] {
        let homes = try await get("/v1.0/m/life/users/homes", params: nil, session: session) as? [[String: Any]] ?? []
        var devices: [TuyaCloudDevice] = []
        for home in homes {
            guard let ownerID = home["ownerId"].map({ "\($0)" }) else { continue }
            let items = try await get("/v1.0/m/life/ha/home/devices", params: ["homeId": ownerID], session: session)
            for item in items as? [[String: Any]] ?? [] {
                guard let id = item["id"] as? String, let localKey = item["local_key"] as? String else { continue }
                devices.append(TuyaCloudDevice(
                    id: id,
                    name: item["name"] as? String ?? id,
                    localKey: localKey,
                    category: item["category"] as? String ?? "",
                    productID: item["product_id"] as? String ?? "",
                    productName: item["product_name"] as? String ?? "",
                    isOnline: item["online"] as? Bool ?? false
                ))
            }
        }
        return devices
    }

    // MARK: Requisições assinadas e cifradas

    private func get(_ path: String, params: [String: String]?, session: TuyaSharingSession) async throws -> Any {
        let requestID = UUID().uuidString.lowercased()
        let keys = TuyaSharingCrypto.keys(requestID: requestID, refreshToken: session.refreshToken)

        var queryEncdata = ""
        if let params, !params.isEmpty {
            let json = String(decoding: try JSONSerialization.data(withJSONObject: params, options: [.sortedKeys]), as: UTF8.self)
            queryEncdata = try TuyaSharingCrypto.encrypt(json, secret: keys.secret, nonce: TuyaSharingCrypto.randomNonce())
        }

        let headers = [
            ("X-appKey", Self.clientID),
            ("X-requestId", requestID),
            ("X-sid", ""),
            ("X-time", String(Int64(now().timeIntervalSince1970 * 1000))),
            ("X-token", session.accessToken),
        ]
        var request = URLRequest(url: try Self.url(
            session.endpoint + path,
            query: queryEncdata.isEmpty ? [] : [("encdata", queryEncdata)]
        ))
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue(
            TuyaSharingCrypto.sign(hashKey: keys.hashKey, headers: headers, queryEncdata: queryEncdata, bodyEncdata: ""),
            forHTTPHeaderField: "X-sign"
        )

        let json = try await sendJSON(request)
        guard json["success"] as? Bool == true else { throw Self.error(from: json) }
        guard let encrypted = json["result"] as? String, !encrypted.isEmpty else { return [Any]() }
        let plain = try TuyaSharingCrypto.decrypt(encrypted, secret: keys.secret)
        return try JSONSerialization.jsonObject(with: plain)
    }

    private func sendJSON(_ request: URLRequest) async throws -> [String: Any] {
        var request = request
        request.timeoutInterval = 15
        let (data, _) = try await transport.send(request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TuyaSharingError.invalidResponse
        }
        return json
    }

    private static func url(_ base: String, query: [(String, String)]) throws -> URL {
        let queryString = query.map { "\($0.0)=\($0.1.urlQueryEncoded)" }.joined(separator: "&")
        guard let url = URL(string: queryString.isEmpty ? base : "\(base)?\(queryString)") else {
            throw URLError(.badURL)
        }
        return url
    }

    private static func error(from json: [String: Any]) -> TuyaSharingError {
        let code = (json["code"] as? Int) ?? Int("\(json["code"] ?? "")") ?? 0
        return .api(code: code, message: json["msg"] as? String ?? "")
    }
}

extension TuyaCloudDevice {
    /// Categorias da Tuya para ar-condicionado (`kt`) e controlador de ar (`ktkzq`).
    public var isAirConditioner: Bool {
        ["kt", "ktkzq"].contains(category)
    }
}

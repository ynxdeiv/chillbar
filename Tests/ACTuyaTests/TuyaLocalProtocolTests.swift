import Foundation
import Testing
@testable import ACTuya

// Vetores gerados com o tinytuya (protocolo 3.3) usando chave e ID fictícios.
private let key = Data("0123456789abcdef".utf8)
private let deviceID = "testdevice22charsxxxxx"

private func hex(_ string: String) -> Data {
    var data = Data()
    var index = string.startIndex
    while index < string.endIndex {
        let next = string.index(index, offsetBy: 2)
        data.append(UInt8(string[index..<next], radix: 16)!)
        index = next
    }
    return data
}

private func json(_ data: Data) throws -> NSDictionary {
    try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
}

@Suite("Protocolo local Tuya 3.3")
struct TuyaLocalProtocolTests {
    let codec = TuyaLocalCodec(localKey: key)

    @Test("comando de controle: cabeçalho 3.3 + AES, igual ao tinytuya")
    func encodesControl() {
        let payload = TuyaLocalCodec.json(["devId": deviceID, "dps": ["2": 260], "t": "1700000000", "uid": deviceID])
        let frame = codec.encode(command: .control, payload: payload, sequence: 1)
        #expect(frame == hex("000055aa000000010000000700000087332e330000000000000000000000000d6545c9afde6f8747f491b90fc111ff676fabfca690418f2ed7df6775b0863afb89d09dc0b8f1e8dbba39e1705fd35803c63c0accb627cb97215642cc424beb2408f2ec888b0b45e2bfeb710bd4b6f4676fabfca690418f2ed7df6775b0863a0efea48a0091daa595a3a780fe13bd0e4021f9410000aa55"))
    }

    @Test("consulta de estado: sem cabeçalho de versão")
    func encodesQuery() {
        let payload = TuyaLocalCodec.json(["devId": deviceID, "gwId": deviceID, "t": "1700000000", "uid": deviceID])
        let frame = codec.encode(command: .dpQuery, payload: payload, sequence: 2)
        #expect(frame == hex("000055aa000000020000000a000000880d6545c9afde6f8747f491b90fc111ff676fabfca690418f2ed7df6775b0863a2029adee0cbc2b2949c57d6f71dc1350676fabfca690418f2ed7df6775b0863a49b9c47a3d78df0d20268e27f855ae022408f2ec888b0b45e2bfeb710bd4b6f4676fabfca690418f2ed7df6775b0863a0efea48a0091daa595a3a780fe13bd0e24287e630000aa55"))
    }

    @Test("batimento (heartbeat): sem cabeçalho de versão")
    func encodesHeartbeat() {
        let payload = TuyaLocalCodec.json(["devId": deviceID, "gwId": deviceID])
        let frame = codec.encode(command: .heartbeat, payload: payload, sequence: 3)
        #expect(frame == hex("000055aa0000000300000009000000580d6545c9afde6f8747f491b90fc111ff676fabfca690418f2ed7df6775b0863a2029adee0cbc2b2949c57d6f71dc1350676fabfca690418f2ed7df6775b0863a0efea48a0091daa595a3a780fe13bd0ec7ea6f3f0000aa55"))
    }

    @Test("consulta para IDs de 22 caracteres (CONTROL_NEW com dps nulos)")
    func encodesDevice22Query() {
        let payload = TuyaLocalCodec.json(["devId": deviceID, "dps": ["1": NSNull()], "t": "1700000000", "uid": deviceID])
        let frame = codec.encode(command: .controlNew, payload: payload, sequence: 4)
        #expect(frame == hex("000055aa000000040000000d00000087332e330000000000000000000000000d6545c9afde6f8747f491b90fc111ff676fabfca690418f2ed7df6775b0863ac514004b1250788cbadeb4061108a425c493a5f40e1abd1f559652c61d38b06c5c9fd68bdf08c101a265075db6085b2d39a995c8549ef04850839809844771ac823fe695ed33ad482effefe8a3a54b692b65fe9b0000aa55"))
    }

    @Test("lê o aviso de mudança enviado pelo aparelho (com cabeçalho 3.3)")
    func decodesStatusPush() throws {
        var buffer = TuyaFrameBuffer()
        buffer.append(hex("000055aa00000007000000080000004b00000000332e33000000000000000000000000f86472d3593e77a2aa34a479d37ebe1b0805e40e58badf589dcea26d5829a88083d83e5c57f74ec0b057c6f26d2b9b603fb715ac0000aa55"))
        let frame = try #require(try buffer.nextFrame())

        #expect(frame.command == TuyaCommand.status.rawValue)
        #expect(frame.returnCode == 0)
        #expect(try json(try codec.decrypt(frame)) == ["dps": ["2": 250, "3": 230], "t": 1700000001])
    }

    @Test("lê a resposta da consulta (sem cabeçalho 3.3)")
    func decodesQueryResponse() throws {
        var buffer = TuyaFrameBuffer()
        buffer.append(hex("000055aa000000020000000a0000005c000000000d6545c9afde6f8747f491b90fc111ff676fabfca690418f2ed7df6775b0863a2125e1846bd4f824d1b2e468c23992668b147eb7436545a6883320bbcb700a941a27ef0d064856e540ad7f1020b7ffdffc68019d0000aa55"))
        let frame = try #require(try buffer.nextFrame())

        #expect(try json(try codec.decrypt(frame)) == ["devId": deviceID, "dps": ["1": true, "2": 250, "4": "cold"]])
    }

    @Test("reconhece o 'data unvalid' dos aparelhos que exigem a consulta alternativa")
    func detectsDataUnvalid() throws {
        var buffer = TuyaFrameBuffer()
        buffer.append(hex("000055aa000000020000000a0000002c000000018cd3914133e1552e781df7a7dcde56e97204d3b73bef1d848be753291d91804baf3e11240000aa55"))
        let frame = try #require(try buffer.nextFrame())

        #expect(String(decoding: try codec.decrypt(frame), as: UTF8.self) == "json obj data unvalid")
    }

    @Test("confirmação vazia do aparelho")
    func decodesEmptyAck() throws {
        var buffer = TuyaFrameBuffer()
        buffer.append(hex("000055aa00000001000000070000000c00000000a505a9140000aa55"))
        let frame = try #require(try buffer.nextFrame())

        #expect(frame.command == TuyaCommand.control.rawValue)
        #expect(try codec.decrypt(frame).isEmpty)
    }

    @Test("mensagem adulterada (CRC errado) é rejeitada")
    func rejectsBadCRC() {
        var buffer = TuyaFrameBuffer()
        buffer.append(hex("000055aa00000001000000070000000c00000000a505a9150000aa55"))
        #expect(throws: TuyaProtocolError.badChecksum) { try buffer.nextFrame() }
    }

    @Test("junta mensagens que chegam picadas e separa as que chegam grudadas")
    func reassemblesStream() throws {
        let ack = hex("000055aa00000001000000070000000c00000000a505a9140000aa55")
        let push = hex("000055aa00000007000000080000004b00000000332e33000000000000000000000000f86472d3593e77a2aa34a479d37ebe1b0805e40e58badf589dcea26d5829a88083d83e5c57f74ec0b057c6f26d2b9b603fb715ac0000aa55")
        let stream = ack + push
        var buffer = TuyaFrameBuffer()

        buffer.append(stream.prefix(10))
        #expect(try buffer.nextFrame() == nil)
        buffer.append(stream.dropFirst(10).prefix(40))
        #expect(try buffer.nextFrame()?.command == 7)
        #expect(try buffer.nextFrame() == nil)
        buffer.append(stream.dropFirst(50))
        #expect(try buffer.nextFrame()?.command == 8)
        #expect(try buffer.nextFrame() == nil)
    }

    @Test("decifra o anúncio de descoberta na rede (UDP 6667)")
    func decodesDiscovery() throws {
        let datagram = hex("000055aa0000000000000013000000ac000000003147c936e9a73aeeff2f4dab0b33499fc76c5adcce3ca655eb2a7e021c57ee1914ccdc69da6f52716f1f7d23a35bb1208b0c6f93a44b789d48244758ebb814f7e37e2491786d8b6efd633e04a61168de172030a98473512a8e23a0d37ed26e6132e8ef8621f63a363795b5e3cdc7ec536c9477537a0b433d14905a23fea05de2beeb735778176a1e477255d1f238a3ca384363dcd0f0705ae4cac595bbf496252bbef0600000aa55")

        let found = try #require(TuyaDiscovery.decode(datagram))

        #expect(found == TuyaDiscoveredDevice(id: deviceID, ip: "192.168.1.50", version: "3.3", productKey: "gncaqbnuk4cj2etp"))
    }

    @Test("datagrama de outro tipo é ignorado na descoberta")
    func ignoresGarbageDiscovery() {
        #expect(TuyaDiscovery.decode(Data("hello".utf8)) == nil)
    }
}

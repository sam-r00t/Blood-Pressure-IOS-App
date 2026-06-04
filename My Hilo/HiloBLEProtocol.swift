import Foundation

enum HiloBLEProtocol {
    static let lockedPeripheralID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    static let currentTimeServiceUUID = "1805"
    static let currentTimeCharacteristicUUID = "2A2B"
    static let batteryServiceUUID = "180F"
    static let batteryLevelCharacteristicUUID = "2A19"

    static let primaryServiceUUID = "A6B41001-003D-4E65-9208-08F4DB958863"
    static let primaryDataCharacteristicUUID = "A6B41002-003D-4E65-9208-08F4DB958863"
    static let podControlPointCharacteristicUUID = "A6B41005-003D-4E65-9208-08F4DB958863"
    static let numberOfFramesCharacteristicUUID = "A6B41003-003D-4E65-9208-08F4DB958863"

    static let fe59ServiceUUID = "FE59"
    static let contextualisationServiceUUID = "8EC90001-F315-4F60-9FB8-838830DAEA50"
    static let contextualisationInputCharacteristicUUID = "8EC90002-F315-4F60-9FB8-838830DAEA50"
    static let contextualisationOutputCharacteristicUUID = "8EC90003-F315-4F60-9FB8-838830DAEA50"

    static let optionalDD890004CharacteristicUUID_BCE5 = "DD890004-BCE5-4D8A-8AF8-9B2125D125A5"
    static let optionalDD890005CharacteristicUUID_BCE5 = "DD890005-BCE5-4D8A-8AF8-9B2125D125A5"
    static let optionalDD890004CharacteristicUUID = "DD890004-2BAF-4F20-969F-0CA8DDA5A7B7"
    static let optionalDD890005CharacteristicUUID = "DD890005-2BAF-4F20-969F-0CA8DDA5A7B7"
}

struct HiloCuffMeasurement: Equatable {
    let systolic: Int
    let diastolic: Int
    let mean: Int
    let heartRate: Int
    let firmwareRevision: Int?
    let serialNumber: Int?
}

enum HiloCuffPacketDecoder {
    static func decode(_ payload: Data) -> HiloCuffMeasurement? {
        let bytes = [UInt8](payload)
        if bytes.count >= 12 {
            let sys = Int(littleEndianUInt16(bytes[0], bytes[1]))
            let dia = Int(littleEndianUInt16(bytes[2], bytes[3]))
            let mean = Int(littleEndianUInt16(bytes[4], bytes[5]))
            let hr = Int(bytes[6])
            guard plausible(sys: sys, dia: dia, mean: mean, hr: hr) else { return nil }

            let fw = Int(bytes[7])
            let serial = Int(littleEndianUInt32(bytes[8], bytes[9], bytes[10], bytes[11]))
            return HiloCuffMeasurement(
                systolic: sys,
                diastolic: dia,
                mean: mean,
                heartRate: hr,
                firmwareRevision: fw,
                serialNumber: serial
            )
        }

        if bytes.count >= 4 {
            let sys = Int(bytes[0])
            let dia = Int(bytes[1])
            let mean = Int(bytes[2])
            let hr = Int(bytes[3])
            guard plausible(sys: sys, dia: dia, mean: mean, hr: hr) else { return nil }
            return HiloCuffMeasurement(
                systolic: sys,
                diastolic: dia,
                mean: mean,
                heartRate: hr,
                firmwareRevision: nil,
                serialNumber: nil
            )
        }

        return nil
    }

    private static func plausible(sys: Int, dia: Int, mean: Int, hr: Int) -> Bool {
        guard (80...220).contains(sys), (40...140).contains(dia), dia < sys else { return false }
        guard (50...180).contains(mean), dia <= mean, mean <= sys else { return false }
        return (35...220).contains(hr)
    }

    private static func littleEndianUInt16(_ b0: UInt8, _ b1: UInt8) -> UInt16 {
        UInt16(b0) | (UInt16(b1) << 8)
    }

    private static func littleEndianUInt32(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8, _ b3: UInt8) -> UInt32 {
        UInt32(b0) | (UInt32(b1) << 8) | (UInt32(b2) << 16) | (UInt32(b3) << 24)
    }
}

#if DEBUG
enum HiloCuffPacketDecoderTests {
    static func run() {
        let payloadLE = Data([0x78, 0x00, 0x4E, 0x00, 0x61, 0x00, 0x44, 0x09, 0x39, 0x30, 0x00, 0x00])
        let decodedLE = HiloCuffPacketDecoder.decode(payloadLE)
        assert(decodedLE == HiloCuffMeasurement(
            systolic: 120,
            diastolic: 78,
            mean: 97,
            heartRate: 68,
            firmwareRevision: 9,
            serialNumber: 12345
        ))

        let payloadU8 = Data([118, 76, 92, 61])
        let decodedU8 = HiloCuffPacketDecoder.decode(payloadU8)
        assert(decodedU8 == HiloCuffMeasurement(
            systolic: 118,
            diastolic: 76,
            mean: 92,
            heartRate: 61,
            firmwareRevision: nil,
            serialNumber: nil
        ))
    }
}
#endif

enum AktiiaTimestampDecoder {

    static let aktiiaEpoch: TimeInterval = 1327410887

    static func decode(from payload: Data, characteristicUUID: String? = nil) -> Date? {

        return nil
    }
}

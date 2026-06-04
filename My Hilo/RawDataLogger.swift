import CoreBluetooth
import Foundation

final class RawDataLogger {
    private let dateFormatter: ISO8601DateFormatter
    private let fileStore: LogFileStore
    private var sequenceByCharacteristic: [CharacteristicKey: Int] = [:]

    init(fileStore: LogFileStore) {
        self.fileStore = fileStore

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withColonSeparatorInTimeZone]
        dateFormatter = formatter
    }

    var logFileURL: URL {
        fileStore.url
    }

    func log(_ category: String, _ lines: [String], timestamp: Date = Date(), consoleOnly: Bool = false) {
        let header = "[BLE][\(category)][\(dateFormatter.string(from: timestamp))]"
        let block = ([header] + lines).joined(separator: "\n") + "\n\n"
        print(block)
        if !consoleOnly {
            fileStore.append(block)
        }
    }

    func logAdvertisement(
        peripheralName: String,
        peripheralID: UUID,
        rssi: Int,
        advertisementData: [String: Any]
    ) {
        let keys = advertisementData.keys.sorted().joined(separator: ",")
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            .map { $0.uuidString }
            .joined(separator: ",")
        let manufacturerDataHex = Self.hexString(advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)

        log("ADV", [
            "peripheral: \(peripheralName) (id: \(peripheralID.uuidString))",
            "rssi: \(rssi)",
            "adv.keys: [\(keys)]",
            "adv.serviceUUIDs: [\(serviceUUIDs)]",
            "adv.manufacturerData.hex: \(manufacturerDataHex)"
        ])
    }

    func logDiscoverySnapshot(peripheral: CBPeripheral, consoleOnly: Bool = false) {
        let services = peripheral.services ?? []
        var lines: [String] = [
            "peripheral: \(displayName(for: peripheral)) (id: \(peripheral.identifier.uuidString))",
            "services.count: \(services.count)"
        ]

        for service in services {
            let characteristics = service.characteristics ?? []
            let parts = characteristics.map { char in
                "\(char.uuid.uuidString)(\(Self.propertiesString(for: char.properties)))"
            }
            lines.append("service \(service.uuid.uuidString) chars: \(parts.joined(separator: ", "))")
        }

        log("DISCOVERY", lines, consoleOnly: consoleOnly)
    }

    func logCharacteristicUpdate(
        peripheral: CBPeripheral,
        service: CBService,
        characteristic: CBCharacteristic,
        value: Data,
        consoleOnly: Bool = false
    ) {
        let key = CharacteristicKey(
            peripheralID: peripheral.identifier,
            serviceUUID: service.uuid,
            characteristicUUID: characteristic.uuid
        )
        let seq = nextSequence(for: key)

        let maybeHRFrame = characteristic.uuid == CBUUID(string: "2A37") ? "yes" : "no"

        log("VALUE", [
            "sequence: \(seq)",
            "peripheral: \(displayName(for: peripheral)) (id: \(peripheral.identifier.uuidString))",
            "service: \(service.uuid.uuidString)",
            "characteristic: \(characteristic.uuid.uuidString) props: [\(Self.propertiesString(for: characteristic.properties))]",
            "len: \(value.count)",
            "hex:  \(Self.hexString(value))",
            "bytes: \(Self.decimalByteArray(value))",
            "ascii: \(Self.asciiGuess(value))",
            "maybeHRFrame(2A37): \(maybeHRFrame)"
        ], consoleOnly: consoleOnly)
    }

    func logError(_ message: String) {
        log("ERROR", [message])
    }

    func tailLines(_ count: Int) -> String {
        fileStore.tailLines(count)
    }

    private func nextSequence(for key: CharacteristicKey) -> Int {
        let next = (sequenceByCharacteristic[key] ?? 0) + 1
        sequenceByCharacteristic[key] = next
        return next
    }

    private func displayName(for peripheral: CBPeripheral) -> String {
        peripheral.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? peripheral.name ?? "Unknown"
            : "Unknown"
    }

    static func propertiesString(for properties: CBCharacteristicProperties) -> String {
        var labels: [String] = []
        if properties.contains(.read) { labels.append("read") }
        if properties.contains(.notify) { labels.append("notify") }
        if properties.contains(.indicate) { labels.append("indicate") }
        if properties.contains(.write) { labels.append("write") }
        if properties.contains(.writeWithoutResponse) { labels.append("writeWithoutResponse") }
        if properties.contains(.broadcast) { labels.append("broadcast") }
        if properties.contains(.authenticatedSignedWrites) { labels.append("authSignedWrite") }
        if properties.contains(.extendedProperties) { labels.append("extended") }
        if properties.contains(.notifyEncryptionRequired) { labels.append("notifyEncrypted") }
        if properties.contains(.indicateEncryptionRequired) { labels.append("indicateEncrypted") }

        return labels.isEmpty ? "none" : labels.joined(separator: ",")
    }

    static func hexString(_ data: Data?) -> String {
        guard let data else { return "<none>" }
        guard !data.isEmpty else { return "<empty>" }
        return data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    static func decimalByteArray(_ data: Data) -> String {
        "[\(data.map { String($0) }.joined(separator: ","))]"
    }

    static func asciiGuess(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }
        return data.map { byte in
            if byte >= 32, byte <= 126 {
                return String(UnicodeScalar(byte))
            }
            return "."
        }.joined()
    }
}

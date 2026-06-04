import CoreBluetooth
import Foundation

struct RawBLEFrame {
    let peripheralID: UUID
    let serviceUUID: String
    let characteristicUUID: String
    let timestamp: Date
    let deviceTimestamp: Date?
    let payload: Data
    let characteristicProperties: CBCharacteristicProperties
}

struct BPMeasurement: Identifiable, Equatable {
    let id: String
    let timestamp: Date
    let systolic: Int
    let diastolic: Int
    let heartRate: Int?
    let source: String
}

struct DiscoveredPeripheral: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
    let lastSeen: Date
    let isPreLocked: Bool
}

struct CharacteristicKey: Hashable {
    let peripheralID: UUID
    let serviceUUID: CBUUID
    let characteristicUUID: CBUUID
}

struct ExplorationWriteResult {
    let writeType: String
    let errorMessage: String?
}

struct ReadCharacteristicResult {
    let value: Data?
    let errorMessage: String?
}

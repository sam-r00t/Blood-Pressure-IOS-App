import Foundation
import CoreBluetooth
import Combine

struct DiscoveredCuff: Identifiable, Equatable {
    let id: UUID
    let peripheral: CBPeripheral
    let name: String
    let rssi: Int
}

@MainActor
protocol CuffBLEManagerDelegate: AnyObject {
    func cuffManagerDidUpdateState(_ manager: CuffBLEManager, isPoweredOn: Bool)
    func cuffManagerDidDiscoverCuff(_ manager: CuffBLEManager, name: String)
    func cuffManagerDidConnect(_ manager: CuffBLEManager)
    func cuffManagerDidDisconnect(_ manager: CuffBLEManager, error: Error?)
    func cuffManagerDidReceiveMeasurement(_ manager: CuffBLEManager, systolic: Int, diastolic: Int, mean: Int, hr: Int)
    func cuffManagerDidReceiveError(_ manager: CuffBLEManager, reason: String)
}

final class CuffBLEManager: NSObject, ObservableObject {
    private var centralManager: CBCentralManager!
    private var cuffPeripheral: CBPeripheral?
    private var measurementCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?

    @Published var isConnected: Bool = false
    @Published var isScanning: Bool = false
    @Published var discoveredCuffs: [DiscoveredCuff] = []
    @Published var currentLogs: String = ""

    private var activeMeasurementContinuation: CheckedContinuation<(sys: Int, dia: Int, hr: Int, logs: String, rawCuffHex: String), Error>?

    weak var delegate: CuffBLEManagerDelegate?

    let MEASUREMENT_UUID_SERVICE = CBUUID(string: "B1E71568-047B-47C4-88C9-0F90E397ACF7")
    let MEASUREMENT_UUID = CBUUID(string: "A6B40002-003D-4E65-9208-08F4DB958863")
    let MEASUREMENT_STATUS_UUID = CBUUID(string: "A6B40003-003D-4E65-9208-08F4DB958863")

    private var pendingMeasurement: CuffMeasurement?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    private func log(_ message: String) {
        let ts = Date().formatted(date: .omitted, time: .standard)
        let formatted = "[\(ts)] \(message)"
        print("[CUFF] \(message)")
        DispatchQueue.main.async { [weak self] in
            if let logs = self?.currentLogs {
                self?.currentLogs = logs.isEmpty ? formatted : logs + "\n" + formatted
            }
        }
    }

    func startScanForCuff() {
        guard centralManager.state == .poweredOn else {
            log("Cannot start scan, central manager state is \(centralManager.state.rawValue)")
            return
        }

        log("Starting unfiltered scan for Aktiia cuff (name prefix 'AKTIIA C' / 'OTA_')")
        isScanning = true
        discoveredCuffs.removeAll()
        centralManager.scanForPeripherals(withServices: nil, options: nil)
    }

    func stopScan() {
        log("Stopping scan")
        isScanning = false
        centralManager.stopScan()
    }

    func connect(to id: UUID? = nil) {
        let target: CBPeripheral?
        if let id = id {
            target = discoveredCuffs.first(where: { $0.id == id })?.peripheral
        } else {
            target = cuffPeripheral ?? discoveredCuffs.first?.peripheral
        }

        guard let cuff = target else { return }
        cuffPeripheral = cuff
        log("Connecting to \(cuff.name ?? "Unknown Cuff")")
        centralManager.connect(cuff, options: nil)
    }

    func disconnect() {
        if let cuff = cuffPeripheral {
            log("Disconnecting")
            centralManager.cancelPeripheralConnection(cuff)
        }
        if let cont = activeMeasurementContinuation {
            activeMeasurementContinuation = nil
            cont.resume(throwing: NSError(domain: "CuffBLEManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Disconnected during measurement."]))
        }
    }

    func startMeasurementOnDemand() {
        DispatchQueue.main.async { self.currentLogs = "" }
        guard let cuff = cuffPeripheral, let measurementChar = measurementCharacteristic else {
            log("Cannot start measurement - Cuff or Measurement Characteristic not ready!")
            Task { @MainActor in delegate?.cuffManagerDidReceiveError(self, reason: "Cuff not ready") }
            return
        }

        log("Triggering On-Demand Measurement by enabling notifications on \(measurementChar.uuid)")

        cuff.setNotifyValue(true, for: measurementChar)
    }

    private var lastRawMeasurementBytes: String = ""
    private var lastRawStatusBytes: String = ""

    func measureOnce() async throws -> (sys: Int, dia: Int, hr: Int, logs: String, rawCuffHex: String) {
        if activeMeasurementContinuation != nil {
            throw NSError(domain: "CuffBLEManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Measurement already in progress"])
        }

        lastRawMeasurementBytes = ""
        lastRawStatusBytes = ""
        startMeasurementOnDemand()

        return try await withCheckedThrowingContinuation { continuation in

            self.activeMeasurementContinuation = continuation
        }
    }

    func stopMeasurement() {
        guard let cuff = cuffPeripheral, let measurementChar = measurementCharacteristic else { return }
        if measurementChar.isNotifying {
            cuff.setNotifyValue(false, for: measurementChar)
        }
    }
}

extension CuffBLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let poweredOn = central.state == .poweredOn
        log("Central Manager state updated: \(central.state.rawValue), poweredOn: \(poweredOn)")
        Task { @MainActor in delegate?.cuffManagerDidUpdateState(self, isPoweredOn: poweredOn) }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Unknown"

        let upperName = name.uppercased()
        guard upperName.hasPrefix("AKTIIA C") || upperName.hasPrefix("OTA_") else { return }

        log("Discovered target cuff: \(name) with RSSI: \(RSSI)")

        if !discoveredCuffs.contains(where: { $0.id == peripheral.identifier }) {
            discoveredCuffs.append(DiscoveredCuff(id: peripheral.identifier, peripheral: peripheral, name: name, rssi: RSSI.intValue))
            discoveredCuffs.sort(by: { $0.rssi > $1.rssi })
        }

        cuffPeripheral = peripheral

        stopScan()

        Task { @MainActor in delegate?.cuffManagerDidDiscoverCuff(self, name: name) }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("Connected to \(peripheral.name ?? "Unknown Cuff"). Discovering services...")
        peripheral.delegate = self
        peripheral.discoverServices([MEASUREMENT_UUID_SERVICE])
        Task { @MainActor in
            self.isConnected = true
            delegate?.cuffManagerDidConnect(self)
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log("Disconnected. Error: \(error?.localizedDescription ?? "None")")
        if peripheral == cuffPeripheral {
            measurementCharacteristic = nil
            statusCharacteristic = nil
            Task { @MainActor in
                self.isConnected = false
                delegate?.cuffManagerDidDisconnect(self, error: error)
            }
        }
    }
}

extension CuffBLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error { log("Error discovering services: \(error)"); return }
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == MEASUREMENT_UUID_SERVICE {
            log("Found Target Service \(service.uuid). Discovering Characteristics...")
            peripheral.discoverCharacteristics([MEASUREMENT_UUID, MEASUREMENT_STATUS_UUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error { log("Error discovering characteristics: \(error)"); return }
        guard let characteristics = service.characteristics else { return }
        for char in characteristics {
            log("Found characteristic: \(char.uuid)")
            if char.uuid == MEASUREMENT_UUID {
                measurementCharacteristic = char
            } else if char.uuid == MEASUREMENT_STATUS_UUID {
                statusCharacteristic = char
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("Update error for \(characteristic.uuid): \(error.localizedDescription)")
            if let cont = activeMeasurementContinuation {
                activeMeasurementContinuation = nil
                cont.resume(throwing: error)
            }
            Task { @MainActor in delegate?.cuffManagerDidReceiveError(self, reason: error.localizedDescription) }
            return
        }

        guard let data = characteristic.value else { return }
        let hexString = data.map { String(format: "%02x", $0) }.joined(separator: " ")
        log("Update for \(characteristic.uuid). Bytes: \(hexString)")

        switch characteristic.uuid {
        case MEASUREMENT_UUID:
            lastRawMeasurementBytes = hexString
            do {
                let m = try AktiiaCuffDecoder.decodeMeasurement(data)
                log("Parsed MEASUREMENT -> SYS: \(m.systolic), DIA: \(m.diastolic), MEAN: \(m.mean), HR: \(m.hr)")
                pendingMeasurement = m

                guard let statusChar = statusCharacteristic else { return }
                log("Triggering status read...")
                peripheral.readValue(for: statusChar)
            } catch {
                log("Measurement decode error: \(error)")
            }

        case MEASUREMENT_STATUS_UUID:
            lastRawStatusBytes = hexString
            do {
                let status = try AktiiaCuffDecoder.decodeStatus(data)
                log("Parsed STATUS -> \(status)")

                if status == .success {
                    if let pm = pendingMeasurement {
                        log("-> Success! Publishing metrics.")
                        if let cont = activeMeasurementContinuation {
                            activeMeasurementContinuation = nil
                            let capturedLogs = currentLogs
                            let rawHex = "Measurement Packet: \(lastRawMeasurementBytes)\nStatus Packet: \(lastRawStatusBytes)"
                            cont.resume(returning: (pm.systolic, pm.diastolic, pm.hr, capturedLogs, rawHex))
                        }
                        Task { @MainActor in delegate?.cuffManagerDidReceiveMeasurement(self, systolic: pm.systolic, diastolic: pm.diastolic, mean: pm.mean, hr: pm.hr) }
                    }
                } else if case .other(let code) = status {
                    var errorMsg = "Measurement failed (Status: \(code))"
                    if let pm = pendingMeasurement {

                        log("-> Failure. Error code from byte0: \(pm.diastolic)")
                        switch pm.diastolic {
                        case 1, 3:
                            errorMsg = "Cuff error. Check that the cuff is snug and correctly positioned, then try again."
                        case 2:
                            errorMsg = "Movement detected during measurement. Please hold perfectly still."
                        default:
                            errorMsg = "Measurement error. Please try again."
                        }
                    }
                    log("Returning error: \(errorMsg)")
                    if let cont = activeMeasurementContinuation {
                        activeMeasurementContinuation = nil
                        cont.resume(throwing: NSError(domain: "CuffBLEManager", code: 3, userInfo: [NSLocalizedDescriptionKey: errorMsg]))
                    }
                    Task { @MainActor in delegate?.cuffManagerDidReceiveError(self, reason: errorMsg) }
                }
            } catch {
                log("Status decode error: \(error)")
            }

        default: break
        }
    }
}

struct CuffMeasurement: Equatable, Codable {
    let systolic: Int
    let diastolic: Int
    let mean: Int
    let hr: Int

    var firmwareRevisionCuff: String?
    var serialNumberCuff: String?
    var batteryLevelCuff: Int?
}

enum CuffMeasurementStatus: Equatable {
    case success
    case other(Int)
}

extension Data {
    func u8(at index: Int) -> UInt8? {
        guard index >= 0, index < count else { return nil }
        return self[self.startIndex.advanced(by: index)]
    }

    func hexToInt() -> Int? {
        let hex = self.map { String(format: "%02x", $0) }.joined()
        return Int(hex, radix: 16)
    }
}

enum AktiiaCuffDecoder {
    static func decodeMeasurement(_ data: Data) throws -> CuffMeasurement {
        guard data.count >= 4 else {
            throw DecodeError.tooShort(expected: 4, got: data.count)
        }
        guard
            let dia = data.u8(at: 0),
            let sys = data.u8(at: 1),
            let mean = data.u8(at: 2),
            let hr = data.u8(at: 3)
        else {
            throw DecodeError.tooShort(expected: 4, got: data.count)
        }

        return CuffMeasurement(
            systolic: Int(sys),
            diastolic: Int(dia),
            mean: Int(mean),
            hr: Int(hr),
            firmwareRevisionCuff: nil,
            serialNumberCuff: nil,
            batteryLevelCuff: nil
        )
    }

    static func decodeStatus(_ data: Data) throws -> CuffMeasurementStatus {
        guard let status = data.hexToInt() else {
            throw DecodeError.invalidHex
        }
        if status == 2 { return .success }
        return .other(status)
    }

    enum DecodeError: Error, CustomStringConvertible {
        case tooShort(expected: Int, got: Int)
        case invalidHex

        var description: String {
            switch self {
            case let .tooShort(expected, got):
                return "Cuff decode error: too short (expected >=\(expected) bytes, got \(got))."
            case .invalidHex:
                return "Cuff decode error: invalid hex."
            }
        }
    }
}

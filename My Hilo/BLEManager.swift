import CoreBluetooth
import Foundation

struct AktiiaMeasurement {
    let systolic: Int
    let diastolic: Int
    let heartRate: Int
    let timestamp: Date
}

protocol BLEManagerDelegate: AnyObject {
    func bleManager(_ manager: BLEManager, didUpdateBluetoothState description: String, isPoweredOn: Bool)
    func bleManager(_ manager: BLEManager, didUpdateDiscoveredPeripherals peripherals: [DiscoveredPeripheral])
    func bleManager(_ manager: BLEManager, didConnect peripheral: DiscoveredPeripheral)
    func bleManagerDidDisconnect(_ manager: BLEManager)
    func bleManager(_ manager: BLEManager, didUpdateScanning isScanning: Bool)
    func bleManager(_ manager: BLEManager, didUpdateErrorMessage message: String?)
    func bleManager(_ manager: BLEManager, didCaptureRawFrame frame: RawBLEFrame)
    func bleManager(_ manager: BLEManager, didDisconnectUnexpectedly unexpected: Bool)
    func bleManager(_ manager: BLEManager, didDetectBondingRequirement message: String)
}

extension BLEManagerDelegate {
    func bleManager(_ manager: BLEManager, didDisconnectUnexpectedly unexpected: Bool) {}
    func bleManager(_ manager: BLEManager, didDetectBondingRequirement message: String) {}
}

final class BLEManager: NSObject {
    weak var delegate: BLEManagerDelegate?

    private static let lockedPeripheralID = HiloBLEProtocol.lockedPeripheralID
    private static let batteryServiceUUID = CBUUID(string: HiloBLEProtocol.batteryServiceUUID)
    private static let batteryLevelCharacteristicUUID = CBUUID(string: HiloBLEProtocol.batteryLevelCharacteristicUUID)
    private static let centralRestoreID = "com.cybelli.apps.myhilo.ble.central"

    private var centralManager: CBCentralManager!
    private var discoveredByID: [UUID: CBPeripheral] = [:]
    private var metadataByID: [UUID: DiscoveredPeripheral] = [:]
    private var discoveredCharacteristicsByKey: [CharacteristicKey: CBCharacteristic] = [:]
    private var connectionInFlight: Set<UUID> = []
    private var connectedPeripheral: CBPeripheral?
    private var pendingCharacteristicDiscoveryServices: Set<CBUUID> = []
    private var lastWriteTimestampByCharacteristic: [CharacteristicKey: Date] = [:]
    private var pendingReadRequest: PendingReadRequest?
    private var pendingMeasurementResults: [AktiiaMeasurement]?

    enum ContextCaptureState: Equatable {
        case idle
        case awaitingFrameCount
        case streaming(expected: Int, received: Int)
        case finished
    }
    private(set) var contextCaptureState: ContextCaptureState = .idle

    private let logger: RawDataLogger

    private(set) var isPoweredOn = false
    private(set) var isScanning = false
    var autoConnectEnabled = false
    var allowWrites = false
    var useSafeMinimalSubscriptions = true

    private struct PendingReadRequest {
        let serviceUUID: String
        let characteristicUUID: String
        let continuation: CheckedContinuation<ReadCharacteristicResult, Never>
    }

    private func parseMeasurementFrames(_ data: Data) -> [AktiiaMeasurement] {

        return []
    }

    init(logger: RawDataLogger) {
        self.logger = logger
        super.init()
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: Self.centralRestoreID]
        )
    }

    var logFileURL: URL {
        logger.logFileURL
    }

    var isConnected: Bool {
        connectedPeripheral != nil
    }

    func tailLogLines(_ count: Int) -> String {
        logger.tailLines(count)
    }

    func setAllowWrites(_ enabled: Bool) {
        allowWrites = enabled
        logger.log("MODE", ["allowWrites: \(enabled)"])
    }

    func connectedPeripheralDisplayName() -> String {
        guard let connectedPeripheral else { return "none" }
        return "\(safeName(for: connectedPeripheral)) (\(connectedPeripheral.identifier.uuidString))"
    }

    func isDiscoveryComplete() -> Bool {
        return connectedPeripheral != nil && pendingCharacteristicDiscoveryServices.isEmpty
    }

    func syncCaptureReadinessError() -> String? {
        guard isPoweredOn else { return "Bluetooth is not powered on." }
        guard connectedPeripheral != nil else { return "Connect to pod first." }
        guard pendingCharacteristicDiscoveryServices.isEmpty else { return "Wait for discovery." }
        return nil
    }

    var podControlCharacteristic: CBCharacteristic? {
        discoveredCharacteristicsByKey.values.first(where: {
            $0.service?.uuid.uuidString.caseInsensitiveCompare(HiloBLEProtocol.primaryServiceUUID) == .orderedSame &&
            $0.uuid.uuidString.caseInsensitiveCompare(HiloBLEProtocol.podControlPointCharacteristicUUID) == .orderedSame
        })
    }

    @discardableResult
    func subscribeIfPresent(serviceUUID: String, characteristicUUID: String) -> Bool {
        guard let connectedPeripheral else { return false }
        guard let characteristic = discoveredCharacteristicsByKey.first(where: { pair in
            pair.key.peripheralID == connectedPeripheral.identifier
                && pair.key.serviceUUID.uuidString.caseInsensitiveCompare(serviceUUID) == .orderedSame
                && pair.key.characteristicUUID.uuidString.caseInsensitiveCompare(characteristicUUID) == .orderedSame
        })?.value else {
            return false
        }
        let props = characteristic.properties
        guard props.contains(.notify) || props.contains(.indicate) else { return false }
        connectedPeripheral.setNotifyValue(true, for: characteristic)
        logger.log("BLE", ["Subscribed to \(characteristicUUID)"])
        return true
    }

    func readCharacteristic(serviceUUID: String, characteristicUUID: String) async -> ReadCharacteristicResult {
        guard let connectedPeripheral else {
            return ReadCharacteristicResult(value: nil, errorMessage: "Not connected")
        }
        guard pendingReadRequest == nil else {
            return ReadCharacteristicResult(value: nil, errorMessage: "Another read is already pending")
        }
        guard let characteristic = discoveredCharacteristicsByKey.first(where: { pair in
            pair.key.peripheralID == connectedPeripheral.identifier
                && pair.key.serviceUUID.uuidString.caseInsensitiveCompare(serviceUUID) == .orderedSame
                && pair.key.characteristicUUID.uuidString.caseInsensitiveCompare(characteristicUUID) == .orderedSame
        })?.value else {
            return ReadCharacteristicResult(value: nil, errorMessage: "Characteristic not found")
        }
        guard characteristic.properties.contains(.read) else {
            return ReadCharacteristicResult(value: nil, errorMessage: "Characteristic is not readable")
        }

        return await withCheckedContinuation { continuation in
            pendingReadRequest = PendingReadRequest(
                serviceUUID: serviceUUID.uppercased(),
                characteristicUUID: characteristicUUID.uppercased(),
                continuation: continuation
            )
            connectedPeripheral.readValue(for: characteristic)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self, let pending = self.pendingReadRequest else { return }
                guard pending.serviceUUID == serviceUUID.uppercased(),
                      pending.characteristicUUID == characteristicUUID.uppercased()
                else { return }
                self.pendingReadRequest = nil
                pending.continuation.resume(returning: ReadCharacteristicResult(
                    value: nil,
                    errorMessage: "Read timeout"
                ))
            }
        }
    }

    func writeControlPointWithResponse(serviceUUID: String, characteristicUUID: String, payload: Data) async -> ExplorationWriteResult {
        guard let connectedPeripheral else {
            return ExplorationWriteResult(writeType: "none", errorMessage: "Not connected")
        }
        guard let characteristic = discoveredCharacteristicsByKey.first(where: { pair in
            pair.key.peripheralID == connectedPeripheral.identifier
                && pair.key.serviceUUID.uuidString.caseInsensitiveCompare(serviceUUID) == .orderedSame
                && pair.key.characteristicUUID.uuidString.caseInsensitiveCompare(characteristicUUID) == .orderedSame
        })?.value else {
            return ExplorationWriteResult(writeType: "none", errorMessage: "Characteristic not found")
        }

        let type: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        connectedPeripheral.writeValue(payload, for: characteristic, type: type)
        return ExplorationWriteResult(writeType: type == .withResponse ? "withResponse" : "withoutResponse", errorMessage: nil)
    }

    func triggerBP() async {
        guard let peripheral = connectedPeripheral else { return }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(abbreviation: "UTC")!
        let now = Date()
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: now)
        let year = UInt16(components.year ?? 2024)
        let yearLo = UInt8(year & 0xFF)
        let yearHi = UInt8((year >> 8) & 0xFF)
        let month = UInt8(components.month ?? 1)
        let day = UInt8(components.day ?? 1)
        let hour = UInt8(components.hour ?? 0)
        let minute = UInt8(components.minute ?? 0)
        let second = UInt8(components.second ?? 0)
        let iosWeekday = components.weekday ?? 1
        let aktiiaWeekday = UInt8(iosWeekday == 1 ? 7 : iosWeekday - 1)

        let payload = Data([
            yearLo, yearHi, month, day, hour, minute, second, aktiiaWeekday, 0x00, 0x02
        ])

        if let timeChar = discoveredCharacteristicsByKey.values.first(where: {
            $0.uuid.uuidString.caseInsensitiveCompare(HiloBLEProtocol.currentTimeCharacteristicUUID) == .orderedSame
        }) {
            print("[BLE] Directed capture trigger. Payload: \(payload.map { String(format: "%02X", $0) }.joined(separator: " "))")
            writeValue(payload, on: peripheral, characteristic: timeChar, reason: "TRIGGER_TIME")
        }

        try? await Task.sleep(for: .milliseconds(400))

        if let controlChar = discoveredCharacteristicsByKey.values.first(where: {
            $0.service?.uuid.uuidString.caseInsensitiveCompare(HiloBLEProtocol.primaryServiceUUID) == .orderedSame &&
            $0.uuid.uuidString.caseInsensitiveCompare(HiloBLEProtocol.podControlPointCharacteristicUUID) == .orderedSame
        }) {
            print("[TRIGGER] Sending clean production start (0x00)")
            writeValue(Data([0x00]), on: peripheral, characteristic: controlChar, reason: "TRIGGER_PRODUCTION_START")
        }
    }

    func triggerOnDemandBP() async {
        guard let peripheral = connectedPeripheral else { return }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(abbreviation: "UTC")!
        let now = Date()
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: now)

        let year = UInt16(components.year ?? 2024)
        let yearLo = UInt8(year & 0xFF)
        let yearHi = UInt8((year >> 8) & 0xFF)
        let month = UInt8(components.month ?? 1)
        let day = UInt8(components.day ?? 1)
        let hour = UInt8(components.hour ?? 0)
        let minute = UInt8(components.minute ?? 0)
        let second = UInt8(components.second ?? 0)

        let iosWeekday = components.weekday ?? 1
        let aktiiaWeekday = UInt8(iosWeekday == 1 ? 7 : iosWeekday - 1)

        let payload = Data([
            yearLo, yearHi, month, day, hour, minute, second, aktiiaWeekday, 0x00, 0x02
        ])

        if let timeChar = discoveredCharacteristicsByKey.values.first(where: {
            $0.uuid.uuidString.caseInsensitiveCompare(HiloBLEProtocol.currentTimeCharacteristicUUID) == .orderedSame
        }) {
            print("[BLE] Triggering On-Demand Waveform. Payload: \(payload.map { String(format: "%02X", $0) }.joined(separator: " "))")
            writeValue(payload, on: peripheral, characteristic: timeChar, reason: "TRIGGER_TIME")
        }

        try? await Task.sleep(for: .milliseconds(400))

        if let controlChar = discoveredCharacteristicsByKey.values.first(where: {
            $0.service?.uuid.uuidString.caseInsensitiveCompare(HiloBLEProtocol.primaryServiceUUID) == .orderedSame &&
            $0.uuid.uuidString.caseInsensitiveCompare(HiloBLEProtocol.podControlPointCharacteristicUUID) == .orderedSame
        }) {
            print("[TRIGGER] Sending clean production start (0x00)")
            writeValue(Data([0x00]), on: peripheral, characteristic: controlChar, reason: "TRIGGER_PRODUCTION_START")
        }
    }

    func stopOnDemandBP() async {
        guard let peripheral = connectedPeripheral else { return }

        if let controlChar = discoveredCharacteristicsByKey.values.first(where: {
            $0.service?.uuid.uuidString.caseInsensitiveCompare(HiloBLEProtocol.primaryServiceUUID) == .orderedSame &&
            $0.uuid.uuidString.caseInsensitiveCompare(HiloBLEProtocol.podControlPointCharacteristicUUID) == .orderedSame
        }) {
            writeValue(Data([0x07]), on: peripheral, characteristic: controlChar, reason: "STOP_ON_DEMAND_STREAM")
        }
    }

    func requestWaveformBurst() async {
        guard let peripheral = connectedPeripheral else { return }
        if let controlChar = podControlCharacteristic {
            writeValue(Data([0x01]), on: peripheral, characteristic: controlChar, reason: "FETCH_DATA_BURST")
        }
    }

    func beginContextualisationRead() async {
        guard let peripheral = connectedPeripheral, let controlChar = podControlCharacteristic else {
            print("[CAPTURE] Cannot begin: no connection / control point.")
            return
        }
        print("[CAPTURE] Writing control-point 0x00 to start raw-data reporting.")
        writeValue(Data([0x00]), on: peripheral, characteristic: controlChar, reason: "RAW_START_REPORTING")

        let res = await readCharacteristic(serviceUUID: HiloBLEProtocol.primaryServiceUUID,
                                           characteristicUUID: HiloBLEProtocol.numberOfFramesCharacteristicUUID)
        if let data = res.value, !data.isEmpty {
            let count = data.reduce(0) { ($0 << 8) | Int($1) }
            print("[CAPTURE] NO_OF_FRAMES (A6B41003) = \(count) (\(RawDataLogger.hexString(data)))")
            contextCaptureState = .streaming(expected: count, received: 0)
        } else {
            print("[CAPTURE] NO_OF_FRAMES read failed (\(res.errorMessage ?? "nil")); will finish on marker/stall.")
            contextCaptureState = .streaming(expected: 0, received: 0)
        }
    }

    func resetContextualisationCapture() {
        contextCaptureState = .idle
    }

    func triggerInitializationMeasurement() {
        guard let peripheral = connectedPeripheral else { return }
        let calibUUIDs = [HiloBLEProtocol.optionalDD890004CharacteristicUUID_BCE5,
                          HiloBLEProtocol.optionalDD890005CharacteristicUUID_BCE5]
        let chars = calibUUIDs.compactMap { uuid in
            discoveredCharacteristicsByKey.first(where: {
                $0.key.peripheralID == peripheral.identifier &&
                $0.key.characteristicUUID.uuidString.caseInsensitiveCompare(uuid) == .orderedSame
            })?.value
        }
        print("[INIT] Re-subscribing DD890004/05 to trigger a fresh measurement (\(chars.count) chars).")
        for ch in chars { peripheral.setNotifyValue(false, for: ch) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let p = self?.connectedPeripheral else { return }
            for ch in chars { p.setNotifyValue(true, for: ch) }
        }
    }

    func readInitializationRawData() {
        guard let peripheral = connectedPeripheral else { return }
        guard let dataChar = discoveredCharacteristicsByKey.first(where: {
            $0.key.peripheralID == peripheral.identifier &&
            $0.key.serviceUUID.uuidString.caseInsensitiveCompare(HiloBLEProtocol.primaryServiceUUID) == .orderedSame &&
            $0.key.characteristicUUID.uuidString.caseInsensitiveCompare(HiloBLEProtocol.primaryDataCharacteristicUUID) == .orderedSame
        })?.value else { return }
        contextCaptureState = .streaming(expected: 0, received: 0)
        print("[INIT] PodQi=DONE -> re-subscribing RAW_DATA (A6B41002) for fresh PPG (no 0x01).")
        peripheral.setNotifyValue(false, for: dataChar)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.connectedPeripheral?.setNotifyValue(true, for: dataChar)
        }
    }

    func releaseDevice() {
        stopScan()
        connectionInFlight.removeAll()
        if let connectedPeripheral {
            centralManager.cancelPeripheralConnection(connectedPeripheral)
        }
    }

    func startScan() {
        guard isPoweredOn else { return }
        if isScanning { return }

        let primaryUUID = CBUUID(string: HiloBLEProtocol.primaryServiceUUID)
        let connected = centralManager.retrieveConnectedPeripherals(withServices: [primaryUUID])
        for peripheral in connected {
            processDiscoveredPeripheral(peripheral, advertisementData: [:], rssi: -50)
        }

        logger.log("BLE", ["Scanning for Aktiia devices..."])
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
        delegate?.bleManager(self, didUpdateScanning: true)
    }

    private func processDiscoveredPeripheral(_ peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        let id = peripheral.identifier
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "unnamed"

        let isMatch = (id == Self.lockedPeripheralID)
                    || name.localizedCaseInsensitiveContains("Aktiia")

        if !isMatch { return }

        if discoveredByID[id] == nil {
            logger.log("BLE", ["Discovered candidate: \(name) (\(id.uuidString))"])
        }

        discoveredByID[id] = peripheral
        let metadata = DiscoveredPeripheral(id: id, name: name, rssi: rssi.intValue, lastSeen: Date(), isPreLocked: id == Self.lockedPeripheralID)
        metadataByID[id] = metadata
        delegate?.bleManager(self, didUpdateDiscoveredPeripherals: Array(metadataByID.values))
    }

    func stopScan() {
        guard isScanning else { return }
        centralManager.stopScan()
        isScanning = false
        delegate?.bleManager(self, didUpdateScanning: false)
    }

    func connect(to peripheralID: UUID) {
        guard isPoweredOn else { return }
        guard let peripheral = discoveredByID[peripheralID] else { return }
        connectionInFlight.insert(peripheralID)
        logger.log("BLE", ["Connecting to \(peripheral.name ?? peripheralID.uuidString)..."], consoleOnly: true)
        centralManager.connect(peripheral, options: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self else { return }
            if self.connectionInFlight.contains(peripheralID) && self.connectedPeripheral?.identifier != peripheralID {
                self.logger.log("BLE", ["Connect timeout for \(peripheralID.uuidString) — Pod likely held by another app. Cancelling + will retry."])
                self.connectionInFlight.remove(peripheralID)
                self.centralManager.cancelPeripheralConnection(peripheral)
            }
        }
    }

    func disconnectCurrentPeripheral() {
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    private func writeValue(_ value: Data, on peripheral: CBPeripheral, characteristic: CBCharacteristic, reason: String, writeType: CBCharacteristicWriteType? = nil) {
        guard allowWrites else { return }
        let type: CBCharacteristicWriteType
        if let override = writeType {
            type = override
        } else {
            type = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        }
        peripheral.writeValue(value, for: characteristic, type: type)
        let key = CharacteristicKey(
            peripheralID: peripheral.identifier,
            serviceUUID: characteristic.service?.uuid ?? CBUUID(string: "FFFF"),
            characteristicUUID: characteristic.uuid
        )
        lastWriteTimestampByCharacteristic[key] = Date()

        logger.log("TX", [
            "reason: \(reason)",
            "characteristic: \(characteristic.uuid.uuidString)",
            "len: \(value.count)",
            "hex: \(RawDataLogger.hexString(value))",
            "type: \(type == .withResponse ? "withResponse" : "withoutResponse")"
        ], consoleOnly: true)
    }

    private func safeName(for peripheral: CBPeripheral) -> String {
        peripheral.name ?? "unnamed"
    }
}

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        isPoweredOn = central.state == .poweredOn
        let description = "\(central.state.rawValue)"
        delegate?.bleManager(self, didUpdateBluetoothState: description, isPoweredOn: isPoweredOn)
        if isPoweredOn && autoConnectEnabled {
            startScan()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        processDiscoveredPeripheral(peripheral, advertisementData: advertisementData, rssi: RSSI)

        let advName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        let isPod = peripheral.identifier == Self.lockedPeripheralID || advName.uppercased().hasPrefix("AKTIIA P")

        if autoConnectEnabled && connectedPeripheral == nil && !connectionInFlight.contains(peripheral.identifier) && isPod {
            logger.log("BLE", ["Auto-connecting to pod: \(advName.isEmpty ? peripheral.identifier.uuidString : advName)"])
            connect(to: peripheral.identifier)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.log("BLE", ["Connected to \(peripheral.name ?? "unnamed")"], consoleOnly: true)
        connectedPeripheral = peripheral
        connectionInFlight.remove(peripheral.identifier)
        peripheral.delegate = self
        if let metadata = metadataByID[peripheral.identifier] {
            delegate?.bleManager(self, didConnect: metadata)
        }
        peripheral.discoverServices(nil)
        stopScan()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionInFlight.remove(peripheral.identifier)
        delegate?.bleManager(self, didUpdateErrorMessage: error?.localizedDescription)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if connectedPeripheral?.identifier == peripheral.identifier {
            connectedPeripheral = nil
            delegate?.bleManagerDidDisconnect(self)
        }
        delegate?.bleManager(self, didDisconnectUnexpectedly: error != nil)
        if autoConnectEnabled {
            startScan()
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {}
}

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            pendingCharacteristicDiscoveryServices.insert(service.uuid)
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        pendingCharacteristicDiscoveryServices.remove(service.uuid)
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            let key = CharacteristicKey(peripheralID: peripheral.identifier, serviceUUID: service.uuid, characteristicUUID: characteristic.uuid)
            discoveredCharacteristicsByKey[key] = characteristic

            if useSafeMinimalSubscriptions {
                if service.uuid.uuidString.caseInsensitiveCompare(HiloBLEProtocol.primaryServiceUUID) == .orderedSame {
                    if characteristic.uuid.uuidString.caseInsensitiveCompare(HiloBLEProtocol.primaryDataCharacteristicUUID) == .orderedSame ||
                       characteristic.uuid.uuidString.caseInsensitiveCompare(HiloBLEProtocol.podControlPointCharacteristicUUID) == .orderedSame {
                        peripheral.setNotifyValue(true, for: characteristic)
                    }
                } else if service.uuid.uuidString.caseInsensitiveCompare(HiloBLEProtocol.batteryServiceUUID) == .orderedSame &&
                          characteristic.uuid.uuidString.caseInsensitiveCompare(HiloBLEProtocol.batteryLevelCharacteristicUUID) == .orderedSame {
                    peripheral.setNotifyValue(true, for: characteristic)
                }

                let c1 = HiloBLEProtocol.optionalDD890004CharacteristicUUID_BCE5
                let c2 = HiloBLEProtocol.optionalDD890005CharacteristicUUID_BCE5
                if characteristic.uuid.uuidString.caseInsensitiveCompare(c1) == .orderedSame ||
                   characteristic.uuid.uuidString.caseInsensitiveCompare(c2) == .orderedSame {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            logger.logError("Read failed for \(characteristic.uuid.uuidString): \(error.localizedDescription)")
            if let pending = pendingReadRequest, pending.serviceUUID == (characteristic.service?.uuid.uuidString.uppercased() ?? ""), pending.characteristicUUID == characteristic.uuid.uuidString.uppercased() {
                pendingReadRequest = nil
                pending.continuation.resume(returning: ReadCharacteristicResult(value: nil, errorMessage: error.localizedDescription))
            }
            return
        }
        guard let value = characteristic.value else { return }

        let isControl = characteristic.uuid.uuidString.caseInsensitiveCompare(HiloBLEProtocol.podControlPointCharacteristicUUID) == .orderedSame
        let isData = characteristic.uuid.uuidString.caseInsensitiveCompare(HiloBLEProtocol.primaryDataCharacteristicUUID) == .orderedSame

        if isControl || isData {

            let endMarker = Data([0x93, 0xCE, 0x58, 0x0D, 0xDE])
            if value.count >= 5 && value.suffix(5) == endMarker {
                print("[BLE] End-of-capture marker (…93CE580DDE) in \(value.count)-byte frame. Finishing.")
                contextCaptureState = .finished
                NotificationCenter.default.post(name: .init("AktiiaMeasurementFinished"), object: nil)
            }

            let results = parseMeasurementFrames(value)
            if !results.isEmpty {
                pendingMeasurementResults = results
            } else if value.count == 20 || value.count == 72 || value.count == 140 {

                print("[BLE] Detected probable log/history packet (len: \(value.count)). Posting AktiiaLogPacketReceived notification.")
                NotificationCenter.default.post(name: .init("AktiiaLogPacketReceived"), object: nil)
            }
        }

        let isCalib1 = characteristic.uuid.uuidString.caseInsensitiveCompare(HiloBLEProtocol.optionalDD890004CharacteristicUUID_BCE5) == .orderedSame
        let isCalib2 = characteristic.uuid.uuidString.caseInsensitiveCompare(HiloBLEProtocol.optionalDD890005CharacteristicUUID_BCE5) == .orderedSame
        if (isCalib1 || isCalib2), let qi = value.first {
            switch qi {
            case 0x02:
                print("[BLE] PodQi=2 CALIBRATION_DONE on \(isCalib2 ? "DD890005" : "DD890004"). Posting AktiiaCalibrationFinished.")
                NotificationCenter.default.post(name: .init("AktiiaCalibrationFinished"), object: nil)
            case 0x03, 0x04, 0x05:
                let reason = qi == 0x03 ? "ERROR" : (qi == 0x04 ? "MOVEMENT_DETECTED" : "BAD_PPG_QUALITY")
                print("[BLE] PodQi=\(qi) (\(reason)) on calibration. Posting AktiiaCalibrationError.")
                NotificationCenter.default.post(name: .init("AktiiaCalibrationError"), object: reason)
            default:
                print("[BLE] PodQi=\(qi) (in-progress / no-calibration) on calibration char.")
            }
        }

        if characteristic.uuid.uuidString.caseInsensitiveCompare(HiloBLEProtocol.batteryLevelCharacteristicUUID) == .orderedSame, let lvl = value.first {
            NotificationCenter.default.post(name: .init("AktiiaBatteryLevel"), object: Int(lvl))
        }

        if let service = characteristic.service {
            logger.logCharacteristicUpdate(peripheral: peripheral, service: service, characteristic: characteristic, value: value, consoleOnly: true)
        }

        if let results = pendingMeasurementResults {
            pendingMeasurementResults = nil
            for measurement in results {
                logger.log("BLE", ["✅ Measurement Ready (\(isControl ? "Control" : "Data"))", "SYS: \(measurement.systolic)", "DIA: \(measurement.diastolic)", "HR: \(measurement.heartRate)"])
                print("✅ Measurement parsed: SYS: \(measurement.systolic), DIA: \(measurement.diastolic), HR: \(measurement.heartRate)")

                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .init("AktiiaMeasurementReady"),
                        object: measurement
                    )
                }
            }
            return
        }

        let deviceTime = AktiiaTimestampDecoder.decode(from: value, characteristicUUID: characteristic.uuid.uuidString)
        if let dt = deviceTime {
            print("[BLE][TIMESTAMP] Extracted from payload: \(dt.formatted(date: .abbreviated, time: .complete))")
        }

        delegate?.bleManager(self, didCaptureRawFrame: RawBLEFrame(
            peripheralID: peripheral.identifier,
            serviceUUID: characteristic.service?.uuid.uuidString ?? "unknown",
            characteristicUUID: characteristic.uuid.uuidString,
            timestamp: Date(),
            deviceTimestamp: deviceTime,
            payload: value,
            characteristicProperties: characteristic.properties
        ))

        NotificationCenter.default.post(name: .init("AktiiaFrameReceived"), object: nil)

        if isData, case .streaming(let expected, let received) = contextCaptureState {
            let now = received + 1
            contextCaptureState = .streaming(expected: expected, received: now)
            if expected > 0 && now >= expected {
                print("[CAPTURE] Received \(now)/\(expected) frames. Finishing (non-destructive, no delete).")
                contextCaptureState = .finished
                NotificationCenter.default.post(name: .init("AktiiaContextCaptureComplete"), object: nil)
            }
        }

        if let pending = pendingReadRequest, pending.serviceUUID == characteristic.service?.uuid.uuidString.uppercased(), pending.characteristicUUID == characteristic.uuid.uuidString.uppercased() {
            pendingReadRequest = nil
            pending.continuation.resume(returning: ReadCharacteristicResult(value: value, errorMessage: nil))
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            logger.logError("Write failed for \(characteristic.uuid.uuidString): \(error.localizedDescription)")
        }
    }
}

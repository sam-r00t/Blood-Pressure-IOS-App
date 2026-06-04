import Foundation
import Combine
import SwiftData
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class BLECentralViewModel: ObservableObject {
    private let localCaptureOnlyMode = true
    @Published private(set) var bluetoothState = "unknown"
    @Published private(set) var isPoweredOn = false
    @Published private(set) var isScanning = false
    @Published private(set) var discoveredPeripherals: [DiscoveredPeripheral] = []
    @Published private(set) var connectedPeripheral: DiscoveredPeripheral?
    @Published private(set) var errorMessage: String?
    @Published private(set) var backendSourceOfTruth = "not-configured"
    @Published private(set) var backendSyncStatus = "idle"
    @Published private(set) var backendMeasurements: [BPMeasurement] = []
    @Published private(set) var receivedFrameCount = 0
    @Published private(set) var batteryLevel: Int? = nil
    @Published private(set) var lastRawCaptureFrameCount: Int = 0

    enum CaptureStage {
        case idle
        case collecting(progress: Double)
        case decoding
        case result
    }
    @Published private(set) var captureStage: CaptureStage = .idle

    enum OnDemandStage: Equatable {
        case idle
        case measuring(step: Int)
        case computing
        case complete
        case failed(reason: String)
    }
    @Published private(set) var onDemandStage: OnDemandStage = .idle
    @Published private(set) var onDemandProgress: Double = 0.0
    @Published private(set) var onDemandMeasurements: [BPMeasurement] = []

    var incomingFramesURL: URL { frameRecorder.url }

    @Published var autoConnectEnabled = true {
        didSet {
            manager.autoConnectEnabled = autoConnectEnabled
        }
    }

    var autoCaptureOnConnect = true

    private let manager: BLEManager
    private let bpStrategy: BPComputationStrategy?
    private let frameRecorder = IncomingFrameRecorder()
    private var frameSyncTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var logPacketNeedsACK = false
    private var measurementFinished = false
    private var lastDataReceivedTime = Date()
    private var collectorBuffer = Data()
    private var isCollectingBurst = false
    var modelContext: ModelContext?

    init() {
        let logger = RawDataLogger(fileStore: LogFileStore())
        manager = BLEManager(logger: logger)

        let localModel = LocalBPModel.loadFromBundleOrDefault()
        let localStrategy = LocalComputedBPStrategy(recorder: frameRecorder, model: localModel)
        self.bpStrategy = localStrategy

        self.backendSourceOfTruth = "Local AI Based Algorithm"
        self.backendSyncStatus = "No reads yet. Capture first."

        try? FileManager.default.removeItem(at: frameRecorder.url)

        manager.autoConnectEnabled = true
        manager.delegate = self
        manager.allowWrites = true
        manager.useSafeMinimalSubscriptions = true

        NotificationCenter.default.addObserver(forName: .init("AktiiaMeasurementReady"), object: nil, queue: .main) { [weak self] note in
            guard let self = self, let measurement = note.object as? AktiiaMeasurement else { return }
            self.lastDataReceivedTime = Date()
            Task { @MainActor in
                await self.saveAktiiaMeasurement(measurement)
            }
        }

        NotificationCenter.default.addObserver(forName: .init("AktiiaLogPacketReceived"), object: nil, queue: .main) { [weak self] _ in
            self?.logPacketNeedsACK = true
            self?.lastDataReceivedTime = Date()
        }

        NotificationCenter.default.addObserver(forName: .init("AktiiaMeasurementFinished"), object: nil, queue: .main) { [weak self] _ in
            print("[VM] Received Measurement Finished signal from pod.")
            self?.measurementFinished = true
        }

        NotificationCenter.default.addObserver(forName: .init("AktiiaFrameReceived"), object: nil, queue: .main) { [weak self] _ in
            self?.lastDataReceivedTime = Date()
        }

        NotificationCenter.default.addObserver(forName: .init("AktiiaBatteryLevel"), object: nil, queue: .main) { [weak self] note in
            if let lvl = note.object as? Int { self?.batteryLevel = lvl }
        }

        NotificationCenter.default.addObserver(forName: .init("AktiiaCalibrationFinished"), object: nil, queue: .main) { [weak self] _ in

            print("[VM] PodQi=DONE -> reading fresh initialization raw data from A6B41002.")
            self?.lastDataReceivedTime = Date()
            self?.manager.readInitializationRawData()
        }
    }

    deinit {
        frameSyncTask?.cancel()
    }

    var connectedDisplayName: String {
        guard let connectedPeripheral else {
            return "Not Connected"
        }
        return "\(connectedPeripheral.name) (\(shortID(connectedPeripheral.id)))"
    }

    func startScan() {
        manager.startScan()
    }

    func stopScan() {
        manager.stopScan()
    }

    func connect(peripheralID: UUID) {
        manager.connect(to: peripheralID)
    }

    func disconnect() {
        manager.disconnectCurrentPeripheral()
    }

    func refreshBackendMeasurements(reason: String = "manual") async {
        guard let bpStrategy else {
            backendSyncStatus = "Compute not configured"
            print("[MEASUREMENT_REFRESH] skipped reason=\(reason) status=not-configured")
            return
        }
        if reason == "bp-screen-appear" && receivedFrameCount == 0 {

            return
        }
        print("[MEASUREMENT_REFRESH] start reason=\(reason)")
        backendSyncStatus = "Computing measurements..."
        do {
            let detailed = try await bpStrategy.fetchLatestDetailed(limit: 100)
            var all = detailed.map { $0.measurement }

            if let context = modelContext {
                let descriptor = FetchDescriptor<StoredBPMeasurement>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
                let stored = (try? context.fetch(descriptor)) ?? []
                for s in stored.prefix(10) {

                    if !all.contains(where: { abs($0.timestamp.timeIntervalSince(s.timestamp)) < 1.0 }) {
                        all.append(BPMeasurement(
                            id: "\(s.sequence)",
                            timestamp: s.timestamp,
                            systolic: s.systolic,
                            diastolic: s.diastolic,
                            heartRate: s.heartRate,
                            source: "production-stored"
                        ))
                    }
                }
            }

            backendMeasurements = all.sorted { $0.timestamp > $1.timestamp }
            backendSyncStatus = "Fetched \(backendMeasurements.count) measurement(s)"
            print("[MEASUREMENT_REFRESH] success reason=\(reason) measurements=\(backendMeasurements.count)")

            self.lastDetailedResult = detailed.first
        } catch {
            backendSyncStatus = "Fetch failed: \(error.localizedDescription)"
            print("[MEASUREMENT_REFRESH] failed reason=\(reason) error=\(error.localizedDescription)")
        }
    }

    private var lastDetailedResult: DetailedBPResult?

    func startDirectedCapture() {
        receivedFrameCount = 0
        let duration: Double = 15.0
        captureStage = .collecting(progress: 0.0)

        captureTask?.cancel()
        captureTask = Task {
            await manager.triggerBP()

            let start = Date()
            while Date().timeIntervalSince(start) < duration {
                if Task.isCancelled { return }
                try? await Task.sleep(for: .milliseconds(100))
                let elapsed = Date().timeIntervalSince(start)
                let progress = min(elapsed / duration, 1.0)
                if case .collecting = captureStage {
                    captureStage = .collecting(progress: progress)
                }
            }

            if Task.isCancelled { return }
            captureStage = .decoding

            try? await Task.sleep(for: .seconds(1))

            if Task.isCancelled { return }
            await refreshBackendMeasurements(reason: "directed-capture")

            if let context = modelContext {
                saveLatestToSwiftData(context: context)
            }

            captureStage = .result
        }
    }

    private func savePodRawCapture() {
        let src = frameRecorder.url
        guard let data = try? Data(contentsOf: src), !data.isEmpty else { return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? src.deletingLastPathComponent()
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dst = docs.appendingPathComponent("pod_raw_\(stamp).jsonl")
        try? data.write(to: dst)
        print("[CAPTURE] Saved raw Pod capture (\(data.count) bytes) -> \(dst.lastPathComponent)")
    }

    private func saveRawPodCaptureRecord(frameCount: Int, context: ModelContext) {
        let raw = (try? String(contentsOf: frameRecorder.url, encoding: .utf8)) ?? ""

        let research = try? LocalBPComputer.computeDetailed(
            fromIncomingFramesJSONL: frameRecorder.url,
            model: LocalBPModel.loadFromBundleOrDefault(),
            windowSeconds: 90.0,
            gated: false
        )
        let sys = research?.measurement.systolic ?? 0
        let dia = research?.measurement.diastolic ?? 0
        let hr = research?.measurement.heartRate
        let seqDescriptor = FetchDescriptor<StoredBPMeasurement>(sortBy: [SortDescriptor(\.sequence, order: .reverse)])
        let nextSeq = ((try? context.fetch(seqDescriptor))?.first?.sequence ?? 0) + 1
        let prefix = (sys > 0 && dia > 0) ? "RESEARCH_POD_ESTIMATE" : "RAW_POD_CAPTURE"
        let stored = StoredBPMeasurement(
            sequence: nextSeq,
            timestamp: Date(),
            systolic: sys,
            diastolic: dia,
            heartRate: hr,
            rawFramesJSON: raw,
            calculationLogs: "\(prefix) frames=\(frameCount)\nUNCALIBRATED research estimate from the Pod raw PPG — NEEDS MORE RESEARCH. The raw single-channel data has no clean heartbeat offline, so this is NOT a real blood pressure. Use the cuff for a real BP.\n\n\(research?.logs ?? "")",
            isCalibration: false
        )
        context.insert(stored)
        try? context.save()
        print("[CAPTURE] Saved \(prefix) record #\(nextSeq) (\(frameCount) frames, est \(sys)/\(dia)).")
    }

    private func saveLatestToSwiftData(context: ModelContext) {
        guard let detailed = lastDetailedResult else { return }
        let latest = detailed.measurement

        let rawData = detailed.rawFramesJSON?.data(using: .utf8) ?? Data()
        let hash = SHA256.hash(data: rawData).map { String(format: "%02x", $0) }.joined()

        let ts = latest.timestamp

        let descriptor = FetchDescriptor<StoredBPMeasurement>(predicate: #Predicate<StoredBPMeasurement> {
            $0.payloadHash == hash || $0.timestamp == ts
        })

        if let existingCount = try? context.fetchCount(descriptor), existingCount > 0 {
            print("[DATABASE] Duplicate detected (hash or timestamp). Skipping save.")

            self.backendMeasurements = []
            self.backendSyncStatus = "Duplicate measurement detected"
            return
        }

        let seqDescriptor = FetchDescriptor<StoredBPMeasurement>(sortBy: [SortDescriptor(\.sequence, order: .reverse)])
        let existing = try? context.fetch(seqDescriptor)
        let nextSeq = (existing?.first?.sequence ?? 0) + 1

        let stored = StoredBPMeasurement(
            sequence: nextSeq,
            timestamp: latest.timestamp,
            systolic: latest.systolic,
            diastolic: latest.diastolic,
            heartRate: latest.heartRate,
            rawFramesJSON: detailed.rawFramesJSON,
            calculationLogs: detailed.logs
        )
        context.insert(stored)
        try? context.save()
        print("[DATABASE] Saved measurement #\(nextSeq) with logs (\(detailed.logs.count) chars)")
    }

    func cancelDirectedCapture() {
        captureTask?.cancel()
        captureTask = nil
        captureStage = .idle
    }

    func resetCapture() {
        captureStage = .idle
    }

    func startOnDemandCapture() {
        onDemandMeasurements = []
        onDemandStage = .measuring(step: 1)
        onDemandProgress = 0.0

        captureTask?.cancel()
        captureTask = Task {

            await MainActor.run {
                onDemandStage = .measuring(step: 1)
                receivedFrameCount = 0
                collectorBuffer = Data()
                isCollectingBurst = false
                measurementFinished = false
            }
            frameRecorder.clear()
            await manager.triggerInitializationMeasurement()
            await manager.triggerOnDemandBP()

            lastDataReceivedTime = Date()
            let start = Date()
            let overall: Double = 150.0
            while Date().timeIntervalSince(start) < overall {
                if Task.isCancelled { break }
                if measurementFinished {
                    print("[CAPTURE] End-of-measurement marker received.")
                    break
                }
                let idle = Date().timeIntervalSince(lastDataReceivedTime)
                if receivedFrameCount > 3 && idle > 8.0 {
                    print("[CAPTURE] \(receivedFrameCount) frames then \(Int(idle))s stall — finishing.")
                    break
                }
                try? await Task.sleep(for: .milliseconds(300))
                await MainActor.run { onDemandProgress = min(Date().timeIntervalSince(start) / overall, 1.0) }
            }

            if Task.isCancelled {
                await MainActor.run { resetOnDemand() }
                return
            }

            manager.resetContextualisationCapture()

            let captured = receivedFrameCount
            savePodRawCapture()
            await MainActor.run {
                self.lastRawCaptureFrameCount = captured
                if captured > 0 {
                    if let context = self.modelContext { self.saveRawPodCaptureRecord(frameCount: captured, context: context) }
                    self.onDemandStage = .complete
                } else {
                    self.onDemandStage = .failed(reason: "No raw data captured. Keep the Pod worn + still and the official Hilo app fully closed, then try again.")
                }
            }
        }
    }

    func cancelOnDemandCapture() {
        captureTask?.cancel()
        captureTask = nil
        Task {

            await MainActor.run {
                resetOnDemand()
            }
        }
    }

    func resetOnDemand() {
        onDemandStage = .idle
        onDemandProgress = 0.0
    }

    func resetHistory() {
        onDemandMeasurements = []
        backendMeasurements = []
        lastDetailedResult = nil
        frameRecorder.clear()
        if let context = modelContext,
           let all = try? context.fetch(FetchDescriptor<StoredBPMeasurement>()) {
            for m in all { context.delete(m) }
            try? context.save()
            print("[RESET] Deleted \(all.count) stored measurement(s).")
            backendSyncStatus = "History reset (\(all.count) removed)."
        } else {
            backendSyncStatus = "History reset."
        }
    }

#if DEBUG

    func injectSimulatedWaveform(frameCount: Int = 50) {
        captureTask?.cancel()
        onDemandMeasurements = []
        onDemandStage = .computing
        onDemandProgress = 1.0
        receivedFrameCount = 0

        captureTask = Task {
            let source = SimulatedWaveformSource()

            frameRecorder.clear()
            let frames = source.makeFrames(frameCount: frameCount, peripheralID: UUID(), sessionStart: Date())
            for f in frames { frameRecorder.record(frame: f) }
            await MainActor.run { self.receivedFrameCount = frames.count }

            let buffer = source.makeContinuousBuffer(frameCount: frameCount)
            await processCollectorBurst(buffer)

            await MainActor.run {
                self.onDemandStage = self.onDemandMeasurements.isEmpty
                    ? .failed(reason: "Simulator produced no measurement.")
                    : .complete
            }
        }
    }
#endif

    func startCalibrationStream() async {
        frameRecorder.clear()
        await manager.triggerInitializationMeasurement()
        await manager.triggerOnDemandBP()
    }

    func stopCalibrationStream() async {
        await manager.stopOnDemandBP()
    }

    func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}

extension BLECentralViewModel: BLEManagerDelegate {
    func bleManager(_ manager: BLEManager, didUpdateBluetoothState description: String, isPoweredOn: Bool) {
        bluetoothState = description
        self.isPoweredOn = isPoweredOn
    }

    func bleManager(_ manager: BLEManager, didUpdateDiscoveredPeripherals peripherals: [DiscoveredPeripheral]) {
        discoveredPeripherals = peripherals
    }

    func bleManager(_ manager: BLEManager, didConnect peripheral: DiscoveredPeripheral) {
        connectedPeripheral = peripheral
        guard autoCaptureOnConnect, onDemandStage == .idle else { return }

        Task { [weak self] in
            guard let self else { return }
            for _ in 0..<60 {
                if self.manager.isDiscoveryComplete() { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            print("[AUTO] Pod connected + discovered -> auto-starting raw-data capture.")
            self.startOnDemandCapture()
        }
    }

    func bleManagerDidDisconnect(_ manager: BLEManager) {
        connectedPeripheral = nil
    }

    func bleManager(_ manager: BLEManager, didDisconnectUnexpectedly unexpected: Bool) {
    }

    func bleManager(_ manager: BLEManager, didDetectBondingRequirement message: String) {
        errorMessage = message
    }

    func bleManager(_ manager: BLEManager, didUpdateScanning isScanning: Bool) {
        self.isScanning = isScanning
    }

    func bleManager(_ manager: BLEManager, didUpdateErrorMessage message: String?) {
        errorMessage = message
    }

    func bleManager(_ manager: BLEManager, didCaptureRawFrame frame: RawBLEFrame) {
        frameRecorder.record(frame: frame)
        receivedFrameCount += 1

        if frame.characteristicUUID.caseInsensitiveCompare(HiloBLEProtocol.primaryDataCharacteristicUUID) == .orderedSame {
            if !isCollectingBurst {
                print("[COLLECTOR] Waveform burst started...")
                isCollectingBurst = true
                collectorBuffer = Data()
            }

            collectorBuffer.append(frame.payload)

            if frame.payload.count < 244 {
                print("[COLLECTOR] End of burst detected (len: \(frame.payload.count)). Triggering handoff...")
                let burstData = collectorBuffer
                isCollectingBurst = false
                collectorBuffer = Data()

                Task {
                    await processCollectorBurst(burstData)
                }
            }
        }
    }

    private func processCollectorBurst(_ buffer: Data) async {
        guard !buffer.isEmpty else { return }
        print("[COLLECTOR] Handoff of \(buffer.count) bytes to Local AI model.")
        let localModel = LocalBPModel.loadFromBundleOrDefault()
        guard let result = try? LocalBPComputer.computeDetailed(fromRawWaveformBuffer: buffer, model: localModel) else {
            print("[COLLECTOR] No measurement computed from \(buffer.count) bytes.")
            return
        }
        await MainActor.run {

            self.onDemandMeasurements.append(result.measurement)
            self.backendMeasurements.insert(result.measurement, at: 0)
        }
    }

    private func saveAktiiaMeasurement(_ am: AktiiaMeasurement) async {
        print("[DATABASE] Saving production measurement: \(am.systolic)/\(am.diastolic)")

        guard let context = modelContext else { return }

        let seqDescriptor = FetchDescriptor<StoredBPMeasurement>(sortBy: [SortDescriptor(\.sequence, order: .reverse)])
        let existing = try? context.fetch(seqDescriptor)
        let nextSeq = (existing?.first?.sequence ?? 0) + 1

        let stored = StoredBPMeasurement(
            sequence: nextSeq,
            timestamp: am.timestamp,
            systolic: am.systolic,
            diastolic: am.diastolic,
            heartRate: am.heartRate,
            rawFramesJSON: "[\"Production internal calculation result\"]",
            calculationLogs: "Aktiia Production Block Ready.\nTimestamp: \(am.timestamp)"
        )
        context.insert(stored)
        try? context.save()

        let uiMeasurement = BPMeasurement(
            id: UUID().uuidString,
            timestamp: am.timestamp,
            systolic: am.systolic,
            diastolic: am.diastolic,
            heartRate: am.heartRate > 0 ? am.heartRate : nil,
            source: "aktiia-production"
        )

        await MainActor.run {
            self.onDemandMeasurements.append(uiMeasurement)
            self.backendMeasurements.insert(uiMeasurement, at: 0)
            if self.onDemandStage == .measuring(step: 1) || self.onDemandStage == .computing {
                self.onDemandStage = .complete
            }
        }

        await refreshBackendMeasurements(reason: "production-block-ready")

        await MainActor.run {
            if !self.backendMeasurements.contains(where: { $0.id == uiMeasurement.id }) {
                self.backendMeasurements.insert(uiMeasurement, at: 0)
            }
        }
    }
}

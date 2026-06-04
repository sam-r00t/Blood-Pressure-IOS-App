import SwiftUI
import SwiftData

struct CalibrationTabView: View {
    @ObservedObject var viewModel: BLECentralViewModel
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<StoredBPMeasurement> { $0.isCalibration }, sort: \.timestamp, order: .reverse)
    private var calibrationHistory: [StoredBPMeasurement]

    @StateObject private var cuffManager = CuffBLEManager()

    enum CalibrationStep: Equatable {
        case prep
        case measuring(readNumber: Int)
        case pausing(secondsLeft: Int)
        case success
        case failed(reason: String)
    }

    @State private var currentStep: CalibrationStep = .prep
    @AppStorage("isCalibrationCompleted") private var isCalibrationCompleted = false
    @State private var calibrationProgress: Double = 0.0
    @State private var reads: [(sys: Int, dia: Int, hr: Int, logs: String, rawCuffHex: String)] = []

    @State private var showingPodScanner = false
    @State private var showingCuffScanner = false

    @State private var singleCuffResult: (sys: Int, dia: Int, hr: Int)? = nil
    @State private var singleCuffBusy = false
    @State private var singleCuffError: String? = nil

    var isPodConnected: Bool {
        viewModel.connectedPeripheral != nil
    }

    var canStartCalibration: Bool {
        isPodConnected && cuffManager.isConnected
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if isCalibrationCompleted {
                        CalibrationBannerView(title: "Calibration Completed", icon: "checkmark.seal.fill", color: .green)
                    } else {
                        CalibrationBannerView(title: "Action Required", icon: "exclamationmark.triangle.fill", color: .orange)
                    }

                    if case .prep = currentStep {
                        prepView
                    } else {
                        activeCalibrationView
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Calibration")
            .onAppear {
                let newCoordinator = Coordinator(parent: self)
                self.coordinator = newCoordinator
                cuffManager.delegate = newCoordinator

                if !cuffManager.isConnected && !cuffManager.isScanning {
                    cuffManager.startScanForCuff()
                }
                if !isPodConnected && !viewModel.isScanning {
                    viewModel.startScan()
                }
            }
        }
        .sheet(isPresented: $showingPodScanner) {
            PodScannerView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingCuffScanner) {
            CuffScannerView(cuffManager: cuffManager)
        }
    }

    private var prepView: some View {
        VStack(spacing: 32) {
            VStack(spacing: 20) {
                Text("Ensure both the Aktiia Pod and Aktiia Cuff are connected before starting the calibration sequence.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                DeviceStatusBox(
                    icon: "applewatch",
                    title: "Aktiia Pod",
                    isConnected: isPodConnected,
                    deviceName: isPodConnected ? viewModel.connectedDisplayName : "Scanning...",
                    actionName: isPodConnected ? nil : "Scan"
                ) {
                    if !isPodConnected {
                        showingPodScanner = true
                    }
                }

                DeviceStatusBox(
                    icon: "rectangle.compress.vertical",
                    title: "Aktiia Cuff",
                    isConnected: cuffManager.isConnected,
                    deviceName: cuffManager.isConnected ? "Cuff Connected" : "Scanning...",
                    actionName: cuffManager.isConnected ? nil : "Scan"
                ) {
                    if !cuffManager.isConnected {
                        showingCuffScanner = true
                    }
                }

                Spacer().frame(height: 20)

                VStack(spacing: 10) {
                    Button {
                        takeSingleCuffReading()
                    } label: {
                        HStack(spacing: 8) {
                            if singleCuffBusy { ProgressView().tint(.white) }
                            Text(singleCuffBusy ? "Measuring with cuff…" : "Take Cuff Reading (real BP)")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background((cuffManager.isConnected && !singleCuffBusy) ? Color.green.gradient : Color.gray.gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(!cuffManager.isConnected || singleCuffBusy)
                    .padding(.horizontal)

                    if let r = singleCuffResult {
                        Text("Cuff: \(r.sys)/\(r.dia) mmHg · \(r.hr) bpm — genuine, saved to history")
                            .font(.subheadline.bold()).foregroundStyle(.green)
                            .multilineTextAlignment(.center).padding(.horizontal)
                    }
                    if let e = singleCuffError {
                        Text(e).font(.caption).foregroundStyle(.red)
                            .multilineTextAlignment(.center).padding(.horizontal)
                    }
                    Text("Reads the Aktiia cuff directly — a real oscillometric blood-pressure measurement (Pod not required).")
                        .font(.caption2).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal)
                }
                .padding(.top, 4)

                Divider().padding(.horizontal).padding(.vertical, 4)

                Button {
                    startCalibrationSequence()
                } label: {
                    Text("Start Calibration (3 paired reads)")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(canStartCalibration ? Color.blue.gradient : Color.gray.gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(!canStartCalibration)
                .padding(.horizontal)
            }
            .padding(.top, 10)

            if !calibrationHistory.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Calibration History")
                        .font(.headline)
                        .padding(.horizontal)

                    ForEach(calibrationHistory) { m in
                        NavigationLink(destination: BPDetailsView(measurement: m)) {
                            HStack(spacing: 16) {
                                Circle()
                                    .fill(Color.blue.opacity(0.1))
                                    .frame(width: 44, height: 44)
                                    .overlay {
                                        Image(systemName: "scale.3d")
                                            .foregroundStyle(.blue)
                                    }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(m.systolic)/\(m.diastolic)")
                                        .font(.system(.title3, design: .rounded, weight: .bold))

                                    Text(m.timestamp.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding()
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(16)
                            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private var activeCalibrationView: some View {
        VStack(spacing: 40) {

            switch currentStep {
            case .measuring(let readNumber):
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 20)
                        .frame(width: 200, height: 200)

                    Circle()
                        .trim(from: 0.0, to: calibrationProgress)
                        .stroke(Color.blue.gradient, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                        .frame(width: 200, height: 200)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.5), value: calibrationProgress)

                    VStack(spacing: 4) {
                        Text("\(Int(calibrationProgress * 100))%")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                    }
                }

                VStack(spacing: 8) {
                    Text("Read \(readNumber) of 3")
                        .font(.title2.bold())
                    Text("The cuff is measuring and the pod is capturing optical data. Please hold perfectly still.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

            case .pausing(let secondsLeft):
                VStack(spacing: 24) {
                    Text("\(secondsLeft)")
                        .font(.system(size: 80, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue.gradient)

                    Text("Preparing next read...")
                        .font(.headline)
                    Text("Relax and keep your arm still.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 40)

            case .success:
                VStack(spacing: 24) {
                    Image(systemName: "checkmark.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .foregroundStyle(.green.gradient)

                    VStack(spacing: 8) {
                        Text("Calibration Successful")
                            .font(.title2.bold())
                        Text("All 3 reads complete. Your pod has been calibrated.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if let avg = computeAverageRead() {
                        HStack(spacing: 24) {
                            VStack {
                                Text("\(avg.sys)")
                                    .font(.title.bold())
                                Text("SYS")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            VStack {
                                Text("\(avg.dia)")
                                    .font(.title.bold())
                                Text("DIA")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            VStack {
                                Text("\(avg.hr)")
                                    .font(.title.bold())
                                Text("BPM")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(12)
                    }

                    Button {
                        Task { @MainActor in
                            withAnimation {
                                currentStep = .prep
                                reads = []
                            }
                        }
                    } label: {
                        Text("Finish")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.green.gradient)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal, 40)
                }

            case .failed(let reason):
                VStack(spacing: 32) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundStyle(.red.gradient)

                    VStack(spacing: 8) {
                        Text("Calibration Failed")
                            .font(.title2.bold())
                        Text(reason)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }

                    Button {
                        Task { @MainActor in
                            withAnimation {
                                currentStep = .prep
                                reads = []
                            }
                        }
                    } label: {
                        Text("Try Again")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.blue.gradient)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal, 40)
                }

            case .prep:
                EmptyView()
            }

            if currentStep != .prep && currentStep != .success && currentStep != .failed(reason: "") {
                Button("Cancel", role: .destructive) {
                    cancelSequence()
                }
            }
        }
    }

    @State private var sequenceTask: Task<Void, Never>? = nil
    @State private var progressTask: Task<Void, Never>? = nil

    @MainActor
    private func takeSingleCuffReading() {
        guard cuffManager.isConnected, !singleCuffBusy else { return }
        singleCuffError = nil
        singleCuffResult = nil
        singleCuffBusy = true
        Task {
            do {
                let r = try await cuffManager.measureOnce()
                let stored = StoredBPMeasurement(
                    sequence: Int(Date().timeIntervalSince1970) % 1_000_000,
                    timestamp: Date(),
                    systolic: r.sys,
                    diastolic: r.dia,
                    heartRate: r.hr,
                    rawFramesJSON: "[\"Cuff reference measurement\"]",
                    calculationLogs: "Genuine oscillometric cuff measurement (reference).\n\(r.sys)/\(r.dia) mmHg, HR \(r.hr)",
                    isCalibration: false
                )
                stored.cuffLogs = r.logs + "\n\nRAW: " + r.rawCuffHex
                modelContext.insert(stored)
                try? modelContext.save()
                await MainActor.run {
                    singleCuffResult = (r.sys, r.dia, r.hr)
                    singleCuffBusy = false
                }
                await viewModel.refreshBackendMeasurements(reason: "cuff_reference")
            } catch {
                await MainActor.run {
                    singleCuffError = error.localizedDescription
                    singleCuffBusy = false
                }
            }
        }
    }

    @MainActor
    private func startCalibrationSequence() {
        reads = []
        calibrationProgress = 0.0

        sequenceTask?.cancel()
        progressTask?.cancel()

        sequenceTask = Task {
            do {
                for iteration in 1...3 {
                    if Task.isCancelled { break }

                    await MainActor.run {
                        currentStep = .measuring(readNumber: iteration)
                        calibrationProgress = 0.0
                    }

                    startProgressSimulation()

                    await viewModel.startCalibrationStream()

                    try? await Task.sleep(for: .seconds(5))

                    let result = try await cuffManager.measureOnce()
                    await MainActor.run {
                        reads.append(result)
                    }

                    await viewModel.stopCalibrationStream()

                    let podRaw = (try? String(contentsOf: viewModel.incomingFramesURL, encoding: .utf8)) ?? "No raw frames"

                    saveReadToDatabase(sys: result.sys, dia: result.dia, hr: result.hr, iteration: iteration, cuffLogs: result.logs, podRawFrames: podRaw, rawCuffHex: result.rawCuffHex)

                    progressTask?.cancel()
                    await MainActor.run {
                        calibrationProgress = 1.0
                    }

                    if iteration < 3 {
                        for wait in (1...10).reversed() {
                            if Task.isCancelled { break }
                            await MainActor.run {
                                currentStep = .pausing(secondsLeft: wait)
                            }
                            try await Task.sleep(for: .seconds(1))
                        }
                    }
                }

                if Task.isCancelled { return }

                let _ = computeAverageRead()
                isCalibrationCompleted = true

                await MainActor.run {
                    currentStep = .success
                }

                Task {
                    await viewModel.refreshBackendMeasurements(reason: "calibration_save")
                }

            } catch {
                await viewModel.stopCalibrationStream()
                await MainActor.run {
                    progressTask?.cancel()
                    currentStep = .failed(reason: error.localizedDescription)
                }
            }
        }
    }

    @MainActor
    private func cancelSequence() {
        sequenceTask?.cancel()
        progressTask?.cancel()
        cuffManager.stopMeasurement()
        Task {
            await viewModel.stopCalibrationStream()
        }
        Task { @MainActor in
            withAnimation {
                currentStep = .prep
                reads = []
            }
        }
    }

    @MainActor
    private func startProgressSimulation() {
        progressTask?.cancel()
        progressTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                await MainActor.run {
                    if calibrationProgress < 0.95 {
                        calibrationProgress += 0.01
                    }
                }
            }
        }
    }

    private func saveReadToDatabase(sys: Int, dia: Int, hr: Int, iteration: Int, cuffLogs: String, podRawFrames: String, rawCuffHex: String) {
        let stored = StoredBPMeasurement(
            sequence: Int(Date().timeIntervalSince1970) % 1000 + iteration,
            timestamp: Date(),
            systolic: sys,
            diastolic: dia,
            heartRate: hr,
            rawFramesJSON: "[\"Calibration Cuff Event, Read \(iteration) of 3\"]",
            calculationLogs: "Paired Calibration Read \(iteration) Success.\nCuff: \(sys)/\(dia)",
            isCalibration: true
        )
        stored.cuffLogs = cuffLogs + "\n\nRAW DATA:\n" + rawCuffHex
        stored.podLogs = podRawFrames
        modelContext.insert(stored)
        try? modelContext.save()
    }

    private func computeAverageRead() -> (sys: Int, dia: Int, hr: Int)? {
        guard !reads.isEmpty else { return nil }
        let sysAvg = reads.map { $0.sys }.reduce(0, +) / reads.count
        let diaAvg = reads.map { $0.dia }.reduce(0, +) / reads.count
        let hrAvg = reads.map { $0.hr }.reduce(0, +) / reads.count
        return (sysAvg, diaAvg, hrAvg)
    }

    class Coordinator: CuffBLEManagerDelegate {
        var parent: CalibrationTabView
        init(parent: CalibrationTabView) { self.parent = parent }
        func cuffManagerDidUpdateState(_ manager: CuffBLEManager, isPoweredOn: Bool) {}
        func cuffManagerDidDiscoverCuff(_ manager: CuffBLEManager, name: String) {

        }
        func cuffManagerDidConnect(_ manager: CuffBLEManager) {}
        func cuffManagerDidDisconnect(_ manager: CuffBLEManager, error: Error?) {

        }
        func cuffManagerDidReceiveMeasurement(_ manager: CuffBLEManager, systolic: Int, diastolic: Int, mean: Int, hr: Int) {

        }
        func cuffManagerDidReceiveError(_ manager: CuffBLEManager, reason: String) {

        }
    }

    @State private var coordinator: Coordinator?
}

struct DeviceStatusBox: View {
    let icon: String
    let title: String
    let isConnected: Bool
    let deviceName: String
    let actionName: String?
    let action: (() -> Void)?

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .foregroundStyle(isConnected ? Color.green.gradient : Color.secondary.gradient)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(deviceName)
                    .font(.subheadline)
                    .foregroundStyle(isConnected ? .primary : .secondary)
            }

            Spacer()

            if let actionName = actionName, let action = action {
                Button(action: action) {
                    Text(actionName)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue.gradient)
                        .clipShape(Capsule())
                }
            } else if isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .padding(.horizontal)
    }
}

struct PodScannerView: View {
    @ObservedObject var viewModel: BLECentralViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List(viewModel.discoveredPeripherals, id: \.id) { peripheral in
                Button {
                    viewModel.connect(peripheralID: peripheral.id)
                    dismiss()
                } label: {
                    HStack {
                        Text(peripheral.name)
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\(peripheral.rssi) dBm")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Select Pod")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if viewModel.isScanning {
                        ProgressView()
                    } else {
                        Button("Scan") { viewModel.startScan() }
                    }
                }
            }
            .onAppear {
                viewModel.startScan()
            }
        }
    }
}

struct CuffScannerView: View {
    @ObservedObject var cuffManager: CuffBLEManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List(cuffManager.discoveredCuffs) { cuff in
                Button {
                    cuffManager.connect(to: cuff.id)
                    dismiss()
                } label: {
                    HStack {
                        Text(cuff.name)
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\(cuff.rssi) dBm")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Select Cuff")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if cuffManager.isScanning {
                        ProgressView()
                    } else {
                        Button("Scan") { cuffManager.startScanForCuff() }
                    }
                }
            }
            .onAppear {
                if !cuffManager.isScanning {
                    cuffManager.startScanForCuff()
                }
            }
        }
    }
}

struct CalibrationBannerView: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(color)
            Spacer()
        }
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

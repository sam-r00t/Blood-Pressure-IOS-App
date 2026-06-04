import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct BPCandidateInspectorView: View {
    @ObservedObject var viewModel: BLECentralViewModel
    @State private var showingShareSheet = false
    @State private var shareItems: [Any] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    statusCard
                    captureProgressSection
                    latestCard
                    captureControls
                    exportCard
                    disclaimer
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("Blood Pressure")
            .onAppear {
                Task { await viewModel.refreshBackendMeasurements(reason: "bp-screen-appear") }
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(activityItems: shareItems)
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Compute: \(viewModel.backendSyncStatus)")
                .font(.subheadline)
                .monospaced()
            Text("Source: \(viewModel.backendSourceOfTruth)")
                .font(.subheadline)
                .monospaced()
            Text("Connected: \(viewModel.connectedDisplayName)")
                .font(.subheadline)
                .monospaced()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
        .cornerRadius(14)
    }

    private var latestCard: some View {
        let latest = viewModel.backendMeasurements.sorted { $0.timestamp > $1.timestamp }.first
        return VStack(alignment: .leading, spacing: 10) {
            Text("Latest")
                .font(.headline)
            if let m = latest {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(m.systolic)/\(m.diastolic)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(m.timestamp.formatted(date: .abbreviated, time: .standard))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let hr = m.heartRate {
                            Text("HR: \(hr) bpm")
                                .font(.subheadline)
                        }
                        Text(m.source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                }
            } else {
                Text("No local waveform frames found yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
        .cornerRadius(14)
    }

    private var captureProgressSection: some View {
        Group {
            if case .idle = viewModel.captureStage {
                EmptyView()
            } else {
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(stageTitle)
                                .font(.headline)
                            Text(stageSubtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()

                        if case .result = viewModel.captureStage {
                            EmptyView()
                        } else {
                            Button(role: .destructive) {
                                viewModel.cancelDirectedCapture()
                            } label: {
                                Label("Cancel", systemImage: "xmark.circle.fill")
                                    .labelStyle(.iconOnly)
                                    .font(.title2)
                            }
                        }
                    }

                    if case .collecting = viewModel.captureStage {
                        HStack {
                            ProgressView(value: caseValue(viewModel.captureStage))
                                .tint(.blue)
                            Text("\(viewModel.receivedFrameCount) frames")
                                .font(.caption)
                                .monospaced()
                                .padding(.leading, 8)
                        }
                    } else if case .decoding = viewModel.captureStage {
                        ProgressView()
                            .scaleEffect(1.2)
                    } else if case .result = viewModel.captureStage {
                        Button("Dismiss") {
                            viewModel.resetCapture()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .background(.blue.opacity(0.1))
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.blue.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }

    private var stageTitle: String {
        switch viewModel.captureStage {
        case .idle: return ""
        case .collecting: return "Collecting Data"
        case .decoding: return "Decoding Waveforms"
        case .result: return "Capture Complete"
        }
    }

    private var stageSubtitle: String {
        switch viewModel.captureStage {
        case .idle: return ""
        case .collecting: return "Hold steady..."
        case .decoding: return "Computing BP estimate..."
        case .result: return "Results updated below."
        }
    }

    private var captureControls: some View {
        VStack(spacing: 12) {
            if case .idle = viewModel.captureStage {

                if viewModel.connectedPeripheral == nil {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Discovered Devices")
                                .font(.headline)
                            Spacer()
                            if viewModel.isScanning {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }

                        if viewModel.discoveredPeripherals.isEmpty {
                            Text("No 'Aktiia' devices found yet. Tap Scan to search.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(viewModel.discoveredPeripherals) { peripheral in
                                Button {
                                    viewModel.connect(peripheralID: peripheral.id)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(peripheral.name)
                                                .font(.body)
                                                .fontWeight(.medium)
                                            Text(peripheral.id.uuidString.prefix(8))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "link.badge.plus")
                                            .foregroundStyle(.blue)
                                    }
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                                Divider()
                            }
                        }
                    }
                    .padding()
                    .background(.thinMaterial)
                    .cornerRadius(14)
                }

                Button {
                    viewModel.startDirectedCapture()
                } label: {
                    Label("Start BP Capture", systemImage: "play.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isPoweredOn || viewModel.connectedPeripheral == nil)

                HStack(spacing: 10) {
                    if !viewModel.isScanning {
                        Button {
                            viewModel.startScan()
                        } label: {
                            Label("Scan", systemImage: "dot.radiowaves.left.and.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button {
                            viewModel.stopScan()
                        } label: {
                            Label("Stop Scan", systemImage: "stop.circle")
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        viewModel.disconnect()
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.connectedPeripheral == nil)
                }
            }
        }
    }

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Export")
                .font(.headline)
            Button {
                shareItems = [viewModel.incomingFramesURL]
                showingShareSheet = true
            } label: {
                Label("Share incoming frames (JSONL)", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
        .cornerRadius(14)
    }

    private var disclaimer: some View {
        Text("Research-only estimate. Not medical-grade; do not use for clinical decisions.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    private func caseValue(_ stage: BLECentralViewModel.CaptureStage) -> Double {
        if case let .collecting(progress) = stage {
            return progress
        }
        return 0.0
    }
}

#if canImport(UIKit)
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

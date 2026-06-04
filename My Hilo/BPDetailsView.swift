import SwiftUI
import SwiftData

struct BPDetailsView: View {
    let measurement: StoredBPMeasurement
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: DetailTab = .visualizations

    enum DetailTab: String, CaseIterable {
        case visualizations = "Visualizations"
        case logs = "Logs"
        case rawData = "Raw Data"
        case calibrationLogs = "Calibration"
    }

    var availableTabs: [DetailTab] {
        if measurement.isCalibration {
            return DetailTab.allCases
        } else {
            return [.visualizations, .logs, .rawData]
        }
    }

    var body: some View {
        VStack(spacing: 0) {

            VStack(spacing: 0) {
                summaryHeader
                divider
                tabSelector
                divider
            }
            .background(Color(.systemBackground))
            .zIndex(1)

            ScrollView {
                VStack(spacing: 20) {
                    explanationSection

                    switch selectedTab {
                    case .visualizations:
                        ComputationStepsView(
                            computationLogs: measurement.calculationLogs ?? "",
                            rawFramesJSON: measurement.rawFramesJSON
                        )
                    case .logs:
                        logsView
                    case .rawData:
                        rawDataView
                    case .calibrationLogs:
                        calibrationLogsView
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Measurement #\(measurement.sequence)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        shareMeasurement()
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        UIPasteboard.general.string = measurement.calculationLogs
                    } label: {
                        Label("Copy Logs", systemImage: "doc.on.doc")
                    }
                    Button {
                        shareRawData()
                    } label: {
                        Label("Share Raw Data", systemImage: "doc.text")
                    }
                    Button {
                        exportMatlabScript()
                    } label: {
                        Label("Export MATLAB Script", systemImage: "chart.xyaxis.line")
                    }
                    if measurement.cuffLogs != nil || measurement.podLogs != nil {
                        Button {
                            shareCalibrationData()
                        } label: {
                            Label("Share Calibration Data", systemImage: "doc.text.magnifyingglass")
                        }
                    }
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("\(measurement.systolic)/\(measurement.diastolic)")
                        .font(.system(size: 52, weight: .bold, design: .rounded))

                    Text("mmHg")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)

                Spacer()

                if let hr = measurement.heartRate {
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                                .font(.title2)

                            Text("\(hr)")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                        }

                        Text("BPM")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 4)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Recorded: \(measurement.timestamp.formatted(date: .long, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Sequence #\(measurement.sequence)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                let category = getBPCategory(measurement.systolic, measurement.diastolic)
                HStack(spacing: 4) {
                    Image(systemName: "chart.bar.fill")
                        .font(.caption2)

                    Text(category.name)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(category.color.opacity(0.15))
                .clipShape(Capsule())
            }
        }
        .padding()
        .background(.thinMaterial)
    }

    private var explanationSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                explanationRow(title: "Systolic Pressure", text: "The pressure in your arteries when your heart beats. Normal is typically < 120 mmHg.")
                explanationRow(title: "Diastolic Pressure", text: "The pressure in your arteries when your heart rests between beats. Normal is typically < 80 mmHg.")
                explanationRow(title: "Heart Rate (HR)", text: "The number of times your heart beats per minute.")
                explanationRow(title: "Category", text: "Classification of your blood pressure based on medical guidelines.")
                explanationRow(title: "Waveform Analysis", text: "The app analyzes the shape of your pulse wave (PPG) to derive cardiovascular features that predict your blood pressure.")
            }
            .padding(.top, 8)
        } label: {
            Label("Understanding Your Measurement", systemImage: "info.circle")
                .font(.headline)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }

    private func explanationRow(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.bold)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(UIColor.separator).opacity(0.5))
            .frame(height: 0.5)
    }

    private var tabSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableTabs, id: \.self) { tab in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            selectedTab = tab
                        }
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(selectedTab == tab ? .white : .primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selectedTab == tab ? Color.blue : Color(UIColor.tertiarySystemFill))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
    }

    private var logsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Computation Logs", systemImage: "terminal")
                    .font(.headline)

                Spacer()

                Button {
                    UIPasteboard.general.string = measurement.calculationLogs
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            if let logs = measurement.calculationLogs, !logs.isEmpty {
                ScrollView {
                    Text(logs)
                        .font(.system(.caption, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.85))
                        .foregroundStyle(.green)
                        .cornerRadius(10)
                }
                .frame(height: 500)
            } else {
                Text("No logs available for this measurement.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 60)
            }

            explanationTableUI(title: "Logs Explained", rows: [
                ("Terminal Output", "Direct real-time console outputs captured simultaneously during the algorithm's execution."),
                ("Compute Details", "Crucial step-by-step mathematical verification confirming array processing, scaling, and parameter logic.")
            ])
        }
        .padding()
    }

    private var rawDataView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Raw Packet Data", systemImage: "doc.text")
                    .font(.headline)

                Spacer()

                if let rawData = measurement.rawFramesJSON, !rawData.isEmpty {
                    Text("\(rawData.components(separatedBy: "\n").count) lines")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 8)

                    Button {
                        shareRawData()
                    } label: {
                        Label("Export JSONL", systemImage: "square.and.arrow.up")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let rawData = measurement.rawFramesJSON, !rawData.isEmpty {

                let lines = rawData.components(separatedBy: "\n")
                let totalLines = lines.count

                VStack(alignment: .leading, spacing: 8) {
                    Text("Showing first 20 of \(totalLines) total rows. Export JSONL to view complete records.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 4)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(lines.prefix(20).enumerated()), id: \.offset) { index, line in
                                if !line.isEmpty {
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("\(index + 1):")
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 40, alignment: .trailing)

                                        Text(line)
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(.primary)
                                            .textSelection(.enabled)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(index % 2 == 0 ? Color.clear : Color.secondary.opacity(0.05))

                                    if index < 19 {
                                        Divider()
                                            .padding(.leading, 60)
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: 500)
                }
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(10)
            } else {
                Text("No raw data saved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 60)
            }

            explanationTableUI(title: "Raw Data Explained", rows: [
                ("JSONL Format", "A compact file layout storing precisely every Bluetooth LE packet transmitted."),
                ("Packet Payload", "Each localized payload contains raw Int16 PPG optical values sampled consistently at ~25Hz.")
            ])
        }
        .padding()
    }

    private var calibrationLogsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Calibration Data", systemImage: "scale.3d")
                .font(.headline)

            if measurement.cuffLogs == nil && measurement.podLogs == nil {
                Text("This measurement does not contain calibration logs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 60)
            } else {
                VStack(spacing: 20) {

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Cuff Data")
                            .font(.subheadline.bold())

                        let logs = measurement.cuffLogs ?? ""
                        let parts = logs.components(separatedBy: "\n\nRAW DATA:\n")
                        let parsedLogs = parts.first ?? logs
                        let rawHex = parts.count > 1 ? parts[1] : nil

                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Parsed Events")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                ScrollView {
                                    Text(parsedLogs)
                                        .font(.system(.caption2, design: .monospaced))
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.black.opacity(0.85))
                                        .foregroundStyle(.green)
                                        .cornerRadius(8)
                                }
                                .frame(height: 250)
                            }

                            if let raw = rawHex {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Raw Packets")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    ScrollView {
                                        Text(raw)
                                            .font(.system(.caption2, design: .monospaced))
                                            .padding(8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color.black.opacity(0.85))
                                            .foregroundStyle(.orange)
                                            .cornerRadius(8)
                                    }
                                    .frame(height: 250)
                                }
                            }
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Pod Stream Data (Optical)")
                            .font(.subheadline.bold())
                        ScrollView {
                            Text(measurement.podLogs ?? "No Pod stream data available.")
                                .font(.system(.caption2, design: .monospaced))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.85))
                                .foregroundStyle(.cyan)
                                .cornerRadius(8)
                        }
                        .frame(height: 300)
                    }
                }
            }
        }
        .padding()
    }

    private func shareMeasurement() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateStr = formatter.string(from: measurement.timestamp)
        let hr = measurement.heartRate?.description ?? "N/A"

        var csv = "Blood Pressure Measurement\n"
        csv += "Date,\(dateStr)\n"
        csv += "Systolic,\(measurement.systolic) mmHg\n"
        csv += "Diastolic,\(measurement.diastolic) mmHg\n"
        csv += "Heart Rate,\(hr) BPM\n"

        if let data = csv.data(using: .utf8) {
            let activityViewController = UIActivityViewController(activityItems: [data], applicationActivities: nil)
            #if canImport(UIKit)
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                rootViewController.present(activityViewController, animated: true)
            }
            #endif
        }
    }

    private func shareRawData() {
        guard let data = measurement.rawFramesJSON else { return }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("measurement_\(measurement.sequence).jsonl")
        try? data.write(to: tempURL, atomically: true, encoding: .utf8)

        let activityViewController = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityViewController, animated: true)
        }
    }

    private func shareCalibrationData() {
        var content = "Calibration Logs for Measurement #\(measurement.sequence)\n\n"
        content += "--- CUFF LOGS ---\n"
        content += measurement.cuffLogs ?? "No cuff logs\n"
        content += "\n--- POD RAW FRAMES ---\n"
        content += measurement.podLogs ?? "No pod raw frames\n"

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("calibration_data_\(measurement.sequence).txt")
        try? content.write(to: tempURL, atomically: true, encoding: .utf8)

        let activityViewController = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityViewController, animated: true)
        }
    }

    private func exportMatlabScript() {
        guard let rawData = measurement.rawFramesJSON, !rawData.isEmpty else { return }

        let lines = rawData.components(separatedBy: "\n")
        var allSamples: [Int] = []
        for line in lines where !line.isEmpty {
            if let data = line.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let decoded = json["decoded244"] as? [String: Any],
               let samples = decoded["samplesInt16LE"] as? [Int] {
                allSamples.append(contentsOf: samples)
            }
        }

        guard !allSamples.isEmpty else { return }

        var script = "% Blood Pressure Measurement Waveform\n"
        script += "% Sequence: \(measurement.sequence)\n"
        script += "fs = 25.0; % Approximate sampling frequency\n"
        script += "data = [\(allSamples.map { String($0) }.joined(separator: ", "))];\n"
        script += "t = (0:length(data)-1) / fs;\n"
        script += "figure;\n"
        script += "plot(t, data, 'b-', 'LineWidth', 1.5);\n"
        script += "title('PPG Waveform');\n"
        script += "xlabel('Time (seconds)');\n"
        script += "ylabel('Amplitude');\n"
        script += "grid on;\n"

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("plot_waveform_\(measurement.sequence).m")
        try? script.write(to: tempURL, atomically: true, encoding: .utf8)

        let activityViewController = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityViewController, animated: true)
        }
    }

    private func getBPCategory(_ systolic: Int, _ diastolic: Int) -> (name: String, color: Color) {
        if systolic < 120 && diastolic < 80 {
            return (name: "Normal", color: .green)
        } else if systolic < 130 && diastolic < 80 {
            return (name: "Elevated", color: .yellow)
        } else if systolic < 140 && diastolic < 90 {
            return (name: "High", color: .orange)
        } else {
            return (name: "High Stage 2", color: .red)
        }
    }
}

#Preview {
    NavigationStack {
        BPDetailsView(measurement: StoredBPMeasurement(
            sequence: 1,
            timestamp: Date(),
            systolic: 141,
            diastolic: 87,
            heartRate: 77,
            rawFramesJSON: """
[{"timestamp":"2024-02-25T13:39:49.991Z","deviceTimestamp":"2024-02-25T13:39:45.456Z","characteristicUUID":"A6B41002-003D-4E65-9208-08F4DB958863","decoded244":{"samplesInt16LE":[14,612,-736,-21308,-16131,-613,1726,-17667,-587,-10313,14,612,-736,-21308,-16131,-613,1726,-17667,-587,-10313,14,612,-736,-21308,-16131,-613,1726,-17667,-587,-10313,14,612,-736,-21308,-16131,-613,1726,-17667,-587,-10313,14,612,-736,-21308,-16131,-613,1726,-17667,-587,-10313]}}
""",
            calculationLogs: """
[COMPUTE][START] Target: A6B41002-003D-4E65-9208-08F4DB958863 Model: research_baseline_v1
[COMPUTE][SESSION] Duration: 0.51s, Samples: 4366, Est. fs: 25.0 Hz
[COMPUTE] Raw Sample Glimpse (first 10): 14, 612, -736, -21308, -16131, -613, 1726, -17667, -587, -10313
[COMPUTE][STEP 2] Preprocessing: Removing DC bias, normalizing, and applying bandpass...
[COMPUTE] Processed Glimpse (first 10): 0.0957, 0.1341, -0.1064, -0.2939, -0.2862, -0.0086, -0.0147, -0.0026, -0.1416, -0.1549
[COMPUTE][STEP 3] Peak Detection: Searching for systolic peaks (dist > 10 samples)...
[COMPUTE] Peak indices detected (168): 14, 41, 74, 89, 100, 133, 166, 233, 258, 296, 317, 331, 342, 361, 396...
[COMPUTE][STEP 4] Feature Extraction: Calculating beat morphology features...
[COMPUTE] First Beat Features: amp=1.10, rise=0.880, decay=1.200, hr=45.5
[COMPUTE][STEP 5] Quality Filter: Validation check...
[COMPUTE] Passed: 55, Rejected: 111
[COMPUTE][STEP 6] Aggregation: Building prediction vector...
  - amplitude       : 0.7763
  - auc             : 0.3438
  - decay_time_s    : 0.4618
  - downstroke_slope: -2.5313
  - hr_bpm          : 76.6337
  - notch_delay_s   : 0.2129
  - rise_time_s     : 0.4749
  - upstroke_slope  : 2.5096
  - width50_s       : 0.3978
[COMPUTE][STEP 7] Prediction: Linear regression...
[COMPUTE][SUCCESS] Est. SBP: 141 mmHg, DBP: 87 mmHg, HR: 77 bpm
"""
        ))
    }
    .modelContainer(for: StoredBPMeasurement.self, inMemory: true)
}

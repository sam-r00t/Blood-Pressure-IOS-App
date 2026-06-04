import SwiftUI

struct ComputationStepsView: View {
    let computationLogs: String
    let rawFramesJSON: String?
    @State private var selectedStep: ComputationStep = .rawWaveform

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                stepSelectorView

                Group {
                    switch selectedStep {
                    case .rawWaveform:
                        RawWaveformStep(logs: computationLogs, rawJSON: rawFramesJSON)
                    case .preprocessing:
                        PreprocessingStep(logs: computationLogs)
                    case .peakDetection:
                        PeakDetectionStep(logs: computationLogs)
                    case .featureExtraction:
                        FeatureExtractionStep(logs: computationLogs)
                    case .qualityFilter:
                        QualityFilterStep(logs: computationLogs)
                    case .aggregation:
                        AggregationStep(logs: computationLogs)
                    case .prediction:
                        PredictionStep(logs: computationLogs)
                    }
                }
            }
        }
    }

    private var stepSelectorView: some View {
        VStack(spacing: 12) {
            Text("Computation Steps")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ComputationStep.allCases, id: \.self) { step in
                        stepButton(step)
                    }
                }
                .padding(.horizontal, 16)
            }
            Divider()
        }
        .padding(.top, 8)
        .background(Color(UIColor.systemBackground))
    }

    private func stepButton(_ step: ComputationStep) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedStep = step
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: step.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(selectedStep == step ? .white : .primary)
                Text(step.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(selectedStep == step ? .white : .primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(selectedStep == step ? Color.blue : Color.secondary)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.blue.opacity(selectedStep == step ? 0 : 1), lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

enum ComputationStep: String, CaseIterable {
    case rawWaveform = "Raw Waveform"
    case preprocessing = "Preprocessing"
    case peakDetection = "Peak Detection"
    case featureExtraction = "Feature Extraction"
    case qualityFilter = "Quality Filter"
    case aggregation = "Aggregation"
    case prediction = "Prediction"

    var icon: String {
        switch self {
        case .rawWaveform: return "waveform.path"
        case .preprocessing: return "slider.horizontal.3"
        case .peakDetection: return "waveform.and.mic"
        case .featureExtraction: return "chart.xyaxis.line"
        case .qualityFilter: return "checkmark.seal.fill"
        case .aggregation: return "square.stack.3d.down.right"
        case .prediction: return "heart.text.square"
        }
    }

    var title: String {
        rawValue
    }
}

struct RawWaveformStep: View {
    let logs: String
    let rawJSON: String?
    @State private var samples: [Double] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(
                title: "Raw Waveform",
                icon: "waveform.path",
                description: "Original PPG signal received from device",
                color: .blue
            )

            if samples.isEmpty {
                Text("No waveform data available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 60)
            } else {
                waveformPlot(samples: samples, title: "Raw PPG Signal", color: .blue, showGrid: true)

                sampleStatistics(samples: samples)

                explanationTableUI(title: "Variables Explained", rows: [
                    ("Min / Max", "Lowest and highest raw sensor readings, giving a sense of the signal's bounds. Rapid shifts indicate movement."),
                    ("Mean", "The average signal level indicating baseline offset due to skin pressure and ambient light."),
                    ("Range", "Difference between max and min. A very low range implies a weak pulse, while a high range suggests clear perfusion."),
                    ("Samples", "Total sequential data points captured during the measurement, representing the sheer volume of optical reads.")
                ])
            }
        }
        .padding()
        .onAppear {
            parseSamplesFromLogs()
        }
    }

    private func parseSamplesFromLogs() {

        if let range = logs.range(of: "[COMPUTE] Raw Sample Glimpse") {
            let idxAfter = logs.index(range.upperBound, offsetBy: 1)
            guard idxAfter < logs.endIndex else { return }

            if let colonIdx = logs[idxAfter...].firstIndex(of: ":") {
                let afterColon = logs.index(colonIdx, offsetBy: 1)
                guard afterColon < logs.endIndex else { return }

                if let newlineIdx = logs[afterColon...].firstIndex(of: "\n") {
                    let sampleString = String(logs[afterColon..<newlineIdx])
                    samples = sampleString.components(separatedBy: ", ")
                        .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                }
            }
        }
    }

    @ViewBuilder
    private func sampleStatistics(samples: [Double]) -> some View {
        if samples.isEmpty {
            EmptyView()
        } else {
            let min = samples.min() ?? 0
            let max = samples.max() ?? 0
            let mean = samples.reduce(0, +) / Double(samples.count)
            let range = max - min

            VStack(alignment: .leading, spacing: 8) {
            Text("Signal Statistics")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    statItem("Min", String(format: "%.0f", min))
                    statItem("Max", String(format: "%.0f", max))
                }
                HStack(spacing: 12) {
                    statItem("Mean", String(format: "%.0f", mean))
                    statItem("Range", String(format: "%.0f", range))
                }
            }

            Text("Samples: \(samples.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private func statItem(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct PreprocessingStep: View {
    let logs: String
    @State private var rawSamples: [Double] = []
    @State private var processedSamples: [Double] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepHeader(
                title: "Preprocessing",
                icon: "slider.horizontal.3",
                description: "DC bias removal, normalization, and bandpass filtering",
                color: .orange
            )

            VStack(alignment: .leading, spacing: 16) {
                preprocessingSubStep(
                    step: 1,
                    title: "1. DC Bias Removal",
                    description: "Subtract mean to center signal around zero",
                    samples: rawSamples,
                    processedSamples: [],
                    color: .red
                )

                preprocessingSubStep(
                    step: 2,
                    title: "2. Normalization",
                    description: "Scale to [-1, 1] range",
                    samples: rawSamples,
                    processedSamples: rawSamples.map { $0 / (rawSamples.map { abs($0) }.max() ?? 1) },
                    color: .orange
                )

                preprocessingSubStep(
                    step: 3,
                    title: "3. Baseline Removal",
                    description: "Remove slow drift with 2-second moving average",
                    samples: rawSamples,
                    processedSamples: [],
                    color: .yellow
                )

                preprocessingSubStep(
                    step: 4,
                    title: "4. Bandpass Filtering",
                    description: "Apply 0.12-second moving average (low-pass)",
                    samples: [],
                    processedSamples: processedSamples,
                    color: .green
                )

                explanationTableUI(title: "Variables Explained", rows: [
                    ("DC Bias Removal", "Subtracts the overall mean value to vertically center the wave at zero, normalizing different skin tones."),
                    ("Normalization", "Scales the signal amplitude dynamically so the maximum peak is capped at 1.0, standardizing beat sizes."),
                    ("Baseline Removal", "Subtracts a 2-second rolling average to erase slow underlying drift caused by breathing and static pressure changes."),
                    ("Bandpass Filtering", "Smooths the wave aggressively to reduce high-frequency noise from ambient light and micro-vibrations.")
                ])
            }
        }
        .padding()
        .onAppear {
            parseSamplesFromLogs()
        }
    }

    private func parseSamplesFromLogs() {

        if let range = logs.range(of: "[COMPUTE] Raw Sample Glimpse") {
            let idxAfter = logs.index(range.upperBound, offsetBy: 1)
            guard idxAfter < logs.endIndex else { return }

            if let colonIdx = logs[idxAfter...].firstIndex(of: ":") {
                let afterColon = logs.index(colonIdx, offsetBy: 1)
                guard afterColon < logs.endIndex else { return }

                if let newlineIdx = logs[afterColon...].firstIndex(of: "\n") {
                    let sampleString = String(logs[afterColon..<newlineIdx])
                    rawSamples = sampleString.components(separatedBy: ", ")
                        .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                }
            }
        }

        if let range = logs.range(of: "[COMPUTE] Processed Glimpse") {
            let idxAfter = logs.index(range.upperBound, offsetBy: 1)
            guard idxAfter < logs.endIndex else { return }

            if let colonIdx = logs[idxAfter...].firstIndex(of: ":") {
                let afterColon = logs.index(colonIdx, offsetBy: 1)
                guard afterColon < logs.endIndex else { return }

                if let newlineIdx = logs[afterColon...].firstIndex(of: "\n") {
                    let sampleString = String(logs[afterColon..<newlineIdx])
                    processedSamples = sampleString.components(separatedBy: ", ")
                        .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                }
            }
        }
    }

    @ViewBuilder
    private func preprocessingSubStep(
        step: Int,
        title: String,
        description: String,
        samples: [Double],
        processedSamples: [Double],
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("\(step)")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.15))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !samples.isEmpty {
                waveformPlot(samples: samples, title: "Input", color: .gray.opacity(0.5), showGrid: false, height: 60)
            }

            if !processedSamples.isEmpty {
                waveformPlot(samples: processedSamples, title: "Output", color: color, showGrid: true, height: 80)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct PeakDetectionStep: View {
    let logs: String
    @State private var samples: [Double] = []
    @State private var peaks: [Int] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(
                title: "Peak Detection",
                icon: "waveform.and.mic",
                description: "Finding systolic peaks using dynamic threshold and prominence",
                color: .purple
            )

            VStack(spacing: 12) {

                VStack(alignment: .leading, spacing: 8) {
                    Text("Detection Parameters")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        paramItem("Threshold", "80th percentile")
                        paramItem("Min Dist", "Max 150 BPM")
                        paramItem("Min Prom", "0.08")
                        paramItem("Width", "80-800ms")
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if !samples.isEmpty && !peaks.isEmpty {

                    peaksWaveformPlot(samples: samples, peaks: peaks)
                }
            }

            if !peaks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Detected Peaks: \(peaks.count)")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(peaks.prefix(10).enumerated()), id: \.offset) { index, peakIdx in
                            HStack(spacing: 12) {
                                Text("#\(index + 1)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, alignment: .trailing)

                                Text("Index: \(peakIdx)")
                                    .font(.system(.caption, design: .monospaced))

                                if peakIdx < samples.count {
                                    Text("Value: \(String(format: "%.4f", samples[peakIdx]))")
                                        .font(.system(.caption, design: .monospaced))
                                }
                            }
                            .padding(4)
                            .background(Color.secondary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }

                        if peaks.count > 10 {
                            Text("... and \(peaks.count - 10) more peaks")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            explanationTableUI(title: "Variables Explained", rows: [
                ("Threshold", "Dynamic minimum height boundary (80th percentile relative to the local signal) that beats must confidently cross."),
                ("Min Dist", "Minimum horizontal space allowed between two detected peaks, strictly enforcing a maximum physiological heart rate of 150 BPM."),
                ("Min Prom", "How much the peak must vertically stand out against its immediate surrounding valleys, filtering out tiny bumps."),
                ("Width", "The physiological expected duration (80-800ms) of a real systolic blood volume surge in the local arteries.")
            ])
        }
        .padding()
        .onAppear {
            parseFromLogs()
        }
    }

    private func parseFromLogs() {

        if let range = logs.range(of: "[COMPUTE] Processed Glimpse") {
            let idxAfter = logs.index(range.upperBound, offsetBy: 1)
            guard idxAfter < logs.endIndex else { return }

            if let colonIdx = logs[idxAfter...].firstIndex(of: ":") {
                let afterColon = logs.index(colonIdx, offsetBy: 1)
                guard afterColon < logs.endIndex else { return }

                if let newlineIdx = logs[afterColon...].firstIndex(of: "\n") {
                    let sampleString = String(logs[afterColon..<newlineIdx])
                    samples = sampleString.components(separatedBy: ", ")
                        .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                }
            }
        }

        if let range = logs.range(of: "[COMPUTE] Peak indices detected") {
            let idxAfter = logs.index(range.upperBound, offsetBy: 1)
            guard idxAfter < logs.endIndex else { return }

            if let colonIdx = logs[idxAfter...].firstIndex(of: ":") {
                let afterColon = logs.index(colonIdx, offsetBy: 1)
                guard afterColon < logs.endIndex else { return }

                if let newlineIdx = logs[afterColon...].firstIndex(of: "\n") {
                    let peakString = String(logs[afterColon..<newlineIdx])

                    if let openParenRange = peakString.range(of: "("),
                       let closeParenIdx = peakString[openParenRange.lowerBound...].firstIndex(of: ")") {
                        let afterCloseParen = peakString.index(after: closeParenIdx)
                        let indicesString = String(peakString[afterCloseParen...])
                        peaks = indicesString.components(separatedBy: ", ")
                            .compactMap { Int($0.trimmingCharacters(in: CharacterSet.whitespaces)) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func paramItem(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct FeatureExtractionStep: View {
    let logs: String
    @State private var beatFeatures: (amp: String, rise: String, decay: String, hr: String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(
                title: "Feature Extraction",
                icon: "chart.xyaxis.line",
                description: "Calculating beat morphology features from detected peaks",
                color: .cyan
            )

            VStack(alignment: .leading, spacing: 16) {

                featureDiagram

                if let features = beatFeatures {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("First Beat Features")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        featureGrid(title: "Amplitude", value: features.amp, unit: "norm")
                        featureGrid(title: "Rise Time", value: features.rise, unit: "s")
                        featureGrid(title: "Decay Time", value: features.decay, unit: "s")
                        featureGrid(title: "Heart Rate", value: features.hr, unit: "bpm")
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                explanationTableUI(title: "All Extracted Features Explained", rows: [
                    ("Amplitude", "Peak-to-baseline vertical height. Indicates blood stroke volume strength."),
                    ("Rise Time", "Time taken for wave to reach peak. Relates directly to ventricular ejection speed."),
                    ("Decay Time", "Time from peak to next baseline. Correlates with arterial stiffness and compliance."),
                    ("Width50", "Pulse width measured at 50% amplitude. Shows overall tissue perfusion duration."),
                    ("AUC", "Area Under Curve (signal strength). Consistently correlates directly with systolic blood output."),
                    ("Upstroke Slope", "Rate of signal incline to peak. Steeper indicates higher central pressure contracting."),
                    ("Downstroke Slope", "Rate of signal decline after peak. Impacted by peripheral capillary resistance."),
                    ("Notch Delay", "Time to the secondary (dicrotic) notch. Represents arterial reflection timing caused by vascular pressure dynamics.")
                ])
            }
        }
        .padding()
        .onAppear {
            parseFromLogs()
        }
    }

    private func parseFromLogs() {
        if let range = logs.range(of: "[COMPUTE] First Beat Features:") {
            let idxAfter = logs.index(range.upperBound, offsetBy: 1)
            guard idxAfter < logs.endIndex else { return }

            if let newlineIdx = logs[idxAfter...].firstIndex(of: "\n") {
                let featureString = String(logs[idxAfter..<newlineIdx])
                beatFeatures = parseFeatureString(featureString)
            }
        }
    }

    private func parseFeatureString(_ featureString: String) -> (amp: String, rise: String, decay: String, hr: String)? {
        var amp: String?
        var rise: String?
        var decay: String?
        var hr: String?

        let parts = featureString.components(separatedBy: ", ")
        for part in parts {
            if part.hasPrefix("amp=") {
                amp = String(part.dropFirst(4))
            } else if part.hasPrefix("rise=") {
                rise = String(part.dropFirst(5))
            } else if part.hasPrefix("decay=") {
                decay = String(part.dropFirst(6))
            } else if part.hasPrefix("hr=") {
                hr = String(part.dropFirst(3))
            }
        }

        if let a = amp, let r = rise, let d = decay, let h = hr {
            return (amp: a, rise: r, decay: d, hr: h)
        }
        return nil
    }

    @ViewBuilder
    private var featureDiagram: some View {
        VStack(spacing: 8) {
            Text("Beat Morphology")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {

                Path { path in
                    let width: CGFloat = 220
                    let height: CGFloat = 120
                    let baseline = height / 2

                    path.move(to: CGPoint(x: 0, y: baseline))
                    path.addLine(to: CGPoint(x: width * 0.2, y: baseline))
                    path.addLine(to: CGPoint(x: width * 0.3, y: baseline - height * 0.35))
                    path.addLine(to: CGPoint(x: width * 0.35, y: baseline - height * 0.85))
                    path.addLine(to: CGPoint(x: width * 0.45, y: baseline - height * 0.45))
                    path.addLine(to: CGPoint(x: width * 0.5, y: baseline - height * 0.65))
                    path.addLine(to: CGPoint(x: width * 0.7, y: baseline - height * 0.25))
                    path.addLine(to: CGPoint(x: width * 0.85, y: baseline))
                }
                .stroke(Color.blue, lineWidth: 3)
                .frame(width: 220, height: 120)

                Rectangle()
                    .fill(Color.blue.opacity(0.5))
                    .frame(height: 2)
                    .frame(maxHeight: .infinity, alignment: .center)

                VStack {
                    HStack {
                        Text("Baseline")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                        Spacer()
                        Text("Amplitude")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.9))
                    .clipShape(Capsule())
                }
                .offset(y: -45)
                .frame(width: 220, alignment: .leading)
            }
            .frame(width: 220, height: 120)
            .padding(.top, 16)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 8)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func featureGrid(title: String, value: String, unit: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)

            Text(value)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)

            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func featureDescription(_ title: String, _ description: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)

            Text(description)
                .font(.system(.caption))
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct QualityFilterStep: View {
    let logs: String
    @State private var passedCount: Int = 0
    @State private var rejectedCount: Int = 0
    @State private var totalCount: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(
                title: "Quality Filter",
                icon: "checkmark.seal.fill",
                description: "Filtering beats based on physiological constraints",
                color: .green
            )

            if totalCount > 0 {
                VStack(spacing: 16) {

                    qualityFilterChart

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Filter Criteria")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        filterCriteria("Heart Rate", "45-140 BPM", .blue)
                        filterCriteria("Amplitude", "10th-95th percentile", .orange)
                        filterCriteria("Rise Time", "80-1200ms (0.08-1.2s)", .yellow)
                        filterCriteria("Width50", "80-1200ms (0.08-1.2s)", .purple)
                        filterCriteria("Upstroke Slope", "Must be > 0", .green)
                        filterCriteria("Downstroke Slope", "Must be < 0", .red)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            explanationTableUI(title: "Filters Explained", rows: [
                ("Physiological Core", "Removes severe artifacts like sudden motion spikes, electrical noise bursts, or completely absent/irregular beats."),
                ("Upstroke / Downstroke", "A valid cardiovascular beat inherently features a rising upstroke (>0) and inherently trailing downstroke (<0)."),
                ("Width Constraints", "Ensures the heart contraction duration falls realistically within acceptable human limits (0.08s - 1.2s).")
            ])
        }
        .padding()
        .onAppear {
            parseFromLogs()
        }
    }

    private func parseFromLogs() {
        if let range = logs.range(of: "[COMPUTE] Passed:") {
            let idxAfter = logs.index(range.upperBound, offsetBy: 1)
            guard idxAfter < logs.endIndex else { return }

            if let colonIdx = logs[idxAfter...].firstIndex(of: ":") {
                let afterColon = logs.index(colonIdx, offsetBy: 1)
                guard afterColon < logs.endIndex else { return }

                if let commaIdx = logs[afterColon...].firstIndex(of: ",") {
                    passedCount = Int(String(logs[afterColon..<commaIdx]).trimmingCharacters(in: .whitespaces)) ?? 0
                }
            }
        }

        if let range = logs.range(of: "[COMPUTE] Rejected:") {
            let idxAfter = logs.index(range.upperBound, offsetBy: 1)
            guard idxAfter < logs.endIndex else { return }

            if let colonIdx = logs[idxAfter...].firstIndex(of: ":") {
                let afterColon = logs.index(colonIdx, offsetBy: 1)
                guard afterColon < logs.endIndex else { return }

                if let newlineIdx = logs[afterColon...].firstIndex(of: "\n") {
                    rejectedCount = Int(String(logs[afterColon..<newlineIdx]).trimmingCharacters(in: .whitespaces)) ?? 0
                }
            }
        }
        totalCount = passedCount + rejectedCount
    }

    private var qualityFilterChart: some View {
        let rejectedRatio = totalCount > 0 ? Double(rejectedCount) / Double(totalCount) : 0
        let passedRatio = totalCount > 0 ? Double(passedCount) / Double(totalCount) : 0

        return VStack(alignment: .leading, spacing: 12) {
            Text("Filter Results")
                .font(.headline)
                .foregroundStyle(.secondary)

            ZStack(alignment: .leading) {

                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 300, height: 24)

                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.green)
                    .frame(width: 300 * passedRatio, height: 24)
                    .animation(.easeInOut(duration: 0.5), value: passedCount)

                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.red)
                    .frame(width: 300 * rejectedRatio, height: 24)
                    .animation(.easeInOut(duration: 0.5), value: rejectedCount)

                HStack(spacing: 4) {
                    Text("Passed: \(passedCount)")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .fontWeight(.semibold)
                    Text("(\(String(format: "%.0f", passedRatio * 100))%)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.9))

                    Spacer()

                    Text("Rejected: \(rejectedCount)")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .fontWeight(.semibold)
                    Text("(\(String(format: "%.0f", rejectedRatio * 100))%)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .frame(width: 300)
                .padding(.horizontal, 8)
            }

            HStack(spacing: 16) {
                legendItem("Passed", .green)
                legendItem("Rejected", .red)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func filterCriteria(_ name: String, _ range: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)

            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)

            Text(range)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func legendItem(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct AggregationStep: View {
    let logs: String
    @State private var features: [(name: String, value: Double)] = []
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepHeader(
                title: "Aggregation",
                icon: "square.stack.3d.down.right",
                description: "Building prediction vector from quality-filtered beats",
                color: .indigo
            )

            if !features.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Aggregated Features")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(features, id: \.name) { feature in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feature.name)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.4f", feature.value))
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.medium)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text("No aggregated features available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 30)
            }

            explanationTableUI(title: "Aggregated Features Explained", rows: [
                ("amplitude", "Average peak-to-baseline vertical height reliably calculated across all surviving high-quality beats."),
                ("auc", "Average area under the entire pulse curve, mathematically related to heart chamber stroke volume."),
                ("decay_time_s", "Average time required from pulse peak to relax entirely and safely return to the baseline state."),
                ("downstroke_slope", "Average rate of signal decline; greatly influenced by vascular wall elasticity dynamics."),
                ("hr_bpm", "Overall stabilized estimated heart rate dynamically derived from true pulse-to-pulse intervals."),
                ("notch_delay_s", "Average propagation lag prior to the waveform returning reflected pressures (the physical dicrotic notch)."),
                ("rise_time_s", "Average temporal duration required from baseline initiation soaring up to the singular systolic surge."),
                ("upstroke_slope", "Average rate of vertical signal incline; strongly mirrors and directly plots to arterial compliance."),
                ("width50_s", "Average pulse contraction physical width accurately recorded cross-sectionally at mid-amplitude levels.")
            ])
        }
        .padding()
        .onAppear {
            parseFromLogs()
        }
    }

    private func parseFromLogs() {

        if let range = logs.range(of: "[COMPUTE][STEP 6] Aggregation:") {
            let idxAfter = logs.index(range.upperBound, offsetBy: 1)
            guard idxAfter < logs.endIndex else { return }

            let remainingLogs = String(logs[idxAfter...])
            var parsedFeatures: [(name: String, value: Double)] = []

            let lines = remainingLogs.components(separatedBy: "\n")
            for line in lines {
                if line.contains("  - ") && line.contains(" : ") {
                    let parts = line.components(separatedBy: " : ")
                    if parts.count >= 2 {
                        let namePart = parts[0]
                        let valuePart = parts[1]

                        if let nameRange = namePart.range(of: "  - ") {
                            let name = String(namePart[nameRange.upperBound...])
                                .trimmingCharacters(in: .whitespaces)

                            if let value = Double(valuePart.trimmingCharacters(in: .whitespaces)) {
                                parsedFeatures.append((name: name, value: value))
                            }
                        }
                    }
                }
            }

            features = parsedFeatures
        }
    }
}

struct PredictionStep: View {
    let logs: String
    @State private var sbp: Int = 0
    @State private var dbp: Int = 0
    @State private var hr: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(
                title: "Prediction",
                icon: "heart.text.square",
                description: "Linear regression model applied to aggregated features",
                color: .red
            )

            VStack(spacing: 16) {

                HStack(spacing: 16) {
                    bpCard(title: "Systolic", value: sbp, color: .red, unit: "mmHg")
                    bpCard(title: "Diastolic", value: dbp, color: .orange, unit: "mmHg")
                    bpCard(title: "Heart Rate", value: hr, color: .pink, unit: "bpm")
                }

                bpClassification(sbp: sbp, dbp: dbp)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Model Details")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Image(systemName: "cpu")
                            .foregroundStyle(.secondary)
                        Text("research_baseline_v1")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    Text("Linear regression with 9 features: hr_bpm, amplitude, rise_time_s, decay_time_s, width50_s, auc, upstroke_slope, downstroke_slope, notch_delay_s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color.secondary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            explanationTableUI(title: "Variables Explained", rows: [
                ("Systolic", "The vastly higher BP number representing exact pressure when the core heart muscle forcefully pulses and actively contracts blood."),
                ("Diastolic", "The notably lower BP number representing the exact physical pressure internally maintained inside arteries while the heart fully rests between beats."),
                ("Regression", "Advanced embedded AI mathematical projection formula natively mapping derived, pure physiological array/time/slope features perfectly into standard Blood Pressure boundaries.")
            ])
        }
        .padding()
        .onAppear {
            parseFromLogs()
        }
    }

    private func parseFromLogs() {

        let patterns = [
            "\\[COMPUTE\\]\\[SUCCESS\\] Est\\. SBP:\\s*(\\d+)\\s*mmHg,\\s*DBP:\\s*(\\d+)\\s*mmHg,\\s*HR:\\s*(\\d+)\\s*bpm",
            "\\[COMPUTE\\]\\[SUCCESS\\] Estimated SBP:\\s*(\\d+)\\s*mmHg,\\s*DBP:\\s*(\\d+)\\s*mmHg,\\s*HR:\\s*(\\d+)\\s*bpm",
            "\\[SUCCESS\\] Est\\. SBP:\\s*(\\d+)\\s*mmHg,\\s*DBP:\\s*(\\d+)\\s*mmHg,\\s*HR:\\s*(\\d+)\\s*bpm",
            "Est\\. SBP:\\s*(\\d+)\\s*mmHg.*DBP:\\s*(\\d+)\\s*mmHg.*HR:\\s*(\\d+)\\s*bpm"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: logs.utf16.count)
                if let match = regex.firstMatch(in: logs, options: [], range: range) {

                    if match.numberOfRanges > 1 {
                        let sbpRange = match.range(at: 1)
                        if let swiftRange = Range(sbpRange, in: logs) {
                            sbp = Int(String(logs[swiftRange])) ?? 0
                        }
                    }

                    if match.numberOfRanges > 2 {
                        let dbpRange = match.range(at: 2)
                        if let swiftRange = Range(dbpRange, in: logs) {
                            dbp = Int(String(logs[swiftRange])) ?? 0
                        }
                    }

                    if match.numberOfRanges > 3 {
                        let hrRange = match.range(at: 3)
                        if let swiftRange = Range(hrRange, in: logs) {
                            hr = Int(String(logs[swiftRange])) ?? 0
                        }
                    }

                    if sbp > 0 || dbp > 0 || hr > 0 {
                        return
                    }
                }
            }
        }

        let lines = logs.components(separatedBy: "\n")
        for line in lines {
            if line.contains("SUCCESS") || line.contains("Est. SBP") {
                if let sbpRange = line.range(of: "SBP:\\s*", options: .regularExpression),
                   let sbpEnd = line[sbpRange.upperBound...].range(of: "\\s*mmHg", options: .regularExpression) {
                    sbp = Int(String(line[sbpRange.upperBound..<sbpEnd.lowerBound])) ?? 0
                }
                if let dbpRange = line.range(of: "DBP:\\s*", options: .regularExpression),
                   let dbpEnd = line[dbpRange.upperBound...].range(of: "\\s*mmHg", options: .regularExpression) {
                    dbp = Int(String(line[dbpRange.upperBound..<dbpEnd.lowerBound])) ?? 0
                }
                if let hrRange = line.range(of: "HR:\\s*", options: .regularExpression),
                   let hrEnd = line[hrRange.upperBound...].range(of: "\\s*bpm", options: .regularExpression) {
                    hr = Int(String(line[hrRange.upperBound..<hrEnd.lowerBound])) ?? 0
                }
            }
        }
    }

    @ViewBuilder
    private func bpCard(title: String, value: Int, color: Color, unit: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\(value)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(color)

            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func bpClassification(sbp: Int, dbp: Int) -> some View {
        let category = getBPCategory(sbp: sbp, dbp: dbp)

        VStack(alignment: .leading, spacing: 8) {
            Text("Classification")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Text(category.name)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(category.color)

                if let guideline = category.guideline {
                    Text(guideline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(category.color.opacity(0.2))
            .clipShape(Capsule())
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func getBPCategory(sbp: Int, dbp: Int) -> (name: String, color: Color, guideline: String?) {
        if sbp < 120 && dbp < 80 {
            return (name: "Normal", color: .green, guideline: "<120/<80 mmHg")
        } else if sbp < 130 && dbp < 80 {
            return (name: "Elevated", color: .yellow, guideline: "120-129/<80 mmHg")
        } else if sbp < 140 && dbp < 90 {
            return (name: "High Stage 1", color: .orange, guideline: "130-139/80-89 mmHg")
        } else {
            return (name: "High Stage 2", color: .red, guideline: "≥140/≥90 mmHg")
        }
    }
}

@ViewBuilder
func explanationTableUI(title: String, rows: [(String, String)]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)

        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .top, spacing: 12) {
                    Text(row.0)
                        .font(.caption)
                        .fontWeight(.bold)
                        .frame(width: 110, alignment: .leading)
                    Text(row.1)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)

                if index < rows.count - 1 {
                    Divider()
                        .padding(.leading, 12)
                }
            }
        }
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

@ViewBuilder
func stepHeader(title: String, icon: String, description: String, color: Color) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 48, height:  48)
                .background(color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

struct waveformPlot: View {
    let samples: [Double]
    let title: String
    let color: Color
    let showGrid: Bool
    var height: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showGrid {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ZStack {

                if showGrid {
                    gridLines
                }

                Path { path in
                    guard !samples.isEmpty else { return }
                    let minY = samples.min() ?? 0
                    let maxY = samples.max() ?? 1
                    let range = maxY - minY
                    let safeRange = max(range, 0.001)

                    let width: CGFloat = 300
                    let height = self.height
                    let padding: CGFloat = 4

                    path.move(to: CGPoint(x: 0, y: height))

                    for (index, sample) in samples.enumerated() {
                        let normalizedY = (sample - minY) / safeRange
                        let y = height - padding - (normalizedY * (height - 2 * padding))
                        let x = CGFloat(index) / CGFloat(max(samples.count - 1, 1)) * width
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                .stroke(color, lineWidth: 2)
                .frame(width: 300, height: height)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var gridLines: some View {
        ZStack {

            ForEach(0..<5) { i in
                let y = CGFloat(i) * (height / 4)
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 300, height: 1)
                    .position(x: 0, y: y)
            }

            ForEach(0..<5) { i in
                let x = CGFloat(i) * (300 / 4)
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1, height: height)
                    .position(x: x, y: 0)
            }
        }
        .frame(width: 300, height: height)
    }
}

struct peaksWaveformPlot: View {
    let samples: [Double]
    let peaks: [Int]
    @State private var displayedPeaks: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Waveform with Detected Peaks")
                .font(.caption)
                .foregroundStyle(.secondary)

            ZStack {

                gridLines

                Path { path in
                    guard !samples.isEmpty else { return }
                    let minY = samples.min() ?? 0
                    let maxY = samples.max() ?? 1
                    let range = maxY - minY
                    let safeRange = max(range, 0.001)

                    let width: CGFloat = 300
                    let height: CGFloat = 120
                    let padding: CGFloat = 4

                    path.move(to: CGPoint(x: 0, y: height))

                    for (index, sample) in samples.enumerated() {
                        let normalizedY = (sample - minY) / safeRange
                        let y = height - padding - (normalizedY * (height - 2 * padding))
                        let x = CGFloat(index) / CGFloat(max(samples.count - 1, 1)) * width
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                .frame(width: 300, height: 120)

                ForEach(Array(peaks.prefix(20).enumerated()), id: \.offset) { index, peakIdx in
                    if peakIdx < samples.count {
                        let sample = samples[peakIdx]
                        let minY = samples.min() ?? 0
                        let maxY = samples.max() ?? 1
                        let range = maxY - minY
                        let safeRange = max(range, 0.001)

                        let width: CGFloat = 300
                        let height: CGFloat = 120
                        let padding: CGFloat = 4

                        let normalizedY = (sample - minY) / safeRange
                        let y = height - padding - (normalizedY * (height - 2 * padding))
                        let x = CGFloat(peakIdx) / CGFloat(max(samples.count - 1, 1)) * width

                        Circle()
                            .fill(Color.purple)
                            .frame(width: 8, height: 8)
                            .position(x: x, y: y)
                    }
                }

                if let selectedPeak = displayedPeaks.first,
                   selectedPeak < samples.count {
                    let sample = samples[selectedPeak]
                    let minY = samples.min() ?? 0
                    let maxY = samples.max() ?? 1
                    let range = maxY - minY
                    let safeRange = max(range, 0.001)

                    let width: CGFloat = 300
                    let height: CGFloat = 120
                    let padding: CGFloat = 4

                    let normalizedY = (sample - minY) / safeRange
                        let y = height - padding - (normalizedY * (height - 2 * padding))
                        let x = CGFloat(selectedPeak) / CGFloat(max(samples.count - 1, 1)) * width

                    Circle()
                        .strokeBorder(Color.purple, lineWidth: 2)
                        .fill(Color.purple.opacity(0.3))
                        .frame(width: 12, height: 12)
                        .position(x: x, y: y)
                }
            }
        }
        .padding()
        .frame(width: 300, height: 120)
    }

    private var gridLines: some View {
        ZStack {

            ForEach(0..<5) { i in
                let y = CGFloat(i) * (120 / 4)
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 300, height: 1)
                    .position(x: 0, y: y)
            }

            ForEach(0..<5) { i in
                let x = CGFloat(i) * (300 / 4)
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1, height: 120)
                    .position(x: x, y: 0)
            }
        }
        .frame(width: 300, height: 120)
    }
}

#Preview {
    ComputationStepsView(
        computationLogs: """
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
""",
        rawFramesJSON: nil
    )
}

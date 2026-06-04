import SwiftUI
import SwiftData

struct ResultsTabView: View {
    @Query(sort: \StoredBPMeasurement.timestamp, order: .reverse) private var measurements: [StoredBPMeasurement]
    @Environment(\.modelContext) private var modelContext
    @State private var sortBy: SortOption = .date
    @State private var filterOption: FilterOption = .all
    @State private var showingExportSheet = false

    enum SortOption: String, CaseIterable {
        case date = "Date"
        case systolic = "Systolic"
        case diastolic = "Diastolic"
    }

    enum FilterOption: String, CaseIterable {
        case all = "All"
        case normal = "Normal (<120/80)"
        case elevated = "Elevated (120-129/<80)"
        case high = "High (130-139/80-89)"
    }

    var body: some View {
        NavigationStack {
            List {
                if measurements.isEmpty {
                    ContentUnavailableView {
                        Label("No recent reads", systemImage: "heart.text.square")
                    } description: {
                        Text("Capture your first blood pressure reading to start tracking your health journey.")
                    }
                    .listRowBackground(Color.clear)
                } else if filteredMeasurements.isEmpty {
                    ContentUnavailableView {
                        Label("No matching measurements", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("Try adjusting the filter to see more results.")
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(filteredMeasurements) { measurement in
                        NavigationLink(destination: BPDetailsView(measurement: measurement)) {
                            measurementCard(measurement)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("History")
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Menu {
                        Label("Sort by", systemImage: "arrow.up.arrow.down")
                        ForEach(SortOption.allCases, id: \.self) { option in
                            Button {
                                sortBy = option
                            } label: {
                                HStack {
                                    Text(option.rawValue)
                                    if sortBy == option {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label(sortBy.rawValue, systemImage: "arrow.up.arrow.down")
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !measurements.isEmpty {
                        Menu {
                            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                            ForEach(FilterOption.allCases, id: \.self) { option in
                                Button {
                                    filterOption = option
                                } label: {
                                    HStack {
                                        Text(option.rawValue)
                                        if filterOption == option {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label(filterOption.rawValue, systemImage: "line.3.horizontal.decrease.circle")
                        }

                        Button {
                            showingExportSheet = true
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportView(measurements: measurements)
        }
    }

    private var filteredMeasurements: [StoredBPMeasurement] {
        let sorted = measurements
            .sorted { m1, m2 in
            switch sortBy {
            case .date:
                return m1.timestamp > m2.timestamp
            case .systolic:
                return m1.systolic > m2.systolic
            case .diastolic:
                return m1.diastolic > m2.diastolic
            }
        }

        switch filterOption {
        case .all:
            return sorted
        case .normal:
            return sorted.filter { $0.systolic < 120 && $0.diastolic < 80 }
        case .elevated:
            return sorted.filter { ($0.systolic >= 120 && $0.systolic <= 129) && $0.diastolic < 80 }
        case .high:
            return sorted.filter { ($0.systolic >= 130 && $0.systolic <= 139) && $0.diastolic >= 80 && $0.diastolic <= 89 }
        }
    }

    private func measurementCard(_ m: StoredBPMeasurement) -> some View {
        HStack(spacing: 0) {

            let bpCategory = getBPCategory(m.systolic, m.diastolic)
            LinearGradient(colors: bpCategory.colors, startPoint: .top, endPoint: .bottom)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Measurement #\(m.sequence)")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundStyle(bpCategory.color)

                        Text(m.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(relativeTimeFormatter.localizedString(for: m.timestamp, relativeTo: Date()))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    if let hr = m.heartRate {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                                .font(.caption2)
                            Text("\(hr)")
                                .font(.system(.subheadline, design: .rounded))
                                .fontWeight(.semibold)
                            Text("BPM")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.red.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }

                if m.systolic == 0 && m.diastolic == 0 {

                    HStack(spacing: 8) {
                        Image(systemName: "waveform.path.ecg").foregroundStyle(.teal)
                        Text("Raw Pod capture")
                            .font(.system(.headline, design: .rounded))
                        if let logs = m.calculationLogs,
                           let r = logs.range(of: "frames=") {
                            Text("· \(logs[r.upperBound...].prefix(while: { $0.isNumber })) frames")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .bottom, spacing: 4) {
                            Text("\(m.systolic)")
                                .font(.system(size: 34, weight: .heavy, design: .rounded))
                            Text("/")
                                .font(.system(size: 24, weight: .light))
                                .foregroundStyle(.secondary)
                            Text("\(m.diastolic)")
                                .font(.system(size: 34, weight: .heavy, design: .rounded))

                            Text("mmHg")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 6)
                                .padding(.leading, 4)

                            Spacer()
                        }
                        if (m.calculationLogs ?? "").hasPrefix("RESEARCH_POD_ESTIMATE") {
                            Label("Research estimate — needs more research; not a real BP (use the cuff).", systemImage: "flask.fill")
                                .font(.caption2).foregroundStyle(.orange)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
            }
            .padding()
            .background(.thinMaterial)
        }
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    private func getBPCategory(_ systolic: Int, _ diastolic: Int) -> BPCategory {
        if systolic < 120 && diastolic < 80 {
            return BPCategory.normal
        } else if systolic < 130 && diastolic < 80 {
            return BPCategory.elevated
        } else if systolic < 140 && diastolic < 90 {
            return BPCategory.high
        } else {
            return BPCategory.high2
        }
    }

    private let relativeTimeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}

struct BPCategory {
    let name: String
    let color: Color
    let colors: [Color]

    static let normal = BPCategory(name: "Normal", color: .green, colors: [.green, .green.opacity(0.3)])
    static let elevated = BPCategory(name: "Elevated", color: .yellow, colors: [.yellow, .yellow.opacity(0.3)])
    static let high = BPCategory(name: "High", color: .orange, colors: [.orange, .orange.opacity(0.3)])
    static let high2 = BPCategory(name: "High Stage 2", color: .red, colors: [.red, .red.opacity(0.3)])
}

struct ExportItem: Identifiable {
    let id = UUID()
    let items: [Any]
}

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ExportView: View {
    let measurements: [StoredBPMeasurement]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMeasurements: Set<String> = []
    @State private var shareItem: ExportItem?

    var selectedItems: [StoredBPMeasurement] {
        measurements.filter { selectedMeasurements.contains($0.id) }
    }

    var avgSystolic: Int {
        guard !selectedItems.isEmpty else { return 0 }
        return selectedItems.reduce(0) { $0 + $1.systolic } / selectedItems.count
    }

    var avgDiastolic: Int {
        guard !selectedItems.isEmpty else { return 0 }
        return selectedItems.reduce(0) { $0 + $1.diastolic } / selectedItems.count
    }

    var avgHeartRate: Int {
        let hrValues = selectedItems.compactMap { $0.heartRate }
        guard !hrValues.isEmpty else { return 0 }
        return hrValues.reduce(0, +) / hrValues.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                HStack {
                    Text("Selected: \(selectedMeasurements.count) / \(measurements.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(selectedMeasurements.count == measurements.count ? "Deselect All" : "Select All") {
                        if selectedMeasurements.count == measurements.count {
                            selectedMeasurements.removeAll()
                        } else {
                            selectedMeasurements = Set(measurements.map { $0.id })
                        }
                    }
                    .font(.subheadline.bold())
                }
                .padding()
                .background(Color(UIColor.systemBackground))

                Divider()

                List(measurements) { m in
                    measurementSelectionRow(m)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)

                Divider()

                VStack(spacing: 12) {
                    Text("Export Format")
                        .font(.headline)
                    HStack(spacing: 16) {
                        exportButton("CSV", icon: "doc.text.fill") { exportCSV() }
                        exportButton("JSON", icon: "doc.json.fill") { exportJSON() }
                        exportButton("Image", icon: "photo.fill") { exportImage() }
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $shareItem) { item in
                ActivityViewController(activityItems: item.items)
            }
            .onAppear {
                selectedMeasurements = Set(measurements.map { $0.id })
            }
        }
    }

    private func measurementSelectionRow(_ m: StoredBPMeasurement) -> some View {
        let isSelected = selectedMeasurements.contains(m.id)
        return HStack {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? .blue : .secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text("Measurement #\(m.sequence)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(m.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(m.systolic)/\(m.diastolic) mmHg")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(isSelected ? .primary : .secondary)

                if let hr = m.heartRate {
                    HStack(spacing: 2) {
                        Image(systemName: "heart.fill").font(.caption2)
                        Text("\(hr) BPM").font(.caption2)
                    }
                    .foregroundStyle(isSelected ? .red : .secondary)
                }
            }
        }
        .padding()
        .background(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
        .cornerRadius(12)
        .contentShape(Rectangle())
        .onTapGesture {
            if selectedMeasurements.contains(m.id) {
                selectedMeasurements.remove(m.id)
            } else {
                selectedMeasurements.insert(m.id)
            }
        }
    }

    private func exportButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(selectedMeasurements.isEmpty ? Color.gray.opacity(0.2) : Color.blue)
            .foregroundStyle(selectedMeasurements.isEmpty ? Color.gray : Color.white)
            .cornerRadius(12)
        }
        .disabled(selectedMeasurements.isEmpty)
    }

    private func saveToTempFile(content: String, fileName: String) -> URL? {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? content.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }

    private func exportCSV() {
        var csv = "Sequence,Date,Systolic,Diastolic,Heart Rate\n"
        for m in selectedItems.sorted(by: { $0.timestamp > $1.timestamp }) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let dateStr = formatter.string(from: m.timestamp)
            let hr = m.heartRate?.description ?? ""
            csv += "\(m.sequence),\(dateStr),\(m.systolic),\(m.diastolic),\(hr)\n"
        }

        guard let url = saveToTempFile(content: csv, fileName: "bp_measurements.csv") else { return }
        shareItem = ExportItem(items: [url])
    }

    private func exportJSON() {
        var jsonString = "[\n"
        let items = selectedItems.sorted(by: { $0.timestamp > $1.timestamp })
        for (index, m) in items.enumerated() {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
            let dateStr = formatter.string(from: m.timestamp)

            jsonString += "  {\n"
            jsonString += "    \"sequence\": \(m.sequence),\n"
            jsonString += "    \"timestamp\": \"\(dateStr)\",\n"
            jsonString += "    \"systolic\": \(m.systolic),\n"
            jsonString += "    \"diastolic\": \(m.diastolic),\n"
            jsonString += "    \"heartRate\": \(m.heartRate ?? 0),\n"
            jsonString += "    \"id\": \"\(m.id)\"\n"
            jsonString += "  }"
            if index < items.count - 1 {
                jsonString += ","
            }
            jsonString += "\n"
        }
        jsonString += "]"

        guard let url = saveToTempFile(content: jsonString, fileName: "bp_measurements.json") else { return }
        shareItem = ExportItem(items: [url])
    }

    @MainActor
    private func exportImage() {
        let items = selectedItems.sorted(by: { $0.timestamp < $1.timestamp })
        guard let firstM = items.first, let lastM = items.last else { return }
        let first = firstM.timestamp
        let last = lastM.timestamp

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let dateRange = first == last ? formatter.string(from: first) : "\(formatter.string(from: first)) - \(formatter.string(from: last))"

        let view = ShareCardLayout(
            sys: avgSystolic,
            dia: avgDiastolic,
            hr: avgHeartRate,
            count: items.count,
            dateRange: dateRange
        )
        .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3.0

        if let uiImage = renderer.uiImage {
            shareItem = ExportItem(items: [uiImage])
        }
    }
}

struct ShareCardLayout: View {
    let sys: Int
    let dia: Int
    let hr: Int
    let count: Int
    let dateRange: String

    var bpStatus: (String, Color, String) {
        if sys < 120 && dia < 80 {
            return ("Normal", .green, "checkmark.circle.fill")
        } else if sys < 130 && dia < 80 {
            return ("Elevated", .orange, "exclamationmark.circle.fill")
        } else if sys < 140 || dia < 90 {
            return ("High Normal", .orange, "exclamationmark.triangle.fill")
        } else if sys < 160 || dia < 100 {
            return ("Hypertension Stage 1", .red, "bolt.heart.fill")
        } else {
            return ("Hypertension Stage 2", .purple, "staroflife.fill")
        }
    }

    var body: some View {
        let (category, color, icon) = bpStatus
        VStack(spacing: 24) {

            VStack(spacing: 4) {
                Text("Health Summary")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                Text("My Hilo Health Report")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ZStack {
                Circle().fill(color.opacity(0.15)).frame(width: 100, height: 100)
                Image(systemName: icon).font(.system(size: 50)).foregroundStyle(color)
            }

            VStack(spacing: 8) {
                Text("AVERAGE STATUS")
                    .font(.caption).fontWeight(.bold).foregroundStyle(.secondary)
                Text(category)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .background(Capsule().fill(color.opacity(0.15)))
            }

            HStack(spacing: 30) {
                VStack(spacing: 4) {
                    Text("\(sys)/\(dia)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                    Text("Avg BP")
                        .font(.caption).foregroundStyle(.secondary)
                }

                VStack(spacing: 4) {
                    Text("\(hr)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.red)
                    Text("Avg HR")
                        .font(.caption).foregroundStyle(.secondary)
                }

                VStack(spacing: 4) {
                    Text("\(count)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                    Text("Readings")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Divider()

            Text(dateRange)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .background(Color.white)
        .cornerRadius(24)
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(color.opacity(0.3), lineWidth: 2))
        .padding()
        .background(Color.white)
        .frame(width: 420)
    }
}

#Preview {
    ResultsTabView()
        .modelContainer(for: StoredBPMeasurement.self, inMemory: true)
}

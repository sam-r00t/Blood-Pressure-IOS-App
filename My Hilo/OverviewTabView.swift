import SwiftUI
import SwiftData

struct OverviewTabView: View {
    @Query private var measurements: [StoredBPMeasurement]

    var avgSystolic: Double {
        guard !measurements.isEmpty else { return 0 }
        return Double(measurements.reduce(0) { $0 + $1.systolic }) / Double(measurements.count)
    }

    var avgDiastolic: Double {
        guard !measurements.isEmpty else { return 0 }
        return Double(measurements.reduce(0) { $0 + $1.diastolic }) / Double(measurements.count)
    }

    var avgHR: Double {
        let hrValues = measurements.compactMap { $0.heartRate }
        guard !hrValues.isEmpty else { return 0 }
        return Double(hrValues.reduce(0, +)) / Double(hrValues.count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    summaryHeader

                    if measurements.isEmpty {
                        ContentUnavailableView("No Data Yet", systemImage: "chart.bar.fill", description: Text("Complete your first capture to see your health overview."))
                            .padding(.top, 40)
                    } else {
                        statusCard
                        averagesGrid
                        healthInsights
                    }
                }
                .padding()
            }
            .navigationTitle("Overview")
        }
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Health Summary")
                .font(.title2.bold())
            Text("Based on \(measurements.count) measurements")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusCard: some View {
        let (category, color, icon) = bpCategory(sys: avgSystolic, dia: avgDiastolic)
        return VStack(spacing: 20) {

            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 100, height: 100)

                if #available(iOS 17.0, *) {
                    Image(systemName: icon)
                        .font(.system(size: 50))
                        .foregroundStyle(color)
                        .symbolEffect(.bounce, value: category)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 50))
                        .foregroundStyle(color)
                }
            }

            VStack(spacing: 8) {
                Text("Average Status")
                    .font(.caption)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.secondary)

                Text(category)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(color.opacity(0.15))
                    )
            }

            HStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text("\(Int(round(avgSystolic)))/\(Int(round(avgDiastolic)))")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                    Text("Avg BP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 4) {
                    Text("\(Int(round(avgHR)))")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.red)
                    Text("Avg HR")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 4) {
                    Text("\(measurements.count)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                    Text("Readings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .overlay(
                    LinearGradient(
                        colors: [color.opacity(0.1), color.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(color.opacity(0.3), lineWidth: 1.5)
        )
    }

    private var averagesGrid: some View {
        HStack(spacing: 16) {
            MetricCard(title: "Avg BP", value: "\(Int(round(avgSystolic)))/\(Int(round(avgDiastolic)))", unit: "mmHg", icon: "heart.fill", color: .blue)
            MetricCard(title: "Avg Heart Rate", value: "\(Int(round(avgHR)))", unit: "BPM", icon: "waveform.path.ecg", color: .red)
        }
    }

    private var healthInsights: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("BP Stages Reference")
                .font(.headline)

            VStack(spacing: 0) {
                StageRow(name: "Normal", range: "< 120 / 80", color: .green)
                Divider()
                StageRow(name: "Elevated / High Normal", range: "120-139 / 80-89", color: .orange)
                Divider()
                StageRow(name: "Hypertension Stage 1", range: "140-159 / 90-99", color: .red)
                StageRow(name: "Hypertension Stage 2", range: ">= 160 / 100", color: .purple)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1))
        }
    }

    private func bpCategory(sys: Double, dia: Double) -> (String, Color, String) {
        if sys < 120 && dia < 80 {
            return ("Normal", .green, "checkmark.circle.fill")
        } else if sys < 130 && dia < 80 {
            return ("Elevated", .orange, "exclamationmark.circle.fill")
        } else if sys < 140 || dia < 90 {
            return ("High Normal", .orange, "exclamationmark.triangle.fill")
        } else if sys < 160 || dia < 100 {
            return ("Hypertension (Stage 1)", .red, "bolt.heart.fill")
        } else {
            return ("Hypertension (Stage 2)", .purple, "staroflife.fill")
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.title3)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(color.opacity(0.15), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

struct StageRow: View {
    let name: String
    let range: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 20, height: 20)

                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            Text(name)
                .font(.subheadline)
                .fontWeight(.medium)
            Spacer()
            Text(range)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.primary.opacity(0.02))
        .contentShape(Rectangle())
    }
}

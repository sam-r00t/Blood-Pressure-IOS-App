import SwiftUI
import SwiftData

struct MainTabView: View {
    @StateObject var viewModel: BLECentralViewModel
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
            OverviewTabView()
                .tabItem {
                    Label("Overview", systemImage: "chart.bar.fill")
                }

            BPCandidateInspectorView(viewModel: viewModel)
                .tabItem {
                    Label("Sync Offline", systemImage: "arrow.triangle.2.circlepath")
                }

            CalibrationTabView(viewModel: viewModel)
                .tabItem {
                    Label("Calibration", systemImage: "target")
                }

            OnDemandCaptureView(viewModel: viewModel)
                .tabItem {
                    Label("Measure", systemImage: "waveform.path.ecg")
                }

            ResultsTabView()
                .tabItem {
                    Label("History", systemImage: "list.bullet.clipboard")
                }
        }
        .onAppear {
            viewModel.modelContext = modelContext
        }
    }
}

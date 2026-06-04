import SwiftUI
import SwiftData

@main
struct My_HiloApp: App {
    @StateObject private var viewModel = BLECentralViewModel()

    init() {

        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        if let path = paths.first {
            try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView(viewModel: viewModel)
        }
        .modelContainer(for: StoredBPMeasurement.self)
    }
}

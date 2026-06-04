import SwiftUI

struct OnDemandCaptureView: View {
    @ObservedObject var viewModel: BLECentralViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {

                HStack {
                    Circle()
                        .fill(viewModel.connectedPeripheral != nil ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text(viewModel.connectedDisplayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)

                Spacer()

                if viewModel.connectedPeripheral == nil {

                    ContentUnavailableView(
                        "Not Connected",
                        systemImage: "link.badge.plus",
                        description: Text("Connect to your pod first before creating an on-demand reading.")
                    )
                } else {
                    switch viewModel.onDemandStage {
                    case .idle:
                        idleView
                    case .measuring(let step):
                        measuringView(step: step)
                    case .computing:
                        computingView
                    case .complete:
                        completeView
                    case .failed(let reason):
                        failedView(reason: reason)
                    }
                }

                Spacer()
            }
            .navigationTitle("Measure Now")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .destructive) {
                        viewModel.resetHistory()
                    } label: {
                        Label("Reset", systemImage: "trash")
                    }
                }
#if DEBUG
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.injectSimulatedWaveform()
                    } label: {
                        Label("Simulate", systemImage: "waveform.path.ecg")
                    }
                }
#endif
            }
        }
    }

    private var idleView: some View {
        VStack(spacing: 32) {
            Image(systemName: "hand.tap.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundStyle(.blue.gradient)
                .symbolEffect(.bounce, options: .repeating)

            VStack(spacing: 8) {
                Text("Capture Pod Raw Data")
                    .font(.title2.bold())
                Text("Triggers a fresh Pod measurement and records the raw waveform frames (research). Wear the Pod snug and stay still for ~90s. Blood pressure comes from the cuff — the Pod's raw data is logged for analysis, not turned into an on-device BP.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }

            Button {
                viewModel.startOnDemandCapture()
            } label: {
                Text("Capture Pod Raw Data")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 40)
        }
    }

    private func measuringView(step: Int) -> some View {
        VStack(spacing: 40) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 20)
                    .frame(width: 200, height: 200)

                Circle()
                    .trim(from: 0.0, to: viewModel.onDemandProgress)
                    .stroke(Color.blue.gradient, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: viewModel.onDemandProgress)

                VStack(spacing: 4) {
                    Text("Step \(step) of 1")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(Int(viewModel.onDemandProgress * 100))%")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                }
            }

            VStack(spacing: 8) {
                Text("Collecting data...")
                    .font(.headline)
                Text("Please hold perfectly still and keep your wrist at heart level.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Button("Cancel", role: .destructive) {
                viewModel.cancelOnDemandCapture()
            }
            .buttonStyle(.bordered)
        }
    }

    private var computingView: some View {
        VStack(spacing: 32) {
            ProgressView()
                .scaleEffect(2)
                .padding()

            VStack(spacing: 8) {
                Text("Computing Chunk...")
                    .font(.title2.bold())
                Text("Analyzing beat morphology...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var completeView: some View {
        VStack(spacing: 32) {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundStyle(.green.gradient)

            VStack(spacing: 8) {
                Text("Raw Data Captured")
                    .font(.title2.bold())
                VStack(spacing: 2) {
                    Text("\(viewModel.lastRawCaptureFrameCount)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                    Text("raw frames captured & saved on device")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 4)

                Label("Blood pressure comes from the cuff. The Pod's raw waveform is logged for research — it isn't turned into an on-device BP.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24).padding(.top, 8)
            }

            Button {
                viewModel.resetOnDemand()
            } label: {
                Text("Done")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.green.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 40)
        }
    }

    private func failedView(reason: String) -> some View {
        VStack(spacing: 32) {
            Image(systemName: "exclamationmark.triangle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundStyle(.red.gradient)

            VStack(spacing: 8) {
                Text("Measurement Failed")
                    .font(.title2.bold())
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }

            Button {
                viewModel.resetOnDemand()
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
    }
}

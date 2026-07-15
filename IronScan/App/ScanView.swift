import SwiftUI

struct ScanView: View {
    @StateObject private var viewModel = ScanViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    prototypeNotice
                    cameraPanel
                    controls
                    if let result = viewModel.result {
                        resultCard(result)
                    }
                    if let benchmark = viewModel.benchmark {
                        benchmarkCard(benchmark)
                    }
                    Text("Confirm with a laboratory test. IronScan is a research prototype and does not replace laboratory testing.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            .navigationTitle("IronScan")
            .task { viewModel.start() }
            .onDisappear { viewModel.stop() }
        }
    }

    private var prototypeNotice: some View {
        Text("Research prototype")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var cameraPanel: some View {
        ZStack(alignment: .bottom) {
            CameraPreviewView(source: viewModel.previewSource)
                .frame(height: 380)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 20))

            #if targetEnvironment(simulator)
            VStack(spacing: 8) {
                Image(systemName: "iphone.gen3.slash")
                    .font(.largeTitle)
                Text("The simulator has no testable rear camera")
                    .font(.headline)
                Text("Use the synthetic fixture below to verify the app and on-device ML flow.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            #endif

            Text(viewModel.statusText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.black.opacity(0.72), in: Capsule())
                .padding(.bottom, 14)
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Button {
                viewModel.capture()
            } label: {
                Label("Capture standardized image", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canCapture)

            #if targetEnvironment(simulator)
            Button {
                viewModel.runSyntheticDemo()
            } label: {
                Label("Run synthetic simulator demo", systemImage: "cpu")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!viewModel.canRunSyntheticWork)
            #endif

            #if !targetEnvironment(simulator)
            Button {
                viewModel.runPhysicalDeviceBenchmark()
            } label: {
                Label("Run 100-scan ML benchmark", systemImage: "gauge.with.dots.needle.67percent")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!viewModel.canRunSyntheticWork)
            #endif
        }
    }

    private func resultCard(_ result: ScanResultSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(result.title)
                .font(.title2.weight(.bold))
            Text(result.detail)
                .foregroundStyle(.secondary)
            Divider()
            LabeledContent("Segmented area", value: result.segmentationAreaRatio.formatted(.percent.precision(.fractionLength(1))))
            LabeledContent("Inference time", value: "\(result.inferenceDurationMs.formatted(.number.precision(.fractionLength(1)))) ms")
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func benchmarkCard(_ benchmark: InferenceBenchmarkSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Physical-device benchmark")
                .font(.title2.weight(.bold))
            Text("Synthetic engineering fixture only")
                .foregroundStyle(.secondary)
            Divider()
            LabeledContent("Device", value: benchmark.deviceModelIdentifier)
            LabeledContent("iOS", value: benchmark.operatingSystemVersion)
            LabeledContent("Iterations", value: benchmark.iterationCount.formatted())
            LabeledContent("Segmentation p95", value: Self.milliseconds(benchmark.segmentationP95Ms))
            LabeledContent("Risk inference p95", value: Self.milliseconds(benchmark.riskInferenceP95Ms))
            LabeledContent("Total pipeline p95", value: Self.milliseconds(benchmark.totalPipelineP95Ms))
            LabeledContent("Peak temporary buffers", value: benchmark.peakTemporaryBufferCount.formatted())
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private static func milliseconds(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)))) ms"
    }
}

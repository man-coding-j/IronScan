import AVFoundation
import SwiftUI
import UIKit

struct ScanView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = ScanViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    prototypeNotice
                    if viewModel.showsPermissionInstructions {
                        permissionInstructions
                    } else {
                        cameraPanel
                        lightingControl
                        captureControls
                    }
                    if let result = viewModel.result {
                        resultCard(result)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
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
                .animation(.spring(response: 0.42, dampingFraction: 0.86), value: viewModel.result)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("IronScan")
            .task { viewModel.start() }
            .onDisappear { viewModel.stop() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    viewModel.refreshPermissionAndRestart()
                }
            }
        }
    }

    private var prototypeNotice: some View {
        Label("Research prototype", systemImage: "testtube.2")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }

    private var permissionInstructions: some View {
        VStack(spacing: 16) {
            Image(systemName: viewModel.permissionStatus == .restricted ? "lock.trianglebadge.exclamationmark" : "camera.fill.badge.exclamationmark")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.orange)
            Text(viewModel.permissionStatus == .restricted ? "Camera access is restricted" : "Camera access is off")
                .font(.title2.weight(.bold))
            Text(viewModel.permissionStatus == .restricted
                 ? "Camera access may be limited by Screen Time or device management settings."
                 : "Open Settings, choose Camera, and allow access for IronScan. Captures remain on this device.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if viewModel.permissionStatus == .denied {
                Button("Open iOS Settings") {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        openURL(settingsURL)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
    }

    private var cameraPanel: some View {
        ZStack {
            CameraPreviewView(source: viewModel.previewSource)
            TongueGuideOverlay()

            if let summary = viewModel.liveScanSummary {
                VStack {
                    HStack {
                        Spacer()
                        LiveAlignmentBadge(summary: summary, isSteady: viewModel.isLiveTongueSteady)
                    }
                    Spacer()
                }
                .padding(14)
            }

            VStack {
                Spacer()
                Text(cameraGuidance)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.68), in: Capsule())
                    .padding(.bottom, 16)
            }
        }
        .frame(height: 430)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
    }

    private var cameraGuidance: String {
        if viewModel.statusText.contains("Processing") || viewModel.statusText.contains("Running") {
            return "Analyzing…"
        }
        if viewModel.isLiveTongueSteady {
            return "Scanning…"
        }
        if let liveScanErrorText = viewModel.liveScanErrorText {
            return liveScanErrorText
        }
        return switch viewModel.readiness {
        case .centerTongue, .moveCloser, .moveFarther: "Align your tongue"
        case .holdStill, .ready: "Hold steady"
        default: viewModel.statusText
        }
    }

    private var lightingControl: some View {
        HStack(spacing: 12) {
            Image(systemName: viewModel.isTorchEnabled ? "flashlight.on.fill" : "flashlight.off.fill")
                .foregroundStyle(viewModel.isTorchEnabled ? .yellow : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Constant lighting")
                    .font(.subheadline.weight(.semibold))
                Text(viewModel.isTorchAvailable ? "Keeps illumination consistent during capture" : "Unavailable in the Simulator")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Constant lighting", isOn: Binding(
                get: { viewModel.isTorchEnabled },
                set: { viewModel.setTorchEnabled($0) }
            ))
            .labelsHidden()
            .disabled(!viewModel.isTorchAvailable || viewModel.isBusy)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var captureControls: some View {
        VStack(spacing: 12) {
            Button {
                viewModel.capture()
            } label: {
                Label(viewModel.previewSource.isSimulated ? "Capture simulated frame" : "Capture standardized image", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canCapture)

            #if !targetEnvironment(simulator)
            Button {
                viewModel.runPhysicalDeviceBenchmark()
            } label: {
                Label("Run 100-scan ML benchmark", systemImage: "gauge.with.dots.needle.67percent")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.canRunSyntheticWork)
            #endif
        }
    }

    private func resultCard(_ result: ScanResultSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.title)
                        .font(.title2.weight(.bold))
                    Text(result.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: result.decision == .unableToAssess ? "questionmark.circle.fill" : "waveform.path.ecg")
                    .font(.title)
                    .foregroundStyle(resultColor(result.decision))
            }
            if let score = result.riskScore {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Research risk score")
                        Spacer()
                        Text(score.formatted(.number.precision(.fractionLength(2))))
                            .font(.title3.monospacedDigit().weight(.bold))
                    }
                    ProgressView(value: min(max(score, 0), 1))
                        .tint(resultColor(result.decision))
                }
            }
            Divider()
            LabeledContent("Segmented area", value: result.segmentationAreaRatio.formatted(.percent.precision(.fractionLength(1))))
            LabeledContent("Inference time", value: "\(result.inferenceDurationMs.formatted(.number.precision(.fractionLength(1)))) ms")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20)
                .fill(resultColor(result.decision))
                .frame(width: 5)
        }
    }

    private func benchmarkCard(_ benchmark: InferenceBenchmarkSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Physical-device benchmark").font(.title2.weight(.bold))
            Text("Synthetic engineering fixture only").foregroundStyle(.secondary)
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
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func resultColor(_ decision: RiskDecision) -> Color {
        switch decision {
        case .lowerObservedRisk: .green
        case .possibleRisk: .orange
        case .unableToAssess: .gray
        }
    }

    private static func milliseconds(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)))) ms"
    }
}

private struct LiveAlignmentBadge: View {
    let summary: LiveScanSummary
    let isSteady: Bool
    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.22), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: min(max(summary.alignmentProgress, 0), 1))
                    .stroke(isSteady ? .green : .orange, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: isSteady ? "dot.radiowaves.left.and.right" : "viewfinder")
                    .foregroundStyle(.white)
                    .scaleEffect(isSteady && isPulsing ? 1.14 : 0.92)
            }
            .frame(width: 48, height: 48)
            Text(isSteady ? "Scanning…" : "Aligning")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
            Text("\(summary.inferenceDurationMs.formatted(.number.precision(.fractionLength(0)))) ms")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.72))
        }
        .padding(10)
        .background(.black.opacity(0.64), in: RoundedRectangle(cornerRadius: 14))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isSteady ? "Tongue aligned, scanning" : "Aligning tongue")
        .accessibilityValue("Alignment \(summary.alignmentProgress.formatted(.percent.precision(.fractionLength(0))))")
    }
}

private struct TongueGuideOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            let targetRect = CGRect(
                x: geometry.size.width * 0.27,
                y: geometry.size.height * 0.25,
                width: geometry.size.width * 0.46,
                height: geometry.size.height * 0.52
            )
            Canvas { context, size in
                var mask = Path(CGRect(origin: .zero, size: size))
                mask.addEllipse(in: targetRect)
                context.fill(mask, with: .color(.black.opacity(0.42)), style: FillStyle(eoFill: true))
                context.stroke(Path(ellipseIn: targetRect), with: .color(.white.opacity(0.95)), style: StrokeStyle(lineWidth: 3, dash: [10, 7]))
            }
            Text("TONGUE TARGET")
                .font(.caption2.weight(.bold))
                .tracking(1.6)
                .foregroundStyle(.white)
                .position(x: targetRect.midX, y: targetRect.minY - 18)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

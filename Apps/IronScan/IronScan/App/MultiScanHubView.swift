import AVFoundation
import SwiftUI
import UIKit

struct MultiScanHubView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scanSessionID = UUID()
    @State private var isCameraFlowActive = true
    private let inference: MultiTissueInferenceActor
    private let onCompleted: (TriangulationResult) -> Void

    init(
        inference: MultiTissueInferenceActor = MultiTissueInferenceActor(),
        onCompleted: @escaping (TriangulationResult) -> Void = { _ in }
    ) {
        self.inference = inference
        self.onCompleted = onCompleted
    }

    var body: some View {
        ZStack {
            Color(red: 18 / 255, green: 18 / 255, blue: 20 / 255)
                .ignoresSafeArea()

            if isCameraFlowActive {
                MultiScanSessionView(
                    inference: inference,
                    onCompleted: onCompleted,
                    onAbort: handleAbort
                )
                .id(scanSessionID)
            } else {
                abortedState
            }
        }
    }

    private var abortedState: some View {
        VStack(spacing: 18) {
            Image(systemName: "house.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(IronTheme.terracottaPrimary)

            Text("Camera flow closed")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text("Start again when you're ready. The next scan will begin fresh at the eye step.")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.72))
                .multilineTextAlignment(.center)

            Button("Start New Scan") {
                scanSessionID = UUID()
                isCameraFlowActive = true
            }
            .buttonStyle(TealPrimaryButtonStyle())
        }
        .padding(28)
    }

    private func handleAbort() {
        isCameraFlowActive = false
        scanSessionID = UUID()
        dismiss()
    }
}

private struct MultiScanSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: MultiScanHubViewModel
    @State private var showsReport = false
    @State private var showsAnalyzing = false
    @State private var showsIncompleteScanAlert = false
    private let onCompleted: (TriangulationResult) -> Void
    private let onAbort: () -> Void

    init(
        inference: MultiTissueInferenceActor,
        onCompleted: @escaping (TriangulationResult) -> Void,
        onAbort: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: MultiScanHubViewModel(inference: inference))
        self.onCompleted = onCompleted
        self.onAbort = onAbort
    }

    var body: some View {
        NavigationStack {
            contentBody
            .toolbar(.hidden, for: .navigationBar)
            .task { viewModel.start() }
            .onDisappear { viewModel.stop() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { viewModel.refreshPermissionAndRestart() }
            }
            .onChange(of: viewModel.isAnalyzingTongueCapture) { _, isAnalyzing in
                withAnimation(.easeInOut(duration: 0.24)) {
                    showsAnalyzing = isAnalyzing
                }
            }
            .onChange(of: viewModel.lastError) { _, error in
                showsIncompleteScanAlert = error == "Scan incomplete. Please retake the tongue photo."
            }
            .onChange(of: viewModel.triangulationResult) { _, result in
                guard let result else { return }
                onCompleted(result)
                showsAnalyzing = false
                showsReport = true
            }
            .alert("Scan incomplete. Please retake the tongue photo.", isPresented: $showsIncompleteScanAlert) {
                Button("OK", role: .cancel) {}
            }
            .sheet(isPresented: $showsReport) {
                reportSheet
            }
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        ZStack {
            Color(red: 18 / 255, green: 18 / 255, blue: 20 / 255)
                .ignoresSafeArea()

            if viewModel.showsPermissionInstructions {
                permissionInstructions
            } else if viewModel.triangulationResult != nil {
                completedCard
            } else if showsAnalyzing {
                analyzingOverlay
            } else {
                cameraExperience
            }
        }
    }

    @ViewBuilder
    private var reportSheet: some View {
        if let result = viewModel.triangulationResult {
            ScanResultView(
                result: result,
                outputs: viewModel.completedOutputs,
                onScanAgain: {
                    showsReport = false
                    showsAnalyzing = false
                    viewModel.resetDemo()
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
        } else {
            Color.clear
        }
    }

    private var cameraExperience: some View {
        VStack(spacing: 16) {
            stepProgress

            CameraView(
                source: viewModel.previewSource,
                lensPosition: viewModel.lensPosition,
                captureOrientation: viewModel.captureOrientation,
                tissue: viewModel.currentTissue,
                statusText: viewModel.statusText,
                eyeGuidanceText: viewModel.eyeGuidanceText,
                isBusy: viewModel.isBusy,
                supportsCameraToggle: viewModel.supportsCameraToggle,
                isTorchAvailable: viewModel.isTorchAvailable,
                isTorchEnabled: viewModel.isTorchEnabled,
                isSwitchingCamera: viewModel.isSwitchingCamera,
                showsMotionWarning: viewModel.showsMotionWarning,
                autoCapturePhase: viewModel.autoCapturePhase,
                imageQualityAssessment: viewModel.imageQualityAssessment,
                onOrientationChange: viewModel.updateCaptureOrientation,
                onClose: handleAbort,
                onToggleTorch: { viewModel.setTorchEnabled(!viewModel.isTorchEnabled) },
                onToggleCamera: { viewModel.toggleCamera() },
                onManualCapture: { viewModel.forceManualCapture() }
            )

            if let error = viewModel.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var stepProgress: some View {
        HStack(spacing: 10) {
            ForEach(Array(TissueSite.allCases.enumerated()), id: \.element) { index, tissue in
                VStack(spacing: 6) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(stepColor(for: tissue))
                        .frame(width: 26, height: 26)
                        .background(stepColor(for: tissue).opacity(0.14), in: Circle())
                    Text(tissue.displayName)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.white.opacity(viewModel.currentTissue == tissue ? 0.96 : 0.6))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var analyzingOverlay: some View {
        AnalyzingView {
            Color.clear
                .ignoresSafeArea()
        }
    }

    private var completedCard: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 50))
                .foregroundStyle(IronTheme.sageAccent)
            Text("Three-step scan complete")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text("Review the combined research summary or begin a new scan.")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.7))
                .multilineTextAlignment(.center)

            Button("Review result") {
                showsReport = true
            }
            .buttonStyle(TealPrimaryButtonStyle())

            Button("Start another scan") {
                showsAnalyzing = false
                viewModel.resetDemo()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(0.78))
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    private var permissionInstructions: some View {
        VStack(spacing: 18) {
            Image(systemName: "camera.fill.badge.exclamationmark")
                .font(.system(size: 42))
                .foregroundStyle(IronTheme.terracottaPrimary)
            Text("Camera access is required for the three-step scan")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("Grant access to continue capturing the eye, nail, and tongue scans.")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.7))
                .multilineTextAlignment(.center)
            if viewModel.permissionStatus == .denied {
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(TealPrimaryButtonStyle())
            }
        }
        .padding(28)
    }

    private func stepColor(for tissue: TissueSite) -> Color {
        if viewModel.completedOutputs[tissue] != nil {
            return IronTheme.sageAccent
        }
        if viewModel.currentTissue == tissue {
            return IronTheme.terracottaPrimary
        }
        return Color.white.opacity(0.38)
    }

    private func handleAbort() {
        showsReport = false
        showsAnalyzing = false
        showsIncompleteScanAlert = false
        viewModel.resetDemo()
        viewModel.stop()
        onAbort()
        dismiss()
    }
}

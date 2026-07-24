import AVFoundation
import SwiftUI
import UIKit

struct MultiScanHubView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: MultiScanHubViewModel
    @State private var showsReport = false
    private let onCompleted: (TriangulationResult) -> Void

    init(
        inference: MultiTissueInferenceActor = MultiTissueInferenceActor(),
        onCompleted: @escaping (TriangulationResult) -> Void = { _ in }
    ) {
        _viewModel = StateObject(wrappedValue: MultiScanHubViewModel(inference: inference))
        self.onCompleted = onCompleted
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    scanHeader
                    stepChecklist
                    if viewModel.showsPermissionInstructions {
                        permissionInstructions
                    } else if viewModel.triangulationResult != nil {
                        completedCard
                    } else {
                        cameraPanel
                        cameraControls
                    }
                    if let error = viewModel.lastError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .liquidGlassCard(cornerRadius: 18)
                    }
                    Text("Research prototype — confirm with a laboratory test.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 120)
            }
            .background(IronTheme.mintBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .task { viewModel.start() }
            .onDisappear { viewModel.stop() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { viewModel.refreshPermissionAndRestart() }
            }
            .onChange(of: viewModel.triangulationResult) { _, result in
                guard let result else { return }
                onCompleted(result)
                showsReport = true
            }
            .sheet(isPresented: $showsReport) {
                if let result = viewModel.triangulationResult {
                    ScrollView {
                        IntegratedResearchReportView(
                            triangulation: result,
                            outputs: viewModel.completedOutputs,
                            onScanAgain: {
                                showsReport = false
                                viewModel.resetDemo()
                            }
                        )
                        .padding(18)
                    }
                    .background(IronTheme.mintBackground.ignoresSafeArea())
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(32)
                }
            }
        }
    }

    private var scanHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Multi-site scan")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(IronTheme.textDark)
            Text("Complete eye, nail, and tongue images in order.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stepChecklist: some View {
        HStack(spacing: 8) {
            ForEach(Array(TissueSite.allCases.enumerated()), id: \.element) { index, tissue in
                VStack(spacing: 7) {
                    Image(systemName: viewModel.completedOutputs[tissue] == nil ? "\(index + 1).circle" : "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            viewModel.completedOutputs[tissue] == nil
                                ? (viewModel.currentTissue == tissue ? IronTheme.tealPrimary : Color.secondary)
                                : IronTheme.tealPrimary
                        )
                    Text(tissue.displayName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(IronTheme.textDark)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    viewModel.currentTissue == tissue && viewModel.triangulationResult == nil
                        ? IronTheme.tealPrimary.opacity(0.14)
                        : Color.clear,
                    in: Capsule()
                )
            }
        }
        .padding(7)
        .liquidGlassCard(cornerRadius: 28)
    }

    private var cameraPanel: some View {
        ZStack {
            CameraPreviewView(
                source: viewModel.previewSource,
                lensPosition: viewModel.lensPosition,
                onOrientationChange: { orientation in
                    viewModel.updateCaptureOrientation(orientation)
                }
            )
            TissueGuideOverlay(tissue: viewModel.currentTissue)
            if viewModel.isAutoCaptureEnabled {
                AutoCaptureCountdownOverlay(phase: viewModel.autoCapturePhase)
            }
            VStack {
                HStack {
                    if viewModel.supportsCameraToggle {
                        Button(action: { viewModel.toggleCamera() }) {
                            Image(systemName: "camera.rotate.fill")
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .organicGlassEffect(
                                    in: Circle(),
                                    tint: Color.black.opacity(0.14),
                                    interactive: true
                                )
                        }
                        .disabled(viewModel.isBusy)
                    }
                    Spacer()
                }
                if viewModel.showsMotionWarning {
                    Label("Hold phone steady...", systemImage: "iphone.gen3.radiowaves.left.and.right")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.orange.opacity(0.9), in: Capsule())
                        .transition(.opacity)
                }
                Spacer()
                Text(viewModel.statusText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(IronTheme.textDark)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .organicGlassEffect(in: Capsule(), tint: IronTheme.cardGlass)
                if viewModel.currentTissue == .eye, let guidance = viewModel.eyeGuidanceText {
                    Label(
                        guidance,
                        systemImage: guidance.hasPrefix("Conjunctiva located")
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        guidance.hasPrefix("Conjunctiva located")
                            ? Color.green.opacity(0.82)
                            : Color.orange.opacity(0.88),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                }
            }
            .padding(14)
        }
        .aspectRatio(viewModel.captureOrientation.isPortrait ? 3 / 4 : 16 / 9, contentMode: .fit)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.8), lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 18, y: 8)
        .transaction { $0.animation = nil }
    }

    private var cameraControls: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Smart auto-capture", systemImage: "viewfinder.circle")
                    Text("Hold alignment for one second, then follow the 3-second countdown.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Smart auto-capture", isOn: Binding(
                    get: { viewModel.isAutoCaptureEnabled },
                    set: { enabled in viewModel.setAutoCaptureEnabled(enabled) }
                ))
                .labelsHidden()
                .disabled(viewModel.isBusy)
            }
            .padding()
            .liquidGlassCard(cornerRadius: 20)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label(
                        "Constant lighting",
                        systemImage: viewModel.isTorchEnabled ? "flashlight.on.fill" : "flashlight.off.fill"
                    )
                    if viewModel.currentTissue == .nail, viewModel.isTorchAvailable {
                        Text("Low-power nail lighting is automatic")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Toggle("Constant lighting", isOn: Binding(
                    get: { viewModel.isTorchEnabled },
                    set: { enabled in viewModel.setTorchEnabled(enabled) }
                ))
                .labelsHidden()
                .disabled(!viewModel.isTorchAvailable || viewModel.isBusy)
            }
            .padding()
            .liquidGlassCard(cornerRadius: 20)

            Button(action: { viewModel.captureCurrentTissue() }) {
                Label(
                    "Manually capture \(viewModel.currentTissue.displayName) image",
                    systemImage: "camera.fill"
                )
            }
            .buttonStyle(TealPrimaryButtonStyle())
            .disabled(!viewModel.canCapture)
        }
    }

    private var completedCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(IronTheme.tealPrimary)
            Text("Three-step scan complete")
                .font(.title2.weight(.bold))
                .foregroundStyle(IronTheme.textDark)
            Text("Review the combined research summary or begin a new scan.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Review result") {
                showsReport = true
            }
            .buttonStyle(TealPrimaryButtonStyle())
            Button("Start another scan") {
                viewModel.resetDemo()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(IronTheme.tealDeep)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .liquidGlassCard()
    }

    private var permissionInstructions: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill.badge.exclamationmark")
                .font(.system(size: 42))
                .foregroundStyle(.orange)
            Text("Camera access is required for the three-step scan")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            if viewModel.permissionStatus == .denied {
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .liquidGlassCard()
    }
}

private struct AutoCaptureCountdownOverlay: View {
    let phase: AutoCapturePhase

    var body: some View {
        if let presentation {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.28), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: presentation.progress)
                    .stroke(
                        IronTheme.tealPrimary,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text(presentation.label)
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            .frame(width: 94, height: 94)
            .padding(14)
            .organicGlassEffect(in: Circle(), tint: Color.black.opacity(0.12))
            .shadow(color: IronTheme.tealPrimary.opacity(0.35), radius: 18)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.accessibilityLabel)
            .animation(.linear(duration: 0.08), value: presentation.progress)
        }
    }

    private var presentation: Presentation? {
        switch phase {
        case let .holding(progress):
            Presentation(
                label: "✓",
                progress: progress,
                accessibilityLabel: "Alignment detected. Hold steady."
            )
        case let .countdown(secondsRemaining, progress):
            Presentation(
                label: "\(secondsRemaining)",
                progress: progress,
                accessibilityLabel: "Auto capture in \(secondsRemaining)"
            )
        case .readyToCapture:
            Presentation(
                label: "✓",
                progress: 1,
                accessibilityLabel: "Capturing image"
            )
        case .disabled, .seeking, .reset:
            nil
        }
    }

    private struct Presentation {
        let label: String
        let progress: Double
        let accessibilityLabel: String
    }
}

private struct TissueGuideOverlay: View {
    let tissue: TissueSite

    var body: some View {
        GeometryReader { geometry in
            let guide = tissue.guideRect(in: geometry.size)
            Canvas { context, size in
                var mask = Path(CGRect(origin: .zero, size: size))
                mask.addPath(tissue.guidePath(in: guide))
                context.fill(mask, with: .color(.black.opacity(0.42)), style: FillStyle(eoFill: true))
                context.stroke(
                    tissue.guidePath(in: guide),
                    with: .color(.white),
                    style: StrokeStyle(lineWidth: 3, dash: [10, 7])
                )
                if tissue == .eye {
                    let target = tissue.conjunctivaTargetRect(in: size)
                    context.stroke(
                        Path(roundedRect: target, cornerRadius: target.height * 0.45),
                        with: .color(.cyan),
                        lineWidth: 3
                    )
                }
            }
            Text(tissue.guideTitle)
                .font(.caption2.weight(.black))
                .tracking(1.4)
                .foregroundStyle(.white)
                .position(x: guide.midX, y: guide.minY - 18)
            if tissue == .eye {
                let target = tissue.conjunctivaTargetRect(in: geometry.size)
                Text("LOWER EYELID TARGET")
                    .font(.caption2.weight(.black))
                    .tracking(1)
                    .foregroundStyle(.cyan)
                    .position(x: target.midX, y: target.maxY + 17)
            }
        }
        .allowsHitTesting(false)
    }
}

private extension TissueSite {
    var instruction: String {
        switch self {
        case .eye: "Center your face, look upward, and gently lower one eyelid."
        case .nail: "Place one fingernail flat inside the rectangle."
        case .tongue: "Center the tongue inside the rounded guide."
        }
    }

    var guideTitle: String {
        switch self {
        case .eye: "EYE GUIDE"
        case .nail: "NAIL GUIDE"
        case .tongue: "TONGUE GUIDE"
        }
    }

    func guideRect(in size: CGSize) -> CGRect {
        switch self {
        case .eye:
            CGRect(x: size.width * 0.18, y: size.height * 0.12, width: size.width * 0.64, height: size.height * 0.68)
        case .nail:
            CGRect(x: size.width * 0.25, y: size.height * 0.27, width: size.width * 0.5, height: size.height * 0.42)
        case .tongue:
            CGRect(x: size.width * 0.27, y: size.height * 0.25, width: size.width * 0.46, height: size.height * 0.5)
        }
    }

    func guidePath(in rect: CGRect) -> Path {
        switch self {
        case .eye, .tongue: Path(ellipseIn: rect)
        case .nail: Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) * 0.12)
        }
    }

    func conjunctivaTargetRect(in size: CGSize) -> CGRect {
        CGRect(
            x: size.width * 0.25,
            y: size.height * 0.39,
            width: size.width * 0.5,
            height: size.height * 0.1
        )
    }
}

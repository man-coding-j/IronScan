import AVFoundation
import SwiftUI
import UIKit

struct CameraView: View {
    let source: CameraPreviewSource
    let lensPosition: CameraLensPosition
    let captureOrientation: CaptureOrientation
    let tissue: TissueSite
    let statusText: String
    let eyeGuidanceText: String?
    let isBusy: Bool
    let supportsCameraToggle: Bool
    let isTorchAvailable: Bool
    let isTorchEnabled: Bool
    let isSwitchingCamera: Bool
    let showsMotionWarning: Bool
    let autoCapturePhase: AutoCapturePhase
    let imageQualityAssessment: ImageQualityGatekeeper.Assessment
    let onOrientationChange: (CaptureOrientation) -> Void
    let onClose: () -> Void
    let onToggleTorch: () -> Void
    let onToggleCamera: () -> Void
    let onManualCapture: () -> Void

    @Namespace private var scanTransition
    @State private var showsResultCards = false

    private let shutterImpact = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        ZStack {
            CameraPreviewView(
                source: source,
                lensPosition: lensPosition,
                onOrientationChange: onOrientationChange
            )
            .ignoresSafeArea()

            viewfinderOverlay
                .ignoresSafeArea()

            controlsOverlay
        }
        .environment(\.colorScheme, .dark)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            showsResultCards = shouldShowResultCards
        }
        .onChange(of: shouldShowResultCards) { _, newValue in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showsResultCards = newValue
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: tissue)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: imageQualityAssessment)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: autoCapturePhase)
    }

    private var controlsOverlay: some View {
        VStack(spacing: 18) {
            topControls

            diagnosticOverlay

            Spacer(minLength: 0)

            bottomControls
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    private var topControls: some View {
        HStack(alignment: .top, spacing: 12) {
            secondaryControlButton(systemName: "xmark", action: onClose)
                .accessibilityLabel("Abort scan and return home")

            VStack(spacing: 4) {
                Text(currentTitle)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(stepLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .cameraFloatingGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            secondaryControlButton(
                systemName: isTorchEnabled ? "flashlight.on.fill" : "flashlight.off.fill",
                action: onToggleTorch,
                enabled: isTorchAvailable
            )
            .accessibilityLabel(isTorchEnabled ? "Turn flashlight off" : "Turn flashlight on")
        }
    }

    private var diagnosticOverlay: some View {
        VStack(spacing: 14) {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 16) {
                    diagnosticContent
                }
            } else {
                diagnosticContent
            }

            if let warningText {
                warningTag(text: warningText)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var diagnosticContent: some View {
        if showsResultCards {
            resultCards
                .transition(.scale(scale: 0.96).combined(with: .opacity))
        } else {
            scanningTags
                .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
    }

    private var scanningTags: some View {
        VStack(spacing: 12) {
            diagnosticTag(
                title: scanningTitle,
                subtitle: statusText,
                systemName: scanningSymbol,
                tint: scanTint,
                glassID: "scanTag"
            )

            HStack(spacing: 12) {
                diagnosticTag(
                    title: lightingText,
                    subtitle: lightingDetailText,
                    systemName: lightingSymbol,
                    tint: outlineTint.opacity(0.22),
                    glassID: "scanQuality"
                )

                if tissue == .eye, let eyeGuidanceText {
                    diagnosticTag(
                        title: "Guidance",
                        subtitle: eyeGuidanceText,
                        systemName: "viewfinder",
                        tint: IronTheme.cardGlass.opacity(0.24),
                        glassID: "scanGuidance"
                    )
                }
            }
        }
    }

    private var resultCards: some View {
        VStack(spacing: 12) {
            resultCard(
                title: resultTitle,
                subtitle: resultSubtitle,
                systemName: "checkmark.circle.fill",
                tint: outlineTint.opacity(0.22),
                glassID: "scanTag"
            )

            HStack(spacing: 12) {
                resultCard(
                    title: "Lighting",
                    subtitle: lightingText,
                    systemName: lightingSymbol,
                    tint: outlineTint.opacity(0.18),
                    glassID: "scanQuality"
                )

                resultCard(
                    title: "Capture",
                    subtitle: captureStateText,
                    systemName: "camera.macro",
                    tint: IronTheme.cardGlass.opacity(0.22),
                    glassID: "scanGuidance"
                )
            }
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                if supportsCameraToggle {
                    secondaryControlButton(
                        systemName: "camera.rotate.fill",
                        action: handleCameraToggle,
                        enabled: !isSwitchingCamera
                    )
                    .accessibilityLabel("Switch camera")
                }

                Button {
                    shutterImpact.impactOccurred()
                    onManualCapture()
                } label: {
                    VStack(spacing: 10) {
                        ShutterButton(phase: autoCapturePhase)

                        Text(isBusy ? "Processing…" : "Capture")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .primaryGlassButtonStyle()
                .disabled(isBusy)
                .accessibilityLabel("Capture \(tissue.displayName) image")

                secondaryControlButton(
                    systemName: isTorchEnabled ? "bolt.fill" : "bolt.slash.fill",
                    action: onToggleTorch,
                    enabled: isTorchAvailable
                )
                .accessibilityLabel(isTorchEnabled ? "Disable flash" : "Enable flash")
            }
        }
    }

    private var viewfinderOverlay: some View {
        GeometryReader { geometry in
            let rect = tissue.cameraTargetRect(in: geometry.size)
            let path = tissue.cameraTargetPath(in: rect)

            ZStack {
                path
                    .stroke(outlineTint.opacity(0.26), lineWidth: 28)
                    .blur(radius: 18)

                path
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.86),
                                outlineTint,
                                Color.white.opacity(0.76)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 4.5, lineCap: .round, dash: [16, 10])
                    )

                GlowingCorners(rect: rect, tint: outlineTint)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }

    private func diagnosticTag(
        title: String,
        subtitle: String,
        systemName: String,
        tint: Color,
        glassID: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cameraFloatingGlass(
            in: Capsule(),
            tint: tint,
            interactive: true
        )
        .cameraGlassEffectID(glassID, in: scanTransition)
    }

    private func resultCard(
        title: String,
        subtitle: String,
        systemName: String,
        tint: Color,
        glassID: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cameraFloatingGlass(
            in: RoundedRectangle(cornerRadius: 20, style: .continuous),
            tint: tint,
            interactive: true
        )
        .cameraGlassEffectID(glassID, in: scanTransition)
    }

    private func warningTag(text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .center)
            .criticalCameraGlass(in: Capsule())
    }

    private func secondaryControlButton(
        systemName: String,
        action: @escaping () -> Void,
        enabled: Bool = true
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline.weight(.bold))
                .foregroundStyle(enabled ? .primary : .secondary)
                .frame(width: 46, height: 46)
        }
        .secondaryGlassButtonStyle()
        .disabled(!enabled)
    }

    private func handleCameraToggle() {
        guard supportsCameraToggle, !isSwitchingCamera else { return }
        onToggleCamera()
    }

    private var shouldShowResultCards: Bool {
        if case .readyToCapture = autoCapturePhase {
            return true
        }
        return false
    }

    private var warningText: String? {
        if showsMotionWarning {
            return "Move Closer"
        }

        switch imageQualityAssessment {
        case .tooDark:
            return "Add More Light"
        case .tooBlurry:
            return "Hold Steady"
        case .optimal:
            return nil
        }
    }

    private var scanningTitle: String {
        switch autoCapturePhase {
        case .disabled:
            "Manual Capture"
        case .seeking:
            "Analyzing…"
        case let .holding(progress):
            "Focusing \(Int(progress * 100))%"
        case let .countdown(secondsRemaining, _):
            "Capturing in \(secondsRemaining)…"
        case .readyToCapture:
            "Ready"
        case let .reset(message):
            message
        }
    }

    private var scanningSymbol: String {
        switch autoCapturePhase {
        case .readyToCapture:
            "checkmark.circle.fill"
        case .countdown:
            "timer"
        case .holding:
            "scope"
        case .reset:
            "arrow.trianglehead.clockwise"
        case .disabled, .seeking:
            "waveform.and.magnifyingglass"
        }
    }

    private var resultTitle: String {
        switch imageQualityAssessment {
        case .optimal:
            "Ready to Capture"
        case .tooDark:
            "Lighting Needs Work"
        case .tooBlurry:
            "Refocus Before Capture"
        }
    }

    private var resultSubtitle: String {
        switch imageQualityAssessment {
        case .optimal:
            return "The framing and clarity look good for the next capture."
        case .tooDark:
            return "Bring the subject into brighter light before continuing."
        case .tooBlurry:
            return "Pause movement briefly so the next frame lands sharply."
        }
    }

    private var captureStateText: String {
        switch autoCapturePhase {
        case .disabled:
            "Tap the shutter to capture manually."
        case .seeking:
            "Searching for stable framing."
        case .holding:
            "Maintaining alignment."
        case .countdown:
            "Auto-capture is almost ready."
        case .readyToCapture:
            "The next frame is primed for capture."
        case let .reset(message):
            message
        }
    }

    private var lightingDetailText: String {
        switch imageQualityAssessment {
        case .optimal:
            "Lighting and sharpness look stable."
        case .tooDark:
            "Scene is underexposed."
        case .tooBlurry:
            "Frame motion is too high."
        }
    }

    private var scanTint: Color {
        switch autoCapturePhase {
        case .readyToCapture:
            IronTheme.sageAccent.opacity(0.24)
        case .countdown:
            Color.green.opacity(0.22)
        case .holding:
            Color.blue.opacity(0.20)
        case .reset:
            Color.orange.opacity(0.22)
        case .disabled, .seeking:
            IronTheme.cardGlass.opacity(0.24)
        }
    }

    private var outlineTint: Color {
        switch imageQualityAssessment {
        case .optimal:
            IronTheme.sageAccent
        case .tooDark:
            IronTheme.terracottaPrimary
        case .tooBlurry:
            Color.yellow
        }
    }

    private var currentTitle: String {
        switch tissue {
        case .eye:
            "Position Your Eye Inside the Frame"
        case .nail:
            "Position Your Nail Inside the Frame"
        case .tongue:
            "Position Your Tongue Inside the Frame"
        }
    }

    private var stepLabel: String {
        switch tissue {
        case .eye:
            "Step 1 of 3"
        case .nail:
            "Step 2 of 3"
        case .tongue:
            "Step 3 of 3"
        }
    }

    private var lightingSymbol: String {
        switch imageQualityAssessment {
        case .optimal:
            "sun.max.fill"
        case .tooDark:
            "sun.haze.fill"
        case .tooBlurry:
            "camera.aperture"
        }
    }

    private var lightingText: String {
        switch imageQualityAssessment {
        case .optimal:
            "EV OK"
        case .tooDark:
            "LOW EV"
        case .tooBlurry:
            "BLUR"
        }
    }
}

private struct ShutterButton: View {
    let phase: AutoCapturePhase

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.86), lineWidth: 6)
                .frame(width: 86, height: 86)

            if let progress {
                Circle()
                    .trim(from: 0, to: progress.value)
                    .stroke(
                        progress.color,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 96, height: 96)

                Text(progress.label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .offset(y: 64)
            }

            Circle()
                .fill(Color.white)
                .frame(width: 64, height: 64)
        }
    }

    private var progress: (value: Double, color: Color, label: String)? {
        switch phase {
        case let .holding(progress):
            (progress, IronTheme.sageAccent, "Hold")
        case let .countdown(secondsRemaining, progress):
            (progress, .green, "\(secondsRemaining)…")
        case .readyToCapture:
            (1, .green, "Now")
        case .disabled, .seeking, .reset:
            nil
        }
    }
}

private struct GlowingCorners: View {
    let rect: CGRect
    let tint: Color

    var body: some View {
        let length = min(rect.width, rect.height) * 0.18

        Group {
            corner(at: CGPoint(x: rect.minX, y: rect.minY), xSign: 1, ySign: 1, length: length)
            corner(at: CGPoint(x: rect.maxX, y: rect.minY), xSign: -1, ySign: 1, length: length)
            corner(at: CGPoint(x: rect.minX, y: rect.maxY), xSign: 1, ySign: -1, length: length)
            corner(at: CGPoint(x: rect.maxX, y: rect.maxY), xSign: -1, ySign: -1, length: length)
        }
        .foregroundStyle(tint)
        .shadow(color: tint.opacity(0.4), radius: 8)
    }

    private func corner(
        at point: CGPoint,
        xSign: CGFloat,
        ySign: CGFloat,
        length: CGFloat
    ) -> some View {
        Path { path in
            path.move(to: CGPoint(x: point.x + xSign * length, y: point.y))
            path.addLine(to: point)
            path.addLine(to: CGPoint(x: point.x, y: point.y + ySign * length))
        }
        .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
    }
}

private struct CameraFloatingGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                content.glassEffect(.regular.tint(tint).interactive(), in: shape)
            } else {
                content.glassEffect(.regular.tint(tint), in: shape)
            }
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(tint.opacity(interactive ? 0.64 : 0.56), in: shape)
                .overlay {
                    shape.stroke(Color.white.opacity(0.28), lineWidth: 0.8)
                }
        }
    }
}

private struct CameraGlassEffectIDModifier: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffectID(id, in: namespace)
        } else {
            content
        }
    }
}

private extension View {
    func cameraFloatingGlass<S: InsettableShape>(
        in shape: S,
        tint: Color = IronTheme.cardGlass,
        interactive: Bool = false
    ) -> some View {
        modifier(CameraFloatingGlassModifier(shape: shape, tint: tint, interactive: interactive))
    }

    func criticalCameraGlass<S: InsettableShape>(in shape: S) -> some View {
        cameraFloatingGlass(in: shape, tint: IronTheme.criticalGlassTint, interactive: true)
    }

    func cameraGlassEffectID(_ id: String, in namespace: Namespace.ID) -> some View {
        modifier(CameraGlassEffectIDModifier(id: id, namespace: namespace))
    }

    @ViewBuilder
    func primaryGlassButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            liquidGlassButtonStyle(prominent: true)
        }
    }

    @ViewBuilder
    func secondaryGlassButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            liquidGlassButtonStyle()
        }
    }
}

private extension TissueSite {
    func cameraTargetRect(in size: CGSize) -> CGRect {
        switch self {
        case .eye:
            CGRect(
                x: size.width * 0.14,
                y: size.height * 0.28,
                width: size.width * 0.72,
                height: size.height * 0.18
            )
        case .nail:
            CGRect(
                x: size.width * 0.24,
                y: size.height * 0.24,
                width: size.width * 0.52,
                height: size.height * 0.34
            )
        case .tongue:
            CGRect(
                x: size.width * 0.30,
                y: size.height * 0.18,
                width: size.width * 0.40,
                height: size.height * 0.56
            )
        }
    }

    func cameraTargetPath(in rect: CGRect) -> Path {
        switch self {
        case .eye:
            Path(roundedRect: rect, cornerRadius: rect.height / 2)
        case .nail:
            Path(roundedRect: rect, cornerRadius: rect.width * 0.14)
        case .tongue:
            Path(roundedRect: rect, cornerRadius: rect.width / 2)
        }
    }
}

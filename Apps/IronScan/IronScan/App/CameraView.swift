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

    private let shutterImpact = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        ZStack {
            Color(red: 18 / 255, green: 18 / 255, blue: 20 / 255)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                topChrome
                ZStack(alignment: .bottom) {
                    CameraPreviewView(
                        source: source,
                        lensPosition: lensPosition,
                        onOrientationChange: onOrientationChange
                    )

                    viewfinderOverlay
                }
                .aspectRatio(captureOrientation.isPortrait ? 3 / 4 : 16 / 9, contentMode: .fit)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.32), radius: 28, y: 16)
                .overlay(alignment: .topLeading) {
                    abortButton
                        .padding(18)
                }

                bottomBar
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
        .environment(\.colorScheme, .dark)
        .toolbar(.hidden, for: .tabBar)
        .animation(.easeInOut(duration: 0.18), value: tissue)
        .animation(.easeInOut(duration: 0.18), value: imageQualityAssessment)
        .animation(.easeInOut(duration: 0.18), value: autoCapturePhase)
    }

    private var topChrome: some View {
        HStack(alignment: .top, spacing: 12) {
            abortButton

            VStack(spacing: 4) {
                Text(currentTitle)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(stepLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.58))
            }
            .frame(maxWidth: .infinity)

            controlButton(
                systemName: isTorchEnabled ? "flashlight.on.fill" : "flashlight.off.fill",
                action: onToggleTorch,
                enabled: isTorchAvailable
            )
        }
        .padding(.horizontal, 2)
    }

    private var viewfinderOverlay: some View {
        GeometryReader { geometry in
            let rect = tissue.cameraTargetRect(in: geometry.size)
            let path = tissue.cameraTargetPath(in: rect)

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                ZStack {
                    path
                        .stroke(outlineTint.opacity(0.32), lineWidth: 28)
                        .blur(radius: 18)

                    path
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.85),
                                    outlineTint,
                                    Color.white.opacity(0.75)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 4.5, lineCap: .round, dash: [16, 10])
                        )

                    GlowingCorners(rect: rect, tint: outlineTint)

                    if showsMotionWarning {
                        warningPill(text: "Hold phone steady…")
                            .offset(y: rect.minY - geometry.size.height * 0.36)
                    } else if let eyeGuidanceText, tissue == .eye {
                        warningPill(text: eyeGuidanceText)
                            .offset(y: rect.minY - geometry.size.height * 0.36)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 4) {
                    Text("Good lighting helps us get accurate results.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.88))
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.62))
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 32)
            }
        }
        .allowsHitTesting(false)
    }

    private var bottomBar: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center) {
                VStack(spacing: 4) {
                    Image(systemName: lightingSymbol)
                        .font(.headline.weight(.semibold))
                    Text(lightingText)
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(Color.white.opacity(0.82))
                .frame(width: 70)

                Spacer()

                Button {
                    shutterImpact.impactOccurred()
                    onManualCapture()
                } label: {
                    ShutterButton(phase: autoCapturePhase)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Capture \(tissue.displayName) image")

                Spacer()

                controlButton(
                    systemName: "camera.rotate.fill",
                    action: handleCameraToggle,
                    enabled: supportsCameraToggle && !isSwitchingCamera
                )
                .frame(width: 70)
            }

            Button {
                shutterImpact.impactOccurred()
                onManualCapture()
            } label: {
                Label("Manual Capture", systemImage: "camera.fill")
                    .font(IronTheme.roundedFont(.headline, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        LinearGradient(
                            colors: [
                                IronTheme.terracottaPrimary,
                                Color(red: 1, green: 126 / 255, blue: 76 / 255)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                    }
                    .shadow(color: IronTheme.terracottaPrimary.opacity(0.28), radius: 18, y: 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Manual capture override")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private var abortButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Abort scan and return home")
    }

    private func controlButton(
        systemName: String,
        action: @escaping () -> Void,
        enabled: Bool = true
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline.weight(.bold))
                .foregroundStyle(enabled ? .white : Color.white.opacity(0.35))
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func warningPill(text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.58), in: Capsule(style: .continuous))
    }

    private func handleCameraToggle() {
        guard supportsCameraToggle, !isSwitchingCamera else { return }
        onToggleCamera()
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

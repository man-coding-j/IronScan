@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// The camera surface deliberately renders only the live preview and alignment guide.
/// Guidance, status, and capture controls belong to the surrounding scan layout so
/// they never cover the tissue target.
struct CameraView: View {
    @ObservedObject var cameraManager: MedicalCameraManager
    let source: CameraPreviewSource
    let lensPosition: CameraLensPosition
    let captureOrientation: CaptureOrientation
    let tissue: TissueSite
    let onOrientationChange: (CaptureOrientation) -> Void
    var previewAspectRatio: CGFloat? = nil

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if TutorialCapture.isEnabled {
                    Color.brandTeal.opacity(0.8)
                    Text("Simulator preview · no camera feed")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 20)
                } else if !source.isSimulated {
                    CameraPreviewView(
                        source: source,
                        lensPosition: lensPosition,
                        onOrientationChange: onOrientationChange
                    )
                } else if let frame = cameraManager.currentFrame {
                    Image(uiImage: frame)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.black
                }
                alignmentGuide

            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .aspectRatio(previewAspectRatio ?? (captureOrientation.isPortrait ? 9 / 16 : 16 / 9), contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.16), radius: 16, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Camera alignment guide for \(tissue.displayName)")
        .onAppear(perform: syncOrientation)
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            syncOrientation()
        }
    }

    private func syncOrientation() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let orientation = CaptureOrientation(interfaceOrientation: scene.interfaceOrientation) else {
            return
        }
        onOrientationChange(orientation)
    }

    private var alignmentGuide: some View {
        GeometryReader { geometry in
            let rect = tissue.cameraTargetRect(in: geometry.size)
            tissue.cameraTargetPath(in: rect)
                .stroke(
                    Color.brandMarigold,
                    style: StrokeStyle(lineWidth: 3, dash: [10, 7])
                )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ScanShutterButton: View {
    let phase: AutoCapturePhase
    let isDisabled: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    isDisabled ? IronTheme.textMuted.opacity(0.45) : IronTheme.terracottaPrimary,
                    lineWidth: 5
                )
                .frame(width: 82, height: 82)

            if let progress {
                Circle()
                    .trim(from: 0, to: progress.value)
                    .stroke(
                        progress.color,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 94, height: 94)
            }

            Circle()
                .fill(isDisabled ? IronTheme.textMuted.opacity(0.35) : IronTheme.terracottaPrimary)
                .frame(width: 62, height: 62)

            if let label = progress?.label {
                Text(label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "camera.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 104, height: 104)
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
            Path(ellipseIn: rect)
        case .nail:
            Path(roundedRect: rect, cornerRadius: rect.width * 0.14)
        case .tongue:
            Path(roundedRect: rect, cornerRadius: rect.width / 2)
        }
    }
}

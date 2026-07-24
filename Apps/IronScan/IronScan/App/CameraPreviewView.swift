import AVFoundation
import SwiftUI
import UIKit

struct CameraPreviewView: View {
    let source: CameraPreviewSource
    let lensPosition: CameraLensPosition
    let onOrientationChange: (CaptureOrientation) -> Void

    var body: some View {
        if let session = source.session {
            CaptureSessionPreview(
                session: session,
                lensPosition: lensPosition,
                onOrientationChange: onOrientationChange
            )
        } else {
            SimulatedTonguePreview()
        }
    }
}

private struct CaptureSessionPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let lensPosition: CameraLensPosition
    let onOrientationChange: (CaptureOrientation) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onOrientationChange = onOrientationChange
        view.lensPosition = lensPosition
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        if view.previewLayer.session !== session {
            view.previewLayer.session = session
        }
        view.onOrientationChange = onOrientationChange
        view.lensPosition = lensPosition
        view.updateConnection()
    }

    static func dismantleUIView(_ view: PreviewView, coordinator: Void) {
        view.previewLayer.session = nil
    }
}

private struct SimulatedTonguePreview: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let background = Path(CGRect(origin: .zero, size: size))
                context.fill(background, with: .linearGradient(
                    Gradient(colors: [Color(red: 0.08, green: 0.06, blue: 0.08), .black]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: size.height)
                ))

                let shift = sin(phase * 0.8) * size.width * 0.012
                let faceRect = CGRect(
                    x: size.width * 0.18,
                    y: size.height * 0.08,
                    width: size.width * 0.64,
                    height: size.height * 0.84
                )
                context.fill(Path(ellipseIn: faceRect), with: .color(Color(red: 0.48, green: 0.27, blue: 0.22)))

                let tongueRect = CGRect(
                    x: size.width * 0.34 + shift,
                    y: size.height * 0.40,
                    width: size.width * 0.32,
                    height: size.height * 0.42
                )
                context.fill(Path(ellipseIn: tongueRect), with: .linearGradient(
                    Gradient(colors: [Color(red: 0.88, green: 0.42, blue: 0.48), Color(red: 0.62, green: 0.20, blue: 0.28)]),
                    startPoint: CGPoint(x: tongueRect.midX, y: tongueRect.minY),
                    endPoint: CGPoint(x: tongueRect.midX, y: tongueRect.maxY)
                ))
            }
        }
        .overlay(alignment: .topLeading) {
            Label("Simulated camera", systemImage: "sparkles.tv")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(9)
                .background(.black.opacity(0.58), in: Capsule())
                .padding(12)
        }
        .accessibilityLabel("Animated synthetic tongue camera preview")
    }
}

private final class PreviewView: UIView {
    var onOrientationChange: ((CaptureOrientation) -> Void)?
    var lensPosition = CameraLensPosition.back
    private var captureOrientation = CaptureOrientation.portrait

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let previewLayer = layer as? AVCaptureVideoPreviewLayer else {
            preconditionFailure("PreviewView requires AVCaptureVideoPreviewLayer")
        }
        return previewLayer
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateInterfaceOrientation()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateInterfaceOrientation()
    }

    func updateConnection() {
        guard let connection = previewLayer.connection else { return }
        if #available(iOS 17.0, *) {
            let angle = captureOrientation.videoRotationAngle
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        } else if connection.isVideoOrientationSupported {
            connection.videoOrientation = captureOrientation.legacyVideoOrientation
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = lensPosition == .front
        }
    }

    private func updateInterfaceOrientation() {
        guard let interfaceOrientation = window?.windowScene?.interfaceOrientation,
              let updatedOrientation = CaptureOrientation(interfaceOrientation: interfaceOrientation) else {
            updateConnection()
            return
        }
        guard captureOrientation != updatedOrientation else {
            updateConnection()
            return
        }
        captureOrientation = updatedOrientation
        updateConnection()
        onOrientationChange?(updatedOrientation)
    }
}

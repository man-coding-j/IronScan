import SwiftUI

struct ScanningOverlayView: View {
    let state: LiveScanningState
    let alignmentProgress: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let targetRect = TongueTargetGeometry.rect(in: geometry.size)
            ZStack {
                if state.isActivelyScanning {
                    scanSweep(in: targetRect)
                        .mask {
                            Ellipse()
                                .frame(width: targetRect.width, height: targetRect.height)
                                .position(x: targetRect.midX, y: targetRect.midY)
                        }
                        .transition(.opacity)
                }
                progressRing
                    .position(x: targetRect.maxX + 34, y: targetRect.minY + 30)
                statusPill
                    .position(x: geometry.size.width / 2, y: min(targetRect.maxY + 42, geometry.size.height - 28))
            }
            .animation(.easeInOut(duration: 0.25), value: state)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live scan status")
        .accessibilityValue(state.statusText)
    }

    @ViewBuilder
    private func scanSweep(in targetRect: CGRect) -> some View {
        if reduceMotion {
            scanLine(width: targetRect.width * 0.82)
                .position(x: targetRect.midX, y: targetRect.midY)
        } else {
            TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1.8) / 1.8
                let triangleWave = phase < 0.5 ? phase * 2 : (1 - phase) * 2
                let verticalInset = targetRect.height * 0.12
                let scanY = targetRect.minY + verticalInset
                    + triangleWave * (targetRect.height - verticalInset * 2)
                scanLine(width: targetRect.width * 0.82)
                    .position(x: targetRect.midX, y: scanY)
            }
        }
    }

    private func scanLine(width: Double) -> some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [.clear, .cyan.opacity(0.9), .white, .cyan.opacity(0.9), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: width, height: 3)
            .shadow(color: .cyan.opacity(0.9), radius: 9)
            .shadow(color: .white.opacity(0.7), radius: 3)
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(.black.opacity(0.45), lineWidth: 7)
            Circle()
                .stroke(.white.opacity(0.24), lineWidth: 5)
            Circle()
                .trim(from: 0, to: displayedProgress)
                .stroke(
                    stateColor,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text(displayedProgress.formatted(.percent.precision(.fractionLength(0))))
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(.white)
        }
        .frame(width: 58, height: 58)
        .shadow(color: stateColor.opacity(0.45), radius: 7)
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Image(systemName: statusSymbol)
                .symbolEffect(.pulse, options: .repeating, isActive: state.isActivelyScanning && !reduceMotion)
            Text(state.statusText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.black.opacity(0.7), in: Capsule())
        .frame(maxWidth: 310)
    }

    private var displayedProgress: Double {
        switch state {
        case .idle:
            min(max(alignmentProgress, 0), 0.1)
        default:
            state.progress
        }
    }

    private var stateColor: Color {
        switch state {
        case .completed: .green
        case .failed: .orange
        case .scanning: .cyan
        case .aligning: .yellow
        case .idle: .white
        }
    }

    private var statusSymbol: String {
        switch state {
        case .idle: "viewfinder"
        case .aligning: "camera.metering.center.weighted"
        case .scanning: "waveform"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
}

enum TongueTargetGeometry {
    static func rect(in size: CGSize) -> CGRect {
        let isLandscape = size.width > size.height
        let targetWidth = isLandscape
            ? min(size.width * 0.34, size.height * 0.58)
            : size.width * 0.46
        let targetHeight = isLandscape
            ? min(size.height * 0.72, targetWidth * 1.18)
            : min(size.height * 0.52, targetWidth * 1.45)
        return CGRect(
            x: (size.width - targetWidth) / 2,
            y: (size.height - targetHeight) / 2,
            width: targetWidth,
            height: targetHeight
        )
    }
}

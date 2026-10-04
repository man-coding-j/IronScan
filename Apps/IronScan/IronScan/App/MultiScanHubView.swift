import SwiftUI
import UIKit

struct MultiScanHubView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var historyManager: ScanHistoryManager
    @AppStorage("userAge") private var userAge = 0
    @AppStorage("userBiologicalSex") private var userBiologicalSex = ""
    @AppStorage("fitzpatrickSkinPhototype") private var fitzpatrickSkinPhototype = FitzpatrickSkinPhototype.notProvided.rawValue
    @AppStorage("lightingEnvironment") private var lightingEnvironment = LightingEnvironment.notProvided.rawValue
    @State private var scanSessionID = UUID()
    @State private var isCameraFlowActive = true
    @State private var showsBiometricSheet = false
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
            IronTheme.beigeBackground
                .ignoresSafeArea()

            if !biometricProfileIsComplete {
                biometricsRequiredState
            } else if isCameraFlowActive {
                PersistentScanSuiteView(
                    inference: inference,
                    historyManager: historyManager,
                    onCompleted: onCompleted,
                    onAbort: handleAbort
                )
                .id(scanSessionID)
            } else {
                abortedState
            }
        }
        .onAppear {
            showsBiometricSheet = !biometricProfileIsComplete
        }
        .sheet(isPresented: $showsBiometricSheet) {
            biometricSheet
                .interactiveDismissDisabled(!biometricProfileIsComplete)
        }
    }

    private var biometricProfileIsComplete: Bool {
        (1...120).contains(userAge)
            && UserBiologicalSex(rawValue: userBiologicalSex) != nil
            && FitzpatrickSkinPhototype(rawValue: fitzpatrickSkinPhototype) != .notProvided
            && LightingEnvironment(rawValue: lightingEnvironment) != .notProvided
    }

    private var biometricsRequiredState: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(IronTheme.terracottaPrimary)
            Text("Complete Your Biometrics First")
                .font(.title2.weight(.bold))
            Text("Age, biological sex, skin phototype, and lighting context are required before the research scan can begin.")
                .font(.subheadline)
                .foregroundStyle(IronTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Complete Biometrics") {
                showsBiometricSheet = true
            }
            .buttonStyle(TealPrimaryButtonStyle())
        }
        .padding(24)
    }

    private var biometricSheet: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Complete Your Biometrics First")
                        .font(IronTheme.roundedFont(.title2, weight: .bold))
                    Text("These values stay on this device and keep the prototype’s preprocessing and calibration inputs complete.")
                        .font(IronTheme.roundedFont(.subheadline))
                        .foregroundStyle(IronTheme.textSecondary)

                    VStack(spacing: 0) {
                        biometricFieldRow(
                            title: "Age",
                            subtitle: "Used to select the appropriate research calibration."
                        ) {
                            Picker("Age", selection: $userAge) {
                                Text("Select Age").tag(0)
                                ForEach(1...120, id: \.self) { age in
                                    Text("\(age)").tag(age)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        Divider().padding(.leading, 16)

                        biometricFieldRow(
                            title: "Biological Sex",
                            subtitle: "Used only for prototype calibration context."
                        ) {
                            Picker("Biological Sex", selection: $userBiologicalSex) {
                                Text("Select Sex").tag("")
                                ForEach(UserBiologicalSex.allCases) { sex in
                                    Text(sex.rawValue).tag(sex.rawValue)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        Text("Normal hemoglobin baseline thresholds vary naturally based on age and biological sex. This data ensures your anemia risk is calculated against the correct medical standard.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)

                        Divider().padding(.leading, 16)

                        biometricFieldRow(
                            title: "Skin Phototype",
                            subtitle: "Fitzpatrick scale I–VI to calibrate pigmentation."
                        ) {
                            Picker("Skin Phototype", selection: $fitzpatrickSkinPhototype) {
                                Text("Select Phototype").tag(FitzpatrickSkinPhototype.notProvided.rawValue)
                                ForEach(FitzpatrickSkinPhototype.allCases.filter { $0 != .notProvided }) { phototype in
                                    Text(phototype.rawValue).tag(phototype.rawValue)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        Text("Skin melanin levels affect how light reflects off your nailbeds and conjunctiva. Providing your skin type allows the AI to calibrate its colorimetry algorithms, ensuring fair and accurate pallor detection across all skin tones.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)

                        Divider().padding(.leading, 16)

                        biometricFieldRow(
                            title: "Lighting Context",
                            subtitle: "Choose the lighting where you will take the scan."
                        ) {
                            Picker("Lighting Context", selection: $lightingEnvironment) {
                                Text("Select Lighting").tag(LightingEnvironment.notProvided.rawValue)
                                ForEach(LightingEnvironment.allCases.filter { $0 != .notProvided }) { lighting in
                                    Text(lighting.rawValue).tag(lighting.rawValue)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }
                    .background(Color.white.opacity(0.44), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.58), lineWidth: 1)
                    }

                    Button("Continue to Scan") {
                        showsBiometricSheet = false
                    }
                    .buttonStyle(TealPrimaryButtonStyle())
                    .frame(maxWidth: .infinity)
                    .disabled(!biometricProfileIsComplete)
                }
                .padding(16)
            }
            .background(IronTheme.beigeBackground.ignoresSafeArea())
        }
    }

    private func biometricFieldRow<Control: View>(
        title: String,
        subtitle: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(IronTheme.roundedFont(.headline, weight: .semibold))
                    .foregroundStyle(IronTheme.textPrimary)
                Text(subtitle)
                    .font(IronTheme.roundedFont(.caption))
                    .foregroundStyle(IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            control()
                .font(IronTheme.roundedFont(.subheadline, weight: .semibold))
                .foregroundStyle(IronTheme.terracottaPrimary)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var abortedState: some View {
        VStack(spacing: 18) {
            Image(systemName: "house.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(IronTheme.terracottaPrimary)

            Text("Camera flow closed")
                .font(.title3.weight(.bold))
                .foregroundStyle(IronTheme.textPrimary)

            Text("Start again when you're ready. The next scan will begin fresh at the eye step.")
                .font(.subheadline)
                .foregroundStyle(IronTheme.textSecondary)
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
    @State private var presentedAlert: ScanSessionAlert?
    private let onCompleted: (TriangulationResult) -> Void
    private let onAbort: () -> Void
    private let shutterImpact = UIImpactFeedbackGenerator(style: .medium)

    init(
        inference: MultiTissueInferenceActor,
        historyManager: ScanHistoryManager,
        onCompleted: @escaping (TriangulationResult) -> Void,
        onAbort: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: MultiScanHubViewModel(historyManager: historyManager, inference: inference))
        self.onCompleted = onCompleted
        self.onAbort = onAbort
    }

    var body: some View {
        NavigationStack {
            contentBody
            .toolbar(.hidden, for: .navigationBar)
            .task {
                if viewModel.permissionStatus == .denied {
                    presentedAlert = .cameraPermission
                }
                viewModel.start()
            }
            .onDisappear { viewModel.stop() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { viewModel.refreshPermissionAndRestart() }
            }
            .onChange(of: viewModel.permissionStatus) { _, status in
                if status == .denied {
                    presentedAlert = .cameraPermission
                }
            }
            .onChange(of: viewModel.lastError) { _, error in
                if error == "Scan incomplete. Please retake the tongue photo." {
                    presentedAlert = .incompleteScan
                } else if error == "Image quality issue detected (poor lighting or glare). Please retake the photo in natural light." {
                    presentedAlert = .imageQuality
                }
            }
            .onChange(of: viewModel.triangulationResult) { _, result in
                guard let result else { return }
                onCompleted(result)
                showsReport = true
            }
            .alert(item: $presentedAlert) { alert in
                switch alert {
                case .cameraPermission:
                    Alert(
                        title: Text("Camera Access Required"),
                        message: Text("Allow Camera access in Settings to begin the three-step scan. Your captured images remain on this device."),
                        primaryButton: .default(Text("Open Settings")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        },
                        secondaryButton: .cancel()
                    )
                case .incompleteScan:
                    Alert(
                        title: Text("Scan Incomplete"),
                        message: Text("Please retake the tongue/lips photo."),
                        dismissButton: .default(Text("OK"))
                    )
                case .imageQuality:
                    Alert(
                        title: Text("Retake Photo"),
                        message: Text("Image quality issue detected (poor lighting or glare). Please retake the photo in natural light."),
                        dismissButton: .default(Text("OK"))
                    )
                }
            }
            .sheet(isPresented: $showsReport) {
                reportSheet
            }
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        ZStack {
            IronTheme.beigeBackground
                .ignoresSafeArea()

            if viewModel.showsPermissionInstructions {
                permissionInstructions
            } else if viewModel.triangulationResult != nil {
                completedCard
            } else {
                cameraExperience
            }

            if let toast = viewModel.errorToast {
                Text(toast)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.82), in: Capsule())
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var reportSheet: some View {
        if let result = viewModel.triangulationResult {
            ScanResultView(
                result: result,
                outputs: viewModel.completedOutputs,
                tissueImages: viewModel.tissuePreviewImages,
                onScanAgain: {
                    showsReport = false
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
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {
                scanTopBar
                guidanceCard

                CameraView(
                    cameraManager: viewModel.cameraManager,
                    source: viewModel.previewSource,
                    lensPosition: viewModel.lensPosition,
                    captureOrientation: viewModel.captureOrientation,
                    tissue: viewModel.currentTissue,
                    onOrientationChange: viewModel.updateCaptureOrientation
                )

                bottomControls
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .background(IronTheme.beigeBackground.ignoresSafeArea())
        .scrollBounceBehavior(.basedOnSize)
    }

    private var scanTopBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                scanControlButton(
                    systemName: "xmark",
                    accessibilityLabel: "Abort scan and return home",
                    action: handleAbort
                )

                Spacer(minLength: 0)

                if viewModel.supportsCameraToggle {
                    scanControlButton(
                        systemName: "camera.rotate.fill",
                        accessibilityLabel: "Switch camera",
                        isEnabled: !viewModel.isSwitchingCamera,
                        action: viewModel.toggleCamera
                    )
                }

                scanControlButton(
                    systemName: viewModel.isTorchEnabled ? "flashlight.on.fill" : "flashlight.off.fill",
                    accessibilityLabel: viewModel.isTorchEnabled ? "Turn flashlight off" : "Turn flashlight on",
                    isEnabled: viewModel.isTorchAvailable && !viewModel.isBusy
                ) {
                    viewModel.setTorchEnabled(!viewModel.isTorchEnabled)
                }
            }

            stepProgress
        }
    }

    private var guidanceCard: some View {
        HStack(alignment: .center, spacing: 12) {
            stepReferenceThumbnail

            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.currentStep.progressTitle)
                    .font(IronTheme.roundedFont(.headline, weight: .bold))
                    .foregroundStyle(IronTheme.textPrimary)
                Text(viewModel.currentStep.guideInstruction)
                    .font(IronTheme.roundedFont(.subheadline))
                    .foregroundStyle(IronTheme.textSecondary)
            }

            Spacer(minLength: 8)

            Text(viewModel.currentStep.stepLabel)
                .font(IronTheme.roundedFont(.caption, weight: .bold))
                .foregroundStyle(IronTheme.terracottaPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(IronTheme.terracottaPrimary.opacity(0.10), in: Capsule())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.44), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var stepReferenceThumbnail: some View {
        if let referenceImage = UIImage(named: viewModel.currentStep.referenceAssetName) {
            Image(uiImage: referenceImage)
                .resizable()
                .scaledToFill()
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel(viewModel.currentStep.referenceAccessibilityLabel)
        } else {
            Image(systemName: "photo")
                .font(.title2.weight(.medium))
                .foregroundStyle(IronTheme.terracottaPrimary)
                .frame(width: 60, height: 60)
                .background(IronTheme.terracottaPrimary.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel("Reference image unavailable. \(viewModel.currentStep.referenceAccessibilityLabel)")
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 12) {
            scanStatusCard

            Button {
                shutterImpact.impactOccurred()
                viewModel.forceManualCapture()
            } label: {
                VStack(spacing: 2) {
                    ScanShutterButton(
                        phase: viewModel.autoCapturePhase,
                        isDisabled: captureButtonIsDisabled
                    )
                    Text(viewModel.isAnalyzing ? "Analyzing…" : "Capture")
                        .font(IronTheme.roundedFont(.headline, weight: .bold))
                        .foregroundStyle(captureButtonIsDisabled ? IronTheme.textMuted : IronTheme.textPrimary)
                }
            }
            .buttonStyle(.plain)
            .disabled(captureButtonIsDisabled)
            .accessibilityLabel("Capture \(viewModel.currentStep.progressTitle) image")

            Button("Skip \(viewModel.currentStep.progressTitle)") {
                viewModel.skipCurrentTissue()
            }
            .font(IronTheme.roundedFont(.subheadline, weight: .bold))
            .foregroundStyle(IronTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .disabled(viewModel.isBusy)
            .opacity(viewModel.isBusy ? 0.55 : 1)
        }
    }

    private var scanStatusCard: some View {
        let status = scanStatusPresentation
        return HStack(spacing: 12) {
            Image(systemName: status.systemName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(status.tint)
                .frame(width: 34, height: 34)
                .background(status.tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(status.title)
                    .font(IronTheme.roundedFont(.subheadline, weight: .bold))
                    .foregroundStyle(IronTheme.textPrimary)
                Text(status.subtitle)
                    .font(IronTheme.roundedFont(.caption))
                    .foregroundStyle(IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if viewModel.captureQualityAssessment?.isAcceptable == false {
                Button("Retake") {
                    viewModel.dismissCaptureQualityFeedback()
                }
                .font(IronTheme.roundedFont(.caption, weight: .bold))
                .foregroundStyle(IronTheme.terracottaPrimary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(status.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(status.tint.opacity(0.20), lineWidth: 1)
        }
    }

    private var captureButtonIsDisabled: Bool {
        viewModel.isBusy || viewModel.cameraState != .ready
    }

    private var scanStatusPresentation: ScanStatusPresentation {
        if let modelError = viewModel.modelError {
            return ScanStatusPresentation(
                title: modelError,
                subtitle: "This model could not be loaded on this device. Scanning is disabled; Simulator mode can use the synthetic fallback.",
                systemName: "cpu.fill",
                tint: IronTheme.warning
            )
        }
        if let error = viewModel.lastError {
            return ScanStatusPresentation(
                title: "Capture Needs Attention",
                subtitle: error,
                systemName: "exclamationmark.triangle.fill",
                tint: IronTheme.warning
            )
        }
        if let assessment = viewModel.captureQualityAssessment {
            return ScanStatusPresentation(
                title: assessment.isAcceptable ? "Optimal Quality" : assessment.feedbackMessage,
                subtitle: assessment.isAcceptable ? "Image is sharp and well-lit." : "Adjust the scene and retake this frame.",
                systemName: assessment.isAcceptable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                tint: assessment.isAcceptable ? IronTheme.sageAccent : IronTheme.warning
            )
        }
        if viewModel.isAnalyzing {
            return ScanStatusPresentation(
                title: "Analyzing…",
                subtitle: viewModel.statusText,
                systemName: "waveform.and.magnifyingglass",
                tint: IronTheme.terracottaPrimary
            )
        }
        if viewModel.showsMotionWarning {
            return ScanStatusPresentation(
                title: "Hold Steady",
                subtitle: "Pause movement briefly before capturing.",
                systemName: "scope",
                tint: IronTheme.warning
            )
        }
        let quality = viewModel.imageQualityAssessment
        let qualityIsUnavailable = !quality.isAcceptable && quality.blurScore == 0 && quality.brightnessScore == 0
        if viewModel.isCheckingFraming {
            return ScanStatusPresentation(
                title: "Checking Framing…",
                subtitle: "Checking lighting and focus inside the guide.",
                systemName: "viewfinder",
                tint: IronTheme.textSecondary
            )
        }
        if qualityIsUnavailable {
            return ScanStatusPresentation(
                title: "Manual Capture Available",
                subtitle: "Automatic framing is unavailable. Align the target and tap Capture.",
                systemName: "camera.fill",
                tint: IronTheme.textSecondary
            )
        }
        if quality.brightnessScore < ImageQualityAnalyzer.minimumBrightness {
            return ScanStatusPresentation(
                title: "Add More Light",
                subtitle: "LOW EV — bring the subject into brighter light.",
                systemName: "sun.haze.fill",
                tint: IronTheme.terracottaPrimary
            )
        }
        if quality.brightnessScore > 0.92 {
            return ScanStatusPresentation(
                title: "Reduce Glare",
                subtitle: "Highlights are clipping.",
                systemName: "sun.dust.fill",
                tint: IronTheme.terracottaPrimary
            )
        }
        if viewModel.currentStep == .conjunctiva, let guidance = viewModel.eyeGuidanceText {
            return ScanStatusPresentation(
                title: "Eye Guidance",
                subtitle: guidance,
                systemName: "eye.fill",
                tint: IronTheme.sageAccent
            )
        }
        return autoCaptureStatusPresentation
    }

    private var autoCaptureStatusPresentation: ScanStatusPresentation {
        switch viewModel.autoCapturePhase {
        case .disabled:
            ScanStatusPresentation(title: "Manual Capture", subtitle: viewModel.statusText, systemName: "camera.fill", tint: IronTheme.textSecondary)
        case .seeking:
            ScanStatusPresentation(title: "Align Target", subtitle: "Automatic framing is active, or tap Capture manually.", systemName: "viewfinder", tint: IronTheme.textSecondary)
        case let .holding(progress):
            ScanStatusPresentation(title: "Focusing \(Int(progress * 100))%", subtitle: viewModel.statusText, systemName: "scope", tint: IronTheme.sageAccent)
        case let .countdown(secondsRemaining, _):
            ScanStatusPresentation(title: "Capturing in \(secondsRemaining)…", subtitle: "Keep the target steady inside the guide.", systemName: "timer", tint: .green)
        case .readyToCapture:
            ScanStatusPresentation(title: "Auto-capture Ready", subtitle: "The next stable frame will be captured.", systemName: "checkmark.circle.fill", tint: .green)
        case let .reset(message):
            ScanStatusPresentation(title: "Reposition Target", subtitle: message, systemName: "arrow.trianglehead.clockwise", tint: IronTheme.warning)
        }
    }

    private func scanControlButton(
        systemName: String,
        accessibilityLabel: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(isEnabled ? IronTheme.textPrimary : IronTheme.textMuted)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.52), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }

    private var stepProgress: some View {
        HStack(spacing: 10) {
            ForEach(ScanStep.allCases) { step in
                VStack(spacing: 6) {
                    Text("\(step.rawValue)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(stepColor(for: step))
                        .frame(width: 26, height: 26)
                        .background(stepColor(for: step).opacity(0.14), in: Circle())
                    Text(step.progressTitle)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(viewModel.currentStep == step ? IronTheme.textPrimary : IronTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var completedCard: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 50))
                .foregroundStyle(IronTheme.sageAccent)
            Text("Multi-site scan complete")
                .font(.title2.weight(.bold))
                .foregroundStyle(IronTheme.textPrimary)
            Text("Review the combined research summary or begin a new scan.")
                .font(.subheadline)
                .foregroundStyle(IronTheme.textSecondary)
                .multilineTextAlignment(.center)

            Button("Review result") {
                showsReport = true
            }
            .buttonStyle(TealPrimaryButtonStyle())

            Button("Start another scan") {
                viewModel.resetDemo()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(IronTheme.textSecondary)
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
            Text(viewModel.permissionStatus == .restricted ? "Camera access is restricted" : "Camera access is required for the three-step scan")
                .font(.title3.weight(.bold))
                .foregroundStyle(IronTheme.textPrimary)
                .multilineTextAlignment(.center)
            Text(viewModel.permissionStatus == .restricted
                 ? "Camera use may be blocked by Screen Time or device-management restrictions."
                 : "Open Settings and allow Camera access to capture the eye, fingernail, and tongue/lips steps.")
                .font(.subheadline)
                .foregroundStyle(IronTheme.textSecondary)
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

    private func stepColor(for step: ScanStep) -> Color {
        if viewModel.completedOutputs[step.tissue] != nil {
            return IronTheme.sageAccent
        }
        if viewModel.skippedTissues.contains(step.tissue) {
            return IronTheme.warning
        }
        if viewModel.currentStep == step {
            return IronTheme.terracottaPrimary
        }
        return Color.white.opacity(0.38)
    }

    private func handleAbort() {
        showsReport = false
        presentedAlert = nil
        viewModel.resetDemo()
        viewModel.stop()
        onAbort()
        dismiss()
    }
}

private enum ScanSessionAlert: String, Identifiable {
    case cameraPermission
    case incompleteScan
    case imageQuality

    var id: String { rawValue }
}

private struct ScanStatusPresentation {
    let title: String
    let subtitle: String
    let systemName: String
    let tint: Color
}

private struct PersistentScanSuiteView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var historyManager: ScanHistoryManager
    @StateObject private var viewModel: MultiScanHubViewModel
    private let onCompleted: (TriangulationResult) -> Void
    private let onAbort: () -> Void

    init(
        inference: MultiTissueInferenceActor,
        historyManager: ScanHistoryManager,
        onCompleted: @escaping (TriangulationResult) -> Void,
        onAbort: @escaping () -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: MultiScanHubViewModel(historyManager: historyManager, inference: inference)
        )
        self.onCompleted = onCompleted
        self.onAbort = onAbort
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.showsPermissionInstructions {
                    permissionView
                } else {
                    scanSuite
                }
            }
            .background(IronTheme.beigeBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .task {
                viewModel.setAutoCaptureEnabled(false)
                viewModel.start()
            }
            .onDisappear { viewModel.stop() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { viewModel.refreshPermissionAndRestart() }
            }
            .onChange(of: viewModel.triangulationResult) { _, result in
                if let result { onCompleted(result) }
            }
            .alert("Retake Image", isPresented: Binding(
                get: { viewModel.validationAlert != nil },
                set: { if !$0 { viewModel.validationAlert = nil } }
            )) {
                Button("OK", role: .cancel) { viewModel.validationAlert = nil }
            } message: {
                Text(viewModel.validationAlert ?? "")
            }
            .fullScreenCover(isPresented: $viewModel.showSummary) {
                if let record = viewModel.scanRecord {
                    ScanSummaryView(record: record) {
                        viewModel.resetDemo()
                    }
                }
            }
        }
    }

    private var scanSuite: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                header
                stepIndicators

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.currentStep.progressTitle)
                        .font(.title3.weight(.bold))
                    Text(viewModel.currentStep.guideInstruction)
                        .font(.subheadline)
                        .foregroundStyle(IronTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                CameraView(
                    cameraManager: viewModel.cameraManager,
                    source: viewModel.previewSource,
                    lensPosition: viewModel.lensPosition,
                    captureOrientation: viewModel.captureOrientation,
                    tissue: viewModel.currentTissue,
                    onOrientationChange: viewModel.updateCaptureOrientation
                )
                .overlay(alignment: .topTrailing) {
                    VStack(spacing: 16) {
                        if viewModel.supportsCameraToggle {
                            Button(action: viewModel.toggleCamera) {
                                Image(systemName: "arrow.triangle.2.circlepath.camera")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 48, height: 48)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isBusy || viewModel.isSwitchingCamera)
                            .accessibilityLabel(viewModel.lensPosition == .front ? "Switch to back camera" : "Switch to front camera")
                        }

                        if viewModel.lensPosition == .back && viewModel.isTorchAvailable {
                            Button(action: viewModel.toggleFlashlight) {
                                Image(systemName: viewModel.isTorchEnabled ? "bolt.fill" : "bolt.slash.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 48, height: 48)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isBusy || viewModel.isSwitchingCamera)
                            .accessibilityLabel(viewModel.isTorchEnabled ? "Turn flashlight off" : "Turn flashlight on")
                        }
                    }
                    .padding(16)
                }
                .overlay(alignment: .top) {
                    Text("Align \(viewModel.currentStep.progressTitle) Here")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.58), in: Capsule())
                        .padding(12)
                        .allowsHitTesting(false)
                }

                captureThumbnails

                Text(viewModel.statusText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(viewModel.lastError == nil ? IronTheme.textSecondary : .red)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)

                Button {
                    viewModel.forceManualCapture()
                } label: {
                    Label(
                        viewModel.isAnalyzing
                            ? "Capturing…"
                            : "Capture \(viewModel.currentStep.progressTitle)",
                        systemImage: "camera.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(Color.red, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .disabled(viewModel.isBusy || viewModel.cameraState != .ready)
                .opacity(viewModel.isBusy || viewModel.cameraState != .ready ? 0.48 : 1)

                Button {
                    viewModel.runMLAssessment()
                } label: {
                    Label("Run Anemia Assessment", systemImage: "waveform.path.ecg")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(Color.green, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .disabled(!viewModel.isSessionComplete || viewModel.isBusy)
                .opacity(!viewModel.isSessionComplete || viewModel.isBusy ? 0.42 : 1)

                Text("Research prototype only. Results are not a diagnosis and require laboratory confirmation.")
                    .font(.caption)
                    .foregroundStyle(IronTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(16)
        }
    }

    private var header: some View {
        HStack {
            Button(action: onAbort) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 42, height: 42)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close scan")

            Spacer()
            Text("New Scan Suite")
                .font(.title2.weight(.bold))
            Spacer()
            Color.clear.frame(width: 42, height: 42)
        }
    }

    private var stepIndicators: some View {
        HStack(spacing: 8) {
            ForEach(ScanStep.allCases) { step in
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(indicatorColor(for: step).opacity(0.16))
                            .frame(width: 30, height: 30)
                        if viewModel.sessionImages[step] != nil {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundStyle(indicatorColor(for: step))
                        } else {
                            Text("\(step.rawValue)")
                                .font(.caption.bold())
                                .foregroundStyle(indicatorColor(for: step))
                        }
                    }
                    Text("\(step.rawValue). \(step.progressTitle)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(IronTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 18))
    }

    private var captureThumbnails: some View {
        HStack(spacing: 10) {
            ForEach(ScanStep.allCases) { step in
                VStack(spacing: 5) {
                    Group {
                        if let image = viewModel.sessionImages[step] {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundStyle(.gray)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.gray.opacity(0.12))
                        }
                    }
                    .frame(height: 72)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Text(step.progressTitle)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var permissionView: some View {
        VStack(spacing: 18) {
            Image(systemName: "camera.fill.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.red)
            Text("Camera Access Required")
                .font(.title2.bold())
            Text("Allow camera access to capture the three local research images.")
                .foregroundStyle(IronTheme.textSecondary)
                .multilineTextAlignment(.center)
            if viewModel.permissionStatus == .denied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(TealPrimaryButtonStyle())
            }
        }
        .padding(28)
    }

    private func indicatorColor(for step: ScanStep) -> Color {
        if viewModel.sessionImages[step] != nil { return .green }
        if viewModel.currentStep == step { return .red }
        return .gray
    }
}

struct ScanSummaryView: View {
    @EnvironmentObject var historyManager: ScanHistoryManager
    let record: ScanRecord
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 8) {
                        Text(record.hemoglobinG_dL.formatted(.number.precision(.fractionLength(1))))
                            .font(.system(size: 78, weight: .black, design: .rounded))
                            .foregroundStyle(.red)
                        Text("Estimated Hemoglobin (g/dL)")
                            .font(.headline)
                            .foregroundStyle(IronTheme.textSecondary)
                        Text(record.riskLevel.rawValue)
                            .font(.title2.bold())
                            .foregroundStyle(.red)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 18) {
                        Text("Decomposed Pallor Indices")
                            .font(.title3.bold())

                        indexRow("Eye Conjunctiva", step: .conjunctiva)
                        indexRow("Nail Bed Perfusion", step: .fingernail)
                        indexRow("Tongue Vascularity", step: .tongue)
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.60), in: RoundedRectangle(cornerRadius: 20))

                    Text("IronScan is a non-clinical research prototype. Confirm any concern with a laboratory test and qualified clinician.")
                        .font(.footnote)
                        .foregroundStyle(IronTheme.textSecondary)
                        .multilineTextAlignment(.center)

                    Button("Done", action: onDone)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(20)
            }
            .background(IronTheme.beigeBackground.ignoresSafeArea())
            .navigationTitle("Scan Summary")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
        }
    }

    private func indexRow(_ title: String, step: ScanStep) -> some View {
        let value = switch step {
        case .conjunctiva: record.conjunctivaScore
        case .fingernail: record.nailScore
        case .tongue: record.tongueScore
        }
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(value.formatted(.number.precision(.fractionLength(6))))
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
            }
            ProgressView(value: value)
                .tint(.red)
        }
    }
}

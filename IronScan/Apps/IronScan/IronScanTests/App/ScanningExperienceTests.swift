// Explicit dependency for Xcode’s app-intents metadata extraction phase.
import AppIntents
import XCTest
import Combine
import UIKit
import CoreMedia
import AVFoundation
import CoreImage
import SwiftUI
@testable import IronScan

final class ScanningExperienceTests: XCTestCase {
    func testThreeEvaluationsCompleteVisualScan() {
        var tracker = LiveScanProgressTracker()
        let report = makeReport()

        XCTAssertEqual(tracker.register(report: report), .scanning(progress: 1.0 / 3.0))
        XCTAssertEqual(tracker.register(report: report), .scanning(progress: 2.0 / 3.0))
        XCTAssertEqual(tracker.register(report: report), .completed(report: report))
        XCTAssertEqual(tracker.evaluationCount, 3)
    }

    func testResetRequiresThreeFreshEvaluations() {
        var tracker = LiveScanProgressTracker()
        let report = makeReport()

        _ = tracker.register(report: report)
        _ = tracker.register(report: report)
        tracker.reset()

        XCTAssertEqual(tracker.evaluationCount, 0)
        XCTAssertEqual(tracker.register(report: report), .scanning(progress: 1.0 / 3.0))
    }

    func testScanningStatusUsesNonClinicalVisualLanguage() {
        XCTAssertEqual(LiveScanningState.idle.statusText, "Align tongue inside the oval…")
        XCTAssertEqual(LiveScanningState.aligning.statusText, "Adjusting focus and lighting…")
        XCTAssertEqual(
            LiveScanningState.scanning(progress: 0.34).statusText,
            "Analyzing mucosal color profile…"
        )
        XCTAssertEqual(
            LiveScanningState.scanning(progress: 0.67).statusText,
            "Calculating visual indicators…"
        )
    }

    func testScanStepsKeepProgressGuideAndInferenceTissueSynchronized() {
        XCTAssertEqual(ScanStep.allCases.map(\.rawValue), [1, 2, 3])
        XCTAssertEqual(ScanStep.allCases.map(\.progressTitle), ["Conjunctiva", "Fingernail Bed", "Tongue"])
        XCTAssertEqual(ScanStep.allCases.map(\.tissue.rawValue), ["eye", "nail", "tongue"])
        XCTAssertEqual(ScanStep.conjunctiva.guideInstruction, "Align Conjunctiva within the guide")
        XCTAssertEqual(ScanStep.fingernail.guideInstruction, "Align Fingernail Bed within the guide")
        XCTAssertEqual(ScanStep.tongue.guideInstruction, "Align Tongue within the guide")
    }

    @MainActor
    func testScanSessionRequiresExactlyAllThreeStepImages() {
        let session = ScanSession()
        let image = UIImage()

        session.store(image, for: .conjunctiva)
        session.store(image, for: .fingernail)
        XCTAssertFalse(session.isComplete)

        session.store(image, for: .tongue)
        XCTAssertTrue(session.isComplete)
        XCTAssertEqual(session.capturedImages.count, 3)

        session.reset()
        XCTAssertFalse(session.isComplete)
        XCTAssertTrue(session.capturedImages.isEmpty)
    }

    @MainActor
    func testDefaultScanModelsRetainTheSharedCameraManager() {
        let first = MultiScanHubViewModel(historyManager: ScanHistoryManager())
        let second = MultiScanHubViewModel(historyManager: ScanHistoryManager())
        XCTAssertTrue(first.cameraManager === MedicalCameraManager.shared)
        XCTAssertTrue(first.cameraManager === second.cameraManager)
    }

    @MainActor
    func testCameraCapabilitiesAreConsumedBeforeStartupCompletesAndFlipReachesController() async throws {
        let camera = SwitchableTestCamera()
        let model = MultiScanHubViewModel(historyManager: ScanHistoryManager(), camera: camera)
        XCTAssertFalse(model.cameraManager === MedicalCameraManager.shared)
        model.start()
        defer { model.stop() }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while !model.supportsCameraToggle, clock.now < deadline {
            try await clock.sleep(for: .milliseconds(10))
        }
        // Startup intentionally remains suspended: a consumer that awaits
        // start() before reading its stream cannot receive this capability.
        XCTAssertTrue(model.supportsCameraToggle)
        XCTAssertFalse(model.canToggleCamera)
        await camera.finishStartup()
        while !model.canToggleCamera, clock.now < deadline {
            try await clock.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(model.canToggleCamera)
        model.toggleCamera()
        model.toggleCamera() // Repeated taps must not enqueue a second flip.
        while model.isSwitchingCamera, clock.now < deadline {
            try await clock.sleep(for: .milliseconds(10))
        }
        let flips = await camera.flipCount
        XCTAssertEqual(flips, 1)
        XCTAssertEqual(model.lensPosition, .back)
        XCTAssertEqual(model.cameraManager.currentPosition, .back)
    }

    @MainActor
    func testFailedCameraFlipKeepsPublishedLensPosition() async throws {
        let manager = MedicalCameraManager(camera: SimulatorCameraActor())
        do {
            try await manager.toggleCamera()
            XCTFail("The simulated camera must reject a physical lens switch")
        } catch {
            XCTAssertEqual(manager.currentPosition, .front)
            XCTAssertTrue(manager.isUsingFrontCamera)
        }
    }

    @MainActor
    func testMedicalCameraManagerCapturesTheDisplayedFrameAndClearsIt() async throws {
        let manager = MedicalCameraManager()
        let buffer = try SyntheticTongueFrameFactory.makePixelBuffer(width: 96, height: 96)
        await manager.display(AnalyzableFrame(pixelBuffer: buffer, timestamp: .zero))

        let displayed = try XCTUnwrap(manager.currentFrame)
        XCTAssertEqual(displayed.imageOrientation, .up)
        XCTAssertTrue(manager.capturePhoto() === displayed)
        XCTAssertEqual(CVPixelBufferGetWidth(try XCTUnwrap(manager.currentVideoFrame).pixelBuffer), 96)

        manager.clear()
        XCTAssertNil(manager.capturePhoto())
        XCTAssertNil(manager.currentVideoFrame)
    }

    @MainActor
    func testThreeImportedPhotosFillOrderedSlotsWithoutRunningOrSaving() {
        let history = ScanHistoryManager()
        let model = MultiScanHubViewModel(historyManager: history)
        let images = [UIImage(), UIImage(), UIImage()]
        model.storeImportedImages(images, startingAt: .tongue)

        XCTAssertTrue(model.isSessionComplete)
        for (index, step) in ScanStep.allCases.enumerated() {
            XCTAssertTrue(model.sessionImages[step] === images[index])
        }
        XCTAssertFalse(model.isRunningAssessment)
        XCTAssertFalse(model.showSummary)
        XCTAssertNil(model.scanRecord)
        XCTAssertTrue(history.records.isEmpty)
        model.stop()
        XCTAssertTrue(model.sessionImages.isEmpty)
        XCTAssertTrue(model.tissuePreviewImages.isEmpty)
    }

    @MainActor
    func testFailedAssessmentReleasesAllImportedImageReferences() async throws {
        let model = MultiScanHubViewModel(historyManager: ScanHistoryManager())
        model.resetSession()
        let preparationClock = ContinuousClock()
        let preparationDeadline = preparationClock.now.advanced(by: .seconds(3))
        while model.isBusy, preparationClock.now < preparationDeadline {
            try await preparationClock.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(model.isBusy)
        weak var retainedImage: UIImage?
        autoreleasepool {
            let image = UIImage() // Synthetic invalid image; no participant data.
            retainedImage = image
            model.storeImportedImages([image, image, image], startingAt: .conjunctiva)
        }
        XCTAssertNotNil(retainedImage)
        model.runMLAssessment()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while model.isRunningAssessment, clock.now < deadline {
            try await clock.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(model.isRunningAssessment)
        XCTAssertNotNil(model.validationAlert)
        XCTAssertTrue(model.assessmentImagesCleared)
        XCTAssertTrue(model.sessionImages.isEmpty)
        XCTAssertTrue(model.tissuePreviewImages.isEmpty)
        XCTAssertNil(model.latestTongueImage)
        XCTAssertNil(model.cameraManager.currentFrame)
        XCTAssertNil(retainedImage)
        model.stop()
    }

    @MainActor
    func testHistoryPublishesNewScanBeforePersistenceCompletes() async throws {
        let suite = "ImmediateHistoryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = ScanHistoryManager(suiteName: suite)
        let record = makeScan(date: Date(timeIntervalSince1970: 200))
        var publishedIDs: [UUID] = []
        let observation = history.$records.sink { publishedIDs = $0.map(\.id) }
        history.addRecord(record)
        // Home and History both observe this manager and read displayRecords.
        XCTAssertEqual(publishedIDs, [record.id])
        XCTAssertEqual(history.displayRecords.map(\.id), [record.id])
        await history.waitForPersistence()
        XCTAssertNil(history.persistenceError)
        let data = try XCTUnwrap(defaults.data(forKey: "ironscan_saved_scans_v1"))
        XCTAssertEqual(try JSONDecoder().decode([ScanRecord].self, from: data).map(\.id), [record.id])
        withExtendedLifetime(observation) {}
    }

    @MainActor
    func testPartialImportAdvancesAndWrapsFromActiveSlot() {
        let model = MultiScanHubViewModel(historyManager: ScanHistoryManager())
        let first = UIImage()
        let second = UIImage()
        model.storeImportedImages([first, second], startingAt: .tongue)

        XCTAssertTrue(model.sessionImages[.tongue] === first)
        XCTAssertTrue(model.sessionImages[.conjunctiva] === second)
        XCTAssertEqual(model.currentStep, .fingernail)
        XCTAssertFalse(model.isSessionComplete)
        XCTAssertFalse(model.isRunningAssessment)
        model.storeImportedImages([UIImage()], startingAt: model.currentStep)
        XCTAssertTrue(model.isSessionComplete)
        model.resetSession()
        XCTAssertFalse(model.isSessionComplete)
        XCTAssertTrue(model.tissuePreviewImages.isEmpty)
        XCTAssertNil(model.cameraManager.currentFrame)
        model.stop()
    }

    @MainActor
    func testCanonicalHistoryPersistsAndMergesAnAddBeforeLoad() async throws {
        let suite = "ScanHistoryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let older = makeScan(date: Date(timeIntervalSince1970: 100))
        let newer = makeScan(date: Date(timeIntervalSince1970: 200))
        let first = ScanHistoryManager(suiteName: suite)
        first.addRecord(older)
        await first.waitForPersistence()

        let second = ScanHistoryManager(suiteName: suite)
        second.addRecord(newer)
        // Persist before loading to cover the previous history-loss race.
        await second.waitForPersistence()
        await second.loadData()
        XCTAssertEqual(second.records.map(\.id), [newer.id, older.id])
        second.addRecord(newer)
        await second.waitForPersistence()
        XCTAssertEqual(second.records.count, 2)

        let reloaded = ScanHistoryManager(suiteName: suite)
        await reloaded.loadData()
        XCTAssertEqual(reloaded.records.map(\.id), [newer.id, older.id])
        XCTAssertEqual(reloaded.displayRecords.first?.estimatedHemoglobin, 11.8)
        XCTAssertEqual(reloaded.displayRecords.first?.severity, .mild)
        let data = try XCTUnwrap(defaults.data(forKey: "ironscan_saved_scans_v1"))
        XCTAssertEqual(try JSONDecoder().decode([ScanRecord].self, from: data).count, 2)
    }

    @MainActor
    func testDemoBaselineReplacesPersistedHistoryAndAcceptsThirdScan() async throws {
        let suite = "DemoBaselineTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = ScanHistoryManager(suiteName: suite)
        let old = makeScan(date: .distantPast)
        history.addRecord(old)
        // Reset must be ordered after this pending write and must not merge it back.
        history.resetToDemoBaseline()
        // Loading immediately must wait for the replacement, not resurrect the old scan.
        await history.loadData()
        await history.waitForPersistence()
        XCTAssertEqual(history.records.count, 2)
        XCTAssertFalse(history.records.contains { $0.id == old.id })
        XCTAssertEqual(history.records.map(\.hemoglobinG_dL), [11.4, 10.9])
        XCTAssertEqual(history.records.map(\.riskLevel), [.mild, .moderate])
        XCTAssertTrue(history.records.allSatisfy { $0.isDemoSample == true })
        XCTAssertTrue(history.displayRecords.allSatisfy { $0.summary == "Synthetic demo baseline" })
        for (record, days) in zip(history.records, [2, 4]) {
            XCTAssertEqual(Calendar.current.dateComponents([.day], from: record.timestamp, to: Date()).day, days)
        }
        let live = makeScan(date: Date())
        history.addRecord(live)
        await history.waitForPersistence()
        let reloaded = ScanHistoryManager(suiteName: suite)
        await reloaded.loadData()
        XCTAssertEqual(reloaded.records.count, 3)
        XCTAssertEqual(reloaded.records.first?.id, live.id)
        XCTAssertNotEqual(reloaded.records.first?.isDemoSample, true)
        reloaded.resetToDemoBaseline()
        reloaded.addRecord(live)
        await reloaded.waitForPersistence()
        let afterPendingAdd = ScanHistoryManager(suiteName: suite)
        await afterPendingAdd.loadData()
        XCTAssertEqual(afterPendingAdd.records.count, 3)
        XCTAssertEqual(afterPendingAdd.records.first?.id, live.id)
        reloaded.resetToDemoBaseline()
        await reloaded.waitForPersistence()
        XCTAssertEqual(reloaded.displayRecords.count, 2)
    }

    @MainActor
    func testResetClearsLegacyCacheAndKeepsSamplesOutOfSyncStore() async throws {
        let suite = "DemoLegacyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: cache)
        }
        let legacy = DashboardHistoryRecords.from([makeScan(date: .distantPast)]).map { record in
            var sample = record
            sample.isSyncedToCloud = true
            return sample
        }
        defaults.set(try JSONEncoder().encode(legacy), forKey: ScanHistoryStore.storageKey)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(legacy).write(to: cache)
        let store = ScanHistoryStore(defaults: defaults, cacheURL: cache)
        let history = ScanHistoryManager(suiteName: suite)
        history.connectSyncStore(store)
        XCTAssertEqual(history.displayRecords.count, 1)
        history.resetToDemoBaseline()
        await history.waitForPersistence()
        XCTAssertNil(history.persistenceError)
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertNil(defaults.data(forKey: ScanHistoryStore.storageKey))
        XCTAssertEqual(history.displayRecords.count, 2)
        // Reconnecting after relaunch must not queue synthetic rows for cloud upload.
        let reloadedStore = ScanHistoryStore(defaults: defaults, cacheURL: cache)
        let reloaded = ScanHistoryManager(suiteName: suite)
        reloaded.connectSyncStore(reloadedStore)
        await reloaded.loadData()
        XCTAssertEqual(reloaded.displayRecords.count, 2)
        XCTAssertEqual(reloadedStore.pendingSyncCount, 0)
        reloaded.clearAllRecords()
        await reloaded.waitForPersistence()
        XCTAssertTrue(reloaded.displayRecords.isEmpty)
    }

    @MainActor
    func testClearBeforeLoadingRemovesHistoryKeyAndPreservesProfile() async throws {
        let suite = "DemoClearTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = ScanHistoryManager(suiteName: suite)
        original.addRecord(makeScan(date: Date()))
        var profile = UserProfile.default
        profile.age = 25
        original.saveProfile(profile)
        await original.waitForPersistence()
        let history = ScanHistoryManager(suiteName: suite)
        history.clearAllRecords()
        await history.loadData()
        await history.waitForPersistence()
        XCTAssertTrue(history.displayRecords.isEmpty)
        XCTAssertNil(defaults.data(forKey: "ironscan_saved_scans_v1"))
        XCTAssertEqual(history.profile.age, 25)
        let reloaded = ScanHistoryManager(suiteName: suite)
        await reloaded.loadData()
        XCTAssertTrue(reloaded.records.isEmpty)
        XCTAssertEqual(reloaded.profile.age, 25)
    }

    @MainActor
    func testCanonicalAndSyncedHistoryShareAnIDWithoutDuplicating() {
        let scan = makeScan(date: Date(timeIntervalSince1970: 100))
        let transport = DashboardHistoryRecords.from([scan])
        let merged = DashboardHistoryRecords.merging([scan], legacy: transport)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.id, scan.id)
        XCTAssertEqual(merged.first?.estimatedHemoglobin, scan.hemoglobinG_dL)
    }

    @MainActor
    func testTrendRendersFirstMeasurementAndHasNonzeroDateDomain() {
        let scan = makeScan(date: Date(timeIntervalSince1970: 100))
        let records = DashboardHistoryRecords.from([scan])
        let chart = HistoricalHemoglobinTrendCard(records: records, emptyMessage: "Empty")
        XCTAssertTrue(chart.supportsTrendChart)
        XCTAssertLessThan(chart.xDomain.lowerBound, scan.timestamp)
        XCTAssertGreaterThan(chart.xDomain.upperBound, scan.timestamp)
        let renderer = ImageRenderer(content: chart.frame(width: 360))
        XCTAssertNotNil(renderer.uiImage)
        XCTAssertFalse(HistoricalHemoglobinTrendCard(records: [], emptyMessage: "Empty").supportsTrendChart)
    }

    func testPortraitNormalizerRotatesAndMirrorsOnlyWhenNeeded() throws {
        let normalizer = CameraPortraitNormalizer()
        let landscape = try SyntheticTongueFrameFactory.makePixelBuffer(width: 96, height: 64)
        let back = try XCTUnwrap(normalizer.normalize(landscape, position: .back, isAlreadyMirrored: false))
        XCTAssertEqual(CVPixelBufferGetWidth(back), 64)
        XCTAssertEqual(CVPixelBufferGetHeight(back), 96)
        let portrait = try SyntheticTongueFrameFactory.makePixelBuffer(width: 64, height: 96)
        let untouched = try XCTUnwrap(normalizer.normalize(portrait, position: .front, isAlreadyMirrored: true))
        XCTAssertTrue(untouched === portrait, "Already upright mirrored selfie buffers must not be rotated or mirrored twice")
        let mirrored = try XCTUnwrap(normalizer.normalize(portrait, position: .front, isAlreadyMirrored: false))
        XCTAssertFalse(mirrored === portrait)
        let restored = try XCTUnwrap(normalizer.normalize(mirrored, position: .front, isAlreadyMirrored: false))
        let context = CIContext()
        let original = try XCTUnwrap(context.createCGImage(CIImage(cvPixelBuffer: portrait), from: CGRect(x: 0, y: 0, width: 64, height: 96)))
        let twice = try XCTUnwrap(context.createCGImage(CIImage(cvPixelBuffer: restored), from: CGRect(x: 0, y: 0, width: 64, height: 96)))
        XCTAssertEqual(original.dataProvider?.data as Data?, twice.dataProvider?.data as Data?)
    }

    func testLandscapeSelfieHasSameUprightPixelsWithEitherConnectionMirroringMode() throws {
        let normalizer = CameraPortraitNormalizer()
        let landscape = try SyntheticTongueFrameFactory.makePixelBuffer(width: 96, height: 64)
        // Asymmetric corner colors reveal both upside-down and mirror errors.
        CVPixelBufferLockBaseAddress(landscape, [])
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(landscape))
        let stride = CVPixelBufferGetBytesPerRow(landscape)
        for y in 0..<64 {
            for x in 0..<96 {
                let pixel = base.advanced(by: y * stride + x * 4).assumingMemoryBound(to: UInt8.self)
                pixel[0] = x < 48 ? 255 : 0
                pixel[1] = y < 32 ? 255 : 0
                pixel[2] = x < 48 && y < 32 ? 255 : 0
                pixel[3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(landscape, [])
        let context = CIContext()
        let connectionMirrored = try SyntheticTongueFrameFactory.makePixelBuffer(width: 96, height: 64)
        context.render(CIImage(cvPixelBuffer: landscape).oriented(.upMirrored), to: connectionMirrored)
        let softwareMirrored = try XCTUnwrap(normalizer.normalize(
            landscape, position: .front, isAlreadyMirrored: false))
        let hardwareMirrored = try XCTUnwrap(normalizer.normalize(
            connectionMirrored, position: .front, isAlreadyMirrored: true))
        XCTAssertEqual(CVPixelBufferGetWidth(hardwareMirrored), 64)
        XCTAssertEqual(CVPixelBufferGetHeight(hardwareMirrored), 96)
        let bounds = CGRect(x: 0, y: 0, width: 64, height: 96)
        let expected = try XCTUnwrap(context.createCGImage(CIImage(cvPixelBuffer: softwareMirrored), from: bounds))
        let actual = try XCTUnwrap(context.createCGImage(CIImage(cvPixelBuffer: hardwareMirrored), from: bounds))
        XCTAssertEqual(expected.dataProvider?.data as Data?, actual.dataProvider?.data as Data?)
    }

    private func makeScan(date: Date) -> ScanRecord {
        ScanRecord(timestamp: date, hemoglobinG_dL: 11.8, riskLevel: .mild,
                   conjunctivaScore: 0.4, nailScore: 0.6, tongueScore: 0.5,
                   calibrationOffsetApplied: 0)
    }

    func testAssessmentFallbackUsesSpecifiedDemoValues() {
        let summary = ScanAssessmentSummary.demoFallback
        XCTAssertEqual(summary.estimatedHemoglobin, 9.8)
        XCTAssertEqual(summary.pallorIndices[.conjunctiva], 0.72)
        XCTAssertEqual(summary.pallorIndices[.fingernail], 0.81)
        XCTAssertEqual(summary.pallorIndices[.tongue], 0.70)
        XCTAssertEqual(summary.warningText, "Severe Anemia Risk")
        XCTAssertTrue(summary.usesDemoFallback)
    }

    private func makeReport() -> TongueVisualAttributeReport {
        let score = VisualAttributeScore(probability: 0.25, lockedThreshold: 0.5)
        return TongueVisualAttributeReport(
            pallor: score,
            toothmark: score,
            crack: score,
            tipSideRed: score,
            furThick: score,
            inferenceDurationMs: 12,
            modelVersion: "test",
            isEngineeringFixture: true
        )
    }
}

/// Synthetic controller: startup waits until the test has observed capabilities.
private actor SwitchableTestCamera: CameraSessionControlling {
    nonisolated let previewSource = CameraPreviewSource.simulated
    private var continuation: AsyncStream<CameraEvent>.Continuation?
    private var startup: CheckedContinuation<Void, Never>?
    private(set) var flipCount = 0

    func eventStream() -> AsyncStream<CameraEvent> {
        let pair = AsyncStream<CameraEvent>.makeStream(bufferingPolicy: .bufferingNewest(12))
        continuation = pair.continuation
        return pair.stream
    }

    func start() async {
        await withCheckedContinuation { startup in
            self.startup = startup
            continuation?.yield(.capabilities(capabilities(position: .front)))
        }
    }

    func finishStartup() {
        startup?.resume()
        startup = nil
        continuation?.yield(.state(.ready))
    }

    func toggleCamera() async throws {
        flipCount += 1
        continuation?.yield(.capabilities(capabilities(position: .back)))
    }

    func capture() async -> Bool { false }
    func updateCaptureOrientation(_ orientation: CaptureOrientation) async {}
    func setOpticsProfile(_ profile: CameraOpticsProfile) async throws {}
    func setTorchEnabled(_ enabled: Bool) async throws {}
    func stabilizeForAlignedTongue() async {}
    func handleInterruptionEnded() async {}
    func stop() async {
        finishStartup()
        continuation?.finish()
        continuation = nil
    }

    private func capabilities(position: CameraLensPosition) -> CameraCapabilities {
        CameraCapabilities(
            hasTorch: false, supportsCameraToggle: true, lensPosition: position,
            supportsFocusPoint: false, supportsExposurePoint: false,
            supportsFocusLock: false, supportsCustomExposure: false,
            supportsWhiteBalanceLock: false, supportsActiveMaxDimensions: false
        )
    }
}

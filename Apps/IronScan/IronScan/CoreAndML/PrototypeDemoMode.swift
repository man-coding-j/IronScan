import Foundation

enum PrototypeDemoMode {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif
    static let minimumSegmentationConfidence = 0.50
    static let acceptedTongueAreaRatio = 0.08 ... 0.90
}

// A simulator-only, explicitly enabled capture fixture. Never loads or uploads participant records.
enum TutorialCapture {
    static var isEnabled: Bool {
        #if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("--tutorial-capture")
        #else
        false
        #endif
    }

    static var screen: String {
        ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--tutorial-screen=") })?
            .split(separator: "=").last.map(String.init) ?? "home"
    }

    static var defaults: UserDefaults {
        let defaults = UserDefaults(suiteName: "org.ironscan.tutorial-capture")!
        defaults.register(defaults: [
            "userFirstName": "Explorer", "userAge": 24, "userBiologicalSex": "Female",
            "fitzpatrickSkinPhototype": "Type III", "lightingEnvironment": "Indoor"
        ])
        return defaults
    }

    static var records: [ScanHistoryRecord] {
        #if DEBUG && targetEnvironment(simulator)
        let end = Date(timeIntervalSince1970: 1_792_665_000)
        let values = [10.5, 10.7, 10.9, 11.1, 11.4, 11.6, 11.8]
        return values.enumerated().map { index, value in
            ScanHistoryRecord(
                id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 1))!,
                capturedAt: end.addingTimeInterval(Double(index - 6) * 86_400),
                summary: "Illustrative sample", opticalPatternIndex: 0.3,
                severity: .mild, estimatedHemoglobin: value, isSyncedToCloud: true
            )
        }.reversed()
        #else
        return []
        #endif
    }
}

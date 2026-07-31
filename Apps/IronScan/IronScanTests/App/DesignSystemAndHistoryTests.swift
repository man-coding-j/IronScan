import XCTest
@testable import IronScan

@MainActor
final class DesignSystemAndHistoryTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    @MainActor
    override func setUp() {
        super.setUp()
        suiteName = "DesignSystemAndHistoryTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    @MainActor
    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testMainNavigationHasFiveStableTabs() {
        XCTAssertEqual(MainTab.allCases, [.home, .history, .scan, .learn, .profile])
        XCTAssertEqual(MainTab.home.symbol, "house")
        XCTAssertEqual(MainTab.history.symbol, "clock")
        XCTAssertEqual(MainTab.scan.symbol, "camera.fill")
        XCTAssertEqual(MainTab.learn.symbol, "book.closed")
        XCTAssertEqual(MainTab.profile.symbol, "person")
    }

    func testHistoryPersistsOnlyBoundedResultSummaries() {
        let store = ScanHistoryStore(defaults: defaults)
        for index in 0 ... ScanHistoryStore.maximumRecordCount {
            store.add(makeResult(score: Double(index) / 100))
        }

        XCTAssertEqual(store.records.count, ScanHistoryStore.maximumRecordCount)
        XCTAssertNil(store.persistenceError)

        let reloaded = ScanHistoryStore(defaults: defaults)
        XCTAssertEqual(reloaded.records.count, ScanHistoryStore.maximumRecordCount)
        XCTAssertEqual(reloaded.records.first?.summary, .lowerObservedRisk)
        XCTAssertNil(reloaded.persistenceError)
    }

    func testCareCopyKeepsLocationLocalAndAvoidsTreatmentClaims() {
        XCTAssertTrue(CareResourceContent.locationPurpose.localizedCaseInsensitiveContains("not stored"))
        let copy = CareResourceContent.topics.map(\.detail).joined(separator: " ").lowercased()
        XCTAssertFalse(copy.contains("supplement"))
        XCTAssertFalse(copy.contains("medication"))
        XCTAssertFalse(copy.contains("you have anemia"))
        XCTAssertTrue(copy.contains("laboratory test"))
    }

    private func makeResult(score: Double) -> TriangulationResult {
        TriangulationResult(
            summary: .lowerObservedRisk,
            opticalPallorIndex: score,
            contributions: [],
            rejectionReasons: [],
            configurationIdentifier: "org.ironscan.test",
            configurationVersion: "1.0.0",
            mode: .prototypeDemo
        )
    }
}

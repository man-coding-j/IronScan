import XCTest
@testable import IronScan

final class OnboardingFlowTests: XCTestCase {
    func testOrganicPaletteUsesLockedHexValues() {
        XCTAssertEqual(IronTheme.Hex.creamBackground, "#F8F6F0")
        XCTAssertEqual(IronTheme.Hex.terracottaPrimary, "#FF6B35")
        XCTAssertEqual(IronTheme.Hex.slateText, "#2A2830")
        XCTAssertEqual(IronTheme.Hex.sageAccent, "#8DAA82")
    }

    func testHeroCopyDoesNotClaimIronMeasurementOrDiagnosis() {
        let copy = "\(OnboardingFlowContent.heroTitle) \(OnboardingFlowContent.heroBody)"
            .lowercased()

        XCTAssertTrue(copy.contains("possible anemia risk"))
        XCTAssertTrue(copy.contains("does not measure iron levels"))
        XCTAssertFalse(copy.contains("you have anemia"))
        XCTAssertFalse(copy.contains("you are iron deficient"))
    }

    func testConsentDisclosesPrototypeLimitations() {
        let copy = "\(OnboardingConsent.summary) \(OnboardingConsent.detail)".lowercased()

        XCTAssertTrue(copy.contains("research prototype"))
        XCTAssertTrue(copy.contains("does not measure iron or hemoglobin"))
        XCTAssertTrue(copy.contains("cannot establish a clinical diagnosis"))
        XCTAssertTrue(copy.contains("laboratory test"))
    }

    func testContextCopyKeepsQuestionnaireSeparateFromOpticalResult() {
        let copy = ScreeningIntakeContent.contextBody.lowercased()

        XCTAssertTrue(copy.contains("optional"))
        XCTAssertTrue(copy.contains("separately from the optical result"))
        XCTAssertFalse(copy.contains("more accurate"))
    }
}

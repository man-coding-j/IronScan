import XCTest
@testable import IronScan

final class OnboardingFlowTests: XCTestCase {
    func testOrganicPaletteUsesLockedHexValues() {
        XCTAssertEqual(IronTheme.Hex.creamBackground, "#F5EBE1")
        XCTAssertEqual(IronTheme.Hex.terracottaPrimary, "#E68A61")
        XCTAssertEqual(IronTheme.Hex.slateText, "#3D3B4A")
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

    func testAccountPreviewDisclosesNoAccountOrCredentialStorage() {
        let copy = OnboardingFlowContent.accountPrivacy.lowercased()

        XCTAssertTrue(copy.contains("never submitted"))
        XCTAssertTrue(copy.contains("no account is created"))
    }

    func testContextCopyKeepsQuestionnaireSeparateFromOpticalResult() {
        let copy = OnboardingFlowContent.contextBody.lowercased()

        XCTAssertTrue(copy.contains("optional"))
        XCTAssertTrue(copy.contains("separately from the optical result"))
        XCTAssertFalse(copy.contains("more accurate"))
    }
}

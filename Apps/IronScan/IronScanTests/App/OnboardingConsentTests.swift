import XCTest
@testable import IronScan

final class OnboardingConsentTests: XCTestCase {
    func testConsentStatesResearchAndLaboratoryLimitations() {
        let content = "\(OnboardingConsent.summary) \(OnboardingConsent.detail)".lowercased()

        XCTAssertTrue(content.contains("research prototype"))
        XCTAssertTrue(content.contains("not fda-cleared"))
        XCTAssertTrue(content.contains("does not measure iron or hemoglobin"))
        XCTAssertTrue(content.contains("confirm with a laboratory test"))
    }

    func testConsentContainsNoTreatmentRecommendation() {
        let content = OnboardingConsent.detail.lowercased()

        XCTAssertFalse(content.contains("supplement"))
        XCTAssertFalse(content.contains("medication"))
    }
}

import XCTest
@testable import IronScan

final class CareResourcesTests: XCTestCase {
    func testHospitalAvailabilityIsClearlyAnEstimate() {
        let availability = AvailabilityEngine().availability(for: "Community Hospital")

        XCTAssertTrue(availability.is24Hours)
        XCTAssertTrue(availability.hours.localizedCaseInsensitiveContains("prototype"))
        XCTAssertTrue(availability.verificationNotice.localizedCaseInsensitiveContains("not live"))
        XCTAssertTrue(availability.verificationNotice.localizedCaseInsensitiveContains("call"))
    }

    func testLaboratoryAvailabilityIncludesWeekdayAndHolidayCaveats() {
        let availability = AvailabilityEngine().availability(for: "Quest Diagnostics")

        XCTAssertEqual(availability.category, .diagnosticLaboratory)
        XCTAssertFalse(availability.is24Hours)
        XCTAssertTrue(availability.hours.contains("Mon–Fri"))
        XCTAssertTrue(availability.holidayStatus.contains("Christmas"))
        XCTAssertTrue(availability.verificationNotice.localizedCaseInsensitiveContains("confirm"))
    }

    func testUnknownVenueDoesNotInventHours() {
        let availability = AvailabilityEngine().availability(for: "Community Wellness Center")

        XCTAssertEqual(availability.category, .unknown)
        XCTAssertTrue(availability.hours.localizedCaseInsensitiveContains("not available"))
        XCTAssertFalse(availability.badgeText.localizedCaseInsensitiveContains("open"))
    }

    func testSearchQueriesCoverRequiredCareCategories() {
        XCTAssertEqual(
            LocationManager.searchQueries,
            [
                "Diagnostic Laboratory",
                "Quest Diagnostics",
                "Labcorp",
                "Urgent Care",
                "Hospital",
            ]
        )
    }

    func testTelephoneURLRemovesFormattingAndRejectsMissingNumber() {
        XCTAssertEqual(
            ClinicActionURLBuilder.telephoneURL(for: "+1 (415) 555-0100")?.absoluteString,
            "tel://+14155550100"
        )
        XCTAssertNil(ClinicActionURLBuilder.telephoneURL(for: nil))
        XCTAssertNil(ClinicActionURLBuilder.telephoneURL(for: "extension only"))
    }

    func testWebsiteAllowsOnlyHTTPAndHTTPS() {
        XCTAssertEqual(
            ClinicActionURLBuilder.websiteURL(from: URL(string: "https://example.org")),
            URL(string: "https://example.org")
        )
        XCTAssertNil(ClinicActionURLBuilder.websiteURL(from: URL(string: "file:///tmp/private")))
        XCTAssertNil(ClinicActionURLBuilder.websiteURL(from: URL(string: "javascript:alert(1)")))
    }
}

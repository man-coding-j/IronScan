import Foundation

enum AvailabilityCategory: Equatable, Sendable {
    case typicallyTwentyFourHours
    case diagnosticLaboratory
    case unknown
}

struct VenueAvailability: Equatable, Sendable {
    let category: AvailabilityCategory
    let hours: String
    let holidayStatus: String
    let verificationNotice: String

    var is24Hours: Bool {
        category == .typicallyTwentyFourHours
    }

    var badgeText: String {
        switch category {
        case .typicallyTwentyFourHours:
            "Typical 24/7 category"
        case .diagnosticLaboratory:
            "Typical weekday hours"
        case .unknown:
            "Hours unavailable"
        }
    }
}

struct AvailabilityEngine: Sendable {
    func availability(for venueName: String) -> VenueAvailability {
        let normalizedName = venueName.lowercased()
        if normalizedName.contains("urgent care")
            || normalizedName.contains("hospital")
            || normalizedName.contains("emergency") {
            return VenueAvailability(
                category: .typicallyTwentyFourHours,
                hours: "Prototype category estimate: 24-hour service may be available.",
                holidayStatus: "Holiday access varies by department and location.",
                verificationNotice: "Not live hours. Call this location before traveling."
            )
        }
        if normalizedName.contains("lab")
            || normalizedName.contains("quest")
            || normalizedName.contains("diagnostic") {
            return VenueAvailability(
                category: .diagnosticLaboratory,
                hours: "Prototype estimate: Mon–Fri, 8:00 AM–5:00 PM.",
                holidayStatus: "May close on Thanksgiving, Christmas, and New Year’s Day.",
                verificationNotice: "Not live hours. Confirm hours and CBC services directly."
            )
        }
        return VenueAvailability(
            category: .unknown,
            hours: "Operating hours are not available from this Apple Maps result.",
            holidayStatus: "Holiday hours are unknown.",
            verificationNotice: "Call or visit the location’s website before traveling."
        )
    }
}

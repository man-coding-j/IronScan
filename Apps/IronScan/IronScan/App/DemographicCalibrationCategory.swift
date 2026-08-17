import Foundation

extension DemographicCalibrationCategory {
    var badgeTitle: String { rawValue }

    var normalHemoglobinReference: String {
        switch self {
        case .adultMale:
            return "13.5-17.5 g/dL"
        case .adultFemale:
            return "12.0-15.5 g/dL"
        case .pregnantFemale:
            return "11.0+ g/dL"
        case .pediatric:
            return "Age-dependent pediatric range"
        case .defaultCategory:
            return "Research default"
        }
    }
}

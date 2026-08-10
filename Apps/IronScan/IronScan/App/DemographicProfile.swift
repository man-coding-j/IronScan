import Foundation

enum DemographicStorageKeys {
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let legacyHasSeenOnboarding = "hasSeenOnboarding"
    static let userAge = "userAge"
    static let userBiologicalSex = "userBiologicalSex"
    static let isPregnant = "isPregnant"
}

enum UserBiologicalSex: String, CaseIterable, Identifiable, Codable, Sendable {
    case male = "Male"
    case female = "Female"
    case other = "Other"

    var id: String { rawValue }
}

enum DemographicCalibrationCategory: String, Codable, Sendable {
    case adultMale
    case adultFemale
    case pregnantFemale
    case generalResearchProfile

    var badgeTitle: String {
        switch self {
        case .adultMale:
            "Adult Male"
        case .adultFemale:
            "Adult Female"
        case .pregnantFemale:
            "Pregnant Female"
        case .generalResearchProfile:
            "General Research Profile"
        }
    }

    var normalHemoglobinReference: String {
        switch self {
        case .adultMale:
            "13.5-17.5 g/dL"
        case .adultFemale:
            "12.0-15.5 g/dL"
        case .pregnantFemale:
            "11.0+ g/dL"
        case .generalResearchProfile:
            "Research default"
        }
    }
}

struct DemographicProfile: Equatable, Sendable {
    let age: Int?
    let biologicalSex: UserBiologicalSex
    let isPregnant: Bool

    var calibration: DemographicCalibration {
        DemographicCalibration(profile: self)
    }

    var ageDescription: String {
        guard let age else { return "Not provided" }
        return "\(age)"
    }
}

struct DemographicCalibration: Equatable, Sendable {
    static let defaultDecisionThreshold = 0.50

    let category: DemographicCalibrationCategory
    let decisionThreshold: Double

    init(profile: DemographicProfile) {
        let isAdult = (profile.age ?? 0) >= 18
        if isAdult, profile.biologicalSex == .female, profile.isPregnant {
            category = .pregnantFemale
            decisionThreshold = 0.56
        } else if isAdult, profile.biologicalSex == .male {
            category = .adultMale
            decisionThreshold = 0.46
        } else if isAdult, profile.biologicalSex == .female {
            category = .adultFemale
            decisionThreshold = 0.50
        } else {
            category = .generalResearchProfile
            decisionThreshold = Self.defaultDecisionThreshold
        }
    }

    var badgeTitle: String { category.badgeTitle }
}

enum DemographicProfileStore {
    static func load(defaults: UserDefaults = .standard) -> DemographicProfile {
        let storedAge = defaults.object(forKey: DemographicStorageKeys.userAge) as? Int
        let rawSex = defaults.string(forKey: DemographicStorageKeys.userBiologicalSex)
            ?? UserBiologicalSex.other.rawValue
        let biologicalSex = UserBiologicalSex(rawValue: rawSex) ?? .other
        let isPregnant = defaults.bool(forKey: DemographicStorageKeys.isPregnant)

        return DemographicProfile(
            age: storedAge,
            biologicalSex: biologicalSex,
            isPregnant: biologicalSex == .female ? isPregnant : false
        )
    }

    static func calibration(defaults: UserDefaults = .standard) -> DemographicCalibration {
        load(defaults: defaults).calibration
    }

    static func syncLegacyOnboardingFlagIfNeeded(defaults: UserDefaults = .standard) {
        let hasCompleted = defaults.bool(forKey: DemographicStorageKeys.hasCompletedOnboarding)
        let legacyHasSeenOnboarding = defaults.bool(forKey: DemographicStorageKeys.legacyHasSeenOnboarding)
        if !hasCompleted, legacyHasSeenOnboarding {
            defaults.set(true, forKey: DemographicStorageKeys.hasCompletedOnboarding)
        }
    }
}

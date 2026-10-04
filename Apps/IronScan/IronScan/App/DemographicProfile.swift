import Foundation
import SwiftUI

enum DemographicStorageKeys {
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let legacyHasSeenOnboarding = "hasSeenOnboarding"
    static let userAge = "userAge"
    static let userBiologicalSex = "userBiologicalSex"
    static let fitzpatrickSkinPhototype = "fitzpatrickSkinPhototype"
    static let lightingEnvironment = "lightingEnvironment"
    static let isPregnant = "isPregnant"
    static let recentLabHemoglobin = "recentLabHemoglobin"
    static let experiencesFatigue = "experiencesFatigue"
    static let experiencesDizziness = "experiencesDizziness"
    static let veganOrVegetarian = "veganOrVegetarian"
    static let heavyMenstrualBleeding = "heavyMenstrualBleeding"
    static let previousAnemiaDiagnosis = "previousAnemiaDiagnosis"
    static let hasActiveChestPain = "hasActiveChestPain"
    static let hasRecentSyncope = "hasRecentSyncope"
    static let hasSevereRestingShortnessOfBreath = "hasSevereRestingShortnessOfBreath"
}

enum UserBiologicalSex: String, CaseIterable, Identifiable, Codable, Sendable {
    case male = "Male"
    case female = "Female"
    case other = "Other"

    var id: String { rawValue }
}

enum FitzpatrickSkinPhototype: String, CaseIterable, Identifiable, Codable, Sendable {
    case notProvided = "Not provided"
    case typeI = "Type I"
    case typeII = "Type II"
    case typeIII = "Type III"
    case typeIV = "Type IV"
    case typeV = "Type V"
    case typeVI = "Type VI"

    var id: String { rawValue }
}

enum LightingEnvironment: String, CaseIterable, Identifiable, Codable, Sendable {
    case notProvided = "Not provided"
    case indoor = "Indoor"
    case naturalSunlight = "Natural Sunlight"
    case lowLight = "Low Light"

    var id: String { rawValue }
}

struct DemographicProfile: Equatable, Sendable {
    let age: Int?
    let biologicalSex: UserBiologicalSex
    let fitzpatrickSkinPhototype: FitzpatrickSkinPhototype?
    let lightingEnvironment: LightingEnvironment?
    let isPregnant: Bool
    let recentLabHemoglobin: Double?
    let experiencesFatigue: Bool
    let experiencesDizziness: Bool
    let veganOrVegetarian: Bool
    let heavyMenstrualBleeding: Bool
    let previousAnemiaDiagnosis: Bool
    let hasActiveChestPain: Bool
    let hasRecentSyncope: Bool
    let hasSevereRestingShortnessOfBreath: Bool

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
        } else if let age = profile.age, age > 0 {
            category = .pediatric
            decisionThreshold = 0.52
        } else {
            category = .defaultCategory
            decisionThreshold = Self.defaultDecisionThreshold
        }
    }

    var badgeTitle: String { category.badgeTitle }
}

class DemographicProfileStore: ObservableObject {
    @AppStorage("userAge") var age: Int = 25
    @AppStorage("userBiologicalSex") var biologicalSex: String = "Male"
    @AppStorage("fitzpatrickSkinPhototype") var fitzpatrickSkinPhototype: String = FitzpatrickSkinPhototype.notProvided.rawValue
    @AppStorage("lightingEnvironment") var lightingEnvironment: String = LightingEnvironment.notProvided.rawValue
    @AppStorage("isPregnant") var isPregnant: Bool = false
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @AppStorage("recentLabHemoglobin") private var recentLabHemoglobinStorage: Double = 0
    @AppStorage("experiencesFatigue") var experiencesFatigue: Bool = false
    @AppStorage("experiencesDizziness") var experiencesDizziness: Bool = false
    @AppStorage("veganOrVegetarian") var veganOrVegetarian: Bool = false
    @AppStorage("heavyMenstrualBleeding") var heavyMenstrualBleeding: Bool = false
    @AppStorage("previousAnemiaDiagnosis") var previousAnemiaDiagnosis: Bool = false
    @AppStorage("hasActiveChestPain") var hasActiveChestPain: Bool = false
    @AppStorage("hasRecentSyncope") var hasRecentSyncope: Bool = false
    @AppStorage("hasSevereRestingShortnessOfBreath") var hasSevereRestingShortnessOfBreath: Bool = false

    var recentLabHemoglobin: Double? {
        get { recentLabHemoglobinStorage > 0 ? recentLabHemoglobinStorage : nil }
        set { recentLabHemoglobinStorage = newValue ?? 0 }
    }

    static func load(defaults: UserDefaults = .standard) -> DemographicProfile {
        let storedAge = defaults.object(forKey: DemographicStorageKeys.userAge) as? Int
        let rawSex = defaults.string(forKey: DemographicStorageKeys.userBiologicalSex)
            ?? UserBiologicalSex.other.rawValue
        let biologicalSex = UserBiologicalSex(rawValue: rawSex) ?? .other
        let rawSkinPhototype = defaults.string(forKey: DemographicStorageKeys.fitzpatrickSkinPhototype)
            ?? FitzpatrickSkinPhototype.notProvided.rawValue
        let rawLightingEnvironment = defaults.string(forKey: DemographicStorageKeys.lightingEnvironment)
            ?? LightingEnvironment.notProvided.rawValue
        let isPregnant = defaults.bool(forKey: DemographicStorageKeys.isPregnant)
        let storedHemoglobin = defaults.object(forKey: DemographicStorageKeys.recentLabHemoglobin) as? Double

        return DemographicProfile(
            age: storedAge,
            biologicalSex: biologicalSex,
            fitzpatrickSkinPhototype: FitzpatrickSkinPhototype(rawValue: rawSkinPhototype)
                .flatMap { $0 == .notProvided ? nil : $0 },
            lightingEnvironment: LightingEnvironment(rawValue: rawLightingEnvironment)
                .flatMap { $0 == .notProvided ? nil : $0 },
            isPregnant: biologicalSex == .female ? isPregnant : false,
            recentLabHemoglobin: storedHemoglobin.map { $0 > 0 ? $0 : nil } ?? nil,
            experiencesFatigue: defaults.bool(forKey: DemographicStorageKeys.experiencesFatigue),
            experiencesDizziness: defaults.bool(forKey: DemographicStorageKeys.experiencesDizziness),
            veganOrVegetarian: defaults.bool(forKey: DemographicStorageKeys.veganOrVegetarian),
            heavyMenstrualBleeding: biologicalSex == .female
                ? defaults.bool(forKey: DemographicStorageKeys.heavyMenstrualBleeding)
                : false,
            previousAnemiaDiagnosis: defaults.bool(forKey: DemographicStorageKeys.previousAnemiaDiagnosis),
            hasActiveChestPain: defaults.bool(forKey: DemographicStorageKeys.hasActiveChestPain),
            hasRecentSyncope: defaults.bool(forKey: DemographicStorageKeys.hasRecentSyncope),
            hasSevereRestingShortnessOfBreath: defaults.bool(forKey: DemographicStorageKeys.hasSevereRestingShortnessOfBreath)
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

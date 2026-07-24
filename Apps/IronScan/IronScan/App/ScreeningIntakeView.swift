import SwiftUI

enum BiologicalSexContext: String, CaseIterable, Identifiable, Sendable {
    case preferNotToSay
    case female
    case male
    case intersex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preferNotToSay: "Prefer not to say"
        case .female: "Female"
        case .male: "Male"
        case .intersex: "Intersex"
        }
    }
}

enum DietContext: String, CaseIterable, Identifiable, Sendable {
    case preferNotToSay
    case plantBased
    case includesMeat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preferNotToSay: "Prefer not to say"
        case .plantBased: "Vegetarian or plant-based"
        case .includesMeat: "Includes meat"
        }
    }
}

enum MenstrualHistoryContext: String, CaseIterable, Identifiable, Sendable {
    case preferNotToSay
    case notApplicable
    case notReported
    case reportsHeavyBleeding

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preferNotToSay: "Prefer not to say"
        case .notApplicable: "Not applicable"
        case .notReported: "No heavy bleeding reported"
        case .reportsHeavyBleeding: "Heavy bleeding reported"
        }
    }
}

struct ScreeningIntakeSnapshot: Equatable, Sendable {
    let biologicalSex: BiologicalSexContext
    let diet: DietContext
    let reportsFatigue: Bool
    let reportsColdHands: Bool
    let menstrualHistory: MenstrualHistoryContext

    init(
        biologicalSex: BiologicalSexContext,
        diet: DietContext,
        reportsFatigue: Bool,
        reportsColdHands: Bool,
        menstrualHistory: MenstrualHistoryContext = .preferNotToSay
    ) {
        self.biologicalSex = biologicalSex
        self.diet = diet
        self.reportsFatigue = reportsFatigue
        self.reportsColdHands = reportsColdHands
        self.menstrualHistory = menstrualHistory
    }

    var symptomSummary: String {
        let symptoms = [
            reportsFatigue ? "Fatigue" : nil,
            reportsColdHands ? "Cold hands" : nil,
        ].compactMap { $0 }
        return symptoms.isEmpty ? "None selected" : symptoms.joined(separator: ", ")
    }
}

enum ScreeningIntakeStorageKeys {
    static let biologicalSex = "researchIntake.biologicalSex"
    static let diet = "researchIntake.diet"
    static let fatigue = "researchIntake.fatigue"
    static let coldHands = "researchIntake.coldHands"
    static let menstrualHistory = "researchIntake.menstrualHistory"
}

struct ScreeningIntakeView: View {
    private let completionButtonTitle: String?
    private let onComplete: (() -> Void)?

    @AppStorage(ScreeningIntakeStorageKeys.biologicalSex)
    private var biologicalSexRaw = BiologicalSexContext.preferNotToSay.rawValue
    @AppStorage(ScreeningIntakeStorageKeys.diet)
    private var dietRaw = DietContext.preferNotToSay.rawValue
    @AppStorage(ScreeningIntakeStorageKeys.fatigue)
    private var reportsFatigue = false
    @AppStorage(ScreeningIntakeStorageKeys.coldHands)
    private var reportsColdHands = false
    @AppStorage(ScreeningIntakeStorageKeys.menstrualHistory)
    private var menstrualHistoryRaw = MenstrualHistoryContext.preferNotToSay.rawValue

    init(
        completionButtonTitle: String? = nil,
        onComplete: (() -> Void)? = nil
    ) {
        self.completionButtonTitle = completionButtonTitle
        self.onComplete = onComplete
    }

    var body: some View {
        Form {
            Section {
                Text("This optional information stays in the app on this device. It is not sent to the model and does not change the visual finding.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Research context")
            }

            Section("Biological sex") {
                Picker("Biological sex", selection: $biologicalSexRaw) {
                    ForEach(BiologicalSexContext.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.inline)
            }

            Section("Diet pattern") {
                Picker("Diet pattern", selection: $dietRaw) {
                    ForEach(DietContext.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.inline)
            }

            Section("Self-reported symptoms") {
                Toggle("Fatigue", isOn: $reportsFatigue)
                Toggle("Cold hands", isOn: $reportsColdHands)
            }

            Section("Menstrual history") {
                Picker("Menstrual history", selection: $menstrualHistoryRaw) {
                    ForEach(MenstrualHistoryContext.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.inline)
            }

            Section {
                Button("Clear saved context", role: .destructive) {
                    biologicalSexRaw = BiologicalSexContext.preferNotToSay.rawValue
                    dietRaw = DietContext.preferNotToSay.rawValue
                    reportsFatigue = false
                    reportsColdHands = false
                    menstrualHistoryRaw = MenstrualHistoryContext.preferNotToSay.rawValue
                }
            }

            if let completionButtonTitle, let onComplete {
                Section {
                    Button(completionButtonTitle, action: onComplete)
                        .buttonStyle(OrganicPrimaryButtonStyle())
                        .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle("Optional context")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(IronTheme.creamBackground.ignoresSafeArea())
        .organicTypography()
    }
}

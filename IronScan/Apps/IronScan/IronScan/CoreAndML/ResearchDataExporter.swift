import Foundation
import Security

enum ResearchDataExporter {
    static func exportAnonymizedResearchBundle(
        history: [ScanHistoryRecord],
        demographics: DemographicProfile
    ) -> URL? {
        let bundle = AnonymizedResearchBundle(
            subjectUUID: secureSubjectUUID(),
            exportedAt: Date(),
            demographicIndicators: DemographicIndicators(
                ageGroup: AgeGroup(age: demographics.age),
                biologicalSex: demographics.biologicalSex.rawValue,
                fitzpatrickSkinPhototype: demographics.fitzpatrickSkinPhototype?.rawValue
            ),
            scans: history
                .sorted { $0.capturedAt < $1.capturedAt }
                .map { record in
                    ResearchScanRecord(
                        capturedAt: record.capturedAt,
                        opticalPallorIndex: record.opticalPatternIndex,
                        confidenceScore: nil,
                        baselineLabHemoglobin: demographics.recentLabHemoglobin
                    )
                },
            schemaNotes: [
                "confidence_score is null when a local confidence metric was not persisted in the on-device scan history cache."
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(bundle) else { return nil }

        let filename = "IronScan_Anonymized_Research_Bundle_\(bundle.subjectUUID).json"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: outputURL, options: .atomic)
            return outputURL
        } catch {
            return nil
        }
    }

    private static func secureSubjectUUID() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)

        if status != errSecSuccess {
            return UUID().uuidString
        }

        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        let uuid = uuid_t(
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuid).uuidString
    }
}

private struct AnonymizedResearchBundle: Encodable {
    let subjectUUID: String
    let exportedAt: Date
    let demographicIndicators: DemographicIndicators
    let scans: [ResearchScanRecord]
    let schemaNotes: [String]

    enum CodingKeys: String, CodingKey {
        case subjectUUID = "subject_uuid"
        case exportedAt = "exported_at"
        case demographicIndicators = "demographic_indicators"
        case scans
        case schemaNotes = "schema_notes"
    }
}

private struct DemographicIndicators: Encodable {
    let ageGroup: AgeGroup
    let biologicalSex: String
    let fitzpatrickSkinPhototype: String?

    enum CodingKeys: String, CodingKey {
        case ageGroup = "age_group"
        case biologicalSex = "biological_sex"
        case fitzpatrickSkinPhototype = "fitzpatrick_skin_phototype"
    }
}

private struct ResearchScanRecord: Encodable {
    let capturedAt: Date
    let opticalPallorIndex: Double?
    let confidenceScore: Double?
    let baselineLabHemoglobin: Double?

    enum CodingKeys: String, CodingKey {
        case capturedAt = "captured_at"
        case opticalPallorIndex = "optical_pallor_index"
        case confidenceScore = "confidence_score"
        case baselineLabHemoglobin = "baseline_lab_hemoglobin"
    }
}

private enum AgeGroup: String, Encodable {
    case unknown = "Unknown"
    case under18 = "Under 18"
    case age18to24 = "18-24"
    case age25to34 = "25-34"
    case age35to44 = "35-44"
    case age45to54 = "45-54"
    case age55to64 = "55-64"
    case age65Plus = "65+"

    init(age: Int?) {
        guard let age else {
            self = .unknown
            return
        }

        switch age {
        case ..<18:
            self = .under18
        case 18 ... 24:
            self = .age18to24
        case 25 ... 34:
            self = .age25to34
        case 35 ... 44:
            self = .age35to44
        case 45 ... 54:
            self = .age45to54
        case 55 ... 64:
            self = .age55to64
        default:
            self = .age65Plus
        }
    }
}

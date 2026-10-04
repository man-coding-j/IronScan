import UIKit

struct ClinicalReportGenerator {
    private static let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
    private static let margin: CGFloat = 36
    private static let footerHeight: CGFloat = 82
    private static let sectionSpacing: CGFloat = 18
    private static let rowSpacing: CGFloat = 12
    private static let imageHeight: CGFloat = 128

    static func generatePDF(
        result: TriangulationResult,
        demographicProfile: DemographicProfile,
        images: [TissueSite: UIImage],
        heatmaps: [TissueSite: UIImage]
    ) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let timestamp = Date()
        let subjectID = anonymizedSubjectID()
        let version = appSemanticVersion()
        let confidenceScore = modelConfidenceScore(for: result)
        let confidenceInterval = hemoglobinConfidenceInterval(for: result)

        return renderer.pdfData { context in
            var pageNumber = 0
            var cursorY = margin

            func drawPageChrome() {
                let headerTitle = pageNumber == 1
                    ? "IronScan Clinical Research Summary"
                    : "IronScan Clinical Research Summary (cont.)"
                let titleRect = CGRect(x: margin, y: margin, width: pageRect.width - (margin * 2), height: 28)
                let titleStyle = NSMutableParagraphStyle()
                titleStyle.alignment = .left
                NSAttributedString(
                    string: headerTitle,
                    attributes: [
                        .font: UIFont.systemFont(ofSize: 22, weight: .bold),
                        .foregroundColor: UIColor.black,
                        .paragraphStyle: titleStyle
                    ]
                ).draw(in: titleRect)

                let metaText = [
                    "Subject ID: \(subjectID)",
                    "Timestamp: \(formattedTimestamp(timestamp))",
                    "App Semantic Version: \(version)"
                ].joined(separator: "    ")
                NSAttributedString(
                    string: metaText,
                    attributes: [
                        .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                        .foregroundColor: UIColor.darkGray
                    ]
                ).draw(in: CGRect(x: margin, y: margin + 30, width: pageRect.width - (margin * 2), height: 18))

                let footerRect = CGRect(
                    x: margin,
                    y: pageRect.height - margin - footerHeight + 6,
                    width: pageRect.width - (margin * 2),
                    height: footerHeight - 12
                )
                let footerPath = UIBezierPath(roundedRect: footerRect, cornerRadius: 14)
                UIColor(red: 0.98, green: 0.94, blue: 0.91, alpha: 1).setFill()
                footerPath.fill()

                let disclaimer = "RESEARCH PROTOTYPE ONLY - NOT AN FDA-APPROVED DIAGNOSTIC DEVICE. This document summarizes optical pallor indices and empirical regression estimates. Confirmatory Complete Blood Count (CBC) laboratory testing is required for clinical decision-making."
                let disclaimerStyle = NSMutableParagraphStyle()
                disclaimerStyle.lineBreakMode = .byWordWrapping
                NSAttributedString(
                    string: disclaimer,
                    attributes: [
                        .font: UIFont.systemFont(ofSize: 9.5, weight: .bold),
                        .foregroundColor: UIColor.black,
                        .paragraphStyle: disclaimerStyle
                    ]
                ).draw(in: footerRect.insetBy(dx: 12, dy: 10))

                NSAttributedString(
                    string: "Page \(pageNumber)",
                    attributes: [
                        .font: UIFont.systemFont(ofSize: 10, weight: .medium),
                        .foregroundColor: UIColor.darkGray
                    ]
                ).draw(
                    in: CGRect(
                        x: pageRect.width - margin - 60,
                        y: pageRect.height - margin - footerHeight - 10,
                        width: 60,
                        height: 12
                    )
                )
            }

            func beginPage() {
                context.beginPage()
                pageNumber += 1
                cursorY = margin + 58
                drawPageChrome()
            }

            func ensureSpace(_ requiredHeight: CGFloat) {
                let maxY = pageRect.height - margin - footerHeight - 10
                if cursorY + requiredHeight > maxY {
                    beginPage()
                }
            }

            func drawSectionTitle(_ title: String) {
                ensureSpace(28)
                NSAttributedString(
                    string: title,
                    attributes: [
                        .font: UIFont.systemFont(ofSize: 16, weight: .bold),
                        .foregroundColor: UIColor.black
                    ]
                ).draw(in: CGRect(x: margin, y: cursorY, width: pageRect.width - (margin * 2), height: 22))
                cursorY += 26
            }

            func drawKeyValueTable(rows: [(String, String)]) {
                let tableWidth = pageRect.width - (margin * 2)
                let rowHeight: CGFloat = 28
                let totalHeight = CGFloat(rows.count) * rowHeight
                ensureSpace(totalHeight + sectionSpacing)

                let tableRect = CGRect(x: margin, y: cursorY, width: tableWidth, height: totalHeight)
                UIColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1).setFill()
                UIBezierPath(roundedRect: tableRect, cornerRadius: 14).fill()

                let leftColumnWidth = tableWidth * 0.38
                let valueStyle = NSMutableParagraphStyle()
                valueStyle.lineBreakMode = .byWordWrapping

                for (index, row) in rows.enumerated() {
                    let rowY = cursorY + CGFloat(index) * rowHeight
                    if index > 0 {
                        UIColor(white: 0.86, alpha: 1).setStroke()
                        let divider = UIBezierPath()
                        divider.move(to: CGPoint(x: margin + 12, y: rowY))
                        divider.addLine(to: CGPoint(x: margin + tableWidth - 12, y: rowY))
                        divider.lineWidth = 0.8
                        divider.stroke()
                    }

                    NSAttributedString(
                        string: row.0,
                        attributes: [
                            .font: UIFont.systemFont(ofSize: 11, weight: .bold),
                            .foregroundColor: UIColor.darkGray
                        ]
                    ).draw(in: CGRect(x: margin + 14, y: rowY + 8, width: leftColumnWidth - 18, height: rowHeight - 12))

                    NSAttributedString(
                        string: row.1,
                        attributes: [
                            .font: UIFont.systemFont(ofSize: 11, weight: .medium),
                            .foregroundColor: UIColor.black,
                            .paragraphStyle: valueStyle
                        ]
                    ).draw(in: CGRect(x: margin + leftColumnWidth, y: rowY + 8, width: tableWidth - leftColumnWidth - 14, height: rowHeight - 10))
                }

                cursorY += totalHeight + sectionSpacing
            }

            func drawFindingsGrid() {
                let totalWidth = pageRect.width - (margin * 2)
                let cardWidth = (totalWidth - (rowSpacing * 2)) / 3
                let cardHeight: CGFloat = 112
                ensureSpace(cardHeight + sectionSpacing)

                let items: [(String, String, UIColor, UIColor)] = [
                    (
                        "Estimated Hemoglobin",
                        estimatedHemoglobinText(result: result, confidenceInterval: confidenceInterval),
                        UIColor.black,
                        UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1)
                    ),
                    (
                        "Overall Anemia Risk Tier",
                        clinicalRiskTier(for: result.severity),
                        badgeColor(for: result.severity),
                        badgeColor(for: result.severity).withAlphaComponent(0.14)
                    ),
                    (
                        "Model Confidence Score",
                        confidenceScore.formatted(.percent.precision(.fractionLength(0))),
                        UIColor.black,
                        UIColor(red: 0.94, green: 0.97, blue: 0.96, alpha: 1)
                    )
                ]

                for (index, item) in items.enumerated() {
                    let x = margin + CGFloat(index) * (cardWidth + rowSpacing)
                    let rect = CGRect(x: x, y: cursorY, width: cardWidth, height: cardHeight)
                    let card = UIBezierPath(roundedRect: rect, cornerRadius: 16)
                    item.3.setFill()
                    card.fill()

                    NSAttributedString(
                        string: item.0,
                        attributes: [
                            .font: UIFont.systemFont(ofSize: 10, weight: .bold),
                            .foregroundColor: UIColor.darkGray
                        ]
                    ).draw(in: CGRect(x: x + 12, y: cursorY + 12, width: cardWidth - 24, height: 24))

                    if index == 1 {
                        let badgeRect = CGRect(x: x + 12, y: cursorY + 46, width: cardWidth - 24, height: 30)
                        let badge = UIBezierPath(roundedRect: badgeRect, cornerRadius: 15)
                        item.2.withAlphaComponent(0.18).setFill()
                        badge.fill()
                        let paragraph = NSMutableParagraphStyle()
                        paragraph.alignment = .center
                        NSAttributedString(
                            string: item.1,
                            attributes: [
                                .font: UIFont.systemFont(ofSize: 15, weight: .bold),
                                .foregroundColor: item.2,
                                .paragraphStyle: paragraph
                            ]
                        ).draw(in: CGRect(x: badgeRect.minX, y: badgeRect.minY + 6, width: badgeRect.width, height: 18))
                    } else {
                        NSAttributedString(
                            string: item.1,
                            attributes: [
                                .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                                .foregroundColor: item.2
                            ]
                        ).draw(in: CGRect(x: x + 12, y: cursorY + 46, width: cardWidth - 24, height: 46))
                    }
                }

                cursorY += cardHeight + sectionSpacing
            }

            func drawImageSection() {
                let tissues: [(TissueSite, String)] = [(.eye, "Conjunctiva"), (.tongue, "Tongue"), (.nail, "Lip")]
                let contentWidth = pageRect.width - (margin * 2)
                let columnWidth = (contentWidth - rowSpacing) / 2
                let blockHeight = imageHeight + 46

                for (tissue, label) in tissues {
                    ensureSpace(blockHeight + 30)
                    NSAttributedString(
                        string: label,
                        attributes: [
                            .font: UIFont.systemFont(ofSize: 13, weight: .bold),
                            .foregroundColor: UIColor.black
                        ]
                    ).draw(in: CGRect(x: margin, y: cursorY, width: contentWidth, height: 18))

                    let rawRect = CGRect(x: margin, y: cursorY + 22, width: columnWidth, height: imageHeight)
                    let heatmapRect = CGRect(x: margin + columnWidth + rowSpacing, y: cursorY + 22, width: columnWidth, height: imageHeight)
                    drawImageCard(image: images[tissue], title: "Raw Image", frame: rawRect)
                    drawImageCard(image: heatmaps[tissue], title: "Saliency Heatmap", frame: heatmapRect)
                    cursorY += blockHeight + 18
                }
            }

            beginPage()
            drawSectionTitle("Demographics & Symptoms")
            drawKeyValueTable(
                rows: [
                    ("Age", demographicProfile.ageDescription),
                    ("Biological Sex", demographicProfile.biologicalSex.rawValue),
                    ("Reported Fatigue", yesNoValue(demographicProfile.experiencesFatigue)),
                    ("Dizziness", yesNoValue(demographicProfile.experiencesDizziness)),
                    ("Dietary Factors", dietaryFactorsDescription(for: demographicProfile)),
                    ("Baseline Lab Hb", baselineHemoglobinText(for: demographicProfile))
                ]
            )

            drawSectionTitle("Primary Findings")
            drawFindingsGrid()

            drawSectionTitle("Visual Inspection & Explainable AI")
            drawImageSection()
        }
    }

    private static func drawImageCard(image: UIImage?, title: String, frame: CGRect) {
        let titleRect = CGRect(x: frame.minX, y: frame.minY - 16, width: frame.width, height: 14)
        NSAttributedString(
            string: title,
            attributes: [
                .font: UIFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: UIColor.darkGray
            ]
        ).draw(in: titleRect)

        let borderPath = UIBezierPath(roundedRect: frame, cornerRadius: 12)
        UIColor(white: 0.90, alpha: 1).setFill()
        borderPath.fill()
        UIColor(white: 0.82, alpha: 1).setStroke()
        borderPath.lineWidth = 1
        borderPath.stroke()

        guard let image else {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            NSAttributedString(
                string: "Image unavailable",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: UIColor.darkGray,
                    .paragraphStyle: paragraph
                ]
            ).draw(in: frame.insetBy(dx: 16, dy: 48))
            return
        }

        let drawRect = aspectFitRect(for: image.size, in: frame.insetBy(dx: 8, dy: 8))
        image.draw(in: drawRect)
    }

    private static func aspectFitRect(for imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let widthScale = bounds.width / imageSize.width
        let heightScale = bounds.height / imageSize.height
        let scale = min(widthScale, heightScale)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - (drawSize.width / 2),
            y: bounds.midY - (drawSize.height / 2),
            width: drawSize.width,
            height: drawSize.height
        )
    }

    private static func anonymizedSubjectID() -> String {
        "IS-\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10))"
    }

    private static func formattedTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func appSemanticVersion() -> String {
        if let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !shortVersion.isEmpty {
            return shortVersion
        }
        if let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           !bundleVersion.isEmpty {
            return bundleVersion
        }
        return "Development"
    }

    private static func clinicalRiskTier(for severity: AnemiaSeverity) -> String {
        switch severity {
        case .normal:
            return "Low"
        case .mild:
            return "Mild"
        case .moderate:
            return "Moderate"
        case .severe:
            return "Severe"
        }
    }

    private static func badgeColor(for severity: AnemiaSeverity) -> UIColor {
        switch severity {
        case .normal:
            return .systemGreen
        case .mild:
            return .systemYellow
        case .moderate:
            return .systemOrange
        case .severe:
            return .systemRed
        }
    }

    private static func yesNoValue(_ value: Bool) -> String {
        value ? "Reported" : "Not reported"
    }

    private static func dietaryFactorsDescription(for profile: DemographicProfile) -> String {
        var factors = [String]()
        if profile.veganOrVegetarian {
            factors.append("Vegetarian/vegan diet")
        }
        if profile.previousAnemiaDiagnosis {
            factors.append("Prior anemia history")
        }
        if factors.isEmpty {
            return "No dietary factors reported"
        }
        return factors.joined(separator: ", ")
    }

    private static func baselineHemoglobinText(for profile: DemographicProfile) -> String {
        guard let hb = profile.recentLabHemoglobin else {
            return "Not provided"
        }
        return "\(hb.formatted(.number.precision(.fractionLength(1)))) g/dL"
    }

    private static func modelConfidenceScore(for result: TriangulationResult) -> Double {
        guard !result.contributions.isEmpty else { return 0.42 }
        let weightedCertainty = result.contributions.reduce(into: 0.0) { partial, contribution in
            let variancePenalty = min(max(contribution.variance ?? 0.18, 0), 0.5)
            let certainty = max(0.35, 1 - (variancePenalty * 1.6))
            partial += contribution.weight * certainty
        }
        return min(max(weightedCertainty, 0.35), 0.98)
    }

    private static func hemoglobinConfidenceInterval(for result: TriangulationResult) -> Double {
        let meanVariance = result.contributions.compactMap(\.variance)
        let variance = meanVariance.isEmpty ? 0.18 : meanVariance.reduce(0, +) / Double(meanVariance.count)
        return min(max(0.5 + (variance * 1.8), 0.5), 1.2)
    }

    private static func estimatedHemoglobinText(result: TriangulationResult, confidenceInterval: Double) -> String {
        guard let hemoglobin = result.estimatedHemoglobin else {
            return "Unavailable"
        }
        return "\(hemoglobin.formatted(.number.precision(.fractionLength(1)))) +/- \(confidenceInterval.formatted(.number.precision(.fractionLength(1)))) g/dL"
    }
}

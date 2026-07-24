import SwiftUI

struct MultiHealthDashboardView: View {
    let report: TongueVisualAttributeReport
    let onScanAgain: () -> Void

    var body: some View {
        IntegratedResearchReportView(report: report, onScanAgain: onScanAgain)
    }
}

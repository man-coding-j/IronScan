import SwiftUI
import UIKit

// Presentation-only fixtures: no HealthKit, inference, persistence, or export calls.
@MainActor
struct DemoFatigueBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("PREDICTIVE FORECAST")
                    .font(.caption.bold())
                Text("Sample trend: potential hemoglobin dip by Thursday. Explore iron-rich food ideas.")
                    .font(.subheadline.weight(.medium))
                Text("Simulated scenario · no personal forecast")
                    .font(.caption)
            }
        }
        .foregroundStyle(Color.brandTeal)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color.brandMarigold.opacity(0.85), Color.brandSand.opacity(0.65)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .accessibilityElement(children: .combine)
    }
}

@MainActor
struct MockWatchVitalsView: View {
    @State private var isWatchSynced = false
    @State private var isSyncing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Apple Health Vitals", systemImage: "applewatch")
                    .font(IronTheme.roundedFont(.headline, weight: .bold))
                Spacer(minLength: 4)
            }

            if isWatchSynced {
                Label("WatchOS Telemetry · Simulated", systemImage: "waveform.path.ecg")
                    .font(.subheadline.bold())
                VStack(spacing: 0) {
                    telemetryRow("SpO2", value: "98%", verified: true)
                    Divider()
                    telemetryRow("Resting HR", value: "68 bpm")
                    Divider()
                    telemetryRow("Perfusion Index", value: "1.2%")
                }
                .padding(.horizontal, 14)
                .background(Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 16))
            } else {
                Text("Preview a sample Apple Watch vitals sync.")
                    .font(.subheadline)
                Button {
                    isSyncing = true
                } label: {
                    HStack(spacing: 10) {
                        if isSyncing {
                            ProgressView().tint(.white)
                        }
                        Text(isSyncing ? "Syncing demo vitals…" : "Sync Apple Health")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(OrganicPrimaryButtonStyle())
                .disabled(isSyncing)
            }

            Text("Static sample values. No watch connection or Apple Health access.")
                .font(.caption)
                .foregroundStyle(IronTheme.textSecondary)
        }
        .foregroundStyle(IronTheme.textPrimary)
        .padding(20)
        .liquidGlassCard(cornerRadius: 26)
        .task(id: isSyncing) {
            guard isSyncing else { return }
            do {
                try await Task.sleep(for: .milliseconds(1_500))
                withAnimation { isWatchSynced = true }
                isSyncing = false
            } catch {
                // SwiftUI cancels the delay when this card leaves the screen.
                isSyncing = false
            }
        }
    }

    private func telemetryRow(_ title: String, value: String, verified: Bool = false) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            Text(value).font(.system(.headline, design: .monospaced)).monospacedDigit()
            if verified {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.brandTeal)
                    .accessibilityLabel("Sample status OK")
            }
        }
        .padding(.vertical, 14)
    }
}

@MainActor
struct NutritionPlanView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var supplementLogged = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Label("AI PLAN PREVIEW · DEMO", systemImage: "sparkles")
                        .font(.caption.bold())
                        .foregroundStyle(IronTheme.terracottaPrimary)
                    Text("Personalized Iron-Rich Nutrition Plan")
                        .font(IronTheme.roundedFont(.largeTitle, weight: .bold))
                    Text("An illustrative research prototype plan using fixed sample content.")
                        .foregroundStyle(IronTheme.textSecondary)

                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: "leaf.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(IronTheme.sageAccent)
                        Text("MEAL INSPIRATION / 01")
                            .font(.caption.bold())
                            .foregroundStyle(IronTheme.textSecondary)
                        Text("Spinach & Lentil Bowl")
                            .font(.title2.bold())
                        Text("Sample iron estimate: 6.5 mg")
                            .font(.headline)
                        Text("Illustrative value only; absorbed iron is not estimated by this demo.")
                            .font(.caption)
                            .foregroundStyle(IronTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                    .background(
                        LinearGradient(colors: [IronTheme.sageAccent.opacity(0.2), .white.opacity(0.7)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 28)
                    )

                    Button {
                        withAnimation { supplementLogged = true }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        Label(supplementLogged ? "Supplement Logged" : "Log Sample Supplement",
                              systemImage: supplementLogged ? "checkmark.circle.fill" : "pills.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .foregroundStyle(.white)
                            .background(supplementLogged ? Color.green : IronTheme.terracottaPrimary,
                                        in: RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                    .disabled(supplementLogged)
                    Text("Demo interaction only. Nothing is saved. This preview does not prescribe supplements or doses.")
                        .font(.caption)
                        .foregroundStyle(IronTheme.textSecondary)
                }
                .padding(24)
            }
            .background(IronTheme.beigeBackground.ignoresSafeArea())
            .navigationTitle("Nutrition Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

@MainActor
struct MockTelehealthPDFView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Label("IRONSCAN", systemImage: "waveform.path.ecg")
                            .font(.headline.bold())
                        Spacer()
                        Text("DEMO / 001").font(.caption.monospaced())
                    }
                    Rectangle().fill(Color.orange).frame(height: 3)
                    Text("IronScan Research Telemetry Report")
                        .font(.system(.largeTitle, design: .serif).bold())
                    Text("SIMULATED DOCUMENT · NON-CLINICAL")
                        .font(.caption.bold())
                        .foregroundStyle(Color.brown)
                    Text("Patient DOB: [Redacted]")
                    Text("Fictional sample record · no participant data")
                        .font(.caption)
                    Divider()
                    Text("01 / MODEL OVERVIEW").font(.caption.bold())
                    Text("Ensemble ML Confidence Score: 94.2%")
                        .font(.title3.bold())
                    Text("Hardcoded presentation value; no model evaluation was performed.")
                        .font(.subheadline)
                    Divider()
                    Text("02 / SAMPLE TELEMETRY").font(.caption.bold())
                    reportRow("SpO2", "98%")
                    reportRow("Resting HR", "68 bpm")
                    reportRow("Perfusion Index", "1.2%")
                    Divider()
                    Text("This static preview demonstrates a report layout. It is not a generated PDF, a medical record, or a basis for care decisions.")
                        .font(.footnote)
                    Text("IRONSCAN RESEARCH PROTOTYPE                                      1 / 1")
                        .font(.caption2.monospaced())
                }
                .foregroundStyle(Color.black)
                .padding(28)
                .frame(maxWidth: 680, alignment: .leading)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 4))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                .padding(16)
                .frame(maxWidth: .infinity)
            }
            .background(Color(white: 0.93))
            .navigationTitle("Report Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private func reportRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).font(.system(.body, design: .monospaced).bold())
        }
    }
}

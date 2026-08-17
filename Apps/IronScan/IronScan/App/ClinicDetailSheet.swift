import MapKit
import SafariServices
import SwiftUI

enum ClinicActionURLBuilder {
    static func telephoneURL(for phoneNumber: String?) -> URL? {
        guard let phoneNumber else { return nil }
        let allowed = Set("+0123456789")
        let normalized = String(phoneNumber.filter(allowed.contains))
        guard normalized.contains(where: \.isNumber) else { return nil }
        return URL(string: "tel://\(normalized)")
    }

    static func websiteURL(from url: URL?) -> URL? {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }
        return url
    }
}

struct ClinicDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let facility: NearbyCareFacility
    @State private var showsWebsite = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                availabilityCard
                actionRow
                Text("Apple Maps directory information and prototype schedule estimates can be incomplete. Confirm hours, services, and holiday access directly with the location.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .background(IronTheme.mintBackground.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
        .sheet(isPresented: $showsWebsite) {
            if let websiteURL {
                SafariView(url: websiteURL)
                    .ignoresSafeArea()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(facility.name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(IronTheme.textDark)
                Text(facility.distanceText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(IronTheme.tealDeep)
                Text(facility.address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(IronTheme.textDark)
                    .frame(width: 36, height: 36)
                    .background(.thinMaterial, in: Circle())
            }
            .accessibilityLabel("Close")
        }
    }

    private var availabilityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                facility.availability.badgeText,
                systemImage: facility.availability.is24Hours ? "clock.badge.checkmark.fill" : "clock.fill"
            )
            .font(.headline)
            .foregroundStyle(facility.availability.is24Hours ? Color.green : IronTheme.tealDeep)

            Text(facility.availability.hours)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(IronTheme.textDark)
            Text(facility.availability.holidayStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(facility.availability.verificationNotice)
                .font(.caption.weight(.bold))
                .foregroundStyle(IronTheme.warning)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 20)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            ClinicActionButton(title: "Call", symbol: "phone.fill", isEnabled: callURL != nil) {
                guard let callURL else { return }
                openURL(callURL)
            }
            ClinicActionButton(title: "Website", symbol: "safari.fill", isEnabled: websiteURL != nil) {
                showsWebsite = true
            }
            ClinicActionButton(title: "Directions", symbol: "car.fill", isEnabled: true) {
                facility.mapItem.openInMaps(launchOptions: [
                    MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving,
                ])
            }
        }
    }

    private var callURL: URL? {
        ClinicActionURLBuilder.telephoneURL(for: facility.phoneNumber)
    }

    private var websiteURL: URL? {
        ClinicActionURLBuilder.websiteURL(from: facility.websiteURL)
    }
}

private struct ClinicActionButton: View {
    let title: String
    let symbol: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.headline)
                Text(title)
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(isEnabled ? IronTheme.tealDeep : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.6), lineWidth: 1.5))
            .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityHint(isEnabled ? "" : "\(title) information is unavailable")
    }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(
        _ uiViewController: SFSafariViewController,
        context: Context
    ) {}
}

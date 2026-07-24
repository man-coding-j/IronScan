import MapKit
import SwiftUI

enum CareResourceContent {
    static let locationPurpose = "Your location is used only while this page is open to find nearby laboratories and clinics. It is not stored by IronScan."

    static let topics = [
        CareEducationTopic(
            title: "Heme and non-heme iron",
            symbol: "leaf.fill",
            detail: "Foods contain different forms of iron. Plant foods such as beans and leafy greens contain non-heme iron, while meat and seafood may contain heme iron. A licensed clinician or dietitian can help with individual dietary questions."
        ),
        CareEducationTopic(
            title: "Vitamin C with meals",
            symbol: "carrot.fill",
            detail: "Vitamin C-containing foods, such as citrus, berries, tomatoes, and bell peppers, can support absorption of non-heme iron when eaten in the same meal."
        ),
        CareEducationTopic(
            title: "Symptoms need context",
            symbol: "list.clipboard.fill",
            detail: "Fatigue, dizziness, or cold hands can have many causes. Visual screening and symptoms cannot establish anemia; confirm concerns with a laboratory test and licensed clinician."
        )
    ]
}

struct CareEducationTopic: Identifiable, Equatable {
    let title: String
    let symbol: String
    let detail: String

    var id: String { title }
}

struct CareResourcesView: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject var viewModel: LocationManager
    @State private var selectedFacility: NearbyCareFacility?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    mapCard
                    educationSection
                    disclaimer
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 120)
            }
            .background(IronTheme.mintBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selectedFacility) { facility in
                ClinicDetailSheet(facility: facility)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Care & Labs")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(IronTheme.textDark)
            Text("Find nearby care and explore general iron-health education.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Nearby laboratories and clinics", systemImage: "map.fill")
                .font(.headline)
                .foregroundStyle(IronTheme.textDark)

            Map(position: $viewModel.cameraPosition) {
                UserAnnotation()
                ForEach(viewModel.facilities) { facility in
                    Annotation(facility.name, coordinate: facility.coordinate) {
                        Button {
                            selectedFacility = facility
                        } label: {
                            Image(systemName: "cross.case.fill")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(IronTheme.tealPrimary, in: Circle())
                                .overlay {
                                    Circle().stroke(Color.white.opacity(0.9), lineWidth: 2)
                                }
                                .shadow(color: Color.black.opacity(0.16), radius: 5, y: 3)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Show details for \(facility.name)")
                    }
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.75), lineWidth: 0.5)
            }

            Text(viewModel.message)
                .font(.caption)
                .foregroundStyle(.secondary)

            if viewModel.needsSettings {
                Button("Open iOS Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
                .buttonStyle(TealPrimaryButtonStyle())
            } else {
                Button {
                    viewModel.findNearbyCare()
                } label: {
                    if viewModel.isSearching {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Label("Find nearby care", systemImage: "location.fill")
                    }
                }
                .buttonStyle(TealPrimaryButtonStyle())
                .disabled(viewModel.isSearching)
            }

            Text(CareResourceContent.locationPurpose)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if !viewModel.facilities.isEmpty {
                facilityList
            }
        }
        .padding(18)
        .liquidGlassCard()
    }

    private var facilityList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(viewModel.facilities.prefix(5)) { facility in
                Button {
                    selectedFacility = facility
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(facility.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(IronTheme.textDark)
                            Text("\(facility.distanceText) · \(facility.availability.badgeText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(IronTheme.tealPrimary)
                    }
                }
                .buttonStyle(.plain)
                if facility.id != viewModel.facilities.prefix(5).last?.id {
                    Divider()
                }
            }
        }
    }

    private var educationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Education")
                .font(.headline)
                .foregroundStyle(IronTheme.textDark)
            ForEach(CareResourceContent.topics) { topic in
                DisclosureGroup {
                    Text(topic.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                } label: {
                    Label(topic.title, systemImage: topic.symbol)
                        .font(.headline)
                        .foregroundStyle(IronTheme.textDark)
                }
                .tint(IronTheme.tealPrimary)
                .padding(16)
                .liquidGlassCard(cornerRadius: 20)
            }
        }
    }

    private var disclaimer: some View {
        Text("IronScan is a research prototype. It does not measure iron or hemoglobin and cannot establish a clinical diagnosis. Confirm concerns with a laboratory test.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
    }
}

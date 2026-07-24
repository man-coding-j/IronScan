import SwiftUI
import UIKit

enum MainTab: String, CaseIterable, Identifiable {
    case home
    case scan
    case care

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Home"
        case .scan: "Scan"
        case .care: "Care & Labs"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .scan: "camera.viewfinder"
        case .care: "map.fill"
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var dependencies: IronScanAppDependencies
    @State private var selection = MainTab.home

    var body: some View {
        ZStack(alignment: .bottom) {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            floatingTabBar
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .background(IronTheme.creamBackground.ignoresSafeArea())
        .tint(IronTheme.terracottaPrimary)
        .organicTypography()
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selection {
        case .home:
            HomeDashboardView(history: dependencies.history) {
                select(.scan)
            }
        case .scan:
            MultiScanHubView(inference: dependencies.multiTissueInference) { result in
                dependencies.history.add(result)
            }
        case .care:
            CareResourcesView(viewModel: dependencies.nearbyCare)
        }
    }

    private var floatingTabBar: some View {
        adaptiveGlassTabContainer {
            floatingTabItems
        }
    }

    private var floatingTabItems: some View {
        HStack(spacing: 6) {
            ForEach(MainTab.allCases) { tab in
                Button {
                    select(tab)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 16, weight: .semibold))
                        if selection == tab {
                            Text(tab.title)
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(selection == tab ? Color.white : IronTheme.slateText.opacity(0.72))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        if selection == tab {
                            Capsule()
                                .fill(IronTheme.terracottaPrimary)
                                .matchedGeometryEffect(id: "active-tab", in: tabAnimation)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .organicGlassEffect(
                    in: Capsule(),
                    tint: selection == tab ? IronTheme.terracottaPrimary : IronTheme.cardGlass,
                    interactive: true
                )
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(7)
        .shadow(color: IronTheme.slateText.opacity(0.12), radius: 18, y: 8)
    }

    @ViewBuilder
    private func adaptiveGlassTabContainer<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 20) {
                content()
            }
        } else {
            content()
                .organicGlassEffect(in: Capsule(), tint: IronTheme.cardGlass)
        }
    }

    @Namespace private var tabAnimation

    private func select(_ tab: MainTab) {
        guard selection != tab else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            selection = tab
        }
    }
}

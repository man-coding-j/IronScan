import SwiftUI

enum OnboardingFlowContent {
    static let heroTitle = "Know Your Iron Signals."
    static let heroBody = "Feeling tired or run down? IronScan checks optical color patterns associated with possible anemia risk in seconds. It does not measure iron levels."
    static let accountTitle = "Welcome! Start screening in under 2 minutes."
    static let accountPrivacy = "Prototype access only. Entries stay in memory for this screen, are never submitted, and no account is created."
    static let contextTitle = "Quick Health Check!"
    static let contextBody = "Before your first scan, you can share a few optional details—diet, energy levels, and symptoms—so your report can show that context separately from the optical result."
}

struct OnboardingFlowView: View {
    private enum Page: Int, CaseIterable {
        case vision
        case accountPreview
        case context
    }

    let onComplete: () -> Void

    @State private var page = Page.vision.rawValue
    @State private var email = ""
    @State private var password = ""
    @State private var confirmedPassword = ""
    @State private var accountMessage: String?
    @State private var understandsResearchUse = false
    @State private var showsIntake = false

    var body: some View {
        NavigationStack {
            ZStack {
                IronTheme.creamBackground.ignoresSafeArea()
                OrganicCornerAccents()

                TabView(selection: $page) {
                    visionPage
                        .tag(Page.vision.rawValue)
                    accountPage
                        .tag(Page.accountPreview.rawValue)
                    contextPage
                        .tag(Page.context.rawValue)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .interactive))
                .animation(.snappy(duration: 0.42), value: page)
            }
            .organicTypography()
            .tint(IronTheme.terracottaPrimary)
            .navigationDestination(isPresented: $showsIntake) {
                ScreeningIntakeView(
                    completionButtonTitle: "Continue to IronScan",
                    onComplete: onComplete
                )
            }
        }
    }

    private var visionPage: some View {
        OnboardingPageLayout {
            VStack(spacing: 30) {
                heroGraphic
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 14) {
                    Text(OnboardingFlowContent.heroTitle)
                        .font(IronTheme.roundedFont(.largeTitle, weight: .bold))
                        .foregroundStyle(IronTheme.slateText)
                    Text(OnboardingFlowContent.heroBody)
                        .font(IronTheme.roundedFont(.title3))
                        .foregroundStyle(IronTheme.slateText.opacity(0.72))
                        .lineSpacing(5)
                }
                .frame(maxWidth: 540, alignment: .leading)
            }
        } action: {
            glassActionGroup {
                Button {
                    advance(to: .accountPreview)
                } label: {
                    actionLabel("Start Now")
                }
                .buttonStyle(OrganicPrimaryButtonStyle())
            }
        }
    }

    private var accountPage: some View {
        OnboardingPageLayout {
            VStack(alignment: .leading, spacing: 24) {
                backButton(to: .vision)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Welcome!")
                        .font(IronTheme.roundedFont(.largeTitle, weight: .bold))
                    Text("Start screening in under 2 minutes.")
                        .font(IronTheme.roundedFont(.title3))
                        .foregroundStyle(IronTheme.slateText.opacity(0.7))
                }

                VStack(spacing: 14) {
                    OrganicTextField(
                        title: "Email",
                        text: $email,
                        contentType: .emailAddress
                    )
                    OrganicSecureField(title: "Password", text: $password)
                    OrganicSecureField(title: "Confirm Password", text: $confirmedPassword)
                }

                Text(OnboardingFlowContent.accountPrivacy)
                    .font(IronTheme.roundedFont(.footnote))
                    .foregroundStyle(IronTheme.slateText.opacity(0.66))

                if let accountMessage {
                    Label(accountMessage, systemImage: "exclamationmark.circle.fill")
                        .font(IronTheme.roundedFont(.footnote, weight: .semibold))
                        .foregroundStyle(IronTheme.warning)
                }
            }
            .frame(maxWidth: 540)
        } action: {
            glassActionGroup {
                Button {
                    continueFromAccountPreview()
                } label: {
                    actionLabel("Continue")
                }
                .buttonStyle(OrganicPrimaryButtonStyle())
            }
        }
    }

    private var contextPage: some View {
        OnboardingPageLayout {
            VStack(alignment: .leading, spacing: 22) {
                backButton(to: .accountPreview)

                Text(OnboardingFlowContent.contextTitle)
                    .font(IronTheme.roundedFont(.largeTitle, weight: .bold))

                HealthContextIllustration()
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)

                Text(OnboardingFlowContent.contextBody)
                    .font(IronTheme.roundedFont(.title3))
                    .foregroundStyle(IronTheme.slateText.opacity(0.72))
                    .lineSpacing(5)

                VStack(alignment: .leading, spacing: 10) {
                    Text(OnboardingConsent.summary)
                        .font(IronTheme.roundedFont(.subheadline, weight: .bold))
                    Text(OnboardingConsent.detail)
                        .font(IronTheme.roundedFont(.footnote))
                        .foregroundStyle(IronTheme.slateText.opacity(0.7))
                    Toggle(
                        "I agree and understand these research limitations.",
                        isOn: $understandsResearchUse
                    )
                    .font(IronTheme.roundedFont(.subheadline, weight: .semibold))
                    .tint(IronTheme.sageAccent)
                }
                .padding(16)
                .liquidGlassCard(cornerRadius: 22)
            }
            .frame(maxWidth: 560)
        } action: {
            glassActionGroup {
                Button {
                    showsIntake = true
                } label: {
                    actionLabel("Get Started")
                }
                .buttonStyle(OrganicPrimaryButtonStyle())
                .disabled(!understandsResearchUse)
                .opacity(understandsResearchUse ? 1 : 0.52)
            }
        }
    }

    private var heroGraphic: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.24))
                .frame(width: 238, height: 238)
            Circle()
                .stroke(
                    IronTheme.sageAccent,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [12, 11])
                )
                .frame(width: 252, height: 252)
            Circle()
                .fill(IronTheme.terracottaPrimary.opacity(0.45))
                .frame(width: 142, height: 184)
                .overlay(alignment: .trailing) {
                    Capsule()
                        .stroke(IronTheme.terracottaPrimary.opacity(0.6), lineWidth: 4)
                        .frame(width: 58, height: 126)
                        .padding(.trailing, 21)
                }
            Circle()
                .fill(IronTheme.terracottaPrimary)
                .frame(width: 82, height: 82)
                .overlay {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(IronTheme.creamBackground)
                }
                .offset(x: 74, y: -83)
        }
    }

    private func actionLabel(_ title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: "arrow.right")
                .font(.system(size: 17, weight: .bold))
        }
    }

    private func backButton(to destination: Page) -> some View {
        Button {
            advance(to: destination)
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .bold))
                .frame(width: 42, height: 42)
                .organicGlassEffect(
                    in: Circle(),
                    tint: IronTheme.cardGlass,
                    interactive: true
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }

    @ViewBuilder
    private func glassActionGroup<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 20) {
                content()
            }
        } else {
            content()
        }
    }

    private func advance(to destination: Page) {
        withAnimation(.snappy(duration: 0.42)) {
            page = destination.rawValue
        }
    }

    private func continueFromAccountPreview() {
        let hasAnyEntry = !email.isEmpty || !password.isEmpty || !confirmedPassword.isEmpty
        guard !hasAnyEntry || password == confirmedPassword else {
            accountMessage = "The password fields do not match."
            return
        }
        accountMessage = nil
        password = ""
        confirmedPassword = ""
        advance(to: .context)
    }
}

private struct OnboardingPageLayout<Content: View, Action: View>: View {
    @ViewBuilder let content: () -> Content
    @ViewBuilder let action: () -> Action

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 22) {
                    content()
                        .frame(maxWidth: .infinity)
                    Spacer(minLength: 12)
                    action()
                        .frame(maxWidth: 540)
                }
                .padding(.horizontal, 26)
                .padding(.top, max(28, proxy.safeAreaInsets.top + 8))
                .padding(.bottom, 54)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct OrganicTextField: View {
    let title: String
    @Binding var text: String
    let contentType: UITextContentType?

    var body: some View {
        TextField(title, text: $text)
            .textContentType(contentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 18)
            .frame(minHeight: 58)
            .background(Color.white.opacity(0.32), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(IronTheme.terracottaPrimary.opacity(0.42), lineWidth: 1)
            }
            .font(IronTheme.roundedFont(.body))
    }
}

private struct OrganicSecureField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        SecureField(title, text: $text)
            .textContentType(.newPassword)
            .padding(.horizontal, 18)
            .frame(minHeight: 58)
            .background(Color.white.opacity(0.32), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(IronTheme.terracottaPrimary.opacity(0.42), lineWidth: 1)
            }
            .font(IronTheme.roundedFont(.body))
    }
}

private struct HealthContextIllustration: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Capsule()
                .fill(IronTheme.sageAccent.opacity(0.18))
                .frame(width: 248, height: 42)

            HStack(alignment: .bottom, spacing: -12) {
                clipboard
                person
            }
        }
        .frame(height: 245)
    }

    private var clipboard: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.white.opacity(0.5))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(IronTheme.sageAccent.opacity(0.48), lineWidth: 2)
            }
            .overlay {
                VStack(spacing: 12) {
                    ForEach(0 ..< 4, id: \.self) { index in
                        Capsule()
                            .fill(IronTheme.sageAccent.opacity(0.45))
                            .frame(width: index.isMultiple(of: 2) ? 88 : 62, height: 8)
                    }
                }
            }
            .overlay(alignment: .top) {
                Circle()
                    .fill(IronTheme.terracottaPrimary)
                    .frame(width: 46, height: 46)
                    .offset(y: -24)
            }
            .frame(width: 156, height: 186)
    }

    private var person: some View {
        VStack(spacing: -2) {
            Circle()
                .fill(Color(red: 239 / 255, green: 190 / 255, blue: 155 / 255))
                .overlay {
                    Circle().stroke(IronTheme.slateText, lineWidth: 7)
                }
                .frame(width: 66, height: 66)
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(IronTheme.sageAccent)
                .frame(width: 92, height: 112)
                .overlay(alignment: .trailing) {
                    Capsule()
                        .stroke(
                            Color(red: 239 / 255, green: 190 / 255, blue: 155 / 255),
                            lineWidth: 15
                        )
                        .frame(width: 38, height: 72)
                        .offset(x: 23)
                }
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(IronTheme.slateText.opacity(0.88))
                .frame(width: 58, height: 84)
        }
    }
}

private struct OrganicCornerAccents: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LeafCluster()
                    .frame(width: 150, height: 150)
                    .offset(x: -42, y: -36)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                LeafCluster()
                    .frame(width: 165, height: 165)
                    .rotationEffect(.degrees(180))
                    .offset(x: 52, y: 48)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct LeafCluster: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(IronTheme.sageAccent.opacity(0.58))
                .frame(width: 42, height: 112)
                .rotationEffect(.degrees(43))
                .offset(x: 22, y: -7)
            Capsule()
                .fill(IronTheme.sageAccent.opacity(0.36))
                .frame(width: 38, height: 104)
                .rotationEffect(.degrees(67))
                .offset(x: 48, y: 20)
            Capsule()
                .fill(IronTheme.sageAccent.opacity(0.72))
                .frame(width: 32, height: 92)
                .rotationEffect(.degrees(27))
                .offset(x: -4, y: -17)
        }
    }
}

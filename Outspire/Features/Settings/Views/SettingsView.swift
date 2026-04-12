import SwiftUI

struct SettingsView: View {
    @Binding var showSettingsSheet: Bool
    var isModal: Bool = false
    @ObservedObject private var authV2 = AuthServiceV2.shared
    @State private var viewRefreshID = UUID()
    @State private var showOnboardingSheet = false
    @State private var animateEntrance = false

    enum SettingsMenu: String, Hashable, CaseIterable {
        case account
        case general
        case notifications
        case gradients
        case about
        case license
        #if DEBUG
            case cache
        #endif
    }

    var body: some View {
        List {
            Section {
                NavigationLink(destination: destinationView(for: .account)) {
                    ProfileHeaderView()
                }
            }
            .staggeredEntry(index: 0, animate: animateEntrance)

            Section {
                settingsLink(.general)
                settingsLink(.notifications)
                settingsLink(.gradients)
                settingsLink(.about)
                settingsLink(.license)
            }
            .staggeredEntry(index: 1, animate: animateEntrance)

            Section {
                ShareLink(
                    item: URL(string: "https://apps.apple.com/us/app/outspire/id6743143348")!,
                    message: Text(
                        "\nCheck out Outspire, an app that makes your WFLA life easier!\nClass countdowns, CAS tracking, and more.\n\nDownload now on the App Store."
                    )
                ) {
                    HStack {
                        Label {
                            Text("Share Outspire")
                                .foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: "square.and.arrow.up.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(
                                    AppColor.brand.gradient,
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                                )
                        }
                        Spacer()
                        Image(systemName: "arrow.up.forward.square")
                            .font(.caption.weight(.medium))
                            .foregroundColor(AppColor.brand)
                    }
                }

                Link(destination: URL(string: "https://outspire.wrye.dev")!) {
                    HStack {
                        Label {
                            Text("Website")
                                .foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: "globe")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(
                                    Color.indigo.gradient,
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                                )
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(AppColor.brand)
                    }
                }

                Link(destination: URL(string: "https://github.com/at-wr/Outspire/issues/new/choose")!) {
                    HStack {
                        Label {
                            Text("Report an Issue")
                                .foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: "exclamationmark.bubble.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(
                                    Color.orange.gradient,
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                                )
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(AppColor.brand)
                    }
                }
            }
            .staggeredEntry(index: 2, animate: animateEntrance)

            #if DEBUG
                Section("Debug Tools") {
                    Button("View Onboarding") {
                        HapticManager.shared.playButtonTap()
                        showOnboardingSheet = true
                    }
                    .foregroundStyle(.blue)

                    NavigationLink(destination: CacheStatusView()) {
                        Label("Cache Status", systemImage: "externaldrive")
                            .foregroundStyle(.primary)
                    }

                    NavigationLink(destination: LiveActivityDebugView()) {
                        Label("Live Activity Test", systemImage: "clock.badge.checkmark")
                            .foregroundStyle(.primary)
                    }
                }
                .staggeredEntry(index: 3, animate: animateEntrance)
            #endif
        }
        .id(viewRefreshID)
        .applyScrollEdgeEffect()
        .onAppear { animateEntrance = true }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if isModal {
                Button(action: {
                    HapticManager.shared.playButtonTap()
                    showSettingsSheet = false
                }) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: Notification.Name.authenticationStatusChanged)
        ) { _ in
            DispatchQueue.main.async { viewRefreshID = UUID() }
        }
        .sheet(isPresented: $showOnboardingSheet) {
            OnboardingView(isPresented: $showOnboardingSheet)
        }
    }

    private func settingsLink(_ item: SettingsMenu) -> some View {
        NavigationLink(destination: destinationView(for: item)) {
            MenuItemView(item: item)
        }
    }

    @ViewBuilder
    private func destinationView(for destination: SettingsMenu) -> some View {
        switch destination {
        case .account:
            AccountWithNavigation()
        case .notifications:
            SettingsNotificationsView()
        case .general:
            SettingsGeneralView()
        case .gradients:
            GradientSettingsView()
        case .about:
            AboutView()
        case .license:
            LicenseView()
        #if DEBUG
            case .cache:
                CacheStatusView()
        #endif
        }
    }
}

struct AccountWithNavigation: View {
    var body: some View {
        Group {
            AccountV2View()
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
    }
}

import SwiftUI

extension Bundle {
    var releaseVersionNumber: String? {
        infoDictionary?["CFBundleShortVersionString"] as? String
    }

    var buildVersionNumber: String? {
        infoDictionary?["CFBundleVersion"] as? String
    }
}

let appVersion = Bundle.main.releaseVersionNumber
let appBuild = Bundle.main.buildVersionNumber

struct AboutView: View {
    @State private var animateEntrance = false
    @State private var iconAppeared = false

    var body: some View {
        List {
            // Hero section
            Section {
                VStack(spacing: 14) {
                    if let icon = Bundle.main.icon {
                        Image(uiImage: icon)
                            .resizable()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                            .shadow(color: AppColor.brand.opacity(0.15), radius: 8, y: 4)
                            .scaleEffect(iconAppeared ? 1.0 : 0.85)
                            .opacity(iconAppeared ? 1.0 : 0)
                            .animation(.spring(response: 0.6, dampingFraction: 0.7), value: iconAppeared)
                    }

                    VStack(spacing: 4) {
                        Text("Outspire")
                            .font(AppText.title)
                            .fontDesign(.rounded)
                        if let version = Bundle.main.releaseVersionNumber,
                           let build = Bundle.main.buildVersionNumber
                        {
                            Text("Version \(version) (\(build))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if ReceiptChecker.isAppStore {
                        Text("Purchased from App Store")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                    } else {
                        Text("Open Source · MIT License")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .staggeredEntry(index: 0, animate: animateEntrance)

            Section("Developer") {
                Label {
                    Text("Alan Ye @ WFLA")
                } icon: {
                    Image(systemName: "person.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.blue.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }
            .staggeredEntry(index: 1, animate: animateEntrance)

            Section("Data Sources") {
                aboutRow("TSIMS for WFLA Int'l", icon: "server.rack", color: .indigo)
                aboutRow("WFLMS.cn", icon: "globe", color: .teal)
            }
            .staggeredEntry(index: 2, animate: animateEntrance)

            Section {
                aboutLink("Contact via Mail", icon: "envelope.fill", color: .blue, url: "mailto:outspire@wrye.dev")
                aboutLink(
                    "Terms of Service",
                    icon: "doc.text.fill",
                    color: .gray,
                    url: "https://github.com/at-wr/Outspire?tab=readme-ov-file#terms-of-service"
                )
                aboutLink(
                    "Privacy Policy",
                    icon: "hand.raised.fill",
                    color: .green,
                    url: "https://github.com/at-wr/Outspire?tab=readme-ov-file#privacy-policy"
                )
                aboutLink(
                    "GitHub Repository",
                    icon: "chevron.left.forwardslash.chevron.right",
                    color: .purple,
                    url: "https://github.com/at-wr/Outspire/"
                )
            }
            .staggeredEntry(index: 3, animate: animateEntrance)
        }
        .onAppear {
            animateEntrance = true
            iconAppeared = true
        }
        .navigationTitle("About")
        .contentMargins(.vertical, 10.0)
    }

    private func aboutRow(_ title: String, icon: String, color: Color) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    private func aboutLink(_ title: String, icon: String, color: Color, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack {
                Label {
                    Text(title)
                        .foregroundColor(.primary)
                } icon: {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppColor.brand)
            }
        }
    }
}

/// Helper to get app icon
extension Bundle {
    var icon: UIImage? {
        if let icons = infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let iconFiles = primary["CFBundleIconFiles"] as? [String],
           let lastIcon = iconFiles.last
        {
            return UIImage(named: lastIcon)
        }
        return nil
    }
}

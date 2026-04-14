import SwiftUI

struct MenuItemView: View {
    let item: SettingsView.SettingsMenu

    private var config: (title: String, icon: String, color: Color) {
        switch item {
        case .general:
            ("General", "switch.2", .gray)
        case .notifications:
            ("Notifications", "bell.badge.fill", .red)
        case .gradients:
            ("Visual", "paintpalette.fill", .purple)
        case .license:
            ("Open Source Licenses", "doc.text.fill", .brown)
        case .about:
            ("About Outspire", "star.fill", .blue)
        default:
            ("", "", .gray)
        }
    }

    var body: some View {
        Label {
            Text(config.title)
        } icon: {
            Image(systemName: config.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(config.color.gradient)
                        .shadow(color: config.color.opacity(0.3), radius: 2, x: 0, y: 1)
                )
        }
    }
}

import SwiftUI

struct ExtraView: View {
    @State private var query: String = ""
    @State private var navTarget: ExploreTarget?

    var body: some View {
        List {
            // Quick links grid
            Section {
                quickLinksGrid
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            // Native iOS list rows
            Section {
                NavigationLink(destination: SchoolArrangementView()) {
                    settingsRow("School Arrangements", icon: "calendar", color: .blue)
                }
                NavigationLink(destination: LunchMenuView()) {
                    settingsRow("Dining Menus", icon: "fork.knife", color: .orange)
                }
                NavigationLink(destination: ClubInfoView()) {
                    settingsRow("Hall of Clubs", icon: "person.2.fill", color: .purple)
                }
                NavigationLink(destination: ReflectionsView()) {
                    settingsRow("Reflections", icon: "square.and.pencil", color: .pink)
                }
                NavigationLink(destination: SettingsView(showSettingsSheet: .constant(false), isModal: false)) {
                    settingsRow("Settings", icon: "gear", color: .gray)
                }
            }

            #if DEBUG
                Section("Debug") {
                    NavigationLink(destination: LiveActivityDebugView()) {
                        settingsRow("Live Activity Test", icon: "clock.badge.checkmark", color: .cyan)
                    }
                }
            #endif
        }
        .listStyle(.insetGrouped)
        .applyScrollEdgeEffect()
        .navigationTitle("Explore")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, prompt: "Search")
        .navigationDestination(item: $navTarget) { target in
            switch target {
            case .today: TodayView()
            case .classes: ModernClasstableView()
            case .activities: ClubActivitiesView()
            case .grades: ScoreView()
            }
        }
    }

    private func settingsRow(_ title: String, icon: String, color: Color) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    private var quickLinksGrid: some View {
        VStack(spacing: AppSpace.sm) {
            HStack(spacing: AppSpace.sm) {
                quickLinkTile(
                    "Today",
                    systemImage: "text.rectangle.page",
                    colors: [AppColor.brand.opacity(0.9), AppColor.brand.opacity(0.7)],
                    target: .today
                )
                quickLinkTile(
                    "Classes",
                    systemImage: "calendar.day.timeline.left",
                    colors: [Color.indigo.opacity(0.85), Color.indigo.opacity(0.65)],
                    target: .classes
                )
            }
            HStack(spacing: AppSpace.sm) {
                quickLinkTile(
                    "Activities",
                    systemImage: "checklist",
                    colors: [Color.green.opacity(0.85), Color.green.opacity(0.65)],
                    target: .activities
                )
                quickLinkTile(
                    "Grades",
                    systemImage: "pencil.and.list.clipboard",
                    colors: [Color.orange.opacity(0.85), Color.orange.opacity(0.65)],
                    target: .grades
                )
            }
        }
    }

    private func quickLinkTile(
        _ title: String,
        systemImage: String,
        colors: [Color],
        target: ExploreTarget
    ) -> some View {
        Button {
            HapticManager.shared.playLightFeedback()
            navTarget = target
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .symbolRenderingMode(.hierarchical)

                Spacer().frame(height: 4)

                Text(title)
                    .font(.headline.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpace.md)
            .coloredRichCard(colors: colors, cornerRadius: AppRadius.lg, shadowRadius: 8)
        }
        .buttonStyle(.pressableCard)
    }
}

private enum ExploreTarget: String, Identifiable, Hashable {
    case today, classes, activities, grades
    var id: String {
        rawValue
    }
}

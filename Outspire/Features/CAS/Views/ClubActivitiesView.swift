import SwiftUI
import Toasts

// Removed ColorfulX usage in favor of system materials

struct ClubActivitiesView: View {
    @ObservedObject private var authV2 = AuthServiceV2.shared
    @StateObject private var viewModel = ClubActivitiesViewModel()
    @State private var showingAddRecordSheet = false
    @State private var animateList = false
    @State private var refreshButtonRotation = 0.0
    @EnvironmentObject var urlSchemeHandler: URLSchemeHandler
    @Environment(\.presentToast) var presentToast
    @EnvironmentObject var gradientManager: GradientManager // Add gradient manager
    @Environment(\.colorScheme) private var colorScheme // Add color scheme
    @State private var activitySearch: String = ""

    var body: some View {
        // Remove the nested NavigationView
        ZStack {
            contentView
        }
        .navigationTitle("Activity Records")
        // .toolbarBackground(Color(UIColor.systemBackground))
        .contentMargins(.vertical, 10.0)
        .toolbar {
            //            ToolbarItem(id: "loadingIndicator", placement: .navigationBarTrailing) {
            //                if viewModel.isLoadingActivities || viewModel.isLoadingGroups {
            //                    ProgressView()
            //                        .controlSize(.small)
            //                }
            //            }

            ToolbarItem(id: "refreshButton", placement: .navigationBarTrailing) {
                Button(action: handleRefreshAction) {
                    Label {
                        Text("Refresh")
                    } icon: {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(refreshButtonRotation))
                    }
                }
                //                .disabled(viewModel.isLoadingActivities || viewModel.isLoadingGroups)
            }

            ToolbarItem(id: "addButton", placement: .navigationBarTrailing) {
                Button(action: {
                    HapticManager.shared.playButtonTap()
                    showingAddRecordSheet.toggle()
                }) {
                    Label {
                        Text("Compose")
                    } icon: {
                        Image(systemName: "square.and.pencil")
                    }
                }
                .disabled(viewModel.isLoadingGroups || viewModel.groups.isEmpty)
            }
        }
        .sheet(isPresented: $showingAddRecordSheet) {
            addRecordSheet
        }
        .confirmationDialog(
            "Delete Record",
            isPresented: $viewModel.showingDeleteConfirmation,
            actions: { deleteConfirmationActions },
            message: { Text("Are you sure you want to delete this record?") }
        )
        .onAppear(perform: {
            handleOnAppear()
            updateGradientForClubActivities()

            // Handle URL scheme navigation to add an activity for a specific club
            if let activityClubId = urlSchemeHandler.navigateToAddActivity {
                viewModel.setSelectedGroupById(activityClubId)
                showingAddRecordSheet = true

                // Reset handler state
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    urlSchemeHandler.navigateToAddActivity = nil
                }
            }
        })
        .onChange(of: urlSchemeHandler.navigateToAddActivity) { _, newClubId in
            if let activityClubId = newClubId {
                viewModel.setSelectedGroupById(activityClubId)
                showingAddRecordSheet = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    urlSchemeHandler.navigateToAddActivity = nil
                }
            }
        }
        .onChange(of: viewModel.isLoadingActivities) {
            handleLoadingChange()
        }
        .onChange(of: viewModel.errorMessage) { _, errorMessage in
            if let errorMessage {
                HapticManager.shared.playError()
                let icon =
                    errorMessage.contains("copied")
                        ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                let toast = ToastValue(
                    icon: Image(systemName: icon).foregroundStyle(.red),
                    message: errorMessage
                )
                presentToast(toast)
            }
        }
        .onChange(of: urlSchemeHandler.closeAllSheets) { _, newValue in
            if newValue {
                // Close the add record sheet if it's open
                showingAddRecordSheet = false

                // Reset any other dialog states if needed
                viewModel.showingDeleteConfirmation = false
            }
        }
    }

    private var contentView: some View {
        Form {
            GroupSelectorSection(viewModel: viewModel)
            ActivitiesSection(
                viewModel: viewModel,
                showingAddRecordSheet: $showingAddRecordSheet,
                animateList: animateList,
                searchText: activitySearch
            )
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .searchable(text: $activitySearch, prompt: "Search activities")
        .refreshable(action: handleRefresh)
    }

    private var addRecordSheet: some View {
        AddRecordSheet(
            availableGroups: viewModel.groups,
            loggedInStudentId: AuthServiceV2.shared.user?.userCode ?? "",
            onSave: { viewModel.fetchActivityRecords(forceRefresh: true) },
            clubActivitiesViewModel: viewModel
        )
    }

    private var deleteConfirmationActions: some View {
        Group {
            Button("Delete", role: .destructive) {
                if let record = viewModel.recordToDelete {
                    viewModel.deleteRecord(record: record)

                    let toast = ToastValue(
                        icon: Image(systemName: "trash.fill").foregroundStyle(.red),
                        message: "Record Deleted"
                    )
                    presentToast(toast)

                    viewModel.recordToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                HapticManager.shared.playButtonTap()
            }
        }
    }

    private func handleOnAppear() {
        if viewModel.groups.isEmpty {
            viewModel.fetchGroups()
        } else if !viewModel.isCacheValid() {
            viewModel.fetchActivityRecords(forceRefresh: true)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                animateList = true
            }
        }
    }

    private func handleLoadingChange() {
        if !viewModel.isLoadingActivities {
            animateList = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    animateList = true
                }
            }
        }
    }

    private func handleRefreshAction() {
        HapticManager.shared.playRefresh()
        withAnimation {
            refreshButtonRotation += 360
        }
        if viewModel.isLoadingActivities { return }

        if viewModel.groups.isEmpty {
            viewModel.fetchGroups(forceRefresh: true)
        } else {
            viewModel.fetchActivityRecords(forceRefresh: true)
        }
    }

    @Sendable private func handleRefresh() async { // Added @Sendable to fix data race warning
        HapticManager.shared.playFeedback(.medium)
        if viewModel.groups.isEmpty {
            await viewModel.fetchGroupsAsync(forceRefresh: true)
        } else {
            await viewModel.fetchActivityRecordsAsync(forceRefresh: true)
        }
    }

    /// Add method to update gradient for activities
    private func updateGradientForClubActivities() {
        #if !targetEnvironment(macCatalyst)
            gradientManager.updateGradientForView(.clubActivities, colorScheme: colorScheme)
        #else
            gradientManager.updateGradient(
                colors: [Color(.systemBackground)],
                speed: 0.0,
                noise: 0.0
            )
        #endif
    }
}

struct GroupSelectorSection: View {
    @ObservedObject var viewModel: ClubActivitiesViewModel

    var body: some View {
        Section {
            if !viewModel.groups.isEmpty {
                Picker("Club", selection: $viewModel.selectedGroupId) {
                    ForEach(viewModel.groups) { group in
                        Text(group.C_NameE).tag(group.C_GroupsID)
                    }
                }
                .onChange(of: viewModel.selectedGroupId) {
                    HapticManager.shared.playSelectionFeedback()
                    withAnimation(.easeInOut(duration: 0.3)) {
                        viewModel.fetchActivityRecords(forceRefresh: true)
                    }
                }
                .disabled(viewModel.isLoadingActivities)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut, value: viewModel.groups.isEmpty)
            }
        }
    }
}

struct ActivitiesSection: View {
    @ObservedObject var viewModel: ClubActivitiesViewModel
    @Binding var showingAddRecordSheet: Bool
    let animateList: Bool
    let searchText: String
    @State private var hasCompletedInitialLoad = false
    @State private var loadAttempted = false
    @Environment(\.presentToast) var presentToast

    var body: some View {
        Section {
            if viewModel.groups.isEmpty && !viewModel.isLoadingGroups {
                Group {
                    let isAuthed = AuthServiceV2.shared.isAuthenticated
                    if isAuthed {
                        ErrorView(
                            errorMessage: "No clubs available. Join a club to continue.",
                            retryAction: {
                                viewModel.fetchGroups(forceRefresh: true)
                                let toast = ToastValue(
                                    icon: Image(systemName: "arrow.clockwise"),
                                    message: "Refreshing clubs..."
                                )
                                presentToast(toast)
                            }
                        )
                    } else {
                        ErrorView(errorMessage: "Please sign in with TSIMS to continue...")
                    }
                }
                .transition(.scale.combined(with: .opacity))
            } else if viewModel.isLoadingActivities || !loadAttempted {
                // Show skeleton during loading or before attempting to load data
                ActivitySkeletonView()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.5), value: viewModel.isLoadingActivities)
                    .onAppear {
                        // Mark that we've attempted to load data
                        if !loadAttempted {
                            loadAttempted = true
                            // If we still don't have groups, force-refresh
                            if viewModel.groups.isEmpty {
                                viewModel.fetchGroups()
                            } else if viewModel.activities.isEmpty {
                                // Force-refresh activities if we have groups but no activities
                                viewModel.fetchActivityRecords(forceRefresh: true)
                            }
                        }
                    }
            } else if viewModel.activities.isEmpty {
                // Only show empty state after loading is complete and we confirmed no activities
                ClubEmptyStateView(action: { showingAddRecordSheet.toggle() })
                    .transition(.scale.combined(with: .opacity))
            } else {
                ActivitiesList(viewModel: viewModel, animateList: animateList, searchText: searchText)
                    .transition(.opacity)
                    .blur(radius: viewModel.isLoadingActivities ? 1.0 : 0)
                    .opacity(viewModel.isLoadingActivities ? 0.7 : 1.0)
            }
        }
        .onChange(of: viewModel.isLoadingActivities) { _, isLoading in
            // After loading completes, mark initial load as complete
            if !isLoading {
                hasCompletedInitialLoad = true
            }
        }
    }
}

// Use shared refresh/loading in SchoolArrangement/Views/Components/UIComponents.swift

struct ClubEmptyStateView: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)
                .padding(.bottom, 8)
            Text("No activity records available")
                .font(AppText.sectionTitle)
                .foregroundStyle(.secondary)
            Text("Add a new activity using the + button")
                .font(AppText.label)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button(action: {
                HapticManager.shared.playButtonTap()
                action()
            }) {
                Label("Add New Activity", systemImage: "plus.circle")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

struct ActivitiesList: View {
    @ObservedObject var viewModel: ClubActivitiesViewModel
    let animateList: Bool
    let searchText: String

    var body: some View {
        let filtered = searchText.isEmpty ? viewModel.activities : viewModel.activities.filter { a in
            a.C_Theme.localizedCaseInsensitiveContains(searchText) ||
                a.C_Reflection.localizedCaseInsensitiveContains(searchText)
        }
        ForEach(Array(filtered.enumerated()), id: \.element.id) { _, activity in
            ActivityCardView(activity: activity, viewModel: viewModel)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .contentTransition(.identity)
        }
    }
}

struct ActivityCardView: View {
    let activity: ActivityRecord
    @ObservedObject var viewModel: ClubActivitiesViewModel
    @Environment(\.presentToast) var presentToast

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Text(activity.C_Theme)
                        .font(AppText.sectionTitle)
                        .lineLimit(1)
                    Spacer()
                    if let status = activity.C_IsConfirm, status == 1 {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                            .accessibilityLabel("Confirmed")
                    }
                }
                Text("Date: \(formatDate(activity.C_Date))")
                    .font(AppText.label)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                CASBadge(type: .creativity, value: activity.C_DurationC)
                    .transition(.scale)
                CASBadge(type: .activity, value: activity.C_DurationA)
                    .transition(.scale)
                CASBadge(type: .service, value: activity.C_DurationS)
                    .transition(.scale)
                Spacer()
                Text("Total: \(String(format: "%.1f", totalDuration))h")
                    .font(AppText.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(Capsule())
            }
            ReflectionView(text: activity.C_Reflection)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .richCard(cornerRadius: 16, shadowRadius: 8)
        .contextMenu {
            Button(
                role: .destructive,
                action: {
                    HapticManager.shared.playDelete()
                    viewModel.recordToDelete = activity
                    viewModel.showingDeleteConfirmation = true
                }
            ) {
                Label("Delete", systemImage: "trash")
            }
            Menu {
                Button(action: {
                    HapticManager.shared.playButtonTap()
                    viewModel.copyTitle(activity)
                    let toast = ToastValue(
                        icon: Image(systemName: "doc.on.clipboard"),
                        message: "Title Copied to Clipboard"
                    )
                    presentToast(toast)
                }) {
                    Label("Copy Title", systemImage: "textformat")
                }
                Button(action: {
                    HapticManager.shared.playButtonTap()
                    viewModel.copyReflection(activity)
                    let toast = ToastValue(
                        icon: Image(systemName: "doc.on.clipboard"),
                        message: "Reflection Copied to Clipboard"
                    )
                    presentToast(toast)
                }) {
                    Label("Copy Reflection", systemImage: "doc.text")
                }
                Button(action: {
                    HapticManager.shared.playButtonTap()
                    viewModel.copyAll(activity)
                    let toast = ToastValue(
                        icon: Image(systemName: "doc.on.clipboard"),
                        message: "Activity Copied to Clipboard"
                    )
                    presentToast(toast)
                }) {
                    Label("Copy All", systemImage: "doc.on.doc")
                }
            } label: {
                Label("Copy", systemImage: "doc.on.clipboard")
            }
        }
        // Removed swipeActions as requested
    }

    private var totalDuration: Double {
        (Double(activity.C_DurationC) ?? 0) + (Double(activity.C_DurationA) ?? 0)
            + (Double(activity.C_DurationS) ?? 0)
    }

    private func formatDate(_ dateString: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        if inputFormatter.date(from: dateString) == nil {
            inputFormatter.dateFormat = "yyyy-MM-dd"
        }

        if let date = inputFormatter.date(from: dateString) {
            let outputFormatter = DateFormatter()
            outputFormatter.dateStyle = .medium
            outputFormatter.timeStyle = .none
            return outputFormatter.string(from: date)
        }

        return dateString.contains(" ") ? String(dateString.split(separator: " ")[0]) : dateString
    }
}

struct ReflectionView: View {
    let text: String
    @State private var isExpanded = false
    @State private var buttonScale = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reflection")
                .font(AppText.label)
                .foregroundStyle(.secondary)
            Text(text)
                .font(AppText.body)
                .lineLimit(isExpanded ? nil : 3)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeOut(duration: 0.3), value: isExpanded)
            if text.count > 100 {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "Show Less" : "Show More")
                            .font(AppText.caption)
                            .foregroundStyle(.blue)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .animation(
                                .spring(response: 0.35, dampingFraction: 0.7), value: isExpanded
                            )
                    }
                    .padding(.top, 4)
                    .scaleEffect(buttonScale)
                }
                .buttonStyle(.plain)
                .onLongPressGesture(
                    minimumDuration: .infinity, maximumDistance: .infinity,
                    pressing: { isPressing in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            buttonScale = isPressing ? 0.92 : 1.0
                        }
                    }, perform: {}
                )
            }
        }
    }
}

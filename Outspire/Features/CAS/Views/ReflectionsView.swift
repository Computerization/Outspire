import SwiftUI
import Toasts

// Removed ColorfulX usage in favor of system materials

struct ReflectionsView: View {
    @ObservedObject private var authV2 = AuthServiceV2.shared
    @StateObject private var viewModel = ReflectionsViewModel()
    @State private var showingAddSheet = false
    @State private var animateList = false
    @State private var refreshButtonRotation = 0.0
    @Environment(\.presentToast) var presentToast
    @EnvironmentObject var gradientManager: GradientManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var sortDescending: Bool = true

    var body: some View {
        ZStack {
            contentView
        }
        .navigationTitle("Reflections")
        .contentMargins(.vertical, 10.0)
        .toolbar {
            //            ToolbarItem(id: "loadingIndicator", placement: .navigationBarTrailing) {
            //                if viewModel.isLoadingGroups || viewModel.isLoadingReflections {
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
                //                .disabled(viewModel.isLoadingGroups || viewModel.isLoadingReflections)
            }
            ToolbarItem(id: "addButton", placement: .navigationBarTrailing) {
                Button(action: {
                    HapticManager.shared.playButtonTap()
                    showingAddSheet.toggle()
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
        .sheet(isPresented: $showingAddSheet) {
            addReflectionSheet
        }
        .confirmationDialog(
            "Delete Reflection",
            isPresented: $viewModel.showingDeleteConfirmation,
            actions: { deleteConfirmationActions },
            message: { Text("Are you sure you want to delete this reflection?") }
        )
        .onAppear(perform: {
            handleOnAppear()
            updateGradientForReflections()
        })
        .onChange(of: viewModel.isLoadingReflections) {
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
    }

    private var contentView: some View {
        Form {
            ReflectionGroupSelectorSection(viewModel: viewModel)
            ReflectionsSection(
                viewModel: viewModel,
                showingAddSheet: $showingAddSheet,
                animateList: animateList
            )
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .refreshable(action: handleRefresh)
    }

    private var addReflectionSheet: some View {
        AddReflectionSheet(
            availableGroups: viewModel.groups,
            studentId: AuthServiceV2.shared.user?.userCode ?? ""
        ) {
            viewModel.fetchReflections(forceRefresh: true)
        }
    }

    private var deleteConfirmationActions: some View {
        Group {
            Button("Delete", role: .destructive) {
                if viewModel.reflectionToDelete != nil {
                    HapticManager.shared.playDelete()
                    viewModel.confirmDelete()
                    let toast = ToastValue(
                        icon: Image(systemName: "trash.fill").foregroundStyle(.red),
                        message: "Reflection Deleted"
                    )
                    presentToast(toast)
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
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                animateList = true
            }
        }
    }

    private func handleLoadingChange() {
        if !viewModel.isLoadingReflections {
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
        if viewModel.isLoadingReflections { return }

        if viewModel.groups.isEmpty {
            viewModel.fetchGroups(forceRefresh: true)
        } else {
            viewModel.fetchReflections(forceRefresh: true)
        }
    }

    @Sendable private func handleRefresh() async {
        HapticManager.shared.playFeedback(.medium)
        if viewModel.groups.isEmpty {
            viewModel.fetchGroups(forceRefresh: true)
        } else {
            viewModel.fetchReflections(forceRefresh: true)
        }
    }

    private func updateGradientForReflections() {
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

struct ReflectionGroupSelectorSection: View {
    @ObservedObject var viewModel: ReflectionsViewModel

    var body: some View {
        Section {
            if !viewModel.groups.isEmpty {
                Picker("Club", selection: $viewModel.selectedGroupId) {
                    ForEach(viewModel.groups) { group in
                        Text(group.displayName).tag(group.id)
                    }
                }
                .onChange(of: viewModel.selectedGroupId) {
                    HapticManager.shared.playSelectionFeedback()
                    withAnimation(.easeInOut(duration: 0.3)) {
                        viewModel.fetchReflections(forceRefresh: true)
                    }
                }
                .disabled(viewModel.isLoadingReflections)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut, value: viewModel.groups.isEmpty)
            }
        }
    }
}

struct ReflectionsSection: View {
    @ObservedObject var viewModel: ReflectionsViewModel
    @Binding var showingAddSheet: Bool
    let animateList: Bool
    @State private var hasCompletedInitialLoad = false
    @State private var loadAttempted = false
    @Environment(\.presentToast) var presentToast
    @State private var searchText: String = ""
    @State private var sortDescending: Bool = true

    var body: some View {
        Section {
            if viewModel.groups.isEmpty && !viewModel.isLoadingGroups {
                Group {
                    let isAuthed = AuthServiceV2.shared.isAuthenticated
                    if isAuthed {
                        ErrorView(
                            errorMessage: "No clubs available. Join a club to continue.",
                            retryAction: {
                                HapticManager.shared.playRefresh()
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
            } else if viewModel.isLoadingReflections || !loadAttempted {
                // Use a generic loading skeleton for reflections
                VStack(spacing: 16) {
                    ForEach(0 ..< 3) { _ in
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.15))
                            .frame(height: 80)
                            .redacted(reason: .placeholder)
                            .padding(.horizontal)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                // Keep implicit transitions
                .onAppear {
                    if !loadAttempted {
                        loadAttempted = true
                        if viewModel.groups.isEmpty {
                            viewModel.fetchGroups()
                        } else if viewModel.reflections.isEmpty {
                            viewModel.fetchReflections(forceRefresh: true)
                        }
                    }
                }
            } else if viewModel.reflections.isEmpty {
                ReflectionEmptyStateView(action: { showingAddSheet.toggle() })
                    .transition(.scale.combined(with: .opacity))
            } else {
                ReflectionsList(
                    viewModel: viewModel,
                    animateList: animateList,
                    searchText: searchText,
                    sortDescending: sortDescending
                )
                .transition(.opacity)
                .blur(radius: viewModel.isLoadingReflections ? 1.0 : 0)
                .opacity(viewModel.isLoadingReflections ? 0.7 : 1.0)
            }
        }
        .searchable(text: $searchText, prompt: "Search reflections")
        .onChange(of: viewModel.isLoadingReflections) { _, isLoading in
            if !isLoading {
                hasCompletedInitialLoad = true
            }
        }
    }
}

struct ReflectionsList: View {
    @ObservedObject var viewModel: ReflectionsViewModel
    let animateList: Bool
    let searchText: String
    let sortDescending: Bool

    var body: some View {
        // Apply simple client-side search and optional date sort
        let list: [Reflection] = (
            searchText.isEmpty
                ? viewModel.reflections
                : viewModel.reflections.filter { r in
                    r.C_Title.localizedCaseInsensitiveContains(searchText)
                        || r.C_Summary.localizedCaseInsensitiveContains(searchText)
                        || r.C_Content.localizedCaseInsensitiveContains(searchText)
                }
        ).sorted { a, b in
            let da = ReflectionDateParser.parse(a.C_Date)
            let db = ReflectionDateParser.parse(b.C_Date)
            return sortDescending ? (da > db) : (da < db)
        }
        ForEach(Array(list.enumerated()), id: \.element.id) { _, reflection in
            ReflectionCardView(
                reflection: reflection,
                onDelete: {
                    HapticManager.shared.playDelete()
                    viewModel.deleteReflection(reflection)
                }
            )
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .contentTransition(.identity)
        }
    }
}

struct ReflectionEmptyStateView: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)
                .padding(.bottom, 8)
            Text("No reflections available")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Add a new reflection using the + button")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button(action: {
                HapticManager.shared.playButtonTap()
                action()
            }) {
                Label("Add New Reflection", systemImage: "plus.circle")
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

private extension String? {
    var isNilOrEmpty: Bool {
        self?.isEmpty ?? true
    }
}

private enum ReflectionDateParser {
    private static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parse(_ dateString: String) -> Date {
        fullFormatter.date(from: dateString)
            ?? dateOnlyFormatter.date(from: dateString)
            ?? .distantPast
    }
}

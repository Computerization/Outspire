import QuickLook
import SwiftUI

// Removed ColorfulX usage in favor of system materials
import Toasts

struct SchoolArrangementView: View {
    @StateObject private var viewModel = SchoolArrangementViewModel()
    @Environment(\.presentToast) var presentToast
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var gradientManager: GradientManager // Add gradient manager
    @State private var searchText = ""
    @State private var refreshButtonRotation = 0.0
    @State private var showDetailSheet = false
    @State private var hasFirstAppeared = false

    /// Track content status
    private var isEmptyState: Bool {
        filteredGroups.isEmpty && !viewModel.isLoading
    }

    // Device adaptive settings
    private let isSmallDevice = UIDevice.isSmallScreen
    private let animationDelay = UIDevice.isSmallScreen ? 0.0 : 0.1

    private var filteredGroups: [ArrangementGroup] {
        if searchText.isEmpty {
            viewModel.arrangementGroups
        } else {
            viewModel.arrangementGroups.compactMap { group in
                let filteredItems = group.items.filter { item in
                    item.title.localizedCaseInsensitiveContains(searchText) ||
                        item.weekNumbers.contains(where: { String($0).contains(searchText) })
                }

                if filteredItems.isEmpty {
                    return nil
                } else {
                    return ArrangementGroup(
                        id: group.id,
                        title: group.title,
                        items: filteredItems,
                        isExpanded: group.isExpanded
                    )
                }
            }
        }
    }

    // Animation constants for consistent timing
    private let transitionDuration = 0.35
    private let staggerDelay = 0.05

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading, viewModel.arrangements.isEmpty {
                    loadingView
                } else if isEmptyState {
                    emptyStateView
                } else {
                    listContent
                }
            }
            .navigationTitle("School Arrangements")
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search by week number or title"
            )
            .toolbar {
//                ToolbarItem(placement: .navigationBarTrailing) {
//                    if viewModel.isLoadingDetail {
//                        ProgressView()
//                            .controlSize(.small)
//                    } else {
//                        LoadingIndicator(isLoading: viewModel.isLoading)
//                    }
//                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    RefreshButton(
                        isLoading: viewModel.isLoading,
                        rotation: $refreshButtonRotation,
                        action: {
                            withAnimation { refreshButtonRotation += 360 }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            viewModel.refreshData()
                        }
                    )
                }
            }
            .sheet(isPresented: $showDetailSheet, onDismiss: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if viewModel.selectedDetail == nil {
                        viewModel.pdfURL = nil
                    }
                }
            }) {
                detailSheetContent
                    .presentationDetents([.large, .medium])
                    .presentationDragIndicator(.visible)
                    .if(UIDevice.current.userInterfaceIdiom == .pad) { view in
                        view.presentationDetents([.large])
                            .presentationContentInteraction(.scrolls)
                    }
            }
            .onChange(of: viewModel.pdfURL) { _, newURL in
                withAnimation(.easeInOut(duration: 0.2)) {
                    showDetailSheet = newURL != nil
                }
            }
            .onChange(of: viewModel.selectedDetail) { _, newDetail in
                withAnimation(.easeInOut(duration: 0.2)) {
                    showDetailSheet = newDetail != nil
                }
            }
            .onChange(of: viewModel.errorMessage) { _, errorMessage in
                if let message = errorMessage {
                    showToast(message)
                }
            }
            .onAppear {
                if !hasFirstAppeared {
                    // Trigger animation only once when view first appears
                    hasFirstAppeared = true
                    viewModel.triggerInitialAnimation(isSmallScreen: isSmallDevice)
                }
                updateGradientForSchoolArrangements()
            }
            // Assign a stable ID to prevent SwiftUI from rebuilding the view hierarchy
            .id("SchoolArrangementViewStableID")
        }
    }

    // MARK: - View Components

    private var loadingView: some View {
        SchoolArrangementSkeletonView()
            .id("LoadingSkeletonStableID")
    }

    private var listContent: some View {
        List {
            ForEach(filteredGroups) { group in
                Section(header: CollapsibleSectionHeader(
                    title: group.title,
                    isExpanded: group.isExpanded,
                    toggle: { viewModel.toggleGroupExpansion(group.id) }
                )) {
                    if group.isExpanded {
                        ForEach(group.items) { item in
                            ArrangementItemRow(
                                item: item,
                                onToggle: { viewModel.toggleItemExpansion(item.id) },
                                onOpen: { viewModel.fetchArrangementDetail(for: item) },
                                isLoadingDetail: viewModel.isLoadingDetail
                            )
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                        }
                    }
                }
                .id(group.id)
            }

            if viewModel.currentPage < viewModel.totalPages, !viewModel.isLoading {
                loadMoreRow
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await performRefresh() }
    }

    private var loadMoreRow: some View {
        HStack {
            Spacer()
            ProgressView("Loading more…")
            Spacer()
        }
        .onAppear { viewModel.fetchNextPage() }
    }

    private var emptyStateView: some View {
        EmptyStateView(
            searchText: searchText,
            isAnimated: viewModel.shouldAnimate,
            isSmallScreen: isSmallDevice,
            refreshAction: { viewModel.refreshData() }
        )
        .id("EmptyStateStableID")
    }

    // MARK: - Helper Methods

    /// Modern collapsible section header for List/Section
    private struct CollapsibleSectionHeader: View {
        let title: String
        let isExpanded: Bool
        let toggle: () -> Void

        var body: some View {
            Button(action: toggle) {
                HStack {
                    Text(title)
                        .font(AppText.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// List row using DisclosureGroup to expand details
    private struct ArrangementItemRow: View {
        let item: SchoolArrangementItem
        let onToggle: () -> Void
        let onOpen: () -> Void
        let isLoadingDetail: Bool

        var body: some View {
            DisclosureGroup(
                isExpanded: .init(
                    get: { item.isExpanded },
                    set: { _ in onToggle() }
                )
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    if !item.weekNumbers.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(item.weekNumbers, id: \.self) { week in
                                    Text("Week \(week)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                                }
                            }
                        }
                    }

                    Button(action: onOpen) {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.viewfinder").font(.caption)
                            Text("View as PDF")
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                    .controlSize(.regular)
                    .disabled(isLoadingDetail)
                }
                .padding(.top, 6)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(AppText.body.weight(.semibold))
                        .lineLimit(2)
                    Text(item.publishDate)
                        .font(AppText.meta)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func performRefresh() async {
        viewModel.refreshData()
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    private func showToast(_ message: String) {
        let toast = ToastValue(
            icon: Image(systemName: "exclamationmark.triangle").foregroundStyle(.red),
            message: message
        )
        presentToast(toast)

        // Add subtle haptic feedback for errors
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)

        // Clear the error message after showing toast
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            viewModel.errorMessage = nil
        }
    }

    /// Add the detail sheet content
    private var detailSheetContent: some View {
        Group {
            if let pdfURL = viewModel.pdfURL {
                UnifiedPDFPreview(url: pdfURL, title: viewModel.selectedDetail?.title ?? "Document")
            } else if viewModel.isLoadingDetail {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Preparing document...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)

                    Text("Content Unavailable")
                        .font(.headline)

                    Text("Unable to load the document content")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button("Dismiss") {
                        showDetailSheet = false
                    }
                    .padding(.top, 10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    // Auto-dismiss if no data loaded after a timeout
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        if viewModel.pdfURL == nil, !viewModel.isLoadingDetail {
                            showDetailSheet = false
                            viewModel.errorMessage = "Failed to load content"
                        }
                    }
                }
            }
        }
    }

    /// Add method to update gradient for school arrangements
    private func updateGradientForSchoolArrangements() {
        #if !targetEnvironment(macCatalyst)
            gradientManager.updateGradientForView(.schoolArrangements, colorScheme: colorScheme)
        #else
            gradientManager.updateGradient(
                colors: [Color(.systemBackground)],
                speed: 0.0,
                noise: 0.0
            )
        #endif
    }
}

/// Helper extension for conditional modifiers
extension View {
    @ViewBuilder
    func `if`(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

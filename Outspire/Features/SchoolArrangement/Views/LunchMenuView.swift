import QuickLook
import SwiftUI

// Removed ColorfulX usage in favor of system materials
import Toasts

struct LunchMenuView: View {
    @StateObject private var viewModel = LunchMenuViewModel()
    @Environment(\.presentToast) var presentToast
    @State private var searchText = ""
    @State private var refreshButtonRotation = 0.0
    @State private var showDetailSheet = false
    @State private var hasFirstAppeared = false
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var gradientManager: GradientManager // Add gradient manager

    /// Track content status
    private var isEmptyState: Bool {
        filteredGroups.isEmpty && !viewModel.isLoading
    }

    // Device adaptive settings
    private let isSmallDevice = UIDevice.isSmallScreen
    private let animationDelay = UIDevice.isSmallScreen ? 0.0 : 0.1

    private var filteredGroups: [LunchMenuGroup] {
        if searchText.isEmpty {
            viewModel.menuGroups
        } else {
            viewModel.menuGroups.compactMap { group in
                let filteredItems = group.items.filter { item in
                    item.title.localizedCaseInsensitiveContains(searchText)
                }

                if filteredItems.isEmpty {
                    return nil
                } else {
                    return LunchMenuGroup(
                        id: group.id,
                        title: group.title,
                        items: filteredItems,
                        isExpanded: group.isExpanded
                    )
                }
            }
        }
    }

    // Animation constants
    private let transitionDuration = 0.35
    private let staggerDelay = 0.05

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading, viewModel.menuItems.isEmpty {
                    loadingView
                } else if isEmptyState {
                    emptyStateView
                } else {
                    listContent
                }
            }
            .navigationTitle("Dining Menus")
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search by week number or title"
            )
            .toolbar {
//                ToolbarItem(placement: .navigationBarTrailing) {
//                    LoadingIndicator(isLoading: viewModel.isLoading)
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
                updateGradientForLunchMenu()
            }
            // Assign a stable ID to prevent SwiftUI from rebuilding the view hierarchy
            .id("LunchMenuViewStableID")
        }
    }

    // MARK: - View Components

    private var loadingView: some View {
        LunchMenuSkeletonView()
            .id("LunchMenuSkeletonStableID")
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
                            LunchMenuItemRow(
                                item: item,
                                onToggle: { viewModel.toggleItemExpansion(item.id) },
                                onOpen: { viewModel.fetchMenuDetail(for: item) },
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
        VStack(spacing: 20) {
            let animationEnabled = !isSmallDevice || AnimationManager.shared.hasAnimated(viewId: "LunchMenuView")

            Image(systemName: "fork.knife")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
                .opacity(viewModel.shouldAnimate ? 1 : 0)
                .scaleEffect(viewModel.shouldAnimate ? 1 : 0.8)
                .animation(animationEnabled ? .spring(response: 0.6).delay(0.1) : nil, value: viewModel.shouldAnimate)

            Text("No Lunch Menus Found")
                .font(.title3)
                .fontWeight(.medium)
                .opacity(viewModel.shouldAnimate ? 1 : 0)
                .offset(y: viewModel.shouldAnimate ? 0 : 10)
                .animation(animationEnabled ? .easeOut.delay(0.2) : nil, value: viewModel.shouldAnimate)

            Text(searchText.isEmpty ? "Pull to refresh or tap the refresh button" : "Try changing your search terms")
                .foregroundStyle(.secondary)
                .opacity(viewModel.shouldAnimate ? 1 : 0)
                .offset(y: viewModel.shouldAnimate ? 0 : 10)
                .animation(animationEnabled ? .easeOut.delay(0.3) : nil, value: viewModel.shouldAnimate)

            Button(action: { viewModel.refreshData() }) {
                Text("Refresh")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(0.1))
                    )
            }
            .buttonStyle(BorderlessButtonStyle())
            .opacity(viewModel.shouldAnimate ? 1 : 0)
            .scaleEffect(viewModel.shouldAnimate ? 1 : 0.9)
            .animation(animationEnabled ? .spring(response: 0.6).delay(0.4) : nil, value: viewModel.shouldAnimate)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .id("EmptyMenuStateStableID")
    }

    private var detailSheetContent: some View {
        Group {
            if let pdfURL = viewModel.pdfURL {
                UnifiedPDFPreview(url: pdfURL, title: viewModel.selectedDetail?.title ?? "Menu Document")
            } else if viewModel.isLoadingDetail {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Preparing menu document...")
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

                    Text("Unable to load the menu content")
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
                            viewModel.errorMessage = "Failed to load menu content"
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helper Methods

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

        // Add haptic feedback for errors
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)

        // Clear the error message after showing toast
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            viewModel.errorMessage = nil
        }
    }

    /// Add method to update gradient for lunch menu
    private func updateGradientForLunchMenu() {
        #if !targetEnvironment(macCatalyst)
            gradientManager.updateGradientForView(.lunchMenu, colorScheme: colorScheme)
        #else
            gradientManager.updateGradient(
                colors: [Color(.systemBackground)],
                speed: 0.0,
                noise: 0.0
            )
        #endif
    }
}

// MARK: - Extracted Components

struct LunchMenuSection: View {
    let group: LunchMenuGroup
    let toggleGroup: () -> Void
    let toggleItem: (String) -> Void
    let fetchDetail: (LunchMenuItem) -> Void
    let isLoadingDetail: Bool
    let shouldAnimate: Bool
    let isSmallScreen: Bool
    let transitionDuration: Double
    let staggerDelay: Double

    @State private var headerHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Year header
            Button(action: {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
                    toggleGroup()
                }
            }) {
                HStack {
                    Text(group.title)
                        .font(.headline)
                        .foregroundStyle(.gray)

                    Spacer()

                    Image(systemName: group.isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(group.isExpanded ? 180 : 0))
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: group.isExpanded)
                        .scaleEffect(headerHovered ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: headerHovered)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
                .onHover { isHovered in
                    headerHovered = isHovered
                }
            }
            .buttonStyle(BorderlessButtonStyle())
            .contentTransition(.opacity)
            .id("header-\(group.id)")

            // Items for this group
            if group.isExpanded {
                VStack(spacing: 12) {
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                        LunchMenuItemView(
                            item: item,
                            toggleItem: { toggleItem(item.id) },
                            fetchDetail: { fetchDetail(item) },
                            isLoadingDetail: isLoadingDetail,
                            shouldAnimate: shouldAnimate,
                            staggerDelay: staggerDelay,
                            itemIndex: index
                        )
                        .id("item-\(item.id)")
                        .transition(.asymmetric(
                            insertion: .opacity
                                .combined(with: .scale(scale: 0.95, anchor: .top))
                                .combined(with: .offset(y: -5))
                                .animation(.spring(response: 0.4, dampingFraction: 0.65)
                                    .delay(Double(index) * 0.05)),
                            removal: .opacity
                                .combined(with: .scale(scale: 0.95, anchor: .top))
                                .animation(.easeOut(duration: 0.2))
                        ))
                    }
                }
            }
        }
        .padding(.top, 4)
        .opacity(shouldAnimate ? 1 : 0)
        .offset(y: shouldAnimate ? 0 : 20)
        // Only animate on larger screens or first appearance
        .animation(
            (isSmallScreen && AnimationManager.shared.hasAnimated(viewId: "LunchMenuView"))
                ? nil
                : .spring(response: 0.5, dampingFraction: 0.8).delay(transitionDuration * 0.2),
            value: shouldAnimate
        )
    }
}

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
private struct LunchMenuItemRow: View {
    let item: LunchMenuItem
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
                Button(action: onOpen) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.viewfinder").font(.caption)
                        Text("View Menu PDF")
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

struct LunchMenuItemView: View {
    let item: LunchMenuItem
    let toggleItem: () -> Void
    let fetchDetail: () -> Void
    let isLoadingDetail: Bool
    let shouldAnimate: Bool
    let staggerDelay: Double
    let itemIndex: Int

    @State private var buttonHovered = false
    @State private var isPressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with title and date
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    isPressed = true
                    // Small haptic feedback for toggle action
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred(intensity: 0.5)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            isPressed = false
                            toggleItem()
                        }
                    }
                }
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.headline)
                            .lineLimit(2)
                            .foregroundColor(.primary)

                        Text(item.publishDate)
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }

                    Spacer()

                    Image(systemName: item.isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                        .rotationEffect(.degrees(item.isExpanded ? 180 : 0))
                        .animation(.spring(response: 0.45, dampingFraction: 0.65), value: item.isExpanded)
                        .scaleEffect(buttonHovered ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: buttonHovered)
                }
                .contentTransition(.opacity)
                .onHover { isHovered in
                    buttonHovered = isHovered
                }
            }
            .buttonStyle(BorderlessButtonStyle())

            // View details button when expanded
            if item.isExpanded {
                MenuDetailButton(
                    action: fetchDetail,
                    isLoading: isLoadingDetail
                )
                .padding(.top, 4)
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: item.isExpanded)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.tertiarySystemBackground))
        )
        .contentShape(Rectangle())
        .opacity(shouldAnimate ? 1 : 0)
        .offset(y: shouldAnimate ? 0 : 20)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(
            .spring(response: 0.5, dampingFraction: 0.7).delay(Double(itemIndex) * staggerDelay),
            value: shouldAnimate
        )
    }
}

struct MenuDetailButton: View {
    let action: () -> Void
    let isLoading: Bool

    @State private var isPressed = false
    @State private var hovered = false
    @State private var opacity: Double = 0

    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isPressed = true
            }

            // Reset press state after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isPressed = false
                }
                action()
            }
        }) {
            HStack {
                Text("View Menu")
                Image(systemName: "doc.viewfinder")
                    .font(.caption)
            }
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(hovered ? 0.15 : 0.1))
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(BorderlessButtonStyle())
        .disabled(isLoading)
        .opacity(isLoading ? 0.6 : 1.0)
        .opacity(opacity)
        .animation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.1), value: isLoading)
        .onAppear {
            // Fade in animation when button appears
            withAnimation(.easeOut(duration: 0.3).delay(0.05)) {
                opacity = 1
            }
        }
        .onHover { isHovered in
            withAnimation(.easeOut(duration: 0.2)) {
                hovered = isHovered
            }
        }
    }
}

struct LunchMenuSkeletonView: View {
    /// Animation states
    @State private var animateItems = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Add spacing at the top to account for the search bar
                Spacer()
                    .frame(height: 16)

                // Add year header skeleton
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 18)
                        .frame(width: 120)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 4)

                ForEach(0 ..< 3, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            // Title skeleton
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 22)
                                .frame(width: 220)

                            Spacer()

                            // Date skeleton
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 16)
                                .frame(width: 100)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(UIColor.secondarySystemBackground))
                    )
                    .opacity(animateItems ? 1 : 0.4)
                    .offset(y: animateItems ? 0 : 10)
                    .animation(
                        .spring(response: 0.5, dampingFraction: 0.8)
                            .delay(Double(index) * 0.07),
                        value: animateItems
                    )
                }
            }
            .padding()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                animateItems = true
            }
        }
        .onDisappear {
            animateItems = false
        }
    }
}

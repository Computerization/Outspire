import LocalAuthentication
import SwiftUI

// Removed ColorfulX usage in favor of system materials

struct ScoreView: View {
    @StateObject private var viewModel = ScoreViewModel()
    @State private var selectedSubjectId: String?
    @State private var animateIn = false
    @State private var refreshButtonRotation = 0.0
    @ObservedObject private var authV2 = AuthServiceV2.shared
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var gradientManager: GradientManager

    var body: some View {
        ZStack {
            // Main content
            if !isAuthenticated {
                ContentUnavailableView(
                    "Authentication Required",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text("Please sign in to view your academic grades.")
                )
                .padding()
                .transition(.opacity)
            } else if viewModel.isUnlocked {
                mainContent
                    .transition(.opacity.combined(with: .offset(y: -10)))
            } else {
                authenticationView
                    .transition(.opacity.combined(with: .offset(y: 10)))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.isUnlocked)
        .navigationTitle("Academic Grades")
        .toolbar {
            toolbarItems
        }
        .onAppear {
            updateGradientForScoreView()

            // Force a reset to the most recent term when the view appears
            if isAuthenticated, viewModel.isUnlocked {
                viewModel.selectMostRecentTerm()
            }
        }
        .task {
            // This ensures initialization happens correctly when switching tabs
            if isAuthenticated {
                if !viewModel.isUnlocked {
                    viewModel.authenticate()
                } else if viewModel.terms.isEmpty {
                    viewModel.fetchTerms()
                } else if viewModel.scores.isEmpty, !viewModel.selectedTermId.isEmpty {
                    viewModel.fetchScores()
                }
            }
        }
        .onChange(of: viewModel.selectedTermId) { oldValue, newValue in
            // When term changes, ensure we load data for the new term
            if !newValue.isEmpty, oldValue != newValue {
                viewModel.fetchScores()
            }
        }
        // Using a unique ID ensures the view is properly recreated when switching tabs
        .id("scoreView-\(isAuthenticated)-\(viewModel.isUnlocked)")
    }

    private var notLoggedInView: some View {
        ContentUnavailableView(
            "Authentication Required",
            systemImage: "person.crop.circle.badge.exclamationmark",
            description: Text("Please sign in to view your academic grades.")
        )
        .padding()
    }

    private var mainContent: some View {
        Group {
            if viewModel.isLoadingTerms, viewModel.terms.isEmpty {
                VStack {
                    // Fixed height container to prevent layout jumps
                    VStack(spacing: 0) {
                        // Empty term selector placeholder with same height
                        Rectangle()
                            .fill(Color(UIColor.secondarySystemBackground))
                            .frame(height: 70)

                        Divider()
                            .background(Color.secondary.opacity(0.3))
                    }

                    LoadingView(message: "Loading terms...", fixedHeight: 400)
                }
            } else if viewModel.terms.isEmpty, !viewModel.isLoadingTerms {
                VStack {
                    // Fixed height container to prevent layout jumps
                    VStack(spacing: 0) {
                        // Empty term selector placeholder with same height
                        Rectangle()
                            .fill(Color(UIColor.secondarySystemBackground))
                            .frame(height: 70)

                        Divider()
                            .background(Color.secondary.opacity(0.3))
                    }

                    ContentUnavailableView(
                        "No Academic Terms",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("No academic terms are available.")
                    )
                    .frame(minHeight: 400)
                }
            } else {
                VStack(spacing: 0) {
                    termSelector
                    scoreContent
                }
            }
        }
        .transition(.opacity)
    }

    private var termSelector: some View {
        VStack(spacing: 0) {
            if !viewModel.terms.isEmpty {
                ScrollViewReader { scrollProxy in
                    // Fix the height of the scroll view to prevent layout jumps
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.terms) { term in
                                TermButton(
                                    term: term,
                                    isSelected: viewModel.selectedTermId == term.W_YearID,
                                    action: {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            // Only fetch if we're changing terms
                                            if viewModel.selectedTermId != term.W_YearID {
                                                viewModel.selectedTermId = term.W_YearID

                                                // Save the selected term ID to make this choice persistent
                                                UserDefaults.standard.set(
                                                    term.W_YearID, forKey: "selectedTermId"
                                                )

                                                // Scroll to make selected term visible
                                                withAnimation {
                                                    scrollProxy.scrollTo(term.id, anchor: .center)
                                                }

                                                viewModel.fetchScores()

                                                // Reset animation state with a short delay for smoother transition
                                                animateIn = false
                                                DispatchQueue.main.asyncAfter(
                                                    deadline: .now() + 0.1
                                                ) {
                                                    withAnimation(
                                                        .spring(response: 0.6, dampingFraction: 0.7)
                                                    ) {
                                                        animateIn = true
                                                    }
                                                }
                                            }
                                        }
                                    },
                                    hasData: viewModel.termsWithData.contains(term.W_YearID)
                                )
                                .id(term.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .frame(height: 60)
                    .background(Color(UIColor.secondarySystemBackground).opacity(0.7))
                    .onAppear {
                        // Scroll to selected term when view appears, but with a slight delay to ensure view is ready
                        if let selectedTerm = viewModel.terms.first(where: {
                            $0.W_YearID == viewModel.selectedTermId
                        }) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                withAnimation {
                                    scrollProxy.scrollTo(selectedTerm.id, anchor: .center)
                                }
                            }
                        } else if !viewModel.terms.isEmpty {
                            // If for some reason the selected term isn't found, scroll to first term
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                withAnimation {
                                    scrollProxy.scrollTo(viewModel.terms[0].id, anchor: .center)
                                }
                            }
                        }
                    }
                }

                // Add a subtle divider
                Divider()
                    .background(Color.secondary.opacity(0.1))
            }
        }
    }

    private var scoreContent: some View {
        ZStack {
            // Background placeholder for stable layout
            Rectangle()
                .fill(Color.clear)
                .frame(maxWidth: .infinity, minHeight: 400)

            if viewModel.isLoading {
                ScoreSkeletonView()
                    .transition(.opacity)
            } else if viewModel.scores.isEmpty, viewModel.errorMessage == nil {
                // Fallback empty state (though this shouldn't happen with our improved handling)
                ContentUnavailableView(
                    "No Scores Available",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("There are no scores available for this term yet.")
                )
                .transition(.opacity)
            } else if viewModel.scores.isEmpty, viewModel.errorMessage != nil {
                // Contextual empty state based on the term
                let message = viewModel.errorMessage ?? "No data available"
                let isUpcoming = message.contains("hasn't started")
                let isPast = message.contains("before your enrollment")

                ContentUnavailableView(
                    isUpcoming ? "Future Term" : (isPast ? "Past Term" : "No Scores Available"),
                    systemImage: isUpcoming
                        ? "calendar.badge.clock"
                        : (isPast ? "calendar.badge.exclamationmark" : "doc.text.magnifyingglass"),
                    description: Text(message)
                )
                .transition(.opacity)
            } else if !viewModel.scores.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(Array(viewModel.scores.enumerated()), id: \.element.id) {
                            index, subject in
                            SubjectScoreCard(
                                subject: subject,
                                isExpanded: selectedSubjectId == subject.id,
                                onTap: {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                        if selectedSubjectId == subject.id {
                                            selectedSubjectId = nil
                                        } else {
                                            selectedSubjectId = subject.id
                                        }
                                    }
                                }
                            )
                            .padding(.horizontal)
                            .offset(y: animateIn ? 0 : 10) // Smaller offset for more subtle animation
                            .opacity(animateIn ? 1 : 0)
                            .animation(
                                .spring(response: 0.4, dampingFraction: 0.8)
                                    .delay(Double(index) * 0.02), // Faster staggered delay for more responsive feel
                                value: animateIn
                            )
                        }

                        // Add space at the bottom for better scrolling
                        Color.clear.frame(height: 30)

                        if !viewModel.scores.isEmpty {
                            VStack(spacing: 4) {
                                Divider()
                                    .padding(.horizontal, 32)
                                    .padding(.bottom, 8)

                                Text(viewModel.formattedLastUpdateTime)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.bottom, 16)
                            }
                            .opacity(animateIn ? 0.7 : 0)
                            .animation(.easeIn.delay(0.5), value: animateIn)
                            .id(viewModel.lastUpdateTime) // This ensures the view updates when the time changes
                        }
                    }
                    .padding(.top)
                    .id(viewModel.selectedTermId) // This ensures scrolling resets when term changes
                }
                .applyScrollEdgeEffect()
                .refreshable {
                    // Reset animation state
                    animateIn = false

                    // Pull to refresh functionality
                    viewModel.fetchScores(forceRefresh: true)

                    // Restart animations after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                            animateIn = true
                        }
                    }
                }
                .transition(.opacity)
            }

            // Error toast overlay - for network errors only, not for empty terms
            // Only show the overlay for actual errors, not for informational messages
            if let errorMessage = viewModel.errorMessage,
               errorMessage.starts(with: "Failed")
            {
                VStack {
                    Spacer() // Push error to bottom

                    ErrorView(
                        errorMessage: errorMessage,
                        retryAction: {
                            // Reset animation state
                            animateIn = false

                            // Refresh data
                            viewModel.refreshData()

                            // Restart animations after a delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                    animateIn = true
                                }
                            }
                        }
                    )
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(UIColor.tertiarySystemBackground))
                            .shadow(radius: 4)
                    )
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .zIndex(100) // Ensure error is on top
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.errorMessage)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.isLoading)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.scores.isEmpty)
        .onAppear {
            // Reset animation state when appearing
            animateIn = false

            // Use a shorter delay for better perceived performance
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                    animateIn = true
                }
            }

            // Check if there's stale data that needs refreshing
            if !viewModel.scores.isEmpty, !viewModel.isLoading,
               !viewModel.isCacheValid(for: "scoresCacheTimestamp-\(viewModel.selectedTermId)")
            {
                // Silently refresh data if cache is stale
                viewModel.fetchScores(forceRefresh: true)
            }
        }
        .onChange(of: viewModel.isLoading) { oldValue, isLoading in
            if !isLoading, !viewModel.scores.isEmpty, oldValue {
                // Reset and re-trigger animation when loading completes
                animateIn = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                        animateIn = true
                    }
                }
            }
        }
    }

    private var authenticationView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .symbolRenderingMode(.hierarchical)

                Text("Authentication Required")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)

                Text("Your academic records are protected.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .padding(.horizontal, 24)
            .coloredRichCard(
                colors: [AppColor.brand.opacity(0.9), AppColor.brand.opacity(0.7)],
                cornerRadius: AppRadius.xl
            )
            .padding(.horizontal, 24)

            if viewModel.isLoading {
                ProgressView()
                    .padding(.top)
            } else {
                Button("Authenticate", action: viewModel.authenticate)
                    .buttonStyle(.borderedProminent)
                    .padding(.top)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var toolbarItems: some ToolbarContent {
        Group {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    HapticManager.shared.playRefresh()
                    withAnimation {
                        refreshButtonRotation += 360
                    }

                    // Reset animation state
                    animateIn = false

                    // Check if we need to authenticate first
                    if !viewModel.isUnlocked {
                        viewModel.authenticate()
                    } else {
                        viewModel.refreshData()
                    }

                    // Restart animations after a small delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                            animateIn = true
                        }
                    }
                }) {
                    Label {
                        Text("Refresh")
                    } icon: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .rotationEffect(.degrees(refreshButtonRotation))
                    .animation(
                        .spring(response: 0.6, dampingFraction: 0.5),
                        value: refreshButtonRotation
                    )
                }
                .disabled(
                    !isAuthenticated || viewModel.isLoading || viewModel.isLoadingTerms
                )
            }
        }
    }

    /// Add method to update gradient for score view
    private func updateGradientForScoreView() {
        gradientManager.updateGradientForView(.score, colorScheme: colorScheme)
    }
}

extension ScoreView {
    private var isAuthenticated: Bool {
        authV2.isAuthenticated
    }
}

struct TermButton: View {
    let term: Term
    let isSelected: Bool
    let action: () -> Void
    let hasData: Bool // We'll keep this parameter but not use it visually

    var body: some View {
        Button(action: {
            HapticManager.shared.playSelectionFeedback()
            action()
        }) {
            VStack(spacing: 4) {
                Text(term.W_Year)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .accentColor : .primary)

                Text("Term \(term.W_Term)")
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .accentColor.opacity(0.8) : .secondary)
            }
            .frame(height: 44)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

struct SubjectScoreCard: View {
    let subject: Score
    let isExpanded: Bool
    let onTap: () -> Void

    private var subjectColor: Color {
        ModernScheduleRow.subjectColor(for: subject.subjectName)
    }

    /// Check if this subject has any valid scores
    private var hasAnyScores: Bool {
        subject.examScores.contains { $0.hasScore }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Rectangle()
                    .fill(subjectColor)
                    .frame(width: 4)
                    .cornerRadius(2)

                Text(subject.subjectName)
                    .font(.system(size: 17, weight: .medium))
                    .lineLimit(1)
                    .foregroundColor(.primary)

                Spacer()

                // Average score pill
                if subject.averageScore > 0 {
                    Text("Avg. \(String(format: "%.1f", subject.averageScore))")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(subjectColor))
                } else {
                    Text("No scores")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if hasAnyScores {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
            .onTapGesture {
                if hasAnyScores {
                    onTap()
                }
            }

            // Expanded content with improved animation
            if isExpanded, hasAnyScores {
                VStack(spacing: 0) {
                    Divider()
                        .padding(.horizontal)

                    VStack(spacing: 12) {
                        ForEach(subject.examScores.filter(\.hasScore)) { exam in
                            HStack {
                                Text(exam.name)
                                    .font(.system(size: 15))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 90, alignment: .leading)

                                Spacer()

                                Text(exam.score)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.primary)

                                if !exam.level.isEmpty, exam.level != "0" {
                                    Text(exam.level)
                                        .font(.system(size: 14))
                                        .foregroundColor(scoreGradeColor(exam.level))
                                        .frame(width: 30, alignment: .trailing)
                                        .fontWeight(.medium)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }
        }
        .richCard(cornerRadius: AppRadius.lg, shadowRadius: 10)
        .opacity(hasAnyScores ? 1 : 0.8)
        .animation(.easeInOut(duration: 0.25), value: isExpanded)
    }

    private func scoreGradeColor(_ grade: String) -> Color {
        switch grade {
        case "A*", "A+":
            Color(red: 0.85, green: 0.65, blue: 0.13) // gold
        case "A":
            .indigo
        case "B":
            .teal
        case "C":
            .green
        case "D":
            .orange
        case "E", "F":
            .red
        default:
            .gray
        }
    }
}

struct ScoreSkeletonView: View {
    @State private var isAnimating = false

    var body: some View {
        // Fixed-size container to prevent layout jumps
        VStack(spacing: 16) {
            ForEach(0 ..< 5, id: \.self) { _ in
                VStack(spacing: 8) {
                    HStack {
                        Circle()
                            .fill(Color.gray.opacity(0.1))
                            .frame(width: 12, height: 12)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.1))
                            .frame(height: 16)
                            .frame(width: 100)

                        Spacer()

                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.gray.opacity(0.1))
                            .frame(height: 24)
                            .frame(width: 80)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(Color(UIColor.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            // Add some spacers to ensure a consistent minimum height
            Spacer().frame(height: 20)
        }
        .padding(.horizontal)
        .padding(.top)
        .frame(minHeight: 400) // Ensures consistent height
        .opacity(isAnimating ? 0.6 : 1.0)
        .animation(
            Animation.easeInOut(duration: 1.2)
                .repeatForever(autoreverses: true),
            value: isAnimating
        )
        .onAppear {
            isAnimating = true
        }
    }
}

#Preview {
    NavigationStack {
        ScoreView()
    }
}

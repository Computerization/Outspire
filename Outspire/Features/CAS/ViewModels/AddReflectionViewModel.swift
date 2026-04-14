import Combine
import Foundation
import SwiftUI
import Toasts

/// ViewModel for the Add Reflection sheet.
@MainActor
class AddReflectionViewModel: ObservableObject {
    // MARK: - Published form fields

    @Published var selectedGroupId: String
    @Published var title: String = ""
    @Published var summary: String = ""
    @Published var content: String = ""
    @Published var lo1 = false
    @Published var lo2 = false
    @Published var lo3 = false
    @Published var lo4 = false
    @Published var lo5 = false
    @Published var lo6 = false
    @Published var lo7 = false
    @Published var lo8 = false

    @Published var errorMessage: String?
    @Published var isSaving: Bool = false
    @Published var saveSucceeded: Bool = false

    // Dependencies
    let availableGroups: [ReflectionGroup]
    private let studentId: String
    private let onSave: () -> Void
    private let llmService: LLMService = .init()

    // AI Suggestion State
    @Published var isFetchingSuggestion = false
    @Published var suggestionError: String?
    @Published var canRevertSuggestion = false
    @Published var showFirstTimeSuggestionAlert = false
    @Published var showCompletedSuggestionAlert = false
    private var originalTitle: String?
    private var originalContent: String?

    private let authV2 = AuthServiceV2.shared

    // Autosave
    private var cancellables = Set<AnyCancellable>()
    private static var cachedFormData: FormCache?

    /// Timer for autosave
    private var autoSaveTimer: Timer?

    /// Struct to store form data for autosave
    struct FormCache: Codable {
        let groupId: String
        let title: String
        let summary: String
        let content: String
        let learningOutcomes: [Bool]
    }

    // Word count limits
    private let defaultSummaryLimit = 100
    private let defaultContentMin = 500
    private let altSummaryLimit = 50
    private let altContentMin = 150
    private let altGroupId = "92"

    init(
        availableGroups: [ReflectionGroup],
        studentId: String,
        onSave: @escaping () -> Void
    ) {
        self.availableGroups = availableGroups
        self.studentId = studentId
        self.onSave = onSave
        // default to first group
        self.selectedGroupId = availableGroups.first?.id ?? ""

        // Check if this is the first time using the suggestion feature
        self.showFirstTimeSuggestionAlert = false

        // Try to restore from cache
        if let cache = AddReflectionViewModel.cachedFormData {
            self.selectedGroupId = cache.groupId
            self.title = cache.title
            self.summary = cache.summary
            self.content = cache.content

            if cache.learningOutcomes.count >= 8 {
                self.lo1 = cache.learningOutcomes[0]
                self.lo2 = cache.learningOutcomes[1]
                self.lo3 = cache.learningOutcomes[2]
                self.lo4 = cache.learningOutcomes[3]
                self.lo5 = cache.learningOutcomes[4]
                self.lo6 = cache.learningOutcomes[5]
                self.lo7 = cache.learningOutcomes[6]
                self.lo8 = cache.learningOutcomes[7]
            }
        }

        // Setup autosave timer
        setupAutoSave()

        // Register for clear cache notification
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ClearCachedFormData"),
            object: nil,
            queue: .main
        ) { _ in
            // Clear the cached form data
            Self.cachedFormData = nil
        }
    }

    deinit {
        autoSaveTimer?.invalidate()
    }

    /// Set up auto-save timer
    private func setupAutoSave() {
        // Set up a timer to save every 2 seconds when content changes
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) {
            [weak self] _ in
            self?.cacheFormData()
        }

        // Setup publishers to monitor form field changes
        $title.sink { [weak self] _ in self?.cacheFormData() }.store(in: &cancellables)
        $summary.sink { [weak self] _ in self?.cacheFormData() }.store(in: &cancellables)
        $content.sink { [weak self] _ in self?.cacheFormData() }.store(in: &cancellables)
        $selectedGroupId.sink { [weak self] _ in self?.cacheFormData() }.store(in: &cancellables)

        // Learning outcomes
        $lo1.sink { [weak self] _ in self?.cacheFormData() }.store(in: &cancellables)
        $lo2.sink { [weak self] _ in self?.cacheFormData() }.store(in: &cancellables)
        $lo3.sink { [weak self] _ in self?.cacheFormData() }.store(in: &cancellables)
        $lo4.sink { [weak self] _ in self?.cacheFormData() }.store(in: &cancellables)
        $lo5.sink { [weak self] _ in self?.cacheFormData() }.store(in: &cancellables)
        $lo6.sink { [weak self] _ in self?.cacheFormData() }.store(in: &cancellables)
        $lo7.sink { [weak self] _ in self?.cacheFormData() }.store(in: &cancellables)
        $lo8.sink { [weak self] _ in self?.cacheFormData() }.store(in: &cancellables)
    }

    /// Cache form data automatically
    func cacheFormData() {
        // Only cache if there's meaningful data
        if !title.isEmpty || !summary.isEmpty || !content.isEmpty || hasAnyLearningOutcome() {
            AddReflectionViewModel.cachedFormData = FormCache(
                groupId: selectedGroupId,
                title: title,
                summary: summary,
                content: content,
                learningOutcomes: [lo1, lo2, lo3, lo4, lo5, lo6, lo7, lo8]
            )
        }
    }

    /// Clear the form and cache
    func clearForm() {
        title = ""
        summary = ""
        content = ""
        lo1 = false
        lo2 = false
        lo3 = false
        lo4 = false
        lo5 = false
        lo6 = false
        lo7 = false
        lo8 = false
        errorMessage = nil
        suggestionError = nil
        canRevertSuggestion = false
        originalTitle = nil
        originalContent = nil
        AddReflectionViewModel.cachedFormData = nil
    }

    /// Clear the cache after successful submission
    func clearCache() {
        AddReflectionViewModel.cachedFormData = nil
    }

    // MARK: - Computed word counts

    var summaryWordCount: Int {
        summary.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    var contentWordCount: Int {
        content.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    /// Current limits based on group
    var summaryLimit: Int {
        selectedGroupId == altGroupId ? altSummaryLimit : defaultSummaryLimit
    }

    var contentMin: Int {
        selectedGroupId == altGroupId ? altContentMin : defaultContentMin
    }

    /// Check if any learning outcome is selected
    func hasAnyLearningOutcome() -> Bool {
        lo1 || lo2 || lo3 || lo4 || lo5 || lo6 || lo7 || lo8
    }

    // MARK: - Validation

    func validate() -> Bool {
        // All required
        guard !selectedGroupId.isEmpty,
              !title.trimmingCharacters(in: .whitespaces).isEmpty,
              !summary.trimmingCharacters(in: .whitespaces).isEmpty,
              !content.trimmingCharacters(in: .whitespaces).isEmpty
        else {
            errorMessage = "Fill all fields"
            return false
        }
        // Summary length limit (chars)
        if summaryWordCount > summaryLimit {
            errorMessage = "Summary ≤ \(summaryLimit) chars"
            return false
        }
        // Content minimum (chars)
        if contentWordCount < contentMin {
            errorMessage = "Content ≥ \(contentMin) chars"
            return false
        }
        // At least one LO selected
        if !hasAnyLearningOutcome() {
            errorMessage = "Select ≥1 outcome"
            return false
        }
        errorMessage = nil
        return true
    }

    // MARK: - Save

    func save() {
        guard validate() else { return }
        // Accept either legacy session or V2 auth cookies
        if !AuthServiceV2.shared.isAuthenticated {
            errorMessage = "Sign in required"
            return
        }

        // Prepare LO values
        let loValues = [
            lo1 ? "Awareness" : "",
            lo2 ? "Challenge" : "",
            lo3 ? "Initiative" : "",
            lo4 ? "Collaboration" : "",
            lo5 ? "Commitment" : "",
            lo6 ? "Global Value" : "",
            lo7 ? "Ethics" : "",
            lo8 ? "New Skills" : ""
        ]

        var params: [String: String] = [
            "groupid": selectedGroupId,
            "refltitle": title,
            "summary": summary,
            "refnote": content,
            "studentid": studentId
        ]
        for idx in 1 ... 8 {
            params["c_lo\(idx)"] = loValues[idx - 1]
        }

        // New TSIMS expects consolidated fields; map to V2 payload
        // Resolve GroupId to numeric (server expects numeric id)
        resolveNumericGroupId(selectedGroupId) { mappedId in
            var v2Form: [String: String] = [
                "id": "0",
                "GroupId": mappedId,
                "Title": self.title,
                "Summary": self.summary,
                "Content": self.content
            ]
            // Map selected learning outcomes to first selected numeric code (1..8)
            if let outcomeCode = self.getSelectedOutcomeCode() {
                v2Form["outcome"] = outcomeCode
            }

            self.isSaving = true
            self.saveSucceeded = false

            TSIMSClientV2.shared.postForm(path: "/Stu/Cas/SaveReflection", form: v2Form) { [weak self] (result: Result<
                ApiResponse<String>,
                NetworkError
            >) in
                DispatchQueue.main.async {
                    switch result {
                    case let .success(env):
                        if env.isSuccess {
                            self?.clearCache()
                            self?.onSave()
                            self?.saveSucceeded = true
                            self?.isSaving = false
                        } else {
                            self?.errorMessage = "Save failed"
                            self?.isSaving = false
                        }
                    case let .failure(error):
                        _ = error
                        self?.errorMessage = "Network error"
                        self?.isSaving = false
                    }
                }
            }
        }
    }

    /// Map GroupNo -> numeric Id using cached group list; prime cache if needed
    private func resolveNumericGroupId(_ idOrNo: String, completion: @escaping (String) -> Void) {
        guard !idOrNo.isEmpty else { completion(""); return }
        if let detail = CASServiceV2.shared.getCachedGroupDetails(idOrNo: idOrNo), let nid = detail.Id {
            completion(String(nid)); return
        }
        CASServiceV2.shared.fetchGroupList(pageIndex: 1, pageSize: 200, categoryId: nil) { _ in
            if let detail = CASServiceV2.shared.getCachedGroupDetails(idOrNo: idOrNo), let nid = detail.Id {
                completion(String(nid))
            } else {
                completion(idOrNo)
            }
        }
    }

    // MARK: - AI Suggestion

    @MainActor
    func fetchLLMSuggestion() {
        // Check if user should see the disclaimer first
        if !DisclaimerManager.shared.hasShownReflectionSuggestionDisclaimer {
            showFirstTimeSuggestionAlert = true
            return
        }

        // Validate learning outcomes are selected
        let loNames = getSelectedLearningOutcomes()
        guard !loNames.isEmpty else {
            errorMessage = "Select at least one outcome"
            return
        }

        // Get club name and context
        let clubName = getClubName()
        let currentTitle = title.trimmingCharacters(in: .whitespaces)
        let currentSummary = summary.trimmingCharacters(in: .whitespaces)
        let currentContent = content.trimmingCharacters(in: .whitespaces)

        // Save original state to enable reverting
        isFetchingSuggestion = true
        suggestionError = nil
        originalTitle = title
        originalContent = content

        Task {
            do {
                // Check if this is a conversation reflection (ID 92)
                let isConversation = selectedGroupId == altGroupId

                // Request the AI suggestion
                let (suggestionTitle, suggestionSummary, suggestionContent) =
                    try await llmService.suggestFullReflection(
                        learningOutcomes: loNames,
                        clubName: clubName,
                        currentTitle: currentTitle,
                        currentSummary: currentSummary,
                        currentContent: currentContent,
                        isConversation: isConversation
                    )

                // Update the content with the suggestion
                title = suggestionTitle
                summary = suggestionSummary
                content = suggestionContent
                canRevertSuggestion = true

                // Show the after-suggestion disclaimer
                showCompletedSuggestionAlert = true
            } catch {
                suggestionError = error.localizedDescription
            }
            isFetchingSuggestion = false
        }
    }

    /// Get all selected learning outcomes as a comma-separated string
    private func getSelectedLearningOutcomes() -> String {
        [
            lo1 ? "Awareness" : nil,
            lo2 ? "Challenge" : nil,
            lo3 ? "Initiative" : nil,
            lo4 ? "Collaboration" : nil,
            lo5 ? "Commitment" : nil,
            lo6 ? "Global Value" : nil,
            lo7 ? "Ethics" : nil,
            lo8 ? "New Skills" : nil
        ].compactMap { $0 }.joined(separator: ", ")
    }

    /// Map first selected outcome to server numeric code (1..8)
    private func getSelectedOutcomeCode() -> String? {
        if lo1 { return "1" }
        if lo2 { return "2" }
        if lo3 { return "3" }
        if lo4 { return "4" }
        if lo5 { return "5" }
        if lo6 { return "6" }
        if lo7 { return "7" }
        if lo8 { return "8" }
        return nil
    }

    /// Get the club name from the selected group
    private func getClubName() -> String {
        if let group = availableGroups.first(where: { $0.id == selectedGroupId }) {
            switch group {
            case let .club(club): return club.C_NameE
            case let .noGroup(nogroup): return nogroup.C_NameE
            }
        }
        return ""
    }

    func dismissFirstTimeSuggestionAlert() {
        // Mark that we've shown the disclaimer
        DisclaimerManager.shared.markReflectionSuggestionDisclaimerAsShown()
        showFirstTimeSuggestionAlert = false

        // Now proceed with the suggestion
        Task { @MainActor in
            fetchLLMSuggestion()
        }
    }

    func dismissCompletedSuggestionAlert() {
        showCompletedSuggestionAlert = false
    }

    func revertSuggestion() {
        if let t = originalTitle { title = t }
        if let c = originalContent { content = c }
        canRevertSuggestion = false
    }
}

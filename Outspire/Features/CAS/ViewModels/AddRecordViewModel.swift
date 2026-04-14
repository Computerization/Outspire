import Combine
import Foundation
import SwiftUI

@MainActor
class AddRecordViewModel: ObservableObject {
    @Published var selectedGroupId: String = ""
    @Published var activityDate = Date()
    @Published var activityTitle: String = ""
    @Published var durationC: Int = 0
    @Published var durationA: Int = 0
    @Published var durationS: Int = 0
    @Published var activityDescription: String = ""
    @Published var errorMessage: String?
    @Published var isSaving: Bool = false
    @Published var saveSucceeded: Bool = false

    // LLM Suggestion State
    @Published var isFetchingSuggestion: Bool = false
    @Published var suggestionError: String?
    @Published var canRevertSuggestion: Bool = false
    @Published var showFirstTimeSuggestionAlert: Bool = false
    @Published var showCompletedSuggestionAlert: Bool = false

    private var originalTitleBeforeSuggestion: String?
    private var originalDescriptionBeforeSuggestion: String?

    // Dependencies
    let clubActivitiesViewModel: ClubActivitiesViewModel
    let llmService: LLMService

    let availableGroups: [ClubGroup]
    let loggedInStudentId: String
    let onSave: () -> Void

    private let authV2 = AuthServiceV2.shared
    private static var cachedFormData: FormCache?
    private var cancellables = Set<AnyCancellable>()

    /// Store form data for persistent recovery
    struct FormCache {
        let groupId: String
        let date: Date
        let title: String
        let durationC: Int
        let durationA: Int
        let durationS: Int
        let description: String
    }

    var totalDuration: Int {
        durationC + durationA + durationS
    }

    /// Calculate word count for the description (TSIMS requires words)
    var descriptionWordCount: Int {
        activityDescription.split(whereSeparator: { $0.isWhitespace }).count
    }

    init(
        availableGroups: [ClubGroup],
        loggedInStudentId: String,
        onSave: @escaping () -> Void,
        clubActivitiesViewModel: ClubActivitiesViewModel,
        llmService: LLMService = LLMService()
    ) {
        self.availableGroups = availableGroups
        self.loggedInStudentId = loggedInStudentId
        self.onSave = onSave
        self.clubActivitiesViewModel = clubActivitiesViewModel
        self.llmService = llmService

        // Try to restore from cache first
        if let cache = AddRecordViewModel.cachedFormData {
            self.selectedGroupId = cache.groupId
            self.activityDate = cache.date
            self.activityTitle = cache.title
            self.durationC = cache.durationC
            self.durationA = cache.durationA
            self.durationS = cache.durationS
            self.activityDescription = cache.description
        } else if let firstGroup = availableGroups.first {
            // Default first option if no cache
            self.selectedGroupId = firstGroup.C_GroupsID
        }

        // Set up publishers to monitor form changes
        setupPublishers()

        // Clear Cache when Receiving Notification
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ClearCachedFormData"),
            object: nil,
            queue: .main
        ) { _ in
            // Clear the cached form data
            Self.cachedFormData = nil
        }
    }

    // MARK: - LLM Suggestion

    @MainActor
    func fetchLLMSuggestion() {
        // Check if user should see the disclaimer first
        if !DisclaimerManager.shared.hasShownRecordSuggestionDisclaimer {
            showFirstTimeSuggestionAlert = true
            return
        }

        // Save originals before AI edit
        isFetchingSuggestion = true
        suggestionError = nil
        originalTitleBeforeSuggestion = activityTitle
        originalDescriptionBeforeSuggestion = activityDescription

        // Get suggestion context
        let userInput = activityTitle
        let pastRecords = Array(clubActivitiesViewModel.activities.prefix(3))

        Task {
            do {
                // Compute club name from selected group
                let selectedGroup = availableGroups.first { $0.C_GroupsID == selectedGroupId }
                let clubNameValue = (selectedGroup?.C_NameE.isEmpty ?? true) ? selectedGroup?
                    .C_NameC ?? "" : selectedGroup?.C_NameE ?? ""
                // Request the AI suggestion
                let suggestion = try await llmService.suggestCasRecord(
                    userInput: userInput,
                    pastRecords: pastRecords,
                    clubName: clubNameValue
                )

                // Update content with suggestion
                if let title = suggestion.title, !title.isEmpty {
                    self.activityTitle = title
                }
                if let desc = suggestion.description, !desc.isEmpty {
                    self.activityDescription = desc
                }
                self.canRevertSuggestion = true

                // Show the post-suggestion disclaimer
                self.showCompletedSuggestionAlert = true
            } catch {
                self.suggestionError = error.localizedDescription
                self.canRevertSuggestion = false
            }
            self.isFetchingSuggestion = false
        }
    }

    func revertSuggestion() {
        if let originalTitle = originalTitleBeforeSuggestion {
            activityTitle = originalTitle
        }
        if let originalDesc = originalDescriptionBeforeSuggestion {
            activityDescription = originalDesc
        }
        canRevertSuggestion = false
    }

    private func setupPublishers() {
        // Combine all form field publishers to update cache on any change
        Publishers.CombineLatest4(
            $selectedGroupId,
            $activityDate,
            $activityTitle,
            Publishers.CombineLatest3($durationC, $durationA, $durationS)
        )
        .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
        .sink { [weak self] _, _, _, _ in
            self?.cacheFormData()
        }
        .store(in: &cancellables)

        $activityDescription
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.cacheFormData()
            }
            .store(in: &cancellables)
    }

    func validateDuration() {
        if totalDuration > 10 {
            errorMessage = "Max 10h total"
            durationC = 0
            durationA = 0
            durationS = 0
        } else {
            errorMessage = nil
        }
    }

    /// Cache current form data automatically
    func cacheFormData() {
        // Only cache if there's meaningful data
        if !activityTitle.isEmpty || !activityDescription.isEmpty || totalDuration > 0 {
            AddRecordViewModel.cachedFormData = FormCache(
                groupId: selectedGroupId,
                date: activityDate,
                title: activityTitle,
                durationC: durationC,
                durationA: durationA,
                durationS: durationS,
                description: activityDescription
            )
        }
    }

    /// Clear the cache after successful submission
    func clearCache() {
        AddRecordViewModel.cachedFormData = nil
    }

    /// Clear all form fields and cache
    func clearForm() {
        selectedGroupId = availableGroups.first?.C_GroupsID ?? ""
        activityDate = Date()
        activityTitle = ""
        durationC = 0
        durationA = 0
        durationS = 0
        activityDescription = ""
        errorMessage = nil
        suggestionError = nil
        canRevertSuggestion = false
        originalTitleBeforeSuggestion = nil
        originalDescriptionBeforeSuggestion = nil
        AddRecordViewModel.cachedFormData = nil
    }

    func saveRecord() {
        guard !selectedGroupId.isEmpty,
              !activityTitle.isEmpty,
              !activityDescription.isEmpty,
              descriptionWordCount >= 80,
              totalDuration > 0
        else {
            errorMessage = "Fill all fields; ≥80 words"
            return
        }

        isSaving = true
        saveSucceeded = false

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let activityDateString = dateFormatter.string(from: activityDate)

        // Map GroupNo -> numeric Id if needed before save
        resolveNumericGroupId(selectedGroupId) { mappedId in
            let form: [String: String] = [
                "id": "0",
                "GroupId": mappedId,
                "ActivityDate": activityDateString,
                "Theme": self.activityTitle,
                "CDuration": String(self.durationC),
                "ADuration": String(self.durationA),
                "SDuration": String(self.durationS),
                "Reflection": self.activityDescription
            ]
            TSIMSClientV2.shared.postForm(path: "/Stu/Cas/SaveRecord", form: form) { [weak self] (result: Result<
                ApiResponse<String>,
                NetworkError
            >) in
                guard let self else { return }
                switch result {
                case let .success(env):
                    if env.isSuccess {
                        self.clearCache()
                        self.onSave()
                        self.saveSucceeded = true
                        self.isSaving = false
                    } else {
                        self.errorMessage = "Save failed"
                        self.isSaving = false
                    }
                case let .failure(err):
                    _ = err // swallow long message
                    self.errorMessage = "Network error"
                    self.isSaving = false
                }
            }
        }
    }

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

    // MARK: - Disclaimer Methods

    func dismissFirstTimeSuggestionAlert() {
        // Mark that we've shown the disclaimer
        DisclaimerManager.shared.markRecordSuggestionDisclaimerAsShown()
        showFirstTimeSuggestionAlert = false

        // Now proceed with the suggestion
        Task { @MainActor in
            fetchLLMSuggestion()
        }
    }

    func dismissCompletedSuggestionAlert() {
        showCompletedSuggestionAlert = false
    }
}

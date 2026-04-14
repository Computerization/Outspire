import SwiftUI

@MainActor
class ClubActivitiesViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var groups: [ClubGroup] = []
    @Published var activities: [ActivityRecord] = []
    @Published var selectedGroupId: String = ""
    @Published var errorMessage: String?
    @Published var isLoadingGroups: Bool = false
    @Published var isLoadingActivities: Bool = false
    @Published var showingDeleteConfirmation = false
    @Published var recordToDelete: ActivityRecord?

    // MARK: - Private Properties

    private var hasAttemptedInitialLoad = false
    private var cachedActivities: [String: [ActivityRecord]] = [:]
    private let cacheTimestampKey = "clubActivitiesCacheTimestamp"
    private let cacheDuration: TimeInterval = 300
    private let authV2 = AuthServiceV2.shared

    // MARK: - Initialization

    init() {
        loadInitialCachedData()
    }

    private func loadInitialCachedData() {
        guard let cachedGroupsData = UserDefaults.standard.data(forKey: "cachedClubGroups"),
              let decodedGroups = try? JSONDecoder().decode([ClubGroup].self, from: cachedGroupsData)
        else {
            return
        }

        self.groups = decodedGroups

        if let savedGroupId = UserDefaults.standard.string(forKey: "selectedClubGroupId"),
           CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: savedGroupId))
        {
            self.selectedGroupId = savedGroupId
            loadCachedActivities(for: savedGroupId)
        } else if let firstGroup = decodedGroups.first {
            self.selectedGroupId = firstGroup.C_GroupsID
        }
    }

    // MARK: - Cache Management

    private func loadCachedActivities(for groupId: String) {
        guard let cachedData = UserDefaults.standard.data(forKey: "cachedActivities-\(groupId)"),
              let decodedActivities = try? JSONDecoder().decode([ActivityRecord].self, from: cachedData)
        else {
            return
        }
        self.activities = decodedActivities
    }

    private func cacheActivities(for groupId: String, activities: [ActivityRecord]) {
        guard let encodedData = try? JSONEncoder().encode(activities) else { return }
        UserDefaults.standard.set(encodedData, forKey: "cachedActivities-\(groupId)")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: cacheTimestampKey)
    }

    private func cacheGroups(_ groups: [ClubGroup]) {
        guard let encodedData = try? JSONEncoder().encode(groups) else { return }
        UserDefaults.standard.set(encodedData, forKey: "cachedClubGroups")
    }

    func isCacheValid() -> Bool {
        let lastUpdate = UserDefaults.standard.double(forKey: cacheTimestampKey)
        let currentTime = Date().timeIntervalSince1970
        return (currentTime - lastUpdate) < cacheDuration
    }

    // MARK: - Network Operations

    @MainActor
    func fetchGroupsAsync(forceRefresh: Bool = false) async {
        await withCheckedContinuation { continuation in
            fetchGroups(forceRefresh: forceRefresh)
            continuation.resume()
        }
    }

    @MainActor
    func fetchActivityRecordsAsync(forceRefresh: Bool = false) async {
        await withCheckedContinuation { continuation in
            fetchActivityRecords(forceRefresh: forceRefresh)
            continuation.resume()
        }
    }

    func fetchGroups(forceRefresh: Bool = false) {
        if !forceRefresh, !groups.isEmpty { return }
        guard !isLoadingGroups else { return }

        isLoadingGroups = true
        errorMessage = nil

        performGroupsRequest()
    }

    private func performGroupsRequest() {
        CASServiceV2.shared.fetchMyGroups { [weak self] res in
            switch res {
            case let .success(groups):
                self?.handleGroupsResponse(.success(GroupDropdownResponse(groups: groups, nogroups: nil)))
            case let .failure(err):
                self?.handleGroupsResponse(.failure(err))
            }
        }
    }

    private func handleGroupsResponse(_ result: Result<GroupDropdownResponse, NetworkError>) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isLoadingGroups = false
            self.hasAttemptedInitialLoad = true

            switch result {
            case let .success(response):
                self.processSuccessfulGroupsResponse(response)
            case let .failure(error):
                self.errorMessage = "\(error.localizedDescription)"
            }
        }
    }

    private func processSuccessfulGroupsResponse(_ response: GroupDropdownResponse) {
        self.groups = response.groups
        self.cacheGroups(response.groups)

        if self.selectedGroupId.isEmpty, let firstGroup = self.groups.first {
            self.selectedGroupId = firstGroup.C_GroupsID
            UserDefaults.standard.set(firstGroup.C_GroupsID, forKey: "selectedClubGroupId")
            self.fetchActivityRecords()
        } else if !self.selectedGroupId.isEmpty {
            self.fetchActivityRecords()
        } else if self.groups.isEmpty {
            // No groups found; show all records as a fallback
            self.fetchActivityRecords()
        }
    }

    func fetchActivityRecords(forceRefresh: Bool = false) {
        if !forceRefresh, isLoadingActivities { return }
        if !forceRefresh, isCacheValid() {
            loadCachedActivities(for: selectedGroupId)
        }

        isLoadingActivities = true
        errorMessage = nil

        performActivitiesRequest()
    }

    private func performActivitiesRequest() {
        UserDefaults.standard.set(selectedGroupId, forKey: "selectedClubGroupId")
        // Allow empty groupId to fetch all records (server supports this)
        let currentGroup = selectedGroupId
        resolveNumericGroupId(currentGroup) { mappedId in
            CASServiceV2.shared.fetchRecords(groupId: mappedId) { [weak self] res in
                switch res {
                case let .success(records):
                    // Show exactly the filtered result; do not auto-fallback to "all"
                    self?.handleActivitiesResponse(.success(ActivityResponse(casRecord: records)))
                case let .failure(err):
                    self?.handleActivitiesResponse(.failure(err))
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

    private func handleActivitiesResponse(_ result: Result<ActivityResponse, NetworkError>) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            self.isLoadingActivities = false

            switch result {
            case let .success(response):
                withAnimation {
                    self.activities = response.casRecord
                    self.cacheActivities(for: self.selectedGroupId, activities: response.casRecord)
                }
            case let .failure(error):
                switch error {
                case .unauthorized: self.errorMessage = "Session expired"
                default: self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func deleteRecord(record: ActivityRecord) {
        errorMessage = nil
        HapticManager.shared.playFeedback(.medium)
        CASServiceV2.shared.deleteRecord(id: record.C_ARecordID) { [weak self] res in
            switch res {
            case let .success(ok):
                if ok {
                    self?.processDeleteSuccess(["status": "ok"], recordId: record.C_ARecordID)
                } else {
                    self?.errorMessage = "Delete failed"
                }
            case let .failure(err):
                self?.errorMessage = err.localizedDescription
            }
        }
    }

    // Legacy PHP deletion path removed in favor of TSIMS V2 API

    private func processDeleteSuccess(_ response: [String: String], recordId: String) {
        if response["status"] == "ok" {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self.activities.removeAll { $0.C_ARecordID == recordId }
                self.cacheActivities(for: self.selectedGroupId, activities: self.activities)
            }
        } else {
            self.errorMessage = response["status"] ?? "Unknown error"
        }
    }

    // MARK: - Copy Functions

    /// showTemporaryMessage duplicate in ClubActivitiesView
    func copyTitle(_ activity: ActivityRecord) {
        HapticManager.shared.playFeedback(.light)
        UIPasteboard.general.string = activity.C_Theme
    }

    func copyReflection(_ activity: ActivityRecord) {
        HapticManager.shared.playFeedback(.light)
        UIPasteboard.general.string = activity.C_Reflection
    }

    func copyAll(_ activity: ActivityRecord) {
        HapticManager.shared.playFeedback(.light)
        let activityInfo = formatActivityInfo(activity)
        UIPasteboard.general.string = activityInfo
    }

    private func formatActivityInfo(_ activity: ActivityRecord) -> String {
        """
        Theme: \(activity.C_Theme)
        Date: \(activity.C_Date)
        Duration: C: \(activity.C_DurationC), A: \(activity.C_DurationA), S: \(activity.C_DurationS)
        Reflection: \(activity.C_Reflection)
        """
    }

    private func showTemporaryMessage(_ message: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            errorMessage = message
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            withAnimation(.easeOut(duration: 0.3)) {
                if self?.errorMessage == message {
                    self?.errorMessage = nil
                }
            }
        }
    }

    func setSelectedGroupById(_ groupId: String) {
        guard !groupId.isEmpty else { return }

        // If the group exists in the loaded list, select and refresh
        if groups.contains(where: { $0.C_GroupsID == groupId }) {
            selectedGroupId = groupId
            UserDefaults.standard.set(groupId, forKey: "selectedClubGroupId")
            fetchActivityRecords(forceRefresh: true)
        } else if groups.isEmpty {
            // If groups are not loaded yet, store the ID for later
            selectedGroupId = groupId
            UserDefaults.standard.set(groupId, forKey: "selectedClubGroupId")
            // Groups will be loaded when fetchGroups is called
        }
    }
}

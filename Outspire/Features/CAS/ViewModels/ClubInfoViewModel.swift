import SwiftSoup
import SwiftUI

@MainActor
class ClubInfoViewModel: ObservableObject {
    @Published var selectedCategory: Category?
    @Published var selectedGroup: ClubGroup?
    @Published var categories: [Category] = []
    @Published var groups: [ClubGroup] = []
    @Published var groupInfo: GroupInfo?
    @Published var members: [Member] = []
    @Published var memberLoadError: String?
    @Published var instructorName: String?
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false
    @Published var refreshing: Bool = false
    @Published var isJoiningClub: Bool = false
    @Published var isExitingClub: Bool = false
    @Published var isUserMember: Bool = false
    @Published var pendingClubId: String?
    @Published var isFromURLNavigation: Bool = false

    private let authV2 = AuthServiceV2.shared

    func fetchCategories() {
        // New TSIMS: static category map
        isLoading = true
        errorMessage = nil
        let mapped: [Category] = [
            Category(C_CategoryID: "0", C_Category: "All"),
            Category(C_CategoryID: "1", C_Category: "Sports"),
            Category(C_CategoryID: "2", C_Category: "Service"),
            Category(C_CategoryID: "3", C_Category: "Arts"),
            Category(C_CategoryID: "4", C_Category: "Life"),
            Category(C_CategoryID: "5", C_Category: "Academic"),
            Category(C_CategoryID: "6", C_Category: "Personal")
        ]
        self.categories = mapped
        self.isLoading = false
        // Default to All to allow browsing without selecting a category
        if self.selectedCategory == nil, let def = mapped.first(where: { $0.C_CategoryID == "0" }) {
            self.selectedCategory = def
            self.fetchGroups(for: def)
        }
    }

    func fetchGroups(for category: Category) {
        isLoading = true
        errorMessage = nil

        // Store the current selection before fetching new groups
        let previousSelection = selectedGroup?.C_GroupsID

        // Track if we're in the middle of a URL navigation
        let isNavigatingFromURL = pendingClubId != nil || isFromURLNavigation

        let cat = (category.C_CategoryID == "0" || category.C_CategoryID.isEmpty) ? nil : category.C_CategoryID
        CASServiceV2.shared.fetchGroupList(pageIndex: 1, pageSize: 200, categoryId: cat) { [weak self] result in
            guard let self else { return }
            self.isLoading = false

            switch result {
            case let .success(groups):
                self.groups = groups

                // Check for pending club ID from URL scheme first
                if let pendingId = self.pendingClubId,
                   let targetGroup = groups.first(where: { $0.C_GroupsID == pendingId })
                {
                    print("Found pending club with ID: \(pendingId) in category \(category.C_Category)")
                    self.selectedGroup = targetGroup
                    self.fetchGroupInfo(for: targetGroup)
                    self.pendingClubId = nil

                    // Keep isFromURLNavigation true while we're fetching group info
                    // Will be reset in fetchGroupInfo completion

                    return
                }

                // If we have a pending ID but didn't find it in current category,
                // try the next one systematically
                if let pendingId = self.pendingClubId {
                    let currentCategoryIndex = self.categories
                        .firstIndex(where: { $0.C_CategoryID == category.C_CategoryID }) ?? -1
                    if currentCategoryIndex < self.categories.count - 1 {
                        // Try the next category
                        let nextCategoryIndex = currentCategoryIndex + 1
                        print(
                            "Club \(pendingId) not found in \(category.C_Category), trying \(self.categories[nextCategoryIndex].C_Category)"
                        )
                        DispatchQueue.main.async {
                            self.selectedCategory = self.categories[nextCategoryIndex]
                            self.fetchGroups(for: self.categories[nextCategoryIndex])
                        }
                        return
                    } else {
                        // We've searched all categories and didn't find the club
                        print("Club \(pendingId) not found in any category after complete search")
                        self.pendingClubId = nil
                        self.isFromURLNavigation = false
                        self.errorMessage = "Club not found. It may have been removed or you may not have access."
                    }
                }

                // Try to preserve previous selection
                if self.isFromURLNavigation {
                    // Don't change selection if we're coming from URL navigation
                    print("Keeping current selection due to URL navigation")
                    return
                } else if let previousId = previousSelection,
                          let previousGroup = groups.first(where: { $0.C_GroupsID == previousId })
                {
                    self.selectedGroup = previousGroup
                    self.fetchGroupInfo(for: previousGroup)
                    return
                }

                // Only apply auto-selection if we're not in the middle of a URL navigation
                if !isNavigatingFromURL {
                    #if targetEnvironment(macCatalyst)
                        // On Mac Catalyst, immediately set selection to avoid "Unavailable" display
                        if self.selectedGroup == nil, !groups.isEmpty {
                            // Use main queue to ensure proper UI update
                            DispatchQueue.main.async {
                                let pick = groups.randomElement() ?? groups[0]
                                self.selectedGroup = pick
                                self.fetchGroupInfo(for: pick)
                            }
                        }
                    #else
                        // When category changes, reset the selectedGroup and show the "Select" option
                        self.selectedGroup = nil

                        // Auto-select first group if available
                        if !groups.isEmpty {
                            // Use a small delay to ensure UI updates properly
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                let pick = groups.randomElement() ?? groups[0]
                                self.selectedGroup = pick
                                self.fetchGroupInfo(for: pick)
                            }
                        }
                    #endif
                }

            case let .failure(error):
                self.errorMessage = "Unable to load groups: \(error.localizedDescription)"
            }
        }
    }

    func fetchGroupInfo(for group: ClubGroup) {
        isLoading = true
        errorMessage = nil

        // New TSIMS: enrich detail from cached group list item
        let detail = CASServiceV2.shared.getCachedGroupDetails(idOrNo: group.C_GroupsID) ??
            CASServiceV2.shared.getCachedGroupDetails(idOrNo: group.C_GroupNo)

        let info = GroupInfo(
            C_GroupsID: group.C_GroupsID,
            C_GroupNo: group.C_GroupNo,
            C_NameC: group.C_NameC,
            C_NameE: group.C_NameE,
            C_Category: selectedCategory?.C_Category ?? "",
            C_CategoryID: selectedCategory?.C_CategoryID ?? "",
            // Use YearName as founded; fallback to empty
            C_FoundTime: detail?.YearName ?? "",
            C_DescriptionC: detail?.DescriptionC ?? "",
            C_DescriptionE: detail?.DescriptionE ?? ""
        )
        self.groupInfo = info
        self.instructorName = detail?.TeacherName
        self.members = []
        self.memberLoadError = nil

        // Two async fetches run in parallel; DispatchGroup gates `isLoading` until both complete.
        let loadGroup = DispatchGroup()

        // Determine membership by checking MyGroups (match by Id or GroupNo)
        loadGroup.enter()
        CASServiceV2.shared.fetchMyGroups { [weak self] res in
            guard let self else { return }
            switch res {
            case let .success(myGroups):
                let targetKeys = Set([group.C_GroupsID, group.C_GroupNo].filter { !$0.isEmpty })
                let myKeys = Set(myGroups.flatMap { [$0.C_GroupsID, $0.C_GroupNo] }.filter { !$0.isEmpty })
                self.isUserMember = !targetKeys.isDisjoint(with: myKeys)
            case .failure:
                self.isUserMember = false
            }
            loadGroup.leave()
        }

        // Fetch the rendered GroupDetail page for Supervisor / President / members.
        // Some endpoints accept numeric group IDs while others accept group numbers, so retry
        // with both identifiers before surfacing an error.
        var detailIdentifiers: [String] = []
        for id in [group.C_GroupsID, group.C_GroupNo] where !id.isEmpty {
            if !detailIdentifiers.contains(id) { detailIdentifiers.append(id) }
        }
        var lastDetailError: NetworkError?
        loadGroup.enter()
        func loadGroupDetail(using identifiers: [String], index: Int = 0) {
            guard index < identifiers.count else {
                if let lastDetailError {
                    self.memberLoadError = "Unable to load the member roster: \(lastDetailError.localizedDescription)"
                } else {
                    self.memberLoadError = "Unable to load the member roster for this club."
                }
                loadGroup.leave()
                return
            }

            CASServiceV2.shared.fetchGroupDetail(groupId: identifiers[index]) { [weak self] res in
                guard let self else { return }

                switch res {
                case let .success(parsed):
                    var roster: [Member] = []
                    if let pres = parsed.president { roster.append(pres) }
                    roster.append(contentsOf: parsed.members)
                    self.members = roster
                    if roster.isEmpty {
                        if Configuration.debugNetworkLogging, !parsed.debugSections.isEmpty {
                            self.memberLoadError = "Parsed detail but found no members. Sections: \(parsed.debugSections.joined(separator: " | "))"
                        } else {
                            self.memberLoadError = "Parsed detail but found no members for this club."
                        }
                    } else {
                        self.memberLoadError = nil
                    }
                    if let sup = parsed.supervisor?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !sup.isEmpty
                    {
                        self.instructorName = sup
                    }
                    loadGroup.leave()
                case let .failure(error):
                    lastDetailError = error
                    loadGroupDetail(using: identifiers, index: index + 1)
                }
            }
        }

        loadGroupDetail(using: detailIdentifiers)

        loadGroup.notify(queue: .main) { [weak self] in
            guard let self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.isLoading = false
                self.isFromURLNavigation = false
            }
        }
    }

    private func retryFetchWithSession(parameters: [String: String]) { /* no-op in V2 */ }

    /// Check if current user is a member of this club
    private func checkUserMembership() {
        guard authV2.isAuthenticated,
              let currentUserId = authV2.user?.userCode
        else {
            isUserMember = false
            return
        }

        let newMembershipStatus = members.contains { member in
            member.StudentID == currentUserId
        }

        // Only update if there's a change to avoid triggering onChange unnecessarily
        if isUserMember != newMembershipStatus {
            isUserMember = newMembershipStatus
        }
    }

    func joinClub(asProject: Bool) {
        guard authV2.isAuthenticated,
              let currentGroup = selectedGroup
        else {
            errorMessage = "You need to be signed in and have a club selected"
            return
        }

        isJoiningClub = true

        CASServiceV2.shared.joinGroup(groupId: currentGroup.C_GroupsID, isProject: asProject) { [weak self] result in
            guard let self else { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isJoiningClub = false

                switch result {
                case let .success(ok):
                    if ok {
                        // Refresh club info to update membership status
                        if let currentGroup = self.selectedGroup {
                            self.fetchGroupInfo(for: currentGroup)
                        }

                        // Clear club activities cache to ensure fresh data on next view
                        CacheManager.clearClubActivitiesCache()
                    } else {
                        self.errorMessage = "Failed to join club"
                    }
                case let .failure(error):
                    self.errorMessage = "Failed to join club: \(error.localizedDescription)"
                }
            }
        }
    }

    func exitClub() {
        guard authV2.isAuthenticated,
              let currentGroup = selectedGroup
        else {
            errorMessage = "You need to be signed in and have a club selected"
            return
        }

        isExitingClub = true

        CASServiceV2.shared.exitGroup(groupId: currentGroup.C_GroupsID) { [weak self] result in
            guard let self else { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isExitingClub = false

                switch result {
                case let .success(ok):
                    if ok {
                        // Refresh club info to update membership status
                        if let currentGroup = self.selectedGroup {
                            self.fetchGroupInfo(for: currentGroup)
                        }

                        // Clear club activities cache to ensure fresh data on next view
                        CacheManager.clearClubActivitiesCache()
                    } else {
                        self.errorMessage = "Failed to exit club"
                    }
                case let .failure(error):
                    self.errorMessage = "Failed to exit club: \(error.localizedDescription)"
                }
            }
        }
    }

    func extractText(from html: String) -> String? {
        do {
            let doc: Document = try SwiftSoup.parse(html)

            // Remove <a> Tags
            // lol this is for you, q1zhen
            let links: Elements = try doc.select("a")
            for link in links {
                try link.remove()
            }

            // Trim Texts
            let text = try doc.text()
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : text
        } catch {
            print("Error parsing HTML: \(error)")
            return nil
        }
    }

    /// Add a method to handle URL navigation requests
    func navigateToClubById(_ clubId: String) {
        print("Navigating to club ID: \(clubId)")

        // Reset any existing club info to prevent UI confusion
        if selectedGroup?.C_GroupsID != clubId {
            groupInfo = nil
            members = []
        }

        // Set URL navigation flags
        isFromURLNavigation = true

        // Use V2 group list to find the group quickly
        CASServiceV2.shared.fetchGroupList(pageIndex: 1, pageSize: 200, categoryId: nil) { [weak self] res in
            guard let self else { return }
            DispatchQueue.main.async {
                switch res {
                case let .success(list):
                    if let group = list.first(where: { $0.C_GroupsID == clubId || $0.C_GroupNo == clubId }) {
                        self.selectedGroup = group
                        self.fetchGroupInfo(for: group)
                    } else {
                        self.errorMessage = "Club not found"
                    }
                case let .failure(err):
                    self.errorMessage = err.localizedDescription
                }
            }
        }
    }

    // v2-only: fetch club info by ID using v2 group list + detail mapping
    func fetchGroupInfoById(_ clubId: String) {
        isLoading = true
        errorMessage = nil

        CASServiceV2.shared.fetchGroupList(pageIndex: 1, pageSize: 200, categoryId: nil) { [weak self] res in
            guard let self else { return }
            DispatchQueue.main.async {
                switch res {
                case let .success(list):
                    if let group = list.first(where: { $0.C_GroupsID == clubId || $0.C_GroupNo == clubId }) {
                        self.selectedGroup = group
                        self.fetchGroupInfo(for: group)
                    } else {
                        self.errorMessage = "Club not found"
                        self.isLoading = false
                    }
                case let .failure(err):
                    self.errorMessage = err.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    /// Helper method to fetch groups for a category with a preselected club
    private func fetchGroupsForCategory(_ category: Category, preselectedGroupId: String) {
        CASServiceV2.shared
            .fetchGroupList(pageIndex: 1, pageSize: 200, categoryId: category.C_CategoryID) { [weak self] result in
                guard let self else { return }

                DispatchQueue.main.async {
                    switch result {
                    case let .success(groups):
                        self.groups = groups

                        // If we already have a group selected, ensure it's in the list
                        if self.selectedGroup?.C_GroupsID == preselectedGroupId {
                            // Find a more complete version of the group in the loaded groups
                            if let fullGroup = groups.first(where: { $0.C_GroupsID == preselectedGroupId }) {
                                self.selectedGroup = fullGroup
                            }
                        }
                    case let .failure(error):
                        print("Failed to load groups for category: \(error.localizedDescription)")
                        // Don't set error message here as we already have the club info displayed
                    }
                }
            }
    }

    /// Helper to fetch categories with a preselection
    private func fetchCategoriesWithPreselection(clubId: String, categoryId: String?) {
        // In V2, categories are static
        self.categories = [
            Category(C_CategoryID: "1", C_Category: "Sports"),
            Category(C_CategoryID: "2", C_Category: "Service"),
            Category(C_CategoryID: "3", C_Category: "Arts"),
            Category(C_CategoryID: "4", C_Category: "Life"),
            Category(C_CategoryID: "5", C_Category: "Academic"),
            Category(C_CategoryID: "6", C_Category: "Personal")
        ]
        if let categoryId,
           let category = self.categories.first(where: { $0.C_CategoryID == categoryId })
        {
            self.selectedCategory = category
            self.fetchGroupsForCategory(category, preselectedGroupId: clubId)
        }
    }

    /// Fallback method to search for a club across all categories
    private func searchClubInCategories(clubId: String) {
        guard !categories.isEmpty else {
            // Can't search without categories
            self.fetchCategories()
            return
        }

        print("Starting systematic search for club \(clubId) across all categories")

        // Start with the first category
        self.selectedCategory = categories[0]
        self.fetchGroups(for: categories[0])
    }
}

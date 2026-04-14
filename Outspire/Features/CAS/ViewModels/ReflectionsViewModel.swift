import SwiftUI

/// ViewModel for managing reflections list and deletion in CAS feature.
enum ReflectionGroup: Identifiable, Hashable {
    case club(ClubGroup)
    case noGroup(NoGroup)

    var id: String {
        switch self {
        case let .club(group): group.C_GroupsID
        case let .noGroup(group): group.C_GroupsID
        }
    }

    var displayName: String {
        switch self {
        case let .club(group):
            if !group.C_NameE.isEmpty {
                group.C_NameE
            } else {
                group.C_NameC
            }
        case let .noGroup(group):
            if !group.C_NameE.isEmpty {
                group.C_NameE
            } else {
                group.C_NameC
            }
        }
    }
}

@MainActor
class ReflectionsViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var groups: [ReflectionGroup] = []
    @Published var reflections: [Reflection] = []
    @Published var selectedGroupId: String = ""
    @Published var isLoadingGroups = false
    @Published var isLoadingReflections = false
    @Published var errorMessage: String?
    @Published var showingDeleteConfirmation = false
    @Published var reflectionToDelete: Reflection?

    private let authV2 = AuthServiceV2.shared

    // MARK: - Fetch Groups

    func fetchGroups(forceRefresh: Bool = false) {
        if !groups.isEmpty, !forceRefresh { return }
        isLoadingGroups = true
        errorMessage = nil

        // Use CASServiceV2 groups to align with new TSIMS
        CASServiceV2.shared.fetchMyGroups { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoadingGroups = false
                switch result {
                case let .success(groups):
                    let combined: [ReflectionGroup] = groups.map { .club($0) }
                    self?.groups = combined
                    if self?.selectedGroupId.isEmpty == true, let first = combined.first {
                        self?.selectedGroupId = first.id
                        self?.fetchReflections()
                    } else if combined.isEmpty {
                        // No groups; fetch all reflections as fallback
                        self?.selectedGroupId = ""
                        self?.fetchReflections()
                    }
                case let .failure(error):
                    switch error {
                    case .unauthorized: self?.errorMessage = "Session expired"
                    default: self?.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    // MARK: - Fetch Reflections

    func fetchReflections(forceRefresh: Bool = false) {
        if isLoadingReflections, !forceRefresh { return }
        isLoadingReflections = true
        errorMessage = nil

        // Map GroupNo to numeric Id, then fetch
        let currentGroup = selectedGroupId
        resolveNumericGroupId(currentGroup) { mappedId in
            CASServiceV2.shared.fetchReflections(groupId: mappedId) { [weak self] result in
                DispatchQueue.main.async {
                    self?.isLoadingReflections = false
                    switch result {
                    case let .success(reflections):
                        // Show exactly the filtered result; do not auto-fallback to "all"
                        self?.reflections = reflections
                    case let .failure(error):
                        self?.errorMessage = error.localizedDescription
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

    // MARK: - Delete Reflection

    func deleteReflection(_ reflection: Reflection) {
        reflectionToDelete = reflection
        showingDeleteConfirmation = true
    }

    func confirmDelete() {
        guard let reflection = reflectionToDelete else { return }
        isLoadingReflections = true
        errorMessage = nil

        CASServiceV2.shared.deleteReflection(id: reflection.C_RefID) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoadingReflections = false
                self?.showingDeleteConfirmation = false

                switch result {
                case let .success(ok):
                    if ok {
                        self?.reflections.removeAll { $0.C_RefID == reflection.C_RefID }
                    } else {
                        self?.errorMessage = "Delete failed"
                    }
                case let .failure(error):
                    self?.errorMessage = error.localizedDescription
                }
                self?.reflectionToDelete = nil
            }
        }
    }
}

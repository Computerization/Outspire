import LocalAuthentication
import SwiftUI

struct Term: Identifiable, Codable {
    let W_YearID: String
    let W_Year: String
    let W_Term: String

    var id: String {
        W_YearID
    }

    var displayName: String {
        "\(W_Year) Term \(W_Term)"
    }
}

struct Score: Identifiable, Codable {
    let IB_SubjectID: String
    let IB_SubjectE: String
    let S_Name: String
    let Score1: String
    let LScore1: String
    let Score2: String
    let LScore2: String
    let Score3: String
    let LScore3: String
    let Score4: String
    let LScore4: String
    let Score5: String
    let LScore5: String

    var id: String {
        IB_SubjectID
    }

    var subjectName: String {
        IB_SubjectE
    }

    var examScores: [ExamScore] {
        [
            ExamScore(name: "Monthly 1", score: Score1, level: LScore1),
            ExamScore(name: "Mid-term", score: Score2, level: LScore2),
            ExamScore(name: "Monthly 2", score: Score3, level: LScore3),
            ExamScore(name: "Final-term", score: Score4, level: LScore4),
            ExamScore(name: "Homework", score: Score5, level: LScore5)
        ]
    }

    var averageScore: Double {
        let validScores = [Score1, Score2, Score3, Score4].compactMap { Double($0) }.filter {
            $0 > 0
        }
        return validScores.isEmpty ? 0 : validScores.reduce(0, +) / Double(validScores.count)
    }

    var highestScore: String {
        let scores = [Score1, Score2, Score3, Score4]
        return scores.compactMap { Double($0) }.filter { $0 > 0 }.max().map { String($0) } ?? "N/A"
    }
}

struct ExamScore: Identifiable {
    let name: String
    let score: String
    let level: String

    var id: String {
        name
    }

    var hasScore: Bool {
        score != "0" && !score.isEmpty
    }
}

class ScoreViewModel: ObservableObject {
    @Published var isUnlocked: Bool = false
    @Published var errorMessage: String?
    @Published var scores: [Score] = []
    @Published var isLoading: Bool = false
    @Published var terms: [Term] = []
    @Published var isLoadingTerms: Bool = false
    @Published var selectedTermId: String = ""
    @Published var lastUpdateTime: Date = .init()
    @Published var formattedLastUpdateTime: String = ""

    /// Track terms with available data
    @Published var termsWithData: Set<String> = []

    private let cacheDuration: TimeInterval = 300

    init() {
        loadCachedData()
        updateFormattedTimestamp()
    }

    private func updateFormattedTimestamp() {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        self.formattedLastUpdateTime = "Last updated: \(formatter.string(from: lastUpdateTime))"
    }

    private func loadCachedData() {
        // Load cached terms with data
        if let cachedTermsWithData = UserDefaults.standard.array(forKey: "termsWithData")
            as? [String]
        {
            self.termsWithData = Set(cachedTermsWithData)
        }

        if let cachedTermsData = UserDefaults.standard.data(forKey: "cachedTerms"),
           let decodedTerms = try? JSONDecoder().decode([Term].self, from: cachedTermsData)
        {
            self.terms = decodedTerms

            // First try to use the previously selected term if it exists
            if let savedTermId = UserDefaults.standard.string(forKey: "selectedTermId"),
               decodedTerms.contains(where: { $0.W_YearID == savedTermId })
            {
                self.selectedTermId = savedTermId
                loadCachedScores(for: savedTermId)
            }
            // If no saved term or it's not in the list, always select the most recent term
            else if let mostRecentTerm = findMostRecentTerm(from: decodedTerms) {
                self.selectedTermId = mostRecentTerm
                // Only load cached scores if available for this term
                if termsWithData.contains(mostRecentTerm) {
                    loadCachedScores(for: mostRecentTerm)
                }
            }
        }
    }

    private func findMostRecentTermWithData(from terms: [Term]) -> String? {
        // Sort terms by year and term number in descending order
        let sortedTerms = terms.sorted {
            // First compare years
            if $0.W_Year != $1.W_Year {
                return $0.W_Year > $1.W_Year
            }
            // Then compare term numbers
            return $0.W_Term > $1.W_Term
        }

        // Find the first term that has data
        return sortedTerms.first { termsWithData.contains($0.W_YearID) }?.W_YearID
    }

    private func findMostRecentTerm(from terms: [Term]) -> String? {
        // Sort terms by year and term number in descending order
        let sortedTerms = terms.sorted {
            // First compare years
            if $0.W_Year != $1.W_Year {
                return $0.W_Year > $1.W_Year
            }
            // Then compare term numbers
            return $0.W_Term > $1.W_Term
        }

        return sortedTerms.first?.W_YearID
    }

    private func loadCachedScores(for termId: String) {
        // Clear any previous error message when loading new scores
        self.errorMessage = nil

        if let cachedData = UserDefaults.standard.data(forKey: "cachedScores-\(termId)"),
           let decodedScores = try? JSONDecoder().decode([Score].self, from: cachedData)
        {
            self.scores = decodedScores

            // Load cached timestamp
            if let cachedTimestamp = UserDefaults.standard.object(
                forKey: "scoresCacheTimestamp-\(termId)"
            ) as? TimeInterval {
                self.lastUpdateTime = Date(timeIntervalSince1970: cachedTimestamp)
            } else {
                self.lastUpdateTime = Date()
            }

            // Update the formatted timestamp
            updateFormattedTimestamp()

            // Update termsWithData based on whether the cached scores are empty or not
            if !decodedScores.isEmpty {
                termsWithData.insert(termId)
            } else {
                termsWithData.remove(termId)
            }
            UserDefaults.standard.set(Array(termsWithData), forKey: "termsWithData")
        } else {
            // If we can't load cached scores, clear the current scores
            self.scores = []

            // Reset timestamp to current time
            self.lastUpdateTime = Date()
            updateFormattedTimestamp()

            // Also remove this term from termsWithData since we have no data for it
            termsWithData.remove(termId)
            UserDefaults.standard.set(Array(termsWithData), forKey: "termsWithData")
        }
    }

    private func cacheTerms(_ terms: [Term]) {
        if let encodedData = try? JSONEncoder().encode(terms) {
            UserDefaults.standard.set(encodedData, forKey: "cachedTerms")
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "termsCacheTimestamp")
        }
    }

    private func cacheScores(for termId: String, scores: [Score]) {
        if let encodedData = try? JSONEncoder().encode(scores) {
            UserDefaults.standard.set(encodedData, forKey: "cachedScores-\(termId)")

            // Save current timestamp
            let currentTime = Date().timeIntervalSince1970
            UserDefaults.standard.set(currentTime, forKey: "scoresCacheTimestamp-\(termId)")
            self.lastUpdateTime = Date()

            // Update terms with data set
            if !scores.isEmpty {
                // If we got scores, add this term to the terms with data set
                termsWithData.insert(termId)
            } else {
                // If there are no scores, remove this term from the terms with data set
                termsWithData.remove(termId)
            }
            // Update the persisted set
            UserDefaults.standard.set(Array(termsWithData), forKey: "termsWithData")
        }
    }

    func isCacheValid(for key: String) -> Bool {
        let lastUpdate = UserDefaults.standard.double(forKey: key)
        let currentTime = Date().timeIntervalSince1970
        return (currentTime - lastUpdate) < cacheDuration
    }

    func authenticate() {
        let context = LAContext()
        context.localizedFallbackTitle = "Use device password"
        var error: NSError?

        // Set loading state first before authentication
        isLoading = true

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            let reason = "Authentication required for requesting sensitive information."

            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) {
                [weak self] success, authenticationError in
                guard let self else { return }

                // Small delay before updating UI to ensure smooth transitions
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.isLoading = false

                    if success {
                        self.isUnlocked = true
                        self.errorMessage = nil
                        // Add a small delay before fetching terms to ensure smooth animation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self.fetchTerms()
                        }
                    } else {
                        self.isUnlocked = false
                        if let authError = authenticationError {
                            self.errorMessage = "\(authError.localizedDescription)"
                        }
                    }
                }
            }
        } else {
            // Small delay before updating UI to ensure smooth transitions
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.isLoading = false
                self.isUnlocked = false
                self.errorMessage = "Authentication is not available on this device."
            }
        }
    }

    func fetchTerms(forceRefresh: Bool = false) {
        if !forceRefresh, !terms.isEmpty, isCacheValid(for: "termsCacheTimestamp") {
            if selectedTermId.isEmpty, let first = terms.first { selectedTermId = first.W_YearID }
            fetchScores()
            return
        }

        isLoadingTerms = true
        errorMessage = nil

        TimetableServiceV2.shared.fetchYearOptions { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isLoadingTerms = false
                switch result {
                case let .success(years):
                    // Map YearOption -> Term (use W_Term = "All")
                    let mapped: [Term] = years.map { Term(W_YearID: $0.id, W_Year: $0.name, W_Term: "All") }
                    self.terms = mapped
                    self.cacheTerms(mapped)
                    if let first = mapped.first { self.selectedTermId = first.W_YearID }
                    self.fetchScores()
                case let .failure(error):
                    self.errorMessage = "Failed to load years: \(error.localizedDescription)"
                }
            }
        }
    }

    func fetchScores(forceRefresh: Bool = false) {
        guard !selectedTermId.isEmpty else {
            errorMessage = "Please select a term."
            return
        }

        if !forceRefresh, isCacheValid(for: "scoresCacheTimestamp-\(selectedTermId)") {
            loadCachedScores(for: selectedTermId)
            return
        }

        isLoading = true
        errorMessage = nil

        ScoreServiceV2.shared.fetchScores(yearId: selectedTermId) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case let .success(items):
                    // Map v2 scores into legacy Score model (keep 5 slots)
                    let mapped: [Score] = items.enumerated().map { idx, item in
                        Score(
                            IB_SubjectID: "v2-\(idx)",
                            IB_SubjectE: item.subject,
                            S_Name: item.subject,
                            Score1: item.score1,
                            LScore1: item.ibScore1,
                            Score2: item.score2,
                            LScore2: item.ibScore2,
                            Score3: item.score3,
                            LScore3: item.ibScore3,
                            Score4: item.score4,
                            LScore4: item.ibScore4,
                            Score5: item.score5,
                            LScore5: item.ibScore5
                        )
                    }
                    self.scores = mapped
                    self.cacheScores(for: self.selectedTermId, scores: mapped)

                    if mapped.isEmpty {
                        self.errorMessage = "No scores available for this year yet."
                    } else {
                        self.errorMessage = nil
                    }
                case let .failure(error):
                    self.errorMessage = "Failed to load scores: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Helper function to determine appropriate message for empty terms
    private func determineEmptyScoreMessage(for termId: String) {
        // Find the term object to get more context
        guard let term = terms.first(where: { $0.W_YearID == termId }) else {
            self.errorMessage = "No scores available for this term yet."
            return
        }

        // Current date for comparison
        let currentDate = Date()
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: currentDate)

        // Extract year from the term.W_Year (assuming it's in a format that includes the year)
        guard let termYear = Int(term.W_Year) else {
            self.errorMessage = "No scores available for this term yet."
            return
        }

        // Term number for sequence context
        let termNumber = Int(term.W_Term) ?? 0

        // Logic for different messages based on term timing
        if termYear > currentYear {
            // Future term
            self.errorMessage = "This term hasn't started yet."
        } else if termYear < currentYear - 3 {
            // Very old term - likely before student enrolled
            self.errorMessage = "This term occurred before your enrollment."
        } else if termYear == currentYear,
                  termNumber > (calendar.component(.month, from: currentDate) / 4) + 1
        {
            // Current year but future term
            self.errorMessage = "This term hasn't started yet."
        } else {
            // Current or recent term without data
            self.errorMessage = "No scores available for this term yet."
        }
    }

    // Legacy fetchScoresWithNullHandling removed (migrated to TSIMS V2)

    func refreshData() {
        // Clear any error message
        errorMessage = nil

        // Update the last update time immediately to give visual feedback
        lastUpdateTime = Date()
        updateFormattedTimestamp()

        // Force refresh data by fetching terms first
        fetchTerms(forceRefresh: true)
    }

    /// Method to explicitly select the most recent term
    func selectMostRecentTerm() {
        if let mostRecentTerm = findMostRecentTerm(from: terms) {
            // Only change if we're not already on the most recent term
            if selectedTermId != mostRecentTerm {
                selectedTermId = mostRecentTerm
                fetchScores()
            }
        }
    }
}

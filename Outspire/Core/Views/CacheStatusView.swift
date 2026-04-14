import SwiftUI

struct CacheStatusView: View {
    @State private var cacheStatus: CacheStatus?
    @State private var estimatedCacheSize: String = "Calculating..."
    @State private var outdatedCacheCount: Int = 0
    @State private var isRefreshing = false

    var body: some View {
        NavigationView {
            List {
                if let status = cacheStatus {
                    // Overall cache health section
                    Section("Cache Health") {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color(status.overallCacheHealth.color))
                            Text("Overall Status")
                            Spacer()
                            Text(status.overallCacheHealth.description)
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Image(systemName: "externaldrive.fill")
                            Text("Estimated Size")
                            Spacer()
                            Text(estimatedCacheSize)
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Image(systemName: "clock.badge.exclamationmark")
                                .foregroundColor(outdatedCacheCount > 0 ? .orange : .gray)
                            Text("Outdated Caches")
                            Spacer()
                            Text("\(outdatedCacheCount)")
                                .foregroundColor(outdatedCacheCount > 0 ? .orange : .secondary)
                        }
                    }

                    // Individual cache components
                    Section("Cache Components") {
                        CacheComponentRow(
                            title: "Academic Years",
                            isValid: status.hasValidYearsCache,
                            lastUpdate: status.lastYearsCacheUpdate,
                            systemImage: "calendar"
                        )

                        CacheComponentRow(
                            title: "Academic Terms",
                            isValid: status.hasValidTermsCache,
                            lastUpdate: status.lastTermsCacheUpdate,
                            systemImage: "doc.text"
                        )

                        CacheComponentRow(
                            title: "Club Activities",
                            isValid: status.hasValidClubsCache,
                            lastUpdate: status.lastClubsCacheUpdate,
                            systemImage: "person.3"
                        )

                        CacheComponentRow(
                            title: "School Arrangements",
                            isValid: status.hasValidArrangementsCache,
                            lastUpdate: status.lastArrangementsCacheUpdate,
                            systemImage: "building.2"
                        )

                        HStack {
                            Image(systemName: "table")
                                .foregroundColor(.blue)
                            Text("Timetable Caches")
                            Spacer()
                            Text("\(status.timetableCacheCount) cached")
                                .foregroundColor(.secondary)
                        }
                    }

                    // Cache actions section
                    Section("Cache Management") {
                        Button(action: {
                            refreshAllCaches()
                        }) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Refresh All Caches")
                                if isRefreshing {
                                    Spacer()
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                        }
                        .disabled(isRefreshing)

                        Button(action: {
                            CacheManager.cleanupOutdatedCache()
                            updateCacheStatus()
                        }) {
                            HStack {
                                Image(systemName: "trash.slash")
                                    .foregroundColor(.orange)
                                Text("Clean Outdated Cache")
                                if outdatedCacheCount > 0 {
                                    Spacer()
                                    Text("(\(outdatedCacheCount))")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                }
                            }
                        }

                        Button(action: {
                            clearSpecificCache(.classtable)
                        }) {
                            HStack {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                                Text("Clear Classtable Cache")
                            }
                        }

                        Button(action: {
                            clearSpecificCache(.academicScores)
                        }) {
                            HStack {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                                Text("Clear Academic Scores Cache")
                            }
                        }

                        Button(action: {
                            clearSpecificCache(.clubActivities)
                        }) {
                            HStack {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                                Text("Clear Club Activities Cache")
                            }
                        }

                        Button(action: {
                            CacheManager.clearAllCache()
                            updateCacheStatus()
                        }) {
                            HStack {
                                Image(systemName: "trash.fill")
                                    .foregroundColor(.red)
                                Text("Clear All Cache")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                } else {
                    Section {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading cache status...")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Cache Status")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh") {
                        updateCacheStatus()
                    }
                }
            }
            .onAppear {
                updateCacheStatus()
            }
        }
    }

    private func updateCacheStatus() {
        cacheStatus = CacheManager.getCacheStatus()
        estimatedCacheSize = CacheManager.getEstimatedCacheSize()
        outdatedCacheCount = CacheManager.getOutdatedCacheCount()
    }

    private func refreshAllCaches() {
        isRefreshing = true

        // Refresh different cache types
        CacheManager.refreshCache(type: .classtable)
        CacheManager.refreshCache(type: .academicScores)
        CacheManager.refreshCache(type: .clubActivities)
        CacheManager.refreshCache(type: .schoolArrangements)

        // Simulate refresh time and update status
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            updateCacheStatus()
            isRefreshing = false
        }
    }

    private func clearSpecificCache(_ type: CacheType) {
        switch type {
        case .classtable:
            CacheManager.clearClasstableCache()
        case .academicScores:
            CacheManager.clearAcademicScoresCache()
        case .clubActivities:
            CacheManager.clearClubActivitiesCache()
        case .schoolArrangements:
            CacheManager.clearSchoolArrangementsCache()
        }

        updateCacheStatus()
    }
}

struct CacheComponentRow: View {
    let title: String
    let isValid: Bool
    let lastUpdate: Date?
    let systemImage: String

    private var statusColor: Color {
        isValid ? .green : .red
    }

    private var statusText: String {
        isValid ? "Valid" : "Expired"
    }

    private var formattedLastUpdate: String {
        guard let lastUpdate else { return "Never" }

        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: lastUpdate, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundColor(.blue)
                Text(title)
                Spacer()
                Text(statusText)
                    .foregroundColor(statusColor)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.1))
                    .cornerRadius(4)
            }

            if lastUpdate != nil {
                HStack {
                    Text("Last updated: \(formattedLastUpdate)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.leading, 20)
            }
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(_ healthColor: String) {
        switch healthColor {
        case "green": self = .green
        case "blue": self = .blue
        case "orange": self = .orange
        case "red": self = .red
        case "gray": self = .gray
        default: self = .gray
        }
    }
}

#Preview {
    CacheStatusView()
}

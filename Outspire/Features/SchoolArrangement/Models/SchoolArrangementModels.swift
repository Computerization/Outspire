import Foundation
import SwiftUI

struct SchoolArrangementItem: Identifiable, Equatable {
    let id: String
    let title: String
    let publishDate: String
    let url: String
    let weekNumbers: [Int]
    var isExpanded: Bool = false

    static func == (lhs: SchoolArrangementItem, rhs: SchoolArrangementItem) -> Bool {
        lhs.id == rhs.id
    }
}

struct SchoolArrangementDetail: Identifiable, Equatable {
    let id: String
    let title: String
    let publishDate: String
    let imageUrls: [String]
    let content: String

    static func == (lhs: SchoolArrangementDetail, rhs: SchoolArrangementDetail) -> Bool {
        lhs.id == rhs.id
    }
}

/// Helper struct for grouping arrangements
struct ArrangementGroup: Identifiable {
    let id: String
    let title: String
    var items: [SchoolArrangementItem] // Change from let to var
    var isExpanded: Bool = true
}

/// Enhanced cache manager for image caching with better memory management
class ImageCache {
    static let shared = ImageCache()
    private var cache = NSCache<NSString, NSData>()
    private var inProgressTasks = [String: URLSessionDataTask]()
    private var taskLock = NSLock()

    init() {
        // Set reasonable cache limits
        cache.countLimit = 100 // Maximum number of items
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB limit

        // Register for memory warning notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearCache),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setImage(data: Data, for url: String) {
        let cost = data.count
        cache.setObject(data as NSData, forKey: url as NSString, cost: cost)
    }

    func getImage(for url: String) -> Data? {
        cache.object(forKey: url as NSString) as Data?
    }

    func loadImageAsync(url: URL, completion: @escaping (Data?) -> Void) {
        // Check cache first
        if let cachedData = getImage(for: url.absoluteString) {
            completion(cachedData)
            return
        }

        taskLock.lock()

        // Check if there's already a task loading this image
        if let existingTask = inProgressTasks[url.absoluteString] {
            taskLock.unlock()
            return // Let the existing task handle it
        }

        // Create a new loading task
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self else { return }

            self.taskLock.lock()
            self.inProgressTasks[url.absoluteString] = nil
            self.taskLock.unlock()

            if let data, error == nil {
                self.setImage(data: data, for: url.absoluteString)
                DispatchQueue.main.async {
                    completion(data)
                }
            } else {
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }

        inProgressTasks[url.absoluteString] = task
        taskLock.unlock()

        task.resume()
    }

    @objc func clearCache() {
        cache.removeAllObjects()

        taskLock.lock()
        for task in inProgressTasks.values {
            task.cancel()
        }
        inProgressTasks.removeAll()
        taskLock.unlock()
    }

    func cancelTask(for url: String) {
        taskLock.lock()
        inProgressTasks[url]?.cancel()
        inProgressTasks[url] = nil
        taskLock.unlock()
    }
}

/// Improved URL validation helper
private func isValidURL(_ urlString: String) -> Bool {
    guard let url = URL(string: urlString) else { return false }
    return UIApplication.shared.canOpenURL(url)
}

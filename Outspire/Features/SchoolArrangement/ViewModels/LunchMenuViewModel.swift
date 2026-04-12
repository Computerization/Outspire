import Combine
import PDFKit
import SwiftSoup
import SwiftUI

@MainActor
class LunchMenuViewModel: ObservableObject {
    @Published var menuItems: [LunchMenuItem] = []
    @Published var menuGroups: [LunchMenuGroup] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var currentPage: Int = 1
    @Published var totalPages: Int = 1
    @Published var selectedDetail: LunchMenuDetail?
    @Published var isLoadingDetail: Bool = false
    @Published var pdfURL: URL?

    // Animation state management
    private let animationViewId = "LunchMenuView"
    @Published var shouldAnimate = false

    private let baseURL = "https://www.wflms.cn"
    private var currentTask: URLSessionDataTask?
    private var detailTask: URLSessionDataTask?
    private var processedImageUrls = Set<String>()

    init() {
        fetchMenuItems()
        shouldAnimate = AnimationManager.shared.hasAnimated(viewId: animationViewId)
    }

    nonisolated deinit {
        // cancelAllTasks and cleanupTemporaryFiles are @MainActor;
        // deinit cannot call them directly. Cleanup is handled by ARC
        // releasing the URLSession tasks and FileManager temp files.
    }

    // MARK: - Public Methods

    func fetchMenuItems(page: Int = 1) {
        guard !isLoading else { return }

        // Cancel any existing task
        currentTask?.cancel()

        isLoading = true
        errorMessage = nil

        let urlString = "\(baseURL)/site/site1/list/1100602ca_list_data_\(page).html"

        guard let url = URL(string: urlString) else {
            self.errorMessage = "Invalid URL"
            self.isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        currentTask = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.isLoading = false

                if let error = error as NSError?, error.code != NSURLErrorCancelled {
                    self.errorMessage = "Failed to load data: \(error.localizedDescription)"
                    return
                }

                guard let data = data, let htmlString = String(data: data, encoding: .utf8) else {
                    self.errorMessage = "Failed to decode response"
                    return
                }

                do {
                    let items = try self.parseMenuListHTML(htmlString)

                    if let totalPages = try? self.parseTotalPages(htmlString) {
                        self.totalPages = totalPages
                    }

                    if page == 1 {
                        self.menuItems = items
                    } else {
                        self.menuItems.append(contentsOf: items)
                    }

                    self.currentPage = page
                    self.updateMenuGroups()
                } catch {
                    self.errorMessage = "Failed to parse HTML: \(error.localizedDescription)"
                }
            }
        }

        currentTask?.resume()
    }

    func fetchNextPage() {
        if currentPage < totalPages, !isLoading {
            fetchMenuItems(page: currentPage + 1)
        }
    }

    func refreshData() {
        fetchMenuItems(page: 1)
    }

    func fetchMenuDetail(for item: LunchMenuItem) {
        guard !isLoadingDetail else { return }

        // Cancel any existing task
        detailTask?.cancel()

        isLoadingDetail = true
        errorMessage = nil
        selectedDetail = nil

        let urlString = "\(baseURL)\(item.url)"
            .replacingOccurrences(of: " ", with: "%20")

        print("DEBUG: Fetching menu detail from \(urlString)")

        guard let url = URL(string: urlString) else {
            print("DEBUG: Invalid URL: \(urlString)")
            self.errorMessage = "Invalid detail URL"
            self.isLoadingDetail = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        detailTask = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }

            if let error = error as NSError?, error.code != NSURLErrorCancelled {
                DispatchQueue.main.async {
                    self.isLoadingDetail = false
                    print("DEBUG: Network error: \(error)")
                    self.errorMessage = "Failed to load detail: \(error.localizedDescription)"
                }
                return
            }

            guard let data = data, let htmlString = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async {
                    self.isLoadingDetail = false
                    print("DEBUG: Failed to decode response")
                    self.errorMessage = "Failed to decode response"
                }
                return
            }

            do {
                // Reset processed URLs for each new detail
                self.processedImageUrls.removeAll()

                let detail = try self.parseMenuDetailHTML(
                    htmlString,
                    id: item.id,
                    title: item.title,
                    publishDate: item.publishDate
                )

                print("DEBUG: Menu detail parsed successfully with \(detail.imageUrls.count) images")

                // Download images and generate PDF
                self.downloadImagesAndCreatePDF(detail: detail)

            } catch {
                print("DEBUG: Detail parsing error: \(error)")
                DispatchQueue.main.async {
                    self.isLoadingDetail = false
                    self.errorMessage = "Failed to parse detail: \(error.localizedDescription)"
                }
            }
        }

        detailTask?.resume()
    }

    func toggleGroupExpansion(_ groupId: String) {
        if let index = menuGroups.firstIndex(where: { $0.id == groupId }) {
            menuGroups[index].isExpanded.toggle()
        }
    }

    func toggleItemExpansion(_ itemId: String) {
        if let groupIndex = menuGroups.firstIndex(where: { group in
            group.items.contains(where: { $0.id == itemId })
        }) {
            var updatedItems = menuGroups[groupIndex].items

            if let itemIndex = updatedItems.firstIndex(where: { $0.id == itemId }) {
                var updatedItem = updatedItems[itemIndex]
                updatedItem.isExpanded.toggle()

                updatedItems[itemIndex] = updatedItem

                var updatedGroup = menuGroups[groupIndex]
                updatedGroup.items = updatedItems

                menuGroups[groupIndex] = updatedGroup
            }
        }
    }

    // Enhanced animation control method
    func triggerInitialAnimation(isSmallScreen: Bool = UIDevice.isSmallScreen) {
        if AnimationManager.shared.hasAnimated(viewId: animationViewId) {
            if isSmallScreen {
                self.shouldAnimate = true
            } else {
                withAnimation(.easeOut(duration: 0.3)) {
                    self.shouldAnimate = true
                }
            }
            return
        }

        let delay = isSmallScreen ? 0.1 : 0.3

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeOut(duration: isSmallScreen ? 0.4 : 0.6)) {
                self.shouldAnimate = true
                AnimationManager.shared.markAnimated(viewId: self.animationViewId)
            }
        }
    }

    // MARK: - Private Methods

    private func updateMenuGroups() {
        // Group by year and semester
        var groups: [String: [LunchMenuItem]] = [:]

        // Extract year and semester pattern from titles
        for item in menuItems {
            let title = item.title
            var key = "Other Menus"

            // Try to extract academic year
            if let yearMatch = title.range(of: #"\d{4}学年"#, options: .regularExpression) {
                let yearPart = String(title[yearMatch])
                key = yearPart
            }

            if groups[key] == nil {
                groups[key] = []
            }
            groups[key]?.append(item)
        }

        // Sort keys by academic year (newest first)
        let sortedKeys = groups.keys.sorted { key1, key2 in
            // Extract year numbers if possible
            let extractYear: (String) -> Int = { str in
                if let match = str.range(of: #"\d{4}"#, options: .regularExpression) {
                    return Int(str[match]) ?? 0
                }
                return 0
            }

            let year1 = extractYear(key1)
            let year2 = extractYear(key2)

            if year1 != year2 {
                return year1 > year2 // Newer years first
            }

            return key1 > key2
        }

        menuGroups = sortedKeys.compactMap { key in
            guard let items = groups[key]?.sorted(by: { $0.publishDate > $1.publishDate }) else { return nil }
            return LunchMenuGroup(id: key, title: key, items: items)
        }
    }

    private func parseMenuListHTML(_ html: String) throws -> [LunchMenuItem] {
        let doc: Document = try SwiftSoup.parse(html)
        let listItems = try doc.select("ul li")

        return try listItems.compactMap { element -> LunchMenuItem? in
            guard let anchor = try? element.select("a").first() else { return nil }

            let url = try anchor.attr("href")

            let titleElement = try anchor.select(".list_categoryName").first()
            let title = try titleElement?.text() ?? "Unknown"

            let publishDateElement = try anchor.select(".publishTime").first()
            let publishDate = try publishDateElement?.text() ?? "Unknown Date"

            // Extract ID from URL
            let components = url.components(separatedBy: "_")
            let id = components.last?.components(separatedBy: ".").first ?? UUID().uuidString

            return LunchMenuItem(
                id: id,
                title: title,
                publishDate: publishDate,
                url: url
            )
        }
    }

    private func parseTotalPages(_ html: String) throws -> Int {
        let doc: Document = try SwiftSoup.parse(html)

        if let scriptText = try doc.select("script").filter({ try $0.html().contains("var pageNumber =") }).first {
            let scriptContent = try scriptText.html()
            if let rangeStart = scriptContent.range(of: "var pageNumber = ('"),
               let rangeEnd = scriptContent.range(
                   of: "'.replace",
                   range: rangeStart.upperBound ..< scriptContent.endIndex
               )
            {
                let numberString = scriptContent[rangeStart.upperBound ..< rangeEnd.lowerBound]
                    .trimmingCharacters(in: CharacterSet(charactersIn: "'\";()"))
                if let totalPages = Int(numberString) {
                    return totalPages
                }
            }
        }

        return 1
    }

    private func parseMenuDetailHTML(
        _ html: String,
        id: String,
        title: String,
        publishDate: String
    ) throws -> LunchMenuDetail {
        print("DEBUG: Starting to parse HTML for \(title)")

        var content = ""
        var imageUrls: [String] = []

        do {
            let doc: Document = try SwiftSoup.parse(html)

            // Extract the main content div
            let contentDiv = try doc.select("#newsContent").first()
            content = try contentDiv?.html() ?? ""

            // Extract images from the content
            let contentImages = try doc.select("#newsContent img")

            for img in contentImages {
                var imgUrl: String?

                for attr in ["src", "_src", "data-src", "data-original"] {
                    if img.hasAttr(attr) {
                        if let src = try? img.attr(attr), !src.isEmpty {
                            imgUrl = src
                            break
                        }
                    }
                }

                if imgUrl == nil && img.hasAttr("fileid") {
                    if let fileId = try? img.attr("fileid"), !fileId.isEmpty {
                        imgUrl = "/oss/\(fileId)"
                    }
                }

                if let imgUrl = imgUrl {
                    let absoluteUrl = imgUrl.hasPrefix("http") ? imgUrl : "\(baseURL)\(imgUrl)"

                    if !processedImageUrls.contains(absoluteUrl) {
                        imageUrls.append(absoluteUrl)
                        processedImageUrls.insert(absoluteUrl)
                    }
                }
            }

            // If no images found through DOM, try regex extraction
            if imageUrls.isEmpty {
                if let regex = try? NSRegularExpression(pattern: "src\\s*=\\s*[\"'](.*?)[\"']") {
                    let range = NSRange(content.startIndex ..< content.endIndex, in: content)
                    let matches = regex.matches(in: content, range: range)

                    for match in matches {
                        if let range = Range(match.range(at: 1), in: content) {
                            let imgUrl = String(content[range])
                            if imgUrl.contains("/oss/") && !imgUrl.contains(".gif") {
                                let absoluteUrl = imgUrl.hasPrefix("http") ? imgUrl : "\(baseURL)\(imgUrl)"
                                if !processedImageUrls.contains(absoluteUrl) {
                                    imageUrls.append(absoluteUrl)
                                    processedImageUrls.insert(absoluteUrl)
                                }
                            }
                        }
                    }
                }
            }

        } catch {
            print("DEBUG: Critical HTML parsing error: \(error)")
        }

        return LunchMenuDetail(
            id: id,
            title: title,
            publishDate: publishDate,
            imageUrls: imageUrls,
            content: content
        )
    }

    private func downloadImagesAndCreatePDF(detail: LunchMenuDetail) {
        print("DEBUG: Starting to download \(detail.imageUrls.count) images for PDF")

        if detail.imageUrls.isEmpty {
            print("DEBUG: No images to download, creating text-only PDF")
            createAndSavePDF(detail: detail, images: [])
            return
        }

        downloadImagesSequentially(detail: detail, imageUrls: detail.imageUrls)
    }

    private func downloadImagesSequentially(detail: LunchMenuDetail, imageUrls: [String]) {
        print("DEBUG: Using sequential image download for \(imageUrls.count) images")

        var downloadedImages: [UIImage] = []
        var failedUrls: [String] = []

        downloadNextImage(
            detail: detail,
            imageUrls: imageUrls,
            currentIndex: 0,
            downloadedImages: downloadedImages,
            failedUrls: failedUrls
        )
    }

    private func downloadNextImage(
        detail: LunchMenuDetail,
        imageUrls: [String],
        currentIndex: Int,
        downloadedImages: [UIImage],
        failedUrls: [String]
    ) {
        if currentIndex >= imageUrls.count {
            print(
                "DEBUG: All \(imageUrls.count) images processed. Success: \(downloadedImages.count), Failed: \(failedUrls.count)"
            )
            createAndSavePDFWithNotice(detail: detail, images: downloadedImages, failedURLs: failedUrls)
            return
        }

        let urlString = imageUrls[currentIndex]
        print("DEBUG: Downloading image \(currentIndex + 1)/\(imageUrls.count): \(urlString)")

        let sanitizedURL = sanitizeAndEncodeURL(urlString)

        guard let url = URL(string: sanitizedURL) else {
            print("DEBUG: Invalid URL after sanitization: \(urlString)")
            var newFailedUrls = failedUrls
            newFailedUrls.append(urlString)

            downloadNextImage(
                detail: detail,
                imageUrls: imageUrls,
                currentIndex: currentIndex + 1,
                downloadedImages: downloadedImages,
                failedUrls: newFailedUrls
            )
            return
        }

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 20.0
        sessionConfig.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
            "Accept": "image/jpeg, image/png, image/*"
        ]
        let session = URLSession(configuration: sessionConfig)

        let task = session.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else { return }

            var newDownloadedImages = downloadedImages
            var newFailedUrls = failedUrls

            if let error = error {
                print("DEBUG: Error downloading image \(currentIndex + 1): \(error.localizedDescription)")
                newFailedUrls.append(urlString)
            } else if let data = data, let image = UIImage(data: data) {
                print("DEBUG: Successfully downloaded image \(currentIndex + 1) - size: \(data.count) bytes")
                newDownloadedImages.append(image)
            } else {
                print("DEBUG: Failed to convert data to image for URL \(currentIndex + 1)")
                newFailedUrls.append(urlString)
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
                self.downloadNextImage(
                    detail: detail,
                    imageUrls: imageUrls,
                    currentIndex: currentIndex + 1,
                    downloadedImages: newDownloadedImages,
                    failedUrls: newFailedUrls
                )
            }
        }

        task.resume()
    }

    private func sanitizeAndEncodeURL(_ urlString: String) -> String {
        var cleaned = urlString
            .replacingOccurrences(of: " ", with: "%20")
            .replacingOccurrences(of: "\\", with: "/")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")

        if !cleaned.hasPrefix("http") && !cleaned.hasPrefix("/") {
            cleaned = "/\(cleaned)"
        }

        if !cleaned.hasPrefix("http") {
            cleaned = "\(baseURL)\(cleaned)"
        }

        if let _ = URL(string: cleaned) {
            return cleaned
        }

        if let encoded = cleaned.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            return encoded
        }

        return cleaned
    }

    private func createAndSavePDFWithNotice(detail: LunchMenuDetail, images: [UIImage], failedURLs: [String]) {
        var contentWithNotice = detail.content

        if !failedURLs.isEmpty {
            let failedNotice = "<p style='color:red;'>Note: \(failedURLs.count) images could not be included in this PDF.</p>"
            contentWithNotice = failedNotice + contentWithNotice
        }

        let detailWithNotice = LunchMenuDetail(
            id: detail.id,
            title: detail.title,
            publishDate: detail.publishDate,
            imageUrls: detail.imageUrls,
            content: contentWithNotice
        )

        createAndSavePDF(detail: detailWithNotice, images: images)
    }

    private func createAndSavePDF(detail: LunchMenuDetail, images: [UIImage]) {
        let sortedImages = images.sorted(by: { $0.size.width * $0.size.height > $1.size.width * $1.size.height })

        guard let pdfData = PDFGenerator.generatePDF(
            title: detail.title,
            date: detail.publishDate,
            content: detail.content,
            images: sortedImages
        ) else {
            DispatchQueue.main.async {
                self.isLoadingDetail = false
                self.errorMessage = "Failed to create PDF document"
            }
            return
        }

        let fileName = "menu_\(detail.id).pdf"
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            try pdfData.write(to: fileURL)

            DispatchQueue.main.async {
                self.isLoadingDetail = false
                self.selectedDetail = detail
                self.pdfURL = fileURL
            }
        } catch {
            DispatchQueue.main.async {
                self.isLoadingDetail = false
                self.errorMessage = "Failed to save PDF document: \(error.localizedDescription)"
            }
        }
    }

    private func cancelAllTasks() {
        currentTask?.cancel()
        currentTask = nil
        detailTask?.cancel()
        detailTask = nil
    }

    private func cleanupTemporaryFiles() {
        if let pdfURL = pdfURL {
            do {
                try FileManager.default.removeItem(at: pdfURL)
            } catch {
                print("DEBUG: Failed to delete temporary PDF: \(error)")
            }
        }
    }
}

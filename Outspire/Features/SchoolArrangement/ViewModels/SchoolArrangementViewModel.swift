import Combine
import PDFKit
import QuickLook
import SwiftSoup
import SwiftUI

@MainActor
class SchoolArrangementViewModel: ObservableObject {
    @Published var arrangements: [SchoolArrangementItem] = []
    @Published var arrangementGroups: [ArrangementGroup] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var currentPage: Int = 1
    @Published var totalPages: Int = 1
    @Published var selectedDetail: SchoolArrangementDetail?
    @Published var isLoadingDetail: Bool = false
    @Published var pdfURL: URL?

    // Animation state management with view ID for persistent tracking
    private let animationViewId = "SchoolArrangementView"
    @Published var shouldAnimate = false

    private let baseURL = "https://www.wflms.cn"
    private var currentTask: URLSessionDataTask?
    private var detailTask: URLSessionDataTask?
    private var processedImageUrls = Set<String>()

    /// Group for async image downloading
    private let downloadGroup = DispatchGroup()

    init() {
        fetchArrangements()
        // Check if animations have already been performed
        shouldAnimate = AnimationManager.shared.hasAnimated(viewId: animationViewId)
    }

    nonisolated deinit {
        // cancelAllTasks and cleanupTemporaryFiles are @MainActor;
        // deinit cannot call them directly. Cleanup is handled by ARC.
    }

    // MARK: - Public Methods

    func fetchArrangements(page: Int = 1) {
        guard !isLoading else { return }

        // Cancel any existing task
        currentTask?.cancel()

        isLoading = true
        errorMessage = nil

        let urlString = "\(baseURL)/site/site1/list/103ca_list_data_\(page).html"

        guard let url = URL(string: urlString) else {
            self.errorMessage = "Invalid URL"
            self.isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        currentTask = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }

            DispatchQueue.main.async {
                self.isLoading = false

                if let error = error as NSError?, error.code != NSURLErrorCancelled {
                    self.errorMessage = "Failed to load data: \(error.localizedDescription)"
                    return
                }

                guard let data, let htmlString = String(data: data, encoding: .utf8) else {
                    self.errorMessage = "Failed to decode response"
                    return
                }

                do {
                    let items = try self.parseArrangementListHTML(htmlString)

                    if let totalPages = try? self.parseTotalPages(htmlString) {
                        self.totalPages = totalPages
                    }

                    if page == 1 {
                        self.arrangements = items
                    } else {
                        self.arrangements.append(contentsOf: items)
                    }

                    self.currentPage = page
                    self.updateArrangementGroups()
                } catch {
                    self.errorMessage = "Failed to parse HTML: \(error.localizedDescription)"
                }
            }
        }

        currentTask?.resume()
    }

    func fetchNextPage() {
        if currentPage < totalPages, !isLoading {
            fetchArrangements(page: currentPage + 1)
        }
    }

    func refreshData() {
        fetchArrangements(page: 1)
    }

    func fetchArrangementDetail(for item: SchoolArrangementItem) {
        guard !isLoadingDetail else { return }

        // Cancel any existing task
        detailTask?.cancel()

        isLoadingDetail = true
        errorMessage = nil
        selectedDetail = nil
        pdfURL = nil // Reset PDF URL

        // Sanitize URL - handle cases where the URL might contain spaces or invalid characters
        let urlString = "\(baseURL)\(item.url)"
            .replacingOccurrences(of: " ", with: "%20")

        print("DEBUG: Fetching detail from \(urlString)")

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
            guard let self else { return }

            if let error = error as NSError?, error.code != NSURLErrorCancelled {
                DispatchQueue.main.async {
                    self.isLoadingDetail = false
                    print("DEBUG: Network error: \(error)")
                    self.errorMessage = "Failed to load detail: \(error.localizedDescription)"
                }
                return
            }

            guard let data, let htmlString = String(data: data, encoding: .utf8) else {
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

                let detail = try self.parseArrangementDetailHTML(
                    htmlString,
                    id: item.id,
                    title: item.title,
                    publishDate: item.publishDate
                )

                // Create the detail object
                print("DEBUG: Detail parsed successfully with \(detail.imageUrls.count) images")

                // Now we need to download all images and generate a PDF
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
        if let index = arrangementGroups.firstIndex(where: { $0.id == groupId }) {
            arrangementGroups[index].isExpanded.toggle()
        }
    }

    func toggleItemExpansion(_ itemId: String) {
        if let groupIndex = arrangementGroups.firstIndex(where: { group in
            group.items.contains(where: { $0.id == itemId })
        }) {
            // Create a mutable copy of the items array
            var updatedItems = arrangementGroups[groupIndex].items

            // Find the item and toggle its expansion state
            if let itemIndex = updatedItems.firstIndex(where: { $0.id == itemId }) {
                // Create a new item with toggled isExpanded value
                var updatedItem = updatedItems[itemIndex]
                updatedItem.isExpanded.toggle()

                // Replace the item in the array
                updatedItems[itemIndex] = updatedItem

                // Create a new group with the updated items
                var updatedGroup = arrangementGroups[groupIndex]
                updatedGroup.items = updatedItems

                // Update the group in the array
                arrangementGroups[groupIndex] = updatedGroup
            }
        }
    }

    // MARK: - Private Methods

    private func updateArrangementGroups() {
        // Group by month and year
        var groups: [String: [SchoolArrangementItem]] = [:]

        let inputDateFormatter = DateFormatter()
        inputDateFormatter.dateFormat = "yyyy-MM-dd"

        let outputDateFormatter = DateFormatter()
        outputDateFormatter.dateFormat = "MMMM yyyy"

        for item in arrangements {
            let key: String = if let date = inputDateFormatter.date(from: item.publishDate) {
                outputDateFormatter.string(from: date)
            } else {
                "Unknown Date"
            }

            if groups[key] == nil {
                groups[key] = []
            }
            groups[key]?.append(item)
        }

        // Sort items within each group
        for key in groups.keys {
            groups[key]?.sort { $0.publishDate > $1.publishDate }
        }

        // Create arrangement groups and sort them
        let sortedKeys = groups.keys.sorted { key1, key2 in
            if key1 == "Unknown Date" { return false }
            if key2 == "Unknown Date" { return true }

            let monthYearFormatter = DateFormatter()
            monthYearFormatter.dateFormat = "MMMM yyyy"

            if let date1 = monthYearFormatter.date(from: key1),
               let date2 = monthYearFormatter.date(from: key2)
            {
                return date1 > date2
            }
            return key1 > key2
        }

        // Create groups
        arrangementGroups = sortedKeys.compactMap { key in
            guard let items = groups[key] else { return nil }
            return ArrangementGroup(id: key, title: key, items: items)
        }
    }

    private func parseArrangementListHTML(_ html: String) throws -> [SchoolArrangementItem] {
        let doc: Document = try SwiftSoup.parse(html)
        let listItems = try doc.select("ul li")

        return try listItems.compactMap { element -> SchoolArrangementItem? in
            guard let anchor = try? element.select("a").first() else { return nil }

            let url = try anchor.attr("href")

            let titleElement = try anchor.select(".list_categoryName").first()
            let title = try titleElement?.text() ?? "Unknown"

            let publishDateElement = try anchor.select(".publishTime").first()
            let publishDate = try publishDateElement?.text() ?? "Unknown Date"

            // Extract ID from URL
            let components = url.components(separatedBy: "_")
            let id = components.last?.components(separatedBy: ".").first ?? UUID().uuidString

            // Extract week numbers
            let weekNumbers = extractWeekNumbers(from: title)

            return SchoolArrangementItem(
                id: id,
                title: title,
                publishDate: publishDate,
                url: url,
                weekNumbers: weekNumbers
            )
        }
    }

    private func parseTotalPages(_ html: String) throws -> Int {
        let doc: Document = try SwiftSoup.parse(html)

        // Try to extract from the JavaScript function
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

        return 1 // Default to 1 page if we can't parse it
    }

    private func parseArrangementDetailHTML(
        _ html: String,
        id: String,
        title: String,
        publishDate: String
    ) throws -> SchoolArrangementDetail {
        print("DEBUG: Starting to parse HTML for \(title)")

        var content = ""
        var imageUrls: [String] = []

        do {
            let doc: Document = try SwiftSoup.parse(html)

            // Extract the main content div
            let contentDiv = try doc.select("#newsContent").first()
            content = try contentDiv?.html() ?? ""
            print("DEBUG: Content extracted, length: \(content.count)")

            // IMPROVED: More thorough image extraction strategy
            // 1. First try to extract images from #newsContent directly
            let contentImages = try doc.select("#newsContent img")
            print("DEBUG: Found \(contentImages.count) images in #newsContent")

            for img in contentImages {
                // Try all possible attributes where image URLs might be stored
                var imgUrl: String?

                // Check multiple possible attributes in priority order
                for attr in ["src", "_src", "data-src", "data-original"] {
                    if img.hasAttr(attr) {
                        if let src = try? img.attr(attr), !src.isEmpty {
                            imgUrl = src
                            print("DEBUG: Found image URL in '\(attr)' attribute: \(src)")
                            break
                        }
                    }
                }

                // If no URL found but has fileid attribute, construct URL
                if imgUrl == nil, img.hasAttr("fileid") {
                    if let fileId = try? img.attr("fileid"), !fileId.isEmpty {
                        imgUrl = "/oss/\(fileId)"
                        print("DEBUG: Constructed image URL from fileid: \(imgUrl!)")
                    }
                }

                // Process the found URL if any
                if let imgUrl {
                    // Build absolute URL if needed
                    let absoluteUrl = imgUrl.hasPrefix("http") ? imgUrl : "\(baseURL)\(imgUrl)"

                    if !processedImageUrls.contains(absoluteUrl) {
                        imageUrls.append(absoluteUrl)
                        processedImageUrls.insert(absoluteUrl)
                        print("DEBUG: Added image URL: \(absoluteUrl)")
                    }
                }
            }

            // 2. If no images found, try to find image URLs in the HTML content itself
            if imageUrls.isEmpty {
                print("DEBUG: No images found by selectors, trying regex extraction from HTML")
                let imgPattern = "src\\s*=\\s*[\"'](.*?)[\"']"
                if let regex = try? NSRegularExpression(pattern: imgPattern) {
                    let range = NSRange(content.startIndex ..< content.endIndex, in: content)
                    let matches = regex.matches(in: content, range: range)

                    for match in matches {
                        if let range = Range(match.range(at: 1), in: content) {
                            let imgUrl = String(content[range])
                            if imgUrl.contains("/oss/"), !imgUrl.contains(".gif") {
                                let absoluteUrl = imgUrl.hasPrefix("http") ? imgUrl : "\(baseURL)\(imgUrl)"
                                if !processedImageUrls.contains(absoluteUrl) {
                                    imageUrls.append(absoluteUrl)
                                    processedImageUrls.insert(absoluteUrl)
                                    print("DEBUG: Extracted image URL from content: \(absoluteUrl)")
                                }
                            }
                        }
                    }
                }
            }

            // 3. Final attempt - check if any paragraph contains direct img tags
            if imageUrls.isEmpty {
                let paragraphs = try doc.select("#newsContent p")
                for p in paragraphs {
                    if let pHtml = try? p.html(), pHtml.contains("<img") {
                        print("DEBUG: Found paragraph with img tag: \(pHtml.prefix(100))...")
                        // Extract URLs from this paragraph
                        if let regex = try? NSRegularExpression(pattern: "src\\s*=\\s*[\"'](.*?)[\"']") {
                            let range = NSRange(pHtml.startIndex ..< pHtml.endIndex, in: pHtml)
                            let matches = regex.matches(in: pHtml, range: range)

                            for match in matches {
                                if let range = Range(match.range(at: 1), in: pHtml) {
                                    let imgUrl = String(pHtml[range])
                                    if !imgUrl.contains(".gif") {
                                        let absoluteUrl = imgUrl.hasPrefix("http") ? imgUrl : "\(baseURL)\(imgUrl)"
                                        if !processedImageUrls.contains(absoluteUrl) {
                                            imageUrls.append(absoluteUrl)
                                            processedImageUrls.insert(absoluteUrl)
                                            print("DEBUG: Extracted image URL from paragraph: \(absoluteUrl)")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            print("DEBUG: Final image count: \(imageUrls.count)")
            for (index, url) in imageUrls.enumerated() {
                print("DEBUG: Image \(index + 1): \(url)")
            }

        } catch {
            print("DEBUG: Critical HTML parsing error: \(error)")
        }

        return SchoolArrangementDetail(
            id: id,
            title: title,
            publishDate: publishDate,
            imageUrls: imageUrls,
            content: content
        )
    }

    private func extractWeekNumbers(from title: String) -> [Int] {
        let pattern = "【(.*?)】"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(title.startIndex ..< title.endIndex, in: title)
        guard let match = regex.firstMatch(in: title, range: range) else {
            return []
        }

        // Extract text inside brackets
        if let matchRange = Range(match.range(at: 1), in: title) {
            let weekText = String(title[matchRange])

            // Split by comma, 、, and spaces
            let components = weekText.components(separatedBy: CharacterSet(charactersIn: ",、 "))

            // Process each component to extract numbers
            var weekNumbers: [Int] = []
            for component in components {
                // Check for range (e.g., "1-3")
                if component.contains("-") {
                    let rangeComponents = component.components(separatedBy: "-")
                    if rangeComponents.count == 2,
                       let start = Int(rangeComponents[0]),
                       let end = Int(rangeComponents[1])
                    {
                        weekNumbers.append(contentsOf: start ... end)
                    }
                } else if let number = Int(component) {
                    weekNumbers.append(number)
                }
            }

            return weekNumbers.sorted()
        }

        return []
    }

    private func cancelAllTasks() {
        currentTask?.cancel()
        currentTask = nil

        detailTask?.cancel()
        detailTask = nil
    }

    /// Improved URL validation helper
    private func isValidURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// Validate and sanitize a URL string
    private func sanitizeURL(_ urlString: String) -> String {
        urlString
            .replacingOccurrences(of: " ", with: "%20")
            .replacingOccurrences(of: "\\", with: "/")
    }

    private func downloadImagesAndCreatePDF(detail: SchoolArrangementDetail) {
        print("DEBUG: Starting to download \(detail.imageUrls.count) images for PDF...")

        // If no images, create PDF with just text
        if detail.imageUrls.isEmpty {
            print("DEBUG: No images to download, creating text-only PDF")
            createAndSavePDF(detail: detail, images: [])
            return
        }

        // For better reliability, download images sequentially
        downloadImagesSequentially(detail: detail, imageUrls: detail.imageUrls)
    }

    /// Sequential approach for more reliable image downloads
    private func downloadImagesSequentially(detail: SchoolArrangementDetail, imageUrls: [String]) {
        print("DEBUG: Using sequential image download for \(imageUrls.count) images")

        // Create arrays to track progress
        var downloadedImages: [UIImage] = []
        var failedUrls: [String] = []

        // Start with the first image
        downloadNextImage(
            detail: detail,
            imageUrls: imageUrls,
            currentIndex: 0,
            downloadedImages: downloadedImages,
            failedUrls: failedUrls
        )
    }

    private func downloadNextImage(
        detail: SchoolArrangementDetail,
        imageUrls: [String],
        currentIndex: Int,
        downloadedImages: [UIImage],
        failedUrls: [String]
    ) {
        // Check if we've processed all images
        if currentIndex >= imageUrls.count {
            print(
                "DEBUG: All \(imageUrls.count) images processed. Success: \(downloadedImages.count), Failed: \(failedUrls.count)"
            )
            createAndSavePDFWithNotice(detail: detail, images: downloadedImages, failedURLs: failedUrls)
            return
        }

        let urlString = imageUrls[currentIndex]
        print("DEBUG: Downloading image \(currentIndex + 1)/\(imageUrls.count): \(urlString)")

        // Process URL: clean and prepare
        let sanitizedURL = sanitizeAndEncodeURL(urlString)

        guard let url = URL(string: sanitizedURL) else {
            print("DEBUG: Invalid URL after sanitization: \(urlString)")
            var newFailedUrls = failedUrls
            newFailedUrls.append(urlString)

            // Continue with next image
            downloadNextImage(
                detail: detail,
                imageUrls: imageUrls,
                currentIndex: currentIndex + 1,
                downloadedImages: downloadedImages,
                failedUrls: newFailedUrls
            )
            return
        }

        // Create session with timeout and appropriate headers
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 20.0
        sessionConfig.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
            "Accept": "image/jpeg, image/png, image/*"
        ]
        let session = URLSession(configuration: sessionConfig)

        let task = session.dataTask(with: url) { [weak self] data, _, error in
            guard let self else { return }

            var newDownloadedImages = downloadedImages
            var newFailedUrls = failedUrls

            if let error {
                print("DEBUG: Error downloading image \(currentIndex + 1): \(error.localizedDescription)")
                newFailedUrls.append(urlString)
            } else if let data, let image = UIImage(data: data) {
                print("DEBUG: Successfully downloaded image \(currentIndex + 1) - size: \(data.count) bytes")
                newDownloadedImages.append(image)
            } else {
                print("DEBUG: Failed to convert data to image for URL \(currentIndex + 1)")
                newFailedUrls.append(urlString)
            }

            // Continue with next image after a short delay
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

    /// More thorough URL sanitization and encoding
    private func sanitizeAndEncodeURL(_ urlString: String) -> String {
        // Step 1: Basic cleaning
        var cleaned = urlString
            .replacingOccurrences(of: " ", with: "%20")
            .replacingOccurrences(of: "\\", with: "/")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")

        // Step 2: Add prefixes if needed
        if !cleaned.hasPrefix("http"), !cleaned.hasPrefix("/") {
            cleaned = "/\(cleaned)"
        }

        // Step 3: Add base URL if needed
        if !cleaned.hasPrefix("http") {
            cleaned = "\(baseURL)\(cleaned)"
        }

        // Step 4: Try to create a valid URL
        if let _ = URL(string: cleaned) {
            return cleaned
        }

        // Step 5: If URL still invalid, try percent encoding
        if let encoded = cleaned.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            return encoded
        }

        return cleaned // Return original if all else fails
    }

    private func createAndSavePDFWithNotice(detail: SchoolArrangementDetail, images: [UIImage], failedURLs: [String]) {
        // Add notice about failed images if any
        var contentWithNotice = detail.content

        if !failedURLs.isEmpty {
            let failedNotice = "<p style='color:red;'>Note: \(failedURLs.count) images could not be included in this PDF.</p>"
            contentWithNotice = failedNotice + contentWithNotice
            print("DEBUG: Adding notice about \(failedURLs.count) failed image downloads")
        }

        // Create modified detail with notice
        let detailWithNotice = SchoolArrangementDetail(
            id: detail.id,
            title: detail.title,
            publishDate: detail.publishDate,
            imageUrls: detail.imageUrls,
            content: contentWithNotice
        )

        // Create and save the PDF
        createAndSavePDF(detail: detailWithNotice, images: images)
    }

    private func createAndSavePDF(detail: SchoolArrangementDetail, images: [UIImage]) {
        print("DEBUG: Creating PDF with \(images.count) images")

        // Sort images to ensure consistent order
        let sortedImages = images.sorted(by: { $0.size.width * $0.size.height > $1.size.width * $1.size.height })

        // Generate PDF data
        guard let pdfData = PDFGenerator.generatePDF(
            title: detail.title,
            date: detail.publishDate,
            content: detail.content,
            images: sortedImages
        ) else {
            print("DEBUG: Failed to generate PDF")
            DispatchQueue.main.async {
                self.isLoadingDetail = false
                self.errorMessage = "Failed to create PDF document"
            }
            return
        }

        // Save PDF to temporary directory
        let fileName = "arrangement_\(detail.id).pdf"
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            try pdfData.write(to: fileURL)
            print("DEBUG: PDF saved to: \(fileURL.path)")

            DispatchQueue.main.async {
                self.selectedDetail = detail

                // Short delay to ensure UI loading indicator is visible
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.pdfURL = fileURL
                    self.isLoadingDetail = false
                }
            }
        } catch {
            print("DEBUG: Failed to save PDF: \(error)")
            DispatchQueue.main.async {
                self.isLoadingDetail = false
                self.errorMessage = "Failed to save PDF document: \(error.localizedDescription)"
            }
        }
    }

    private func cleanupTemporaryFiles() {
        // Clean up the temporary PDF if it exists
        if let pdfURL {
            do {
                try FileManager.default.removeItem(at: pdfURL)
                print("DEBUG: Removed temporary PDF file")
            } catch {
                print("DEBUG: Failed to delete temporary PDF: \(error)")
            }
        }
    }

    /// Enhanced animation control method with device-specific behavior
    func triggerInitialAnimation(isSmallScreen: Bool = UIDevice.isSmallScreen) {
        // Skip if already animated according to the global manager
        if AnimationManager.shared.hasAnimated(viewId: animationViewId) {
            // For small screens, instantly set the animation state without animation
            if isSmallScreen {
                self.shouldAnimate = true
            } else {
                // For larger screens, we can still animate if needed
                withAnimation(.easeOut(duration: 0.3)) {
                    self.shouldAnimate = true
                }
            }
            return
        }

        // First time animation with appropriate timing
        let delay = isSmallScreen ? 0.1 : 0.3 // Less delay on small screens

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeOut(duration: isSmallScreen ? 0.4 : 0.6)) {
                self.shouldAnimate = true
                // Mark as animated in the global manager
                AnimationManager.shared.markAnimated(viewId: self.animationViewId)
            }
        }
    }
}

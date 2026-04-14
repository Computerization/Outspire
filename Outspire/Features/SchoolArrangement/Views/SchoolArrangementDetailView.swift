import SwiftUI

struct SchoolArrangementDetailView: View {
    let detail: SchoolArrangementDetail
    @State private var animateContent = false
    @State private var selectedImageIndex: Int?
    @State private var showingFullScreenImage = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title section
                VStack(alignment: .leading, spacing: 8) {
                    Text(detail.title)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(detail.publishDate)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom)
                .opacity(animateContent ? 1 : 0)
                .offset(y: animateContent ? 0 : 10)
                .animation(.easeOut(duration: 0.4).delay(0.1), value: animateContent)

                // Images section - only show if we have images
                if !detail.imageUrls.isEmpty {
                    Text("Attachments")
                        .font(.headline)
                        .padding(.bottom, 4)
                        .opacity(animateContent ? 1 : 0)
                        .offset(y: animateContent ? 0 : 10)
                        .animation(.easeOut(duration: 0.4).delay(0.2), value: animateContent)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(detail.imageUrls.enumerated()), id: \.1) { index, imageUrlString in
                                if let imageUrl = URL(string: imageUrlString) {
                                    ImageThumbnail(url: imageUrl)
                                        .frame(height: 200)
                                        .frame(width: 280)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .contentShape(Rectangle())
                                        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                                        .onTapGesture {
                                            // Make sure image URL is valid before setting index
                                            if URL(string: detail.imageUrls[index]) != nil {
                                                selectedImageIndex = index
                                                showingFullScreenImage = true
                                            }
                                        }
                                        .opacity(animateContent ? 1 : 0)
                                        .offset(y: animateContent ? 0 : 15)
                                        .animation(
                                            .easeOut(duration: 0.5).delay(0.3 + Double(index) * 0.1),
                                            value: animateContent
                                        )
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                } else {
                    // No images message
                    Text("No attachments found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                        .opacity(animateContent ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(0.2), value: animateContent)
                }

                // Content section
                if !detail.content.isEmpty {
                    Divider()
                        .padding(.vertical, 8)
                        .opacity(animateContent ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(0.4), value: animateContent)

                    Text("Description")
                        .font(.headline)
                        .padding(.bottom, 4)
                        .opacity(animateContent ? 1 : 0)
                        .offset(y: animateContent ? 0 : 10)
                        .animation(.easeOut(duration: 0.4).delay(0.5), value: animateContent)

                    HTMLContentView(htmlContent: detail.content)
                        .opacity(animateContent ? 1 : 0)
                        .offset(y: animateContent ? 0 : 10)
                        .animation(.easeOut(duration: 0.4).delay(0.6), value: animateContent)
                } else {
                    // No content message
                    Text("No description available")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                        .opacity(animateContent ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(0.4), value: animateContent)
                }
            }
            .padding()
        }
        .navigationTitle("School Arrangement")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(UIColor.systemBackground))
        .fullScreenCover(isPresented: $showingFullScreenImage) {
            if let index = selectedImageIndex,
               index < detail.imageUrls.count,
               let validUrlString = detail.imageUrls[index]
               .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               URL(string: validUrlString) != nil
            { // Validate URL more thoroughly
                ImageViewer(
                    imageUrl: validUrlString, // Use the encoded URL string
                    title: detail.title,
                    date: detail.publishDate
                )
            } else {
                // Fallback when URL is invalid
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Invalid Image URL")
                        .font(.headline)
                    Button("Dismiss") {
                        showingFullScreenImage = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(UIColor.systemBackground))
                .edgesIgnoringSafeArea(.all)
            }
        }
        .onAppear {
            print("DEBUG: Detail view appeared with \(detail.imageUrls.count) images")

            // Animate content when view appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                animateContent = true
            }
        }
    }
}

/// Simple thumbnail for the image list
struct ImageThumbnail: View {
    let url: URL
    @State private var loadFailed = false
    @State private var retryCount = 0
    private let maxRetries = 2

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .overlay {
                        ProgressView()
                    }
            case let .success(image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .onAppear {
                        // Reset failure state if we loaded successfully after a retry
                        if loadFailed {
                            loadFailed = false
                        }
                    }
            case .failure:
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor.tertiarySystemBackground))
                    .overlay {
                        VStack {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.title)
                                .foregroundStyle(.secondary)

                            Text("Failed to load")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if retryCount < maxRetries {
                                Button("Retry") {
                                    retryCount += 1
                                    // Simpler approach to force reload:
                                    withAnimation {
                                        loadFailed = true
                                    }

                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        withAnimation {
                                            loadFailed = false
                                        }
                                    }
                                }
                                .padding(.top, 5)
                                .font(.caption)
                            }
                        }
                    }
                    .onAppear {
                        loadFailed = true
                    }
            @unknown default:
                Color.gray
            }
        }
    }
}

/// Update the ImageViewer to handle URL creation errors
struct ImageViewer: View {
    let imageUrl: String
    let title: String
    let date: String
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset = CGSize.zero
    @State private var lastOffset = CGSize.zero
    @State private var error: Bool = false
    @State private var loadFailed = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header info
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(2)

                    Text(date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(UIColor.secondarySystemBackground))

                // Image content
                GeometryReader { geo in
                    if let url = URL(string: imageUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            case let .success(image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .scaleEffect(scale)
                                    .offset(offset)
                                    .gesture(
                                        MagnificationGesture()
                                            .onChanged { value in
                                                let delta = value / lastScale
                                                lastScale = value

                                                // Limit zoom scale between 1 and 5
                                                scale = min(max(1.0, scale * delta), 5.0)
                                            }
                                            .onEnded { _ in
                                                lastScale = 1.0
                                            }
                                    )
                                    .simultaneousGesture(
                                        DragGesture()
                                            .onChanged { value in
                                                // Only allow panning when zoomed in
                                                if scale > 1.0 {
                                                    offset = CGSize(
                                                        width: lastOffset.width + value.translation.width,
                                                        height: lastOffset.height + value.translation.height
                                                    )
                                                }
                                            }
                                            .onEnded { _ in
                                                lastOffset = offset
                                            }
                                    )
                                    .simultaneousGesture(
                                        TapGesture(count: 2)
                                            .onEnded {
                                                withAnimation(.spring()) {
                                                    if scale > 1.0 {
                                                        // Reset zoom and position
                                                        scale = 1.0
                                                        offset = .zero
                                                        lastOffset = .zero
                                                    } else {
                                                        // Zoom in to 3x at current position
                                                        scale = 3.0
                                                    }
                                                }
                                            }
                                    )
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            case .failure:
                                VStack(spacing: 16) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.largeTitle)
                                        .foregroundStyle(.secondary)
                                    Text("Failed to load image")
                                        .foregroundStyle(.secondary)

                                    Button("Try Again") {
                                        // Force image reload
                                        loadFailed = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            loadFailed = false
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(Color.blue.opacity(0.1))
                                    )
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .onAppear {
                                    loadFailed = true
                                }
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .id(loadFailed ? "reload-\(UUID().uuidString)" : "stable") // Force reload when needed
                        .frame(width: geo.size.width, height: geo.size.height)
                    } else {
                        // Handle invalid URL
                        VStack {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("Invalid image URL")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 1) {
                    // Single tap dismisses only if not zoomed in
                    if scale <= 1.1 {
                        dismiss()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if scale > 1.0 || offset != .zero {
                        Button {
                            withAnimation(.spring()) {
                                scale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            }
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                    }
                }
            }
            .background(Color.black)
        }
    }
}

struct HTMLContentView: View {
    let htmlContent: String

    var body: some View {
        Text(attributedString)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true) // Important for proper text sizing
    }

    private var attributedString: AttributedString {
        do {
            // Process HTML content more safely
            let processedHTML = htmlContent
                .replacingOccurrences(of: "<br>", with: "\n")
                .replacingOccurrences(of: "<br/>", with: "\n")
                .replacingOccurrences(of: "<br />", with: "\n")
                // Strip script tags completely
                .replacingOccurrences(of: "<script[^>]*>.*?</script>", with: "", options: .regularExpression)
                // Strip style tags
                .replacingOccurrences(of: "<style[^>]*>.*?</style>", with: "", options: .regularExpression)
                // Remove potentially problematic tags
                .replacingOccurrences(of: "<iframe[^>]*>.*?</iframe>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "<object[^>]*>.*?</object>", with: "", options: .regularExpression)

            // Ensure we have valid HTML
            let safeHTML = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="UTF-8">
                <style>
                    body { font-family: -apple-system; font-size: 16px; }
                </style>
            </head>
            <body>
                \(processedHTML)
            </body>
            </html>
            """

            if let data = safeHTML.data(using: .utf8) {
                let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ]

                let attributed = try NSAttributedString(data: data, options: options, documentAttributes: nil)
                return try AttributedString(attributed)
            }
        } catch {
            print("DEBUG: HTML parsing error: \(error)")
        }

        // Fallback to plain text if HTML parsing fails
        let plainText = htmlContent
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if plainText.isEmpty {
            return AttributedString("No content available")
        }

        return AttributedString(plainText)
    }
}

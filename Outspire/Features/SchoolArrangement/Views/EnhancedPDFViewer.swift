import PDFKit
import SwiftUI

struct EnhancedPDFViewer: View {
    let url: URL
    let title: String
    let publishDate: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var isShowingControls = true
    @State private var animateIn = false

    /// Detect if device is iPad
    private var isIpad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)

                // PDF Content
                PDFKitView(url: url)
                    .edgesIgnoringSafeArea(.all)
                    .scaleEffect(scale)
                    .offset(offset)
                    .opacity(animateIn ? 1.0 : 0.0)
                    .animation(.easeOut(duration: 0.3), value: animateIn)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastScale
                                lastScale = value

                                // Limit zoom scale between 1 and 4
                                scale = min(max(1.0, scale * delta), 4.0)
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
                                        width: value.translation.width + lastOffset.width,
                                        height: value.translation.height + lastOffset.height
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
                                        scale = 1.0
                                        offset = .zero
                                        lastOffset = .zero
                                    } else {
                                        scale = 2.0
                                    }
                                }
                            }
                    )
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isShowingControls.toggle()
                        }
                    }

                // Floating controls
                VStack {
                    if isShowingControls {
                        // Top controls
                        HStack {
                            Button(action: {
                                withAnimation(.spring(response: 0.4)) {
                                    scale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                }
                            }) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(12)
                                    .background(Circle().fill(Color.black.opacity(0.6)))
                            }
                            .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)

                            Spacer()

                            if !isIpad {
                                Button(action: {
                                    dismiss()
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(12)
                                        .background(Circle().fill(Color.black.opacity(0.6)))
                                }
                                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
                            }
                        }
                        .padding([.horizontal, .top])
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    Spacer()

                    if isShowingControls {
                        // Bottom controls
                        HStack {
                            Button(action: {
                                // Share PDF
                                presentShareSheet(url: url)
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Share PDF")
                                }
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(Color.blue))
                            }
                            .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
                        }
                        .padding()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .opacity(animateIn ? 1.0 : 0.0)
                .animation(.easeOut(duration: 0.5).delay(0.2), value: animateIn)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(isIpad ? .large : .inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                animateIn = true
            }
        }
        .preferredColorScheme(.light) // Ensures consistent PDF viewing experience
    }

    private func presentShareSheet(url: URL) {
        let activityVC = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )

        // Present the activity view controller
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController
        {
            // On iPad, set the popover presentation controller's source
            if UIDevice.current.userInterfaceIdiom == .pad {
                activityVC.popoverPresentationController?.sourceView = rootVC.view
                activityVC.popoverPresentationController?.sourceRect = CGRect(
                    x: UIScreen.main.bounds.width / 2,
                    y: UIScreen.main.bounds.height / 2,
                    width: 0,
                    height: 0
                )
                activityVC.popoverPresentationController?.permittedArrowDirections = []
            }
            rootVC.present(activityVC, animated: true)
        }
    }
}

/// PDF view wrapper using PDFKit
struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.displayMode = .singlePage
        pdfView.autoScales = true
        pdfView.displayDirection = .vertical
        pdfView.document = PDFDocument(url: url)
        pdfView.minScaleFactor = pdfView.scaleFactorForSizeToFit
        pdfView.maxScaleFactor = 4.0 * pdfView.scaleFactorForSizeToFit

        // Set background color to match system background
        pdfView.backgroundColor = .systemBackground

        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        // No update needed
    }
}

#Preview {
    // Preview with a sample PDF
    let url = Bundle.main.url(forResource: "sample", withExtension: "pdf") ?? URL(string: "about:blank")!
    return EnhancedPDFViewer(url: url, title: "Sample Document", publishDate: "2023-04-12")
}

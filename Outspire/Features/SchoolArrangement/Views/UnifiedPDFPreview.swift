import QuickLook
import SwiftUI
import UIKit

struct UnifiedPDFPreview: View {
    let url: URL
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            QuickLookPreviewWithCustomization(url: url, title: title)
                .edgesIgnoringSafeArea(.all)
                .ignoresSafeArea()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// QuickLook preview with customization to hide the duplicate navigation bar
struct QuickLookPreviewWithCustomization: UIViewControllerRepresentable {
    let url: URL
    let title: String

    func makeUIViewController(context: Context) -> UINavigationController {
        let previewController = CustomQLPreviewController()
        previewController.dataSource = context.coordinator
        previewController.delegate = context.coordinator

        // Create navigation controller but don't add our own share button
        let navigationController = UINavigationController(rootViewController: previewController)
        navigationController.isNavigationBarHidden = true // Hide the internal nav bar

        return navigationController
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        if let previewController = uiViewController.topViewController as? QLPreviewController {
            previewController.reloadData()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        let parent: QuickLookPreviewWithCustomization

        init(_ parent: QuickLookPreviewWithCustomization) {
            self.parent = parent
            super.init()
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            parent.url as NSURL
        }

        /// Remove the document title from QuickLook
        func previewController(
            _ controller: QLPreviewController,
            editingModeFor previewItem: QLPreviewItem
        ) -> QLPreviewItemEditingMode {
            .disabled
        }

        /// Handle any additional customization needed when the preview loads
        func previewControllerDidStartPreview(_ controller: QLPreviewController) {
            // Remove any toolbar items from the QuickLook controller's view
            if let customController = controller as? CustomQLPreviewController {
                customController.hideTopTitleBar()
            }
        }
    }
}

/// Custom QLPreviewController to hide only the top title bar while preserving the bottom toolbar
class CustomQLPreviewController: QLPreviewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        hideTopTitleBar()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hideTopTitleBar()

        // Additional check with a slight delay to ensure the title bar is hidden
        // after QuickLook completely loads all its interface elements
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.hideTopTitleBar()
        }
    }

    /// Selectively hide only the top title bar
    func hideTopTitleBar() {
        // Find the navigation bar in the view hierarchy that's showing the document title
        findAndHideTopNavigationBar(in: self.view)
    }

    private func findAndHideTopNavigationBar(in view: UIView) {
        // Navigation bars in QuickLook that show the filename typically appear at the top
        // They are different from the bottom toolbar that contains sharing options
        if let navigationBar = view as? UINavigationBar {
            // Check if this is a top navigation bar (showing document title)
            // Top bars are usually positioned within the top 100 points of the screen
            if navigationBar.frame.origin.y < 100 {
                navigationBar.isHidden = true
            }
        }

        // Recursively search in subviews
        for subview in view.subviews {
            findAndHideTopNavigationBar(in: subview)
        }
    }
}

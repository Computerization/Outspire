// ReceiptChecker.swift
// Outspire
//
// Utility to detect current app environment (Simulator, TestFlight, App Store)
//

import Foundation

enum ReceiptChecker {
    private static var isSimulator: Bool {
        #if targetEnvironment(simulator)
            return true
        #else
            return false
        #endif
    }

    private static var hasEmbeddedProvision: Bool {
        Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") != nil
    }

    private static var isSandboxReceipt: Bool {
        guard !isSimulator, let url = Bundle.main.appStoreReceiptURL else { return false }
        return url.lastPathComponent == "sandboxReceipt"
    }

    static var isTestFlight: Bool {
        isSandboxReceipt && !hasEmbeddedProvision
    }

    static var isAppStore: Bool {
        !isSimulator && !isSandboxReceipt && !hasEmbeddedProvision
    }
}

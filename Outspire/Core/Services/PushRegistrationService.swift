import CryptoKit
import Foundation
import OSLog

/// Sends push tokens and schedule data to the CF Worker for Live Activity push delivery.
enum PushRegistrationService {
    private static let workerBaseURL = "https://outspire-apns.wrye.dev"
    private static let deviceIdKey = "push_device_id"
    private static let pendingUnregisterKey = "push_pending_unregister"
    private static let registerFingerprintKey = "push_register_fingerprint"
    private static let registerTimestampKey = "push_register_timestamp"
    private static let registerSkipWindow: TimeInterval = 12 * 60 * 60

    /// Stable per-device identifier stored in Keychain. Survives app reinstalls.
    static var deviceId: String {
        if let existing = SecureStore.get(deviceIdKey) {
            return existing
        }
        let newId = UUID().uuidString
        SecureStore.set(newId, for: deviceIdKey)
        return newId
    }

    static var isSandbox: Bool {
        #if DEBUG
            return true
        #else
            return false
        #endif
    }

    struct RegisterPayload: Encodable {
        let deviceId: String
        let pushStartToken: String
        let sandbox: Bool
        let track: String
        let entryYear: String
        let studentCode: String?
        let schedule: [String: [Period]]

        struct Period: Encodable {
            let periodNumber: Int
            let start: String
            let end: String
            let name: String
            let room: String
            let isSelfStudy: Bool
        }
    }

    struct ActivityTokenPayload: Encodable {
        let deviceId: String
        let activityId: String
        let dayKey: String
        let pushUpdateToken: String
        let owner: String
    }

    struct ActivityEndedPayload: Encodable {
        let deviceId: String
        let activityId: String
        let dayKey: String
    }

    static func register(
        pushStartToken: String,
        studentCode: String,
        studentInfo: StudentInfo,
        timetable: [[String]],
        completion: ((Bool) -> Void)? = nil
    ) {
        let schedule = buildWeekSchedule(from: timetable)

        let payload = RegisterPayload(
            deviceId: deviceId,
            pushStartToken: pushStartToken,
            sandbox: isSandbox,
            track: studentInfo.track.rawValue,
            entryYear: studentInfo.entryYear,
            studentCode: studentCode,
            schedule: schedule
        )

        if let fingerprint = registerFingerprint(for: payload),
           shouldSkipRegister(fingerprint: fingerprint)
        {
            Log.net.info("Skipping redundant push register")
            completion?(true)
            return
        }

        post(endpoint: "/register", body: payload) { success in
            if success {
                // A successful register supersedes any pending unregister from a previous logout
                UserDefaults.standard.removeObject(forKey: pendingUnregisterKey)
                if let fingerprint = registerFingerprint(for: payload) {
                    recordSuccessfulRegister(fingerprint: fingerprint)
                }
            }
            completion?(success)
        }
    }

    static func pause(resumeDate: String? = nil) {
        struct Body: Encodable {
            let deviceId: String
            let resumeDate: String?
        }
        post(endpoint: "/pause", body: Body(deviceId: deviceId, resumeDate: resumeDate))
    }

    static func resume() {
        struct Body: Encodable {
            let deviceId: String
        }
        post(endpoint: "/resume", body: Body(deviceId: deviceId))
    }

    static func updateActivityToken(
        activityId: String,
        dayKey: String,
        pushUpdateToken: String,
        owner: String,
        completion: ((Bool) -> Void)? = nil
    ) {
        let body = ActivityTokenPayload(
            deviceId: deviceId,
            activityId: activityId,
            dayKey: dayKey,
            pushUpdateToken: pushUpdateToken,
            owner: owner
        )
        post(endpoint: "/activity-token", body: body, completion: completion)
    }

    static func notifyActivityEnded(
        activityId: String,
        dayKey: String,
        completion: ((Bool) -> Void)? = nil
    ) {
        let body = ActivityEndedPayload(
            deviceId: deviceId,
            activityId: activityId,
            dayKey: dayKey
        )
        post(endpoint: "/activity-ended", body: body, completion: completion)
    }

    /// Remove this device's registration from the Worker (logout / account switch).
    /// Persists a tombstone so the unregister is retried if the network is down.
    static func unregister() {
        // Mark as pending so we retry on next launch if this fails
        UserDefaults.standard.set(true, forKey: pendingUnregisterKey)
        clearRegisterCache()

        struct Body: Encodable {
            let deviceId: String
        }
        post(endpoint: "/unregister", body: Body(deviceId: deviceId)) { success in
            if success {
                UserDefaults.standard.removeObject(forKey: pendingUnregisterKey)
                clearRegisterCache()
            }
        }
    }

    /// Call on app launch to retry any unregister that failed previously.
    static func retryPendingUnregisterIfNeeded() {
        guard UserDefaults.standard.bool(forKey: pendingUnregisterKey) else { return }
        Log.net.info("Retrying pending push unregister...")
        struct Body: Encodable {
            let deviceId: String
        }
        post(endpoint: "/unregister", body: Body(deviceId: deviceId)) { success in
            if success {
                UserDefaults.standard.removeObject(forKey: pendingUnregisterKey)
                clearRegisterCache()
                Log.net.info("Pending push unregister succeeded")
            }
        }
    }

    // MARK: - Private

    private static func post<T: Encodable>(
        endpoint: String,
        body: T,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard let url = URL(string: workerBaseURL + endpoint) else {
            completion?(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Configuration.pushWorkerAuthSecret, forHTTPHeaderField: "x-auth-secret")
        request.timeoutInterval = 10

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            Log.net.error("Failed to encode push registration: \(error.localizedDescription)")
            completion?(false)
            return
        }

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error {
                Log.net.error("Push registration failed: \(error.localizedDescription)")
                completion?(false)
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                Log.net.info("Push registration successful for \(endpoint)")
                completion?(true)
            } else {
                Log.net.warning("Push registration returned non-200")
                completion?(false)
            }
        }.resume()
    }

    /// Convert the app's 2D timetable grid into a weekday-keyed schedule
    /// matching the CF Worker's expected format.
    private static func buildWeekSchedule(
        from timetable: [[String]]
    ) -> [String: [RegisterPayload.Period]] {
        guard !timetable.isEmpty else { return [:] }

        let periods = ClassPeriodsManager.shared.classPeriods
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        var result: [String: [RegisterPayload.Period]] = [:]

        for dayIndex in 0 ..< 5 {
            let normalized = NormalizedScheduleBuilder.buildDaySchedule(
                from: timetable,
                dayIndex: dayIndex,
                periods: periods
            )

            result[String(dayIndex + 1)] = normalized.map { period in
                RegisterPayload.Period(
                    periodNumber: period.periodNumber,
                    start: timeFormatter.string(from: period.startTime),
                    end: timeFormatter.string(from: period.endTime),
                    name: period.className,
                    room: period.roomNumber,
                    isSelfStudy: period.isSelfStudy
                )
            }
        }

        return result
    }

    private static func registerFingerprint(for payload: RegisterPayload) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        guard let data = try? encoder.encode(payload) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func shouldSkipRegister(fingerprint: String) -> Bool {
        guard !UserDefaults.standard.bool(forKey: pendingUnregisterKey) else { return false }
        guard UserDefaults.standard.string(forKey: registerFingerprintKey) == fingerprint else { return false }

        let lastRegisteredAt = UserDefaults.standard.double(forKey: registerTimestampKey)
        guard lastRegisteredAt > 0 else { return false }

        return Date().timeIntervalSince1970 - lastRegisteredAt < registerSkipWindow
    }

    private static func recordSuccessfulRegister(fingerprint: String) {
        UserDefaults.standard.set(fingerprint, forKey: registerFingerprintKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: registerTimestampKey)
    }

    private static func clearRegisterCache() {
        UserDefaults.standard.removeObject(forKey: registerFingerprintKey)
        UserDefaults.standard.removeObject(forKey: registerTimestampKey)
    }
}

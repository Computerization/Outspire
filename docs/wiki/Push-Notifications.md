# Push Notifications

## Local Notifications

`NotificationManager` (`Core/Services/NotificationManager.swift`) schedules local class reminders.

### Configuration

- Category: `CLASS_REMINDER`
- Lead time: 5 minutes before class start

### Scheduling

`scheduleClassReminders(timetable:)` processes the 2D timetable grid:

1. Cancels all existing class reminders
2. For each non-empty cell with a future start time:
   - Extracts subject and room from cell data
   - Creates `UNNotificationRequest` with 5-minute-before trigger
   - ID format: `class-reminder-{periodNumber}`
3. Only schedules for today's classes that haven't started yet

### Lifecycle

- `handleAppBecameActive()` -- Reschedules if onboarding complete
- `handleNotificationSettingsChange()` -- Re-schedules when permissions change
- `cancelAllNotifications()` -- Removes all pending notifications

## APNs Push Worker

Server-driven Live Activity updates via a Cloudflare Worker at `outspire-apns.wrye.dev`. Uses D1 (SQL database) for registrations and dispatch jobs, KV for caching external calendar/holiday data.

For the full worker architecture (D1 schema, cron phases, APNs integration, state model), see [Push-Worker.md](Push-Worker.md).

### iOS Client Integration

`PushRegistrationService` (`Core/Services/PushRegistrationService.swift`) handles registration:

**Endpoints:**

| Endpoint | Purpose |
|----------|---------|
| `/register` | Full schedule payload (device ID, tokens, track, schedule) |
| `/unregister` | Remove device |
| `/pause` | Pause with optional resume date |
| `/resume` | Re-enable |
| `/activity-token` | Update token for specific activity |
| `/activity-ended` | Signal activity completion |

**Registration Payload:**
```swift
RegisterPayload {
    deviceId: String        // Stable UUID from Keychain
    pushStartToken: String  // ActivityKit pushToStartToken
    sandbox: Bool           // Debug vs production APNs
    track: String           // "ibdp" or "alevel"
    entryYear: String       // e.g., "2023"
    studentCode: String
    schedule: [String: [Period]]  // Weekday-keyed schedule
}
```

**Deduplication:**
- SHA256 hash of sorted JSON payload = fingerprint
- Skips registration if fingerprint matches and <12 hours elapsed
- Fingerprint + timestamp stored in UserDefaults

**Reliability:**
- Failed unregister persisted as tombstone (`push_pending_unregister`)
- `retryPendingUnregisterIfNeeded()` called on app launch
- All requests use `x-auth-secret` header from `Configuration.pushWorkerAuthSecret`
- 10-second timeout

### Device Identity

Each device generates a stable UUID on first launch, stored in Keychain (`SecureStore` key: `push_device_id`). This ID is the primary key in the worker's D1 `registrations` table, so re-registrations upsert the same row.

### Authentication

All mutating endpoints require `x-auth-secret` header matching the `APNS_AUTH_SECRET` Wrangler secret. The iOS client reads this from `Configuration.pushWorkerAuthSecret` (in git-ignored `Configurations.local.swift`).

### Logout Cleanup

`AuthServiceV2.clearSession()` triggers:
1. `ClassActivityManager.endAllActivities()` -- Ends running Live Activities
2. `PushRegistrationService.unregister()` -- Removes device from Worker

If offline at logout, the unregister is tombstoned and retried on next launch.

For the full push worker architecture (D1 schema, cron phases, APNs integration), see [Push-Worker.md](Push-Worker.md).

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

Server-driven Live Activity updates via a Cloudflare Worker at `outspire-apns.wrye.dev`.

### Architecture

Two-phase system:

1. **Daily Planner** (cron: CST 06:30) -- Pre-computes the entire day's push schedule into time-indexed KV dispatch slots
2. **Per-Minute Dispatcher** (cron: CST 07:00-18:59) -- Reads one KV key per minute and fires pushes

This is O(1) per minute regardless of user count.

### Push Schedule per Day

| Time | Event | Content State |
|------|-------|---------------|
| 30 min before first class | `start` | First class, status: `upcoming` |
| Class start time | `update` | Current class, status: `ongoing` |
| 5 min before class end | `update` | Current class, status: `ending` |
| Class end time | `update` | Next class, status: `break` |
| Last class end time | `end` | Dismisses Live Activity after 15 min |

### Day Decision Logic

For each user during daily planning:
1. Check pause state (skip if paused; auto-resume if `resumeDate` reached)
2. Check school calendar (semester range, special days, cancellations, makeup days)
3. Check Chinese statutory holidays/workdays
4. Check weekday (skip weekends unless makeup day)
5. Build dispatch slots for normal school days

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

Each device generates a stable UUID on first launch, stored in Keychain (`SecureStore` key: `push_device_id`). This ID is used as the KV key for the Cloudflare Worker, so re-registrations overwrite the same record instead of creating duplicates.

### KV Schema

| Key Pattern | Contents | TTL |
|-------------|----------|-----|
| `reg:{deviceId}` | Registration (tokens, schedule, pause state) | 30 days |
| `dispatch:{YYYY-MM-DD}:{HH:MM}` | Push jobs for that minute | ~20 hours |
| `cache:school-cal:{year}` | School calendar JSON | 5 min |
| `cache:holiday-cn:{year}` | Chinese holiday list | 1 hour |

### Authentication

All mutating endpoints require `x-auth-secret` header matching the `APNS_AUTH_SECRET` Wrangler secret. The iOS client reads this from `Configuration.pushWorkerAuthSecret` (in git-ignored `Configurations.local.swift`).

### Logout Cleanup

`AuthServiceV2.clearSession()` triggers:
1. `ClassActivityManager.endAllActivities()` -- Ends running Live Activities
2. `PushRegistrationService.unregister()` -- Removes device from Worker

If offline at logout, the unregister is tombstoned and retried on next launch.

For the full push worker architecture, see [docs/archive/apns-push-worker.md](../archive/apns-push-worker.md).

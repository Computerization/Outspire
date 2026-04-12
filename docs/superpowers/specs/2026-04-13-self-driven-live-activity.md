# Spec: Self-Driven Live Activity (No Update Push Required)

## Problem

The current Live Activity architecture requires `pushUpdateToken` to send update/end pushes via the Worker. This token is per-activity-instance — every new LA gets a new one, and it can only be observed when the app process is running (`activity.pushTokenUpdates`).

This means:
- Worker can remote-start a LA via `pushStartToken` (global, stable)
- But subsequent update/end pushes need the new LA's `pushUpdateToken`
- If the app isn't running, nobody observes the new token → Worker has stale token → updates fail
- Result: **LA shows the first class and freezes at 0:00 when it ends**

Users must open the app at least once per school day for the push-update flow to work.

## Solution

**Embed the full day's schedule in the start push's content-state.** The LA UI uses `TimelineView` to self-drive through the day's classes based on current time. No update pushes needed.

### Architecture Change

```
BEFORE: Worker sends ~15 pushes/day/user (1 start + ~13 updates + 1 end)
  start(class1) → update(ongoing) → update(ending) → update(break) → update(class2) → ... → end

AFTER: Worker sends 1 push/day/user (start only)
  start(full_schedule) → LA UI self-drives all transitions → app ends when foregrounded
```

## Constraints & Limitations

### 8-Hour System Hard Cap
Apple may auto-end Live Activities after ~8 hours. School day runs 08:15–16:30 (~8.25 hours). **Start the LA at 08:00 (first bell)** — this gives 08:00→16:30 = 8h 30min, tight but feasible. If Apple enforces strictly, the last class or two may lose the LA. This is acceptable — the app can restart it when foregrounded. Starting at 08:00 rather than 07:50 preserves end-of-day coverage which matters more than 10 min of pre-bell visibility.

### staleDate Does NOT Dismiss
`staleDate` only marks the LA as `.stale` (dimmed UI). It does **not** remove it. Actual removal requires:
- **App in foreground**: `activity.end(dismissalPolicy:)` — existing `endActivity()` handles this
- **App not running**: LA persists in stale/dimmed state until system removes it (~4 hours after stale) or user swipes it away
- This is acceptable — a dimmed "school's out" LA for a few hours is not harmful

### push-to-start Requires Alert
Apple requires an `alert` configuration in the push-to-start payload. The current Worker start push is missing this. Must add:
```json
{
  "aps": {
    "timestamp": 1234567890,
    "event": "start",
    "alert": {
      "title": "Today's Schedule",
      "body": "Your class schedule is now live"
    },
    "content-state": { ... },
    "attributes-type": "ClassActivityAttributes",
    "attributes": { "startDate": ... },
    "stale-date": ...
  }
}
```

### push-to-start is iOS 17.2+
Already gated in `ClassActivityManager.init()` with `if #available(iOS 17.2, *)`.

### TimelineView Refresh is Best-Effort
`TimelineView(.periodic(from:by:30))` triggers view re-evaluation, but the system may coalesce refreshes on the lock screen. Transitions between classes may be delayed 30–60 seconds for non-countdown elements (class name, room, status label, progress bar). `Text(timerInterval:)` countdown remains precise regardless.

**Accepted tradeoff**: A 30-60 second delay in switching labels is far better than being stuck on the first class forever.

## Data Model

### New ContentState

```swift
struct ClassActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var classes: [ClassInfo]
        
        struct ClassInfo: Codable, Hashable {
            var name: String
            var room: String
            var start: Date
            var end: Date
        }
    }
    
    var startDate: Date
}
```

### Size Estimate (Must be < 4KB)

Codex verified: 9 classes with realistic names → ~870 bytes for content-state, ~920 bytes for full `aps` payload. With 40-char names and 12-char rooms: ~1.2KB. Hard limit is 4KB.

**Safety target**: < 2KB. Add a unit test that encodes the exact payload and fails above 3KB.

## LA UI Design

The UI reuses the existing visual design (class name, room, countdown, progress bar) but computes the current state from the schedule array instead of reading it from content-state fields.

### State Computation Logic

```swift
/// Pure function — computes display state from schedule + current time.
/// Moved from ClassActivityManager into the widget view layer.
struct DisplayState {
    var className: String
    var roomNumber: String
    var status: Status
    var periodStart: Date
    var periodEnd: Date
    var nextClassName: String?
    
    enum Status { case ongoing, ending, upcoming, `break`, done }
}

func currentState(from classes: [ClassActivityAttributes.ContentState.ClassInfo], at now: Date) -> DisplayState? {
    // Currently in a class?
    if let current = classes.first(where: { $0.start <= now && $0.end > now }) {
        let next = classes.first(where: { $0.start >= current.end })
        let remaining = current.end.timeIntervalSince(now)
        return DisplayState(
            className: current.name,
            roomNumber: current.room,
            status: remaining <= 300 ? .ending : .ongoing,
            periodStart: current.start,
            periodEnd: current.end,
            nextClassName: next?.name
        )
    }
    
    // Between classes (break)?
    let previous = classes.last(where: { $0.end <= now })
    if let next = classes.first(where: { $0.start > now }) {
        if let prev = previous {
            let gap = next.start.timeIntervalSince(prev.end)
            return DisplayState(
                className: gap > 1800 ? "Lunch Break" : "Break",
                roomNumber: "",
                status: .break,
                periodStart: prev.end,
                periodEnd: next.start,
                nextClassName: next.name
            )
        }
        // Before first class
        return DisplayState(
            className: next.name,
            roomNumber: next.room,
            status: .upcoming,
            periodStart: next.start,
            periodEnd: next.end,
            nextClassName: classes.first(where: { $0.start > next.start })?.name
        )
    }
    
    // All classes done — return nil to let staleDate dim the LA.
    // Don't show a "School's Out" badge in compact views.
    return nil
}
```

### TimelineView Usage

```swift
TimelineView(.periodic(from: .now, by: 30)) { timeline in
    if let state = currentState(from: context.state.classes, at: timeline.date) {
        // Render class name, room, countdown, progress...
        // Text(timerInterval:) gets new range each time TimelineView re-evaluates
    }
}
```

- `Text(timerInterval: state.periodStart...state.periodEnd, countsDown: true)` — system-driven, precise to the second
- TimelineView body re-evaluation (~30s) — updates class name, room, status, progress bar
- When body re-evaluates with a new `periodStart...periodEnd`, `Text(timerInterval:)` starts counting down the new range

### No Per-Transition Foreground Updates

Codex correctly noted: since ContentState is now `classes:[]`, calling `activity.update()` per transition adds no value — the UI already derives state from the array. **Drop `updateForCurrentState` entirely.** The app only calls:
- `activity.end()` when all classes are done (app in foreground)
- No other updates needed

## Worker Changes

### Simplified Push Schedule

`buildPushSchedule` generates exactly **one** start event per day:

```typescript
function buildPushSchedule(periods: ClassPeriod[], decision: DayDecision): ScheduledPush[] {
    if (decision.cancelsClasses) {
        return [{
            time: "07:45",
            event: "start",
            contentState: {
                classes: [{
                    name: decision.eventName ?? "No Classes",
                    room: "",
                    start: timeToAppleDate("07:45"),
                    end: timeToAppleDate("08:45")
                }]
            },
            staleDate: timeToAppleDate("09:00"),
            alert: { title: decision.eventName ?? "No Classes", body: "Classes are cancelled today" }
        }];
    }
    
    if (periods.length === 0) return [];
    
    // Start at 08:00 (first bell) to stay within 8-hour LA cap
    return [{
        time: "08:00",
        event: "start",
        contentState: {
            classes: periods.map(p => ({
                name: p.name,
                room: p.room,
                start: timeToAppleDate(p.start),
                end: timeToAppleDate(p.end)
            }))
        },
        staleDate: timeToAppleDate(periods[periods.length - 1].end) + 900,
        alert: { title: "Today's Schedule", body: `${periods.length} classes today` }
    }];
}
```

### Simplified Dispatch Architecture

One push per day makes the multi-slot dispatch architecture overkill. Simplify:

- **Daily planner (06:30 CST)**: For each user, compute the day's decision + build the single start push. Write to **one dispatch slot per user**: `dispatch:{date}:08:00` (or the appropriate start time).
- **Minute dispatcher**: Unchanged — reads `dispatch:{date}:{HH:MM}`, fires pushes, deletes slot. But now most slots have all users bundled into a single `08:00` slot.
- **Mid-day registration**: If a user `/register`s after 08:00, **send the start push immediately** with only remaining classes (filter out classes where `end < now`). This ensures late joiners get a LA for the rest of the day.

### Registration Changes

`/register` no longer requires `pushUpdateToken`:
```typescript
interface RegisterBody {
    deviceId: string;
    pushStartToken: string;
    // pushUpdateToken: removed
    sandbox?: boolean;
    track: "ibdp" | "alevel";
    entryYear: string;
    schedule: Record<string, ClassPeriod[]>;
}

interface StoredRegistration {
    pushStartToken: string;
    // pushUpdateToken: removed
    sandbox: boolean;
    track: "ibdp" | "alevel";
    entryYear: string;
    schedule: Record<string, ClassPeriod[]>;
    paused: boolean;
    resumeDate?: string;
}
```

### Cron Simplification

```toml
# wrangler.toml
# Daily planner: 22:30 UTC = 06:30 CST
# Dispatch window: only 00:00 UTC = 08:00 CST (one slot per day)
# Keep small window for late registrations: 00:00-09:00 UTC = 08:00-17:00 CST
crons = ["30 22 * * *", "* 0-9 * * *"]
```

## iOS Client Changes

### ClassActivityManager Simplification

**Registration**: `registerIfReady()` drops the `lastPushUpdateToken` requirement. Only needs `pushStartToken` + timetable + user info. Can register any day including weekends.

**Start**: `startActivity()` builds ContentState with full schedule `classes:[]` instead of single-class fields.

**Update**: Drop `updateForCurrentState()` entirely. The view self-drives.

**End**: Keep `endActivity()` — called when app is foregrounded and all classes are done.

**Restore**: `restoreExistingActivity()` simplified — just reattach to existing activity for end-of-day cleanup, no token observation needed.

### PushRegistrationService

Remove `pushUpdateToken` from `RegisterPayload`. Remove `lastPushUpdateToken` tracking from `ClassActivityManager`. Remove `observePushTokenUpdates`.

## Files to Modify

| File | Change |
|------|--------|
| `Outspire/Features/LiveActivity/ClassActivityAttributes.swift` | Replace ContentState with `classes: [ClassInfo]` |
| `OutspireWidget/Shared/ClassActivityAttributes.swift` | Same (must stay in sync) |
| `OutspireWidget/OutspireWidgetLiveActivity.swift` | Rewrite views: add `currentState()` function, wrap all rendering in `TimelineView`, handle `.done` state |
| `Outspire/Features/LiveActivity/ClassActivityManager.swift` | Drop `lastPushUpdateToken`, `observePushTokenUpdates`, `updateForCurrentState`. Simplify `registerIfReady`. Update `startActivity` to build new ContentState. |
| `Outspire/Core/Services/PushRegistrationService.swift` | Remove `pushUpdateToken` from RegisterPayload |
| `worker/src/index.ts` | Simplify `buildPushSchedule` (1 event), `StoredRegistration` (no updateToken), `scheduleToPushJobs` (add alert), mid-day immediate push. Remove update/end push logic. |
| `worker/wrangler.toml` | Narrow cron window |
| `docs/apns-push-worker.md` | Update architecture description |

## Migration & Backward Compatibility

- Old app versions receiving new-format start push: `ContentState` decode fails → LA silently doesn't appear (safe)
- New app version with old Worker: won't happen (deploy Worker first)
- Deployment order: **Worker first**, **then app update**

## Implementation Notes

### Sorting Invariant
Both the Worker and the `currentState()` function assume `classes` are sorted by `start` time ascending. The Worker builds the array from `periods` which come sorted from the app's timetable grid. Add an explicit sort in `currentState()` as a safety measure: `let sorted = classes.sorted { $0.start < $1.start }`.

### Mid-Day Registration
Factor one shared function for building the start push payload. Both the daily planner and `/register` handler call it. For mid-day `/register`:
- Filter classes where `end > now`
- If no remaining classes → return `200 { ok: true, pushed: false }`, don't send push
- If remaining classes → send start push immediately via `sendPush()`, don't write dispatch slot
- Key idempotency on `deviceId + date` — if already pushed today, skip (track in KV: `pushed:{date}:{deviceId}` with 20h TTL)

### Schema Drift Prevention
One canonical `ClassActivityAttributes` struct shared across both targets via the Xcode file reference. Add an end-to-end decode test: construct a JSON payload matching Worker output, verify `JSONDecoder().decode(ClassActivityAttributes.ContentState.self, from:)` succeeds.

## Testing Plan

1. **Unit test**: `currentState(from:at:)` with various time inputs (before school, during class, break, lunch, after school, all done)
2. **Size test**: Encode 9-class ContentState + full `aps` payload, assert < 2KB (fail at 3KB)
3. **Simulator**: Start LA locally, verify TimelineView transitions between classes
4. **Real device**: 
   - Push a start via Worker, kill app, observe LA self-driving through schedule on lock screen
   - Verify `Text(timerInterval:)` picks up new range at class boundaries
   - Verify staleDate dims the LA after last class
5. **Edge cases**: 0 classes day, cancelled classes day, weekend registration, mid-day registration (remaining classes only)
6. **8-hour cap**: Start LA at 08:00, verify it survives until 16:30

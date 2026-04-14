# Push Worker (outspire-apns)

Server-driven Live Activity updates via Cloudflare Workers + APNs.

**Source:** `worker/src/index.ts`, `worker/src/apns.ts`

## Overview

The Cloudflare Worker at `outspire-apns.wrye.dev` manages push-driven Live Activity updates. It uses a **two-phase architecture**: a daily planner pre-computes the entire day's push schedule, and a per-minute dispatcher fires pushes from pre-built dispatch slots.

## Storage

The worker uses **two Cloudflare storage backends**:

### D1 Database (primary storage)

Binding: `OUTSPIRE_DB`, database: `outspire-push`

**Schema** (from `worker/d1-schema.sql`):

```sql
-- Device registrations
CREATE TABLE registrations (
  device_id TEXT PRIMARY KEY,
  push_start_token TEXT NOT NULL,
  sandbox INTEGER NOT NULL DEFAULT 0,
  track TEXT NOT NULL,              -- "ibdp" or "alevel"
  entry_year TEXT NOT NULL,
  schedule_json TEXT NOT NULL,       -- JSON: Record<weekday, ClassPeriod[]>
  paused INTEGER NOT NULL DEFAULT 0,
  resume_date TEXT,
  current_activity_json TEXT,        -- JSON: ActivityRecord (active Live Activity)
  updated_at INTEGER NOT NULL
);

-- Pre-computed push dispatch slots
CREATE TABLE dispatch_jobs (
  day_key TEXT NOT NULL,             -- "YYYY-MM-DD"
  time TEXT NOT NULL,                -- "HH:MM" in CST
  device_id TEXT NOT NULL,
  kind TEXT NOT NULL,                -- "start", "update", or "end"
  token TEXT NOT NULL,               -- APNs device token
  sandbox INTEGER NOT NULL DEFAULT 0,
  push_type TEXT NOT NULL,           -- "liveactivity"
  topic TEXT NOT NULL,               -- APNs topic
  payload_json TEXT NOT NULL,        -- Full APNs payload as JSON
  attempts INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (day_key, time, device_id, kind)
);

-- Indexes
CREATE INDEX idx_dispatch_jobs_slot ON dispatch_jobs(day_key, time);
CREATE INDEX idx_dispatch_jobs_device_day ON dispatch_jobs(day_key, device_id);
```

### KV Namespace (cache only)

Binding: `OUTSPIRE_KV`

Used exclusively for caching external API responses:

| Key Pattern | Contents | TTL |
|-------------|----------|-----|
| `cache:holiday-cn:{year}` | Chinese statutory holiday list | 1 hour |
| `cache:school-cal:{academicYear}` | School calendar JSON | 5 minutes |

## Two-Phase Cron Architecture

### Phase 1: Daily Planner

**Cron:** `30 22 * * *` (UTC) = 06:30 CST

Runs once per day before school starts:

1. Cleanup stale data (old dispatch jobs, expired registrations)
2. For each registration in D1:
   - Clear stale `currentActivity` from previous day
   - Evaluate day decision (school calendar, holidays, pause state, weekday)
   - Build state transitions (upcoming → ongoing → ending → break → done)
   - Write `start` job to `dispatch_jobs` table
3. Batch-insert all jobs (50 per D1 batch)

### Phase 2: Per-Minute Dispatcher

**Cron:** `* 23 * * *`, `* 0-8 * * *` (UTC) = CST 07:00-16:59

Runs every minute during school hours:

1. Query `dispatch_jobs` for `day_key = today AND time = HH:MM`
2. For each job:
   - Verify registration still exists
   - Verify token matches current activity (for update/end jobs)
   - Skip start jobs if activity already exists for today
   - Send APNs push via `sendPush()`
   - Update `lastSequence` on successful update pushes
   - Clear `currentActivity` on successful end pushes
3. Handle failures:
   - **410 (token revoked)**: Delete registration + all pending jobs
   - **429 or 5xx**: Retry up to 2 times with 1-2 minute delay
4. Clean up dispatched slot

## API Endpoints

All mutating endpoints require `x-auth-secret` header.

| Endpoint | Method | Body | Effect |
|----------|--------|------|--------|
| `/health` | GET | -- | Returns `{ ok, date }` |
| `/register` | POST | `RegisterBody` | Upsert registration, schedule start job |
| `/activity-token` | POST | `ActivityTokenBody` | Attach push update token, schedule update/end jobs |
| `/activity-ended` | POST | `ActivityEndedBody` | Clear activity, remove pending jobs |
| `/unregister` | POST | `{ deviceId }` | Delete registration + all pending jobs |
| `/pause` | POST | `{ deviceId, resumeDate? }` | Pause + remove pending jobs |
| `/resume` | POST | `{ deviceId }` | Unpause + schedule start job |

### RegisterBody

```typescript
{
  deviceId: string;
  pushStartToken: string;
  sandbox?: boolean;
  track: "ibdp" | "alevel";
  entryYear: string;
  studentCode?: string;
  schedule: Record<string, ClassPeriod[]>;  // weekday → periods
}
```

### ActivityTokenBody

```typescript
{
  deviceId: string;
  activityId: string;
  dayKey: string;           // "YYYY-MM-DD"
  pushUpdateToken: string;
  owner: "app" | "worker";
}
```

## Push Schedule per Day

For each registered device on a school day:

| Time | Kind | Phase | Content |
|------|------|-------|---------|
| 30 min before first class | `start` | `upcoming` | First class info, countdown to start |
| Class start time | `update` | `ongoing` | Current class, countdown to end |
| 5 min before class end | `update` | `ending` | Same class, ending warning |
| Class end time | `update` | `break` | Break/lunch, next class preview |
| Last class end time | `end` | `done` | "Schedule Complete", dismisses after 15 min |

For cancelled-class days (special events):
- 07:45: `start` with phase `event` and event name
- 08:45: `end` with phase `done`

## Day Decision Logic

`decideTodayForUser()` evaluates per-user:

1. **Pause check** -- Skip if paused (auto-resume if `resumeDate` reached)
2. **School calendar** -- Fetch from GitHub (`wfla-events` repo), check semester range
3. **Special days** -- Check for class cancellations or makeup days (with `followsWeekday`)
4. **Chinese holidays** -- Fetch from holiday-cn CDN, check if off-day
5. **Weekend** -- Skip Saturday/Sunday unless makeup day
6. Normal school day → `shouldSendPushes = true`

Calendar filtering respects student `track` (ibdp/alevel) and `entryYear` via `specialDayApplies()`.

## Activity Lifecycle

```
/register
  → scheduleStartJobsForRegistration()
    → If start time is future: write start job to dispatch_jobs
    → If start time is past: send push immediately

[Minute dispatcher fires start push]
  → App receives push-to-start → starts Live Activity
  → App sends /activity-token with pushUpdateToken

/activity-token
  → Store currentActivity on registration
  → Remove start job (already started)
  → scheduleUpdateJobsForActivity()
    → Write update/end jobs for remaining transitions

[Minute dispatcher fires update/end pushes]
  → Update: track lastSequence to avoid duplicate states
  → End: clear currentActivity, dismiss after 15 min
```

## APNs Integration

`worker/src/apns.ts` handles Apple Push:

- **Auth:** ES256 JWT using Web Crypto API (no Node.js deps)
- **JWT caching:** Cached for 50 minutes (APNs tokens last 1 hour)
- **DER handling:** Converts DER signatures to raw r||s format
- **Endpoints:** `api.push.apple.com` (production) or `api.sandbox.push.apple.com`
- **Push type:** Always `liveactivity`
- **Topic:** `{bundleId}.push-type.liveactivity`

## State Model

```typescript
interface SnapshotState {
  dayKey: string;           // "YYYY-MM-DD"
  phase: ActivityPhase;     // upcoming|ongoing|ending|break|event|done
  title: string;            // Class name or status
  subtitle: string;         // Room, "Class-Free Period", or status detail
  rangeStart: number;       // Apple reference date (seconds since 2001-01-01)
  rangeEnd: number;
  nextTitle?: string;       // Next class name (for break phases)
  sequence: number;         // Monotonic counter for ordering
}
```

Sequence numbering: `index * 3 + offset` where offset is 1 (ongoing), 2 (ending), 3 (break).

## Configuration

### wrangler.toml

```toml
[[kv_namespaces]]
binding = "OUTSPIRE_KV"

[[d1_databases]]
binding = "OUTSPIRE_DB"
database_name = "outspire-push"

[triggers]
crons = ["30 22 * * *", "* 23 * * *", "* 0-8 * * *"]

[vars]
GITHUB_CALENDAR_URL = "https://raw.githubusercontent.com/Computerization/wfla-events/main"
HOLIDAY_CN_URL = "https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master"
APNS_BUNDLE_ID = "dev.wrye.Outspire"
```

### Environment Secrets

Set via `wrangler secret put`:

| Secret | Purpose |
|--------|---------|
| `APNS_KEY_ID` | Apple Push key ID |
| `APNS_TEAM_ID` | Apple Developer Team ID |
| `APNS_PRIVATE_KEY` | `.p8` key contents (PEM) |
| `APNS_AUTH_SECRET` | Shared secret for client → Worker auth |

## Reliability

- **Retry logic**: 429/5xx responses retried up to 2 times with 1-2 min delay
- **Token cleanup**: APNs 410 (revoked) → delete registration + all pending jobs
- **Stale data cleanup**: Daily planner removes old dispatch jobs and expired registrations (30-day TTL)
- **Batch writes**: D1 batch limit of 50 statements per batch
- **Idempotent registration**: `ON CONFLICT DO UPDATE` prevents duplicates
- **Sequence tracking**: `lastSequence` on activity records prevents duplicate state pushes
- **Mid-day registration**: Only schedules future time slots (skips passed times)
- **Concurrent safety**: Auto-init with `ensureStorageReady()` on every entry point

## iOS Client Integration

See [Push-Notifications.md](Push-Notifications.md) for the iOS-side `PushRegistrationService` and `ClassActivityManager` integration.

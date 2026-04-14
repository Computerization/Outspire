# APNs Push Worker Architecture

Server-driven Live Activity updates via Cloudflare Workers + APNs.

## Overview

The app registers device push tokens and class schedules with a Cloudflare Worker (`outspire-apns.wrye.dev`). The Worker uses a **two-phase architecture**: a daily planner pre-computes the entire day's push schedule into time-indexed dispatch slots, and a per-minute dispatcher reads a single KV key and fires the pushes. This is O(1) per minute regardless of user count.

## Components

### iOS Client

| File | Role |
|------|------|
| `Core/Services/PushRegistrationService.swift` | Sends device registration, pause, resume, and unregister requests to the Worker |
| `Features/LiveActivity/ClassActivityManager.swift` | Observes `pushToStartTokenUpdates` and `pushTokenUpdates`, triggers registration when both tokens are available |
| `Core/Services/TSIMS/AuthServiceV2.swift` | Calls `unregister()` + `endAllActivities()` on logout to clean up |

### Cloudflare Worker (`worker/`)

| File | Role |
|------|------|
| `src/index.ts` | HTTP endpoints + two-phase cron (daily planner + minute dispatcher) + decision logic |
| `src/apns.ts` | APNs JWT (ES256) auth + push delivery via Web Crypto API |
| `wrangler.toml` | KV namespace, cron triggers, env vars |

## Device Identity

Each device generates a stable UUID on first launch, stored in Keychain (`SecureStore` key: `push_device_id`). This ID is used as the KV key (`reg:{deviceId}`), so re-registrations (token refresh, app restart) overwrite the same record instead of creating garbage entries.

## KV Schema

| Key pattern | Contents | TTL |
|-------------|----------|-----|
| `reg:{deviceId}` | `StoredRegistration` (tokens, schedule, track, pause state) | 30 days |
| `dispatch:{YYYY-MM-DD}:{HH:MM}` | `PushJob[]` — all push jobs for that exact minute | ~20 hours |
| `cache:school-cal:{academicYear}` | School calendar JSON (e.g. `2025-2026`) | 5 min |
| `cache:holiday-cn:{year}` | Holiday-cn day list | 1 hour |

## API Endpoints

All endpoints accept `POST` with JSON body.

| Endpoint | Body | Effect |
|----------|------|--------|
| `/register` | `{ deviceId, pushStartToken, pushUpdateToken, track, entryYear, schedule }` | Creates/overwrites registration + plans today's dispatch |
| `/unregister` | `{ deviceId }` | Deletes registration + removes from all today's dispatch slots |
| `/pause` | `{ deviceId, resumeDate? }` | Pauses + removes from today's dispatch |
| `/resume` | `{ deviceId }` | Unpauses + re-plans today's dispatch |
| `/health` | — | Returns `{ ok: true, time }` |

## Two-Phase Cron Architecture

### Phase 1: Daily Planner (`30 22 * * *` = CST 06:30)

Runs once per day. For each `reg:*` device:

1. Evaluate day decision (school calendar, holidays, pause state, weekday)
2. Build push schedule (start/update/end events with exact `HH:MM` times)
3. Convert to `PushJob` objects (with APNs token, topic, payload template)
4. Write to `dispatch:{date}:{HH:MM}` KV keys, merging with other devices

Also cleans up yesterday's leftover dispatch keys.

**KV operations:** N reads (registrations) + ~15-20×N writes (dispatch slots) — runs once/day.

### Phase 2: Per-Minute Dispatcher (`* 23,0-10 * * *` = CST 07:00-18:59)

Runs every minute during school hours:

1. Read `dispatch:{today}:{HH:MM}` — **single KV read**
2. If empty → return (no-op)
3. Stamp timestamps on payloads and fire each `PushJob` via APNs
4. Delete the dispatch key

**KV operations per minute:** 1 read + 0-1 delete. Constant regardless of user count.

### Cost Comparison

| | Old (every-minute scan) | New (two-phase) |
|---|---|---|
| Per minute | 1 list + N reads + 2 cache reads | 1 read |
| Per day (100 users) | ~148,000 KV ops | ~3,700 KV ops (plan) + ~720 reads (dispatch) ≈ 4,420 |
| Non-school day | Same as school day | ~720 reads (all null) |
| Scaling | O(N) per minute | O(1) per minute, O(N) once/day |

## Push Schedule per Day

| Time | Event | Content State |
|------|-------|---------------|
| 30min before first class | `start` | First class, status: `upcoming` |
| Class start time | `update` | Current class, status: `ongoing` |
| 5min before class end | `update` | Current class, status: `ending` |
| Class end time | `update` | Next class, status: `break` |
| Last class end time | `end` | Dismisses Live Activity after 15min |

## Day Decision Logic

Evaluated per user during daily planning:

1. **Pause check** — skip if paused (auto-resume if `resumeDate` reached)
2. **School calendar** — fetch from GitHub (`calendar/{year-1}-{year}.json` + `calendar/{year}-{year+1}.json`), merge semesters and special days, check semester range and special days (cancellations, makeup days with `followsWeekday`)
3. **Holiday-cn** — check Chinese statutory holidays/workdays
4. **Weekend** — skip Saturday/Sunday unless makeup day
5. Normal school day → build dispatch slots

## Logout / Account Switch

`AuthServiceV2.clearSession()` (called on both successful and failed logout) triggers:
1. `ClassActivityManager.shared.endAllActivities()` — immediately ends any running Live Activity
2. `PushRegistrationService.unregister()` — tells Worker to delete registration + dispatch entries

If the device is offline at logout, the unregister is persisted as a tombstone (`push_pending_unregister` in UserDefaults) and retried on next app launch via `retryPendingUnregisterIfNeeded()`.

On re-login, the same `deviceId` is reused, so the new account's schedule overwrites cleanly.

## Optimistic Auth

On cold launch, if the device has a saved user + Keychain credentials, `AuthServiceV2` immediately sets `isAuthenticated = true` before the network verify completes. This lets the UI show cached timetable data instantly instead of flashing the sign-in prompt. If background verification fails, it attempts reauth; only marks `isAuthenticated = false` if reauth also fails.

## Registration Deduplication

`ClassActivityManager` tracks a `hasRegistered` flag that prevents duplicate `/register` calls within a single token lifecycle. Registration only fires when:
- Both `pushStartToken` and `pushUpdateToken` are available
- A valid timetable has been set via `setTimetable(_:)`
- User info (track, entry year) is available

The flag resets when either token changes or when `setTimetable` is called with new data. A `registerGeneration` counter ensures that responses from outdated register requests (e.g., if a token changed mid-flight) are discarded. `hasRegistered` is not persisted — app kill/relaunch may trigger one redundant but idempotent `/register`.

On launch, existing activities are restored from `Activity.activities` and their `pushTokenUpdates` are re-observed. `lastPushUpdateToken` is cleared when activities end to prevent stale tokens from being registered.

## Authentication

All mutating HTTP endpoints (`/register`, `/unregister`, `/pause`, `/resume`) require an `x-auth-secret` header matching the `APNS_AUTH_SECRET` Wrangler secret. The iOS client reads the secret from `Configuration.pushWorkerAuthSecret` (defined in git-ignored `Configurations.local.swift`).

## Environment Secrets (Wrangler)

Set via `wrangler secret put`:
- `APNS_KEY_ID` — Apple Push key ID
- `APNS_TEAM_ID` — Apple Developer Team ID
- `APNS_PRIVATE_KEY` — `.p8` key contents (PEM)
- `APNS_AUTH_SECRET` — shared secret for client → Worker auth

## Reliability

- **KV list pagination**: All `KV.list()` calls use `kvListAll()` which follows the cursor, handling >1000 keys correctly
- **APNs 410 cleanup**: If APNs returns 410 (token permanently revoked), the Worker deletes the device registration
- **APNs failure logging**: Non-2xx responses are logged via `console.error` for Wrangler tail observability
- **Mid-day registration**: `/register` only plans future time slots (skips already-passed times)
- **Daily planner batching**: Collects all users' jobs in memory first, writes each time slot once — avoids read-merge-write per user

## Known Limitations

- If the daily planner's day-decision data changes after it runs (e.g., school calendar updated mid-day), existing dispatch entries are not recomputed until next day
- APNs 429 (rate limit) and 5xx responses are logged but not retried

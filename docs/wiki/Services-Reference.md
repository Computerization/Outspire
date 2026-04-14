# Services Reference

All major services are singletons accessed via `.shared`.

## AuthServiceV2
**File:** `Core/Services/TSIMS/AuthServiceV2.swift`

| Property | Type | Description |
|----------|------|-------------|
| `user` | `V2User?` | Current authenticated user |
| `isAuthenticated` | `Bool` | Authentication state |
| `isResolvingSession` | `Bool` | True during initial session verification |

| Method | Description |
|--------|-------------|
| `login(code:password:)` | 3-step login (seed → submit → verify) |
| `logout()` | Server logout + full state cleanup |
| `clearSession()` | Delete cookies, reset session, clear storage |
| `fetchProfile()` | HTML scrape of student info page |
| `verifySession()` | GET /Home/GetMenu to check session validity |
| `refreshSessionIfNeeded()` | Re-login with stored credentials if session expired |

## TSIMSClientV2
**File:** `Core/Services/TSIMS/TSIMSClientV2.swift`

| Method | Description |
|--------|-------------|
| `postFormAsync<T>(path:params:)` | POST with form-encoded body |
| `getJSONAsync<T>(path:queryParams:)` | GET with query parameters |
| `postForm<T>(path:params:completion:)` | Callback-based POST |
| `getJSON<T>(path:queryParams:completion:)` | Callback-based GET |
| `postFormRaw(path:params:completion:)` | POST returning raw Data |

Automatic reauthentication on 401, 302, or HTML responses.

## CASServiceV2
**File:** `Core/Services/TSIMS/CASServiceV2.swift`

| Method | Description |
|--------|-------------|
| `fetchGroupList()` | All groups (paginated) |
| `fetchMyGroups()` | Student's joined groups |
| `fetchRecords(groupId:)` | Activity records for group |
| `fetchReflections(groupId:)` | Reflections for group |
| `deleteReflection(id:)` | Remove reflection |
| `deleteRecord(id:)` | Remove record |
| `isGroupLeader(groupId:)` | Check leadership status |
| `joinGroup(groupId:isProject:)` | Join group |
| `exitGroup(groupId:)` | Leave group |
| `fetchEvaluateData(groupId:)` | Scores and evaluation |
| `getCachedGroupDetails(id:)` | Lookup cached group info |

## ScoreServiceV2
**File:** `Core/Services/TSIMS/ScoreServiceV2.swift`

| Method | Description |
|--------|-------------|
| `fetchScores(yearId:)` | GET academic scores for year |

## TimetableServiceV2
**File:** `Core/Services/TSIMS/TimetableServiceV2.swift`

| Method | Description |
|--------|-------------|
| `fetchYearOptions()` | HTML scrape of year dropdown |
| `fetchTimetable(yearId:)` | GET timetable (tries simple then alternate format) |

## HomeServiceV2 (DEAD CODE)
**File:** `Core/Services/TSIMS/HomeServiceV2.swift`

> **Dead code:** `fetchMenu()` is never called by any part of the app. The entire service is unused.

| Method | Description |
|--------|-------------|
| `fetchMenu()` | GET /Home/GetMenu menu structure |

## CacheManager
**File:** `Core/Services/CacheManager.swift`

| Method | Description |
|--------|-------------|
| `clearAllCache()` | Wipe all caches (preserves hideAcademicScore) |
| `clearClasstableCache()` | Clear timetable data |
| `clearAcademicScoresCache()` | Clear score data |
| `clearClubActivitiesCache()` | Clear activity records |
| `clearArrangementsCache()` | Clear school arrangements |
| `getCacheStatus()` | Returns validity flags and timestamps |
| `getEstimatedCacheSize()` | Human-readable size |
| `refreshCache(type:)` | Post refresh notification |
| `cleanupOutdatedCache()` | Remove expired entries |
| `scheduleAutomaticCleanup()` | Daily cleanup timer |

## ConnectivityManager
**File:** `Core/Services/ConnectivityManager.swift`

| Property | Type | Description |
|----------|------|-------------|
| `isInternetAvailable` | `Bool` | Network path status |
| `isCheckingConnectivity` | `Bool` | Check in progress |
| `showNoInternetAlert` | `Bool` | Alert display flag |

| Method | Description |
|--------|-------------|
| `startMonitoring()` | NWPathMonitor + server checks |
| `stopMonitoring()` | Clean up monitor and timers |
| `checkConnectivity()` | HEAD request to TSIMS server |
| `setOnboardingActive()` | Suppress alerts during setup |

## NotificationManager
**File:** `Core/Services/NotificationManager.swift`

| Method | Description |
|--------|-------------|
| `requestAuthorization()` | Request notification permissions |
| `scheduleClassReminders(timetable:)` | Schedule 5-min-before reminders |
| `cancelAllNotifications()` | Remove all pending |
| `handleAppBecameActive()` | Reschedule if needed |

## ClassActivityManager
**File:** `Features/LiveActivity/ClassActivityManager.swift`

| Method | Description |
|--------|-------------|
| `setTimetable(_:)` | Set timetable data, trigger activity |
| `setHolidayActive(_:)` | Enable/disable holiday mode |
| `startLiveActivityIfNeeded()` | Start if classes exist and 30 min before first |
| `endAllActivities()` | End all running activities |

## PushRegistrationService
**File:** `Core/Services/PushRegistrationService.swift`

| Method | Description |
|--------|-------------|
| `register(payload:)` | Register with push worker |
| `unregister(deviceId:)` | Remove from push worker |
| `pause(deviceId:resumeDate:)` | Pause push delivery |
| `resume(deviceId:)` | Resume push delivery |
| `retryPendingUnregisterIfNeeded()` | Retry tombstoned unregister |

## URLSchemeHandler
**File:** `Core/Services/URLSchemeHandler.swift`

| Property | Type | Description |
|----------|------|-------------|
| `navigateToToday` | `Bool` | Navigate to Today |
| `navigateToClassTable` | `Bool` | Navigate to timetable |
| `navigateToClub` | `String?` | Club ID to open |
| `navigateToAddActivity` | `String?` | Club ID for new activity |

| Method | Description |
|--------|-------------|
| `handleURL(_:)` | Process outspire:// URL |
| `handleUniversalLink(_:)` | Process https://outspire.wrye.dev URL |
| `createDeepLink(for:)` | Generate outspire:// URL |
| `createUniversalLink(for:)` | Generate https:// URL |

## WidgetDataManager
**File:** `Core/Services/WidgetDataManager.swift`

| Method | Description |
|--------|-------------|
| `updateTimetable(_:)` | Write timetable to App Group |
| `updateAuthState(_:)` | Write auth state |
| `updateHolidayMode(_:hasEndDate:endDate:)` | Write holiday state |
| `updateStudentInfo(track:entryYear:)` | Write student info |
| `clearAll()` | Clear all shared data |

## LLMService
**File:** `Core/Services/LLMService.swift`

| Method | Description |
|--------|-------------|
| `suggestCasRecord(records:clubName:)` | AI title + description |
| `suggestReflectionOutline(records:clubName:outcomes:)` | AI outline |
| `suggestFullReflection(...)` | Full 550+ word AI reflection |
| `suggestConversationReflection(...)` | Short 200-240 word reflection |

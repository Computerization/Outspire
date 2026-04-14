# Navigation & Deep Linking

## Tab Navigation

`RootTabView` provides the primary navigation with three implementation branches:

| iOS Version | Implementation | Style |
|-------------|----------------|-------|
| 26+ | `TabView` with `.sidebarAdaptable` | Liquid Glass tab bar |
| 18-25 | `TabView` with `Tab()` API | Standard tab bar |
| 17 (Legacy) | `TabView` with `.tabItem` | Legacy tab items |

### Tabs

| Tab | Label | Destination |
|-----|-------|-------------|
| Today | "Today" + house icon | `TodayView` |
| Class | "Class" + book icon | `ModernClasstableView` / `ScoreView` |
| Activities | "Activities" + sparkles icon | CAS views |
| Explore | "Explore" + safari icon | `ExtraView` (quick links grid) |

Each tab contains its own `NavigationStack` to preserve navigation state independently. The Explore tab uses a `NavigationPath`-bound `NavigationStack` to support programmatic push navigation for deep links (e.g., `outspire://club/{id}` pushes `ClubInfoView` onto the Explore stack).

## iPad Navigation (DEAD CODE)

> **Note:** `NavSplitView` exists in the codebase but is never instantiated. It was replaced by `RootTabView`. The file is dead code.

`NavSplitView` was designed as a `NavigationSplitView` for iPad with a sidebar and detail pane, but `OutspireApp.swift` uses `RootTabView()` exclusively.

## URL Schemes

`URLSchemeHandler` handles both custom URL schemes and universal links.

### Custom Schemes

| URL | Action |
|-----|--------|
| `outspire://today` | Navigate to Today tab |
| `outspire://classtable` | Navigate to timetable |
| `outspire://club/{clubId}` | Open club info |
| `outspire://addactivity/{clubId}` | Open add activity sheet for club |

### Universal Links

Domain: `outspire.wrye.dev`

| URL | Mapped To |
|-----|-----------|
| `https://outspire.wrye.dev/app/today` | `outspire://today` |
| `https://outspire.wrye.dev/app/club/{id}` | `outspire://club/{id}` |
| etc. | Same mapping pattern |

### Link Creation

```swift
URLSchemeHandler.createDeepLink(for: "club/123")
// → outspire://club/123

URLSchemeHandler.createUniversalLink(for: "club/123")
// → https://outspire.wrye.dev/app/club/123
```

### Navigation State

URLSchemeHandler publishes navigation triggers as `@Published` properties:

- `navigateToToday: Bool`
- `navigateToClassTable: Bool`
- `navigateToClub: String?`
- `navigateToAddActivity: String?`
- `closeAllSheets: Bool`

`RootTabView` observes these properties via `.onChange` and switches to the appropriate tab. For `navigateToClub`, it also programmatically pushes `ClubInfoView` onto the Explore tab's `NavigationPath`. Individual views (`ClubInfoView`, `ClubActivitiesView`, `TodayView`) respond to the relevant properties in `.onAppear`/`.onChange` to complete the navigation.

The handler includes:
- **Queued navigation** -- If app isn't ready, URL is queued and fired after 0.5s
- **Reset-and-set pattern** -- Navigation flags reset before being set to detect same-destination re-navigation
- **Sheet dismissal** -- `closeAllSheets` flag resets after 0.5s

## Onboarding

`OnboardingView` shows on first launch or when the app version crosses a threshold (currently 0.5.1). It presents 6 pages:

1. Welcome
2. Smart Schedule
3. CAS Tracking
4. Academic Performance
5. Live Activity Permission (interactive toggle)
6. Complete

Supports gesture navigation, keyboard shortcuts (arrows, ESC, Return), and saves Live Activity preference on completion.

## ViewType Enum

`ViewType` enumerates all navigation destinations:

```
today, classtable, score, clubInfo, clubActivities,
clubReflections, schoolArrangements, lunchMenu, map,
notSignedIn, weekend, holiday, help
```

Each case has a `displayName` property and can be parsed from link strings via `ViewType.fromLink(_:)`.

# Documentation Changelog

## 2026-04-14 (update 3)

### Fixed
- Deep link navigation in RootTabView -- all `outspire://` deep links now switch to the correct tab
  - `outspire://today` and `outspire://classtable` switch tabs
  - `outspire://club/{id}` switches to Explore tab and pushes ClubInfoView via NavigationPath
  - `outspire://addactivity/{id}` switches to Activities tab
- Added `.onChange` handler for `navigateToAddActivity` in ClubActivitiesView (previously only handled in `.onAppear`)
- Removed dead `navigateToReflection` property from URLSchemeHandler (never set, no route, no view response)
- Removed dead `.onChange(of: navigateToReflection)` from NavSplitView

### Changed
- Navigation-Deep-Linking.md updated to reflect working deep link flow and removed reflection route
- Explore tab NavigationStack now uses NavigationPath for programmatic deep link navigation

## 2026-04-14 (update 2)

### Added
- Dead-Code.md -- Comprehensive dead code audit with 5 dead files, 2 dead models, and dead ViewType members
- Dead code annotations in Project-Structure.md, Architecture-Overview.md, Navigation-Deep-Linking.md, Services-Reference.md, Models-Reference.md, Utilities-Reference.md

### Changed
- Updated wiki pages to mark dead/legacy code: CaptchaRecognizer, HomeServiceV2, SchoolCalendar, NavSplitView, HelpView, GroupInfoResponse, StatusResponse
- NavSplitView section in Navigation-Deep-Linking.md now marked as dead code (replaced by RootTabView)

## 2026-04-14

### Added
- Complete project wiki in `docs/wiki/` with 17 pages covering architecture, features, infrastructure, and reference
  - Home.md -- Table of contents and project overview
  - Project-Structure.md -- Directory layout, targets, dependencies
  - Architecture-Overview.md -- MVVM pattern, singleton services, data flow diagrams
  - Authentication.md -- TSIMS v2 auth, session lifecycle, optimistic auth, install detection
  - Networking.md -- TSIMSClientV2, API envelope, retry logic, connectivity monitoring
  - Navigation-Deep-Linking.md -- Tab bar, URL schemes, universal links, onboarding
  - Today-Dashboard.md -- Dashboard hub, gradient system, cards, day overrides
  - Academics.md -- Timetable, scores, class periods, year options
  - CAS.md -- Club management, activity records, reflections, LLM integration
  - School-Arrangements.md -- Weekly arrangements, lunch menus, PDF generation
  - Map.md -- Campus map, GCJ-02 coordinate conversion, region detection
  - Settings-Account.md -- Preferences, profile, configuration persistence
  - Widget-Live-Activities.md -- Small widget, Live Activity, Dynamic Island, data flow
  - Push-Notifications.md -- Local reminders, APNs worker, registration, KV schema
  - Caching.md -- CacheManager TTLs, cleanup, cache health
  - Design-System.md -- Tokens, glassmorphics, typography, gradients, haptics
  - Configuration.md -- Feature flags, secrets, identifiers, logging
  - Testing.md -- Unit tests, UI tests, mock patterns, build commands
  - Models-Reference.md -- All data models with fields
  - Services-Reference.md -- All singleton services with method signatures
  - Utilities-Reference.md -- Parsers, helpers, managers
- docs/README.md as documentation entry point
- docs/archive/ for historical planning documents
- docs/CHANGELOG.md (this file)

### Changed
- Reorganized docs/ folder: moved planning docs and specs to archive/
- Removed superpowers/ subdirectory (contents archived)

### Preserved
- docs/apns-push-worker.md -- Architecture decision record (still current)

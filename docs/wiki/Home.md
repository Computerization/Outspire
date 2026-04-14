# Outspire Wiki

Outspire is an iOS/macOS campus companion app for WFLA (World Foreign Language Academy) students. It connects to TSIMS (the school's information management system) to provide class schedules, academic scores, CAS tracking, and school announcements.

- **Bundle ID:** `dev.wrye.Outspire`
- **App Group:** `group.dev.wrye.Outspire`
- **Deployment targets:** iOS 17.0 (main app), iOS 18.2 (widget extension)
- **Swift:** 5.0
- **License:** MIT

## Table of Contents

### Architecture

- [Project Structure](Project-Structure.md) -- Directory layout, targets, and file organization
- [Architecture Overview](Architecture-Overview.md) -- MVVM, singleton services, data flow
- [Authentication](Authentication.md) -- Dual-backend auth, session lifecycle, optimistic auth
- [Networking](Networking.md) -- TSIMSClientV2, API envelope, retry logic
- [Navigation & Deep Linking](Navigation-Deep-Linking.md) -- Tab bar, URL schemes, universal links

### Features

- [Today Dashboard](Today-Dashboard.md) -- Daily schedule hub, gradient system, cards
- [Academics](Academics.md) -- Timetable, scores, class periods
- [CAS (Activities & Reflections)](CAS.md) -- Club management, records, reflections, LLM integration
- [School Arrangements & Lunch Menus](School-Arrangements.md) -- Weekly arrangements, PDF viewer
- [Map](Map.md) -- Campus map, China coordinate conversion
- [Settings & Account](Settings-Account.md) -- User preferences, profile, about

### Infrastructure

- [Widget & Live Activities](Widget-Live-Activities.md) -- Small widget, Live Activity, Dynamic Island
- [Push Notifications](Push-Notifications.md) -- Local reminders, push registration (iOS side)
- [Push Worker](Push-Worker.md) -- Cloudflare Worker, D1/KV storage, APNs dispatch, cron architecture
- [Caching](Caching.md) -- Cache manager, TTLs, cleanup
- [Design System](Design-System.md) -- Tokens, glassmorphic components, typography, gradients
- [Configuration](Configuration.md) -- Feature flags, server URLs, secrets management
- [Testing](Testing.md) -- Unit tests, UI tests, mock patterns

### Reference

- [Models Reference](Models-Reference.md) -- All data models and their fields
- [Services Reference](Services-Reference.md) -- All singleton services and their APIs
- [Utilities Reference](Utilities-Reference.md) -- Parsers, helpers, managers
- [Dead Code](Dead-Code.md) -- Legacy/unused code identified for cleanup

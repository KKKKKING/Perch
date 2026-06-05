# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Perch** — a native macOS app (Swift 5.9 + AppKit, macOS 13+) that renders a multi-column X/Twitter timeline reader. It implements an HTML/CSS/JS design prototype (`design/`) pixel-for-pixel. X login and reads/writes are **live** against X's undocumented GraphQL API (cookie auth). Weibo support is mock/UI-only ("Coming soon").

## Build & run

```bash
swift build                      # debug build
swift build -c release           # release build
./build.sh [debug|release]       # build + codesign (needed for Keychain + WKWebView login)
.build/debug/Perch               # run
```

No test target exists. The `swift` extension in `.vscode/launch.json` provides "Debug/Release Perch" launch configs.

Codesigning matters: the live login flow stores cookies in the Keychain and uses `WKWebView`; an unsigned binary may fail those. `build.sh` signs with `com.perch.twitter` (override via `CODESIGN_IDENTITY` / `CODESIGN_IDENTIFIER` env vars).

## Workflow

At the end of every turn, commit the changes made during that turn. Keep commits scoped to the current turn's work and do not include unrelated dirty worktree changes.

### Debug snapshots (visual verification without a live session)

The app can launch a given UI state, screenshot it to PNG, and quit — useful for verifying layout changes without credentials or manual clicking:

```bash
PERCH_SNAPSHOT=/tmp/out.png PERCH_STATE=settings .build/debug/Perch
PERCH_THEME=light PERCH_SNAPSHOT=/tmp/out.png .build/debug/Perch   # force light theme
PERCH_ICON_PNG=/tmp/icon.png .build/debug/Perch                    # export the app icon (PerchAppIcon) to PNG and quit
```

`PERCH_STATE` values (see `RootViewController.debugApply`): `compose`, `tray`, `detail`, `profile`, `reply`, `notif`, `acctmenu`, `settings`, `addaccount`, `xlogin`, `detailvideo`, `mediavideo`, `mediaimages`, `colmenu`, `newposts`, `welcome`. Snapshots with `PERCH_SNAPSHOT` skip session restore so they render deterministically; states referencing live tweet ids degrade to stubs.

## Architecture

### UI layer — AppKit, manual layout

Everything is hand-laid-out AppKit: `FlippedView` + frame-based positioning. **No SwiftUI, no Auto Layout.** Match this style in new code.

- `App.swift` → `AppDelegate` owns one `NSWindow` and swaps its `contentViewController` between `WelcomeViewController` (onboarding, shown when no accounts) and `RootViewController` (the main app). Auxiliary surfaces (compose, settings, add-account, media viewer) are separate `PanelWindow`s.
- `RootViewController` = icon rail (`IconRailView`) + a horizontally scrolling canvas of `ColumnView`s + overlays (popovers, toast, column-manager tray). It is the `AppState` delegate and **rebuilds the canvas** in response to most state changes (throttled during live resize).
- `ColumnView` owns a push/pop nav stack (timeline → detail/profile). The `mentions`/bell column is a full **notification center** (`NotifCenterPanel`), not a plain @-mentions list.
- Rendering primitives live in `Core/` (`GlyphView` draws literal SVG paths from the design; `Theme`/`ThemeManager` is a singleton supporting light/dark/system + 6 accent colors; `ImageLoader`, `SVGPath`).

### State — centralized + delegate pattern

`Core/AppState.swift` is the single source of truth, mirroring the prototype's React state. It exposes an `AppStateDelegate` protocol; `RootViewController` implements it and re-renders. Key conventions:

- **Optimistic writes**: `onAction` (like/repost/bookmark) updates a local `overrides` dict immediately, fires the delegate, then mirrors to X via `syncLiveAction` — reverting the override on network failure.
- **Live data is keyed and cached**: `liveTimelines[accountId]`, `liveColumns[colId]`, `liveProfiles[handle]`, `liveReplies[rootId]`, `liveNotifications[accountId]`. Refresh methods all follow the same shape: guard against re-entrancy + an existing cache, run a `Task`, hop back to `MainActor`, store, then call `appStateDidChangeActive` to trigger a rebuild.
- `mergePost` layers `overrides` (and injected replies/quotes) over a base post at read time; `findBase` searches all live caches by id.
- `postsFor`/`notificationsFor` return live data only for the logged-in X account, `[]` otherwise — never mock fallback.

### Live X integration — `Sources/Perch/API/`

Cookie-authed client for X's undocumented endpoints, modeled on the Flare/`xqt` client. **This layer is inherently fragile** (see below).

- `TwitterService` — singleton coordinator. Owns the `TwitterAPIClient`, derives the Perch `Account` (id = `axlive_<userId>`), bridges async fetches to the main thread, exposes a clean read/write surface. Start here.
- `TwitterAPIClient` — `URLSession` client. Reads → `graphqlGET` (variables/features as query params), writes → `graphqlPOST` (JSON body). Notifications use the **legacy v2 REST** endpoint `2/notifications/all.json`, not GraphQL. Every GraphQL call is signed with an `x-client-transaction-id` header.
- `TwitterTransactionID` — actor; computes the transaction-id signature (SHA256+XOR). Depends on a third-party GitHub-hosted `pair.json`; best-effort (nil → header omitted).
- `TwitterQueryIDs` — actor; hardcoded GraphQL operation query IDs + a runtime bundle-scrape to refresh them once per session.
- `TwitterResponseTypes` — Codable GraphQL structs. `TwitterDataMapper` — maps GraphQL nodes → Perch `Post`/`Person`/`Profile`/`NotifItem`.
- `TwitterCredentials` — Keychain store (service `com.perch.twitter`). `XLoginWebView` / `XLoginWindowController` — real `WKWebView` login (`x.com/i/flow/login`), scrapes `auth_token` + `ct0` cookies once both are present.

Login flow: `AddAccountView` → X webview → cookies scraped → `TwitterService.login` validates + persists. On launch, `restoreSession()` loads saved cookies (skipped under `PERCH_SNAPSHOT`).

**API fragility** — when live calls fail, suspect these first:
- Query IDs and per-operation `features` dicts rotate with X's client bundles. Wrong/missing feature keys → HTTP 400. The runtime `discover()` refreshes query IDs but **not** features; seeded fallbacks may be stale.
- The `x-client-transaction-id` depends on an external `pair.json`; if its URL/format changes the header is silently dropped.
- Quote tweets use `attachment_url`; un-retweet uses `source_tweet_id` while most writes use `tweet_id`.

**Home "new posts" pill avatars** — the centered home pill's faces come *only* from X's `TimelineShowAlert` instruction (`usersResults`). X returns that alert only on a **Top-cursor fetch-newer** request (`count:40`, Top cursor, populated `seenTweetIds`, `requestContext` omitted) — *not* on the launch/cold load (`requestContext:"launch"`), which is Perch's default refresh. So with the default path the alert (and faces) rarely surface. The experimental `perch.ptrRefresh` flag (`defaults write Perch perch.ptrRefresh -bool true`; default off) routes **user-initiated** home refreshes through the fetch-newer path to elicit the alert. Flag off → byte-identical to the original launch refresh; the pill still renders (chevron + count) without faces when no alert is present.

## Gotchas

- **Never name a project type `Notification`.** It shadows `Foundation.Notification` module-wide and silently breaks AppKit delegate methods (e.g. `applicationDidFinishLaunching(_:)`) — the app launches with no window and no crash, only a "nearly matches optional requirement" build warning. Prefix model types: `NotifItem`, `NotifKind`, `NotifFilter`.
- The app force-unwraps `accounts.first!` in `AppState.active`; this is safe only because the main window is shown exclusively when `hasAccounts` is true.

## Design source

`design/` is a handoff bundle of HTML/CSS/JS prototypes (read `design/README.md`). Recreate visual output faithfully in AppKit; don't copy the prototype's internal structure. Glyphs are ported as literal SVG path data.

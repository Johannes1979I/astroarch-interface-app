# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`astroarch-interface-app` is the **Flutter / Android** front-end of Astroarch Interface. It pairs with [astroarch-bridge](https://github.com/Johannes1979I/astroarch-bridge), a Python daemon running on a Raspberry Pi 5 (AstroArch) that exposes KStars/Ekos, INDI (port 7624) and PHD2 (port 4400). The two repos are **version-locked** — `kAppVersion` in `lib/app_version.dart` must match the bridge `pyproject.toml` version on the Pi the user pairs with. Bumping one almost always means bumping the other.

The app is written in Italian first; English is a runtime translation layer (see i18n below). Do not hardcode UI strings in English.

## Commands

```bash
flutter pub get                          # install deps
flutter run                              # debug on attached device
flutter build apk --release              # produce APK (uploaded as release asset)
flutter build web --release --no-web-resources-cdn   # web build, CanvasKit incluso
flutter analyze                          # lint (flutter_lints rules)
flutter test                             # run tests in test/
python build_manual.py                   # regen AstroarchInterface_Manual.pdf from sources
```

Single test: `flutter test test/<file>_test.dart`.

Dart SDK pinned: `^3.5.0`. Flutter ≥ 3.32 expected.

## Architecture: state, transport, screens

**One global `AppState` (`lib/state/app_state.dart`)** is the single source of truth, served via Provider/ChangeNotifier. It owns:

- The **multi-bridge list** (`List<BridgeConnection> bridges` + `activeBridgeId`), persisted as JSON in SharedPreferences under `bridges_v1`. Legacy single-bridge prefs are auto-migrated on first load. The `host`/`port`/`token`/`useHttps` getters on `AppState` are **facades** that delegate to `activeBridge` — never read those fields elsewhere, always go through AppState so a `switchTo(id)` call flips the entire app.
- The **mirror of bridge state**: INDI properties cache, PHD2 live history (for the guide chart), last frame, devices, selected device per role (camera/mount/focuser/filter-wheel), ekos/system status flags.
- The **app-owned active target** (`activeTargetName/RaHours/DecDeg`). This is the architectural fix for KStars "Center & Slew" not updating `Ekos.Align.target` automatically: the app holds the target and re-pushes it via `setTargetCoords` before every plate-solve. Do not bypass this — Plate Solve / Sync / Slew rely on it.
- The **capture jobs list** (`captureJobs`, persisted via `CaptureJobsStore`).
- UI prefs: `nightMode`, `locale` (`AppLocale.it`/`en`).

`switchTo(id)` calls `_resetBridgeLocalState()` which wipes properties/devices/target — necessary because the new RPi might have a different observatory configuration.

**Transport (`lib/api/`)**:
- `ApiClient` — REST client with bearer token. Every call goes through here and is recorded in `ApiLog` (a circular buffer of the last 100 calls, viewable in Activity Log / Logs screens). When debugging "did the bridge get the request", check `ApiLog.entries` first.
- `WsClient` — generic auto-reconnecting WebSocket with backoff. Two instances run: one on `/ws/state` (JSON), one on `/ws/frames` (binary JPEG).

**Screens (`lib/screens/`)**: one file per top-level screen. The shell has 5 bottom-nav tabs (Dash · Mount · Align · Capture · Guide) defined in `shell_screen.dart::_bottomScreens`. Everything else (Focus, Files, Logs, INDI panel, Live view, Activity, Connections, Setup, Settings, Analyze, Scheduler, Observatory) is in the drawer. Use `openShellDrawer()` from any screen's AppBar.

Sub-folders contain split tab implementations:
- `screens/align/` — `plate_solve_tab.dart` (owns the "target selector card" + re-push logic) and `polar_align_tab.dart`.
- `screens/capture/` — `job_form.dart`, `sequence_runner.dart`, `cooler_panel.dart`. The capture screen polls `/ekos_status` every 3s so the **stop button stays reachable** while a sequence runs (previous bug: user couldn't abort).

## i18n: italian-as-key

`lib/i18n/strings.dart` holds a single `const Map<String, String> _en` keyed by the **Italian** source string → English translation. Use `.tr(context)` on a literal Italian string at the call site:

```dart
Text('Avvia sequenza'.tr(context))
```

If a key is missing, `.tr` falls back to the Italian source so nothing crashes in production. For interpolation use `{0}`, `{1}`, … placeholders and `.trFmt(context, [args])`. **Duplicate keys break the const map evaluation** — when adding entries, scan for collisions (the project has had to dedupe several times after agent edits).

## Cross-repo invariants

When changing anything that crosses the wire, check the bridge side too:

- **Routes**: the bridge mounts REST under `/api/<area>/`. The full list lives in the bridge README; common areas: `system`, `mount`, `camera`, `focuser`, `filter_wheel`, `guide`, `align`, `capture`, `observation`, `files`, `indi`, `observatory`, `scheduler`, `setup`. If you add a new endpoint here, add it there.
- **WebSockets**: `/ws/state` and `/ws/frames`. The frame meta JSON shape (header before the JPEG bytes) is shared; don't change it on one side only.
- **Non-invasive rule**: the bridge **must not modify** the user's Ekos UI settings (UPLOAD_MODE, fileDirectoryT, placeholderFormatT, target coordinates) — they're read from the canonical sources (DBus, INDI, `~/.local/share/kstars/userdb.sqlite`). The app side mirrors this: never send a "set everything" request just to force a known state. Read first, only push what the user explicitly changed in the UI.
- **Version pinning**: bump both `pubspec.yaml > version` AND `lib/app_version.dart > kAppVersion` for every release. They must match.

## Pairing & login

`LoginScreen` is shown when `state.api == null` (no active bridge configured). Pairing flow:
1. The bridge's `/api/system/qr` returns a QR with `host:port` (the **Tailscale IP**, not LAN) + token.
2. App scans via `qr_scan_screen.dart` (mobile_scanner), or user enters manually.
3. On success a `BridgeConnection` is appended to `bridges` and `activeBridgeId` is set; `ApiClient` is built and `ShellScreen` mounts.

`ConnectionsScreen` is the drawer-accessible manager for the saved bridges list (add/rename/delete/switch). The active row has an "ATTIVA" badge.

## Dashboard widgets worth knowing

- `widgets/ekos_master_toggle.dart` — big pill button polling `/api/system/ekos_state` every 3s. 5 visual states (active/inactive/pending/error/unknown). Tap toggles via `/ekos_start` or `/ekos_stop` with optimistic UI.
- `widgets/launch_apps_card.dart` — KStars and PHD2 launch/close pills. Polls both `/gui_apps_state` AND `/ekos_state` in parallel every 3s. **Pressing the button only kills the app when `ekos_state` is inactive** (red master button) — otherwise it's a no-op safety: don't want to close apps mid-session.

## Releases / assets

- `astroarch-interface-vX.Y.Z.apk` at the repo root is the latest release APK, also attached to the GitHub release with the matching tag.
- `AstroarchInterface_Manual.pdf` is regenerated by `build_manual.py` (Italian + English, single PDF).
- `mockups.html` is a static design doc, not built into the app.

## Related repos

- [astroarch-bridge](https://github.com/Johannes1979I/astroarch-bridge) — Python backend. Required at runtime.
- [astroarch-interface](https://github.com/Johannes1979I/astroarch-interface) — original monorepo, kept read-only as combined history.

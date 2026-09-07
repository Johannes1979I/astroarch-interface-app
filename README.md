# Astroarch Interface — Android App

> **Mobile-friendly clone of KStars/Ekos for your AstroArch observatory.**
> Full remote control from your Android smartphone over Tailscale.

[![Version](https://img.shields.io/badge/version-0.2.30-f5a623?style=flat-square)](https://github.com/Johannes1979I/astroarch-interface-app/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/Android-8.0%2B-green?style=flat-square&logo=android)](#)
[![Flutter](https://img.shields.io/badge/Flutter-3.32-02569B?style=flat-square&logo=flutter)](#)

**Author**: Zarletti-Osservatorio Jupiter
**Companion repo (bridge backend)**: [Johannes1979I/astroarch-bridge](https://github.com/Johannes1979I/astroarch-bridge)

---

## What this repo contains

This is the **Android app** side of Astroarch Interface — a Flutter
project that produces the APK installed on the phone. It talks over
Tailscale to a Python **bridge** that runs on the Raspberry Pi 5
inside the AstroArch installation. The bridge lives in a separate
repository: **[astroarch-bridge](https://github.com/Johannes1979I/astroarch-bridge)**.

You need **both** to use the system:

| Repo | What it is | Where it runs |
|---|---|---|
| **astroarch-interface-app** *(this one)* | Flutter / Android app | the phone |
| [**astroarch-bridge**](https://github.com/Johannes1979I/astroarch-bridge) | Python bridge — daemon | the Raspberry Pi 5 (AstroArch) |

---

## Features

14 dedicated screens + cross-cutting features. Everything mobile-tuned.

### 🆕 In the latest releases

- **Launch KStars/Ekos & PHD2 (v0.2.30)** — two buttons on the
  Dashboard that spawn the GUI apps on the RPi's monitor, with live
  "running" indicators (polled every 3 s)
- **Multi-bridge (v0.2.29)** — save more than one Pi (e.g. two
  different telescopes) and switch with one tap on the Dashboard
- **Ekos-native autofocus (v0.2.26)** — live params, frame preview,
  real V-curve from `Ekos.Focus.newHFR`, log tail
- **PHD2-style guide chart (v0.2.25)** — RA/DEC signed arcsec, per-
  frame `RADistanceRaw`/`DECDistanceRaw` like the desktop chart
- **App-owned active target (v0.2.24)** — pushed to Ekos before every
  solve; KStars "Center & Slew" no longer leaves Ekos with stale targets
- **Pairing QR auto-generated with Tailscale IP (v0.2.18)** — works
  from any network with Tailscale on
- **IT / EN language selector (v0.2.16)** in Settings, persistent
- **Master Start/Stop Ekos (v0.2.17)** big toggle on the Dashboard

### All modules

- 📊 **Dashboard** with system master toggle + multi-bridge name selector
- 🔭 **Mount** — SIMBAD search, GoTo/Sync/Track, joypad with rate
  selector, park/unpark, emergency stop
- 🎯 **Align (Plate Solve)** — exact clone of Ekos Align: live FITS
  preview auto-stretched (PixInsight-style adaptive STF), exposure/
  gain/binning, Sync / Slew to target / Nothing chips, app-owned
  active target (SIMBAD / mount position / manual) pushed to Ekos
  before every solve
- 📷 **Capture** — multi-job persistent sequencer (Ekos-style),
  drag-and-drop reorder, save/load JSON presets, three exec modes
  (Full Observation, Via Ekos, Direct INDI). Stop button always
  reachable; **reads your Ekos save folder + placeholder format** from
  KStars userdb so jobs save where you configured in Ekos
- 🎯 **Guide (PHD2)** — live guide-star image with crosshair, RMS
  cards, real PHD2-style error chart, Find Star / Calibrate / Dither
- 🎛️ **Focus** — Ekos-native autofocus + bridge iterative fallback
- 🌡️ **Cooler** with stuck-driver detection and one-tap reconnect
- 🌐 **Observatory** (dome, weather, dust cap, flat panel)
- 📅 **Scheduler** with twilight / sun & moon altitude / weather safe
- ⚙️ **Setup / Profiles** read from `~/.local/share/kstars/userdb.sqlite`
- 🎛️ **INDI Panel** — exact clone of KStars's INDI Control Panel
- 📁 **Files** browser (`~/Pictures/Ekos`) with thumbnails, batch
  delete, RPi disk usage
- 📈 **Analyze**, 🔬 **Activity Log** (every API call with timing)
- 🌐 **Connessioni** — manage all your saved bridges in one place
- ⚙️ **Settings** — language, theme, pairing QR, app info

---

## Quick start (AstroArch users)

> Tested on AstroArch (ArchLinux ARM) + Raspberry Pi 5. Setup time: **~10 minutes**.

### 1) Install the bridge on the Pi (separate repo)

```bash
ssh astronaut@RPI_IP
git clone https://github.com/Johannes1979I/astroarch-bridge
cd astroarch-bridge
sudo bash deploy/install.sh --user astronaut
```

The script generates a token, creates the systemd service, and prints
the Tailscale URL + LAN URL + token. See the
[**astroarch-bridge README**](https://github.com/Johannes1979I/astroarch-bridge#readme)
for full backend instructions.

### 2) Tailscale on Pi and phone

```bash
# On the Pi (if not already)
sudo pacman -S tailscale
sudo systemctl enable --now tailscaled
sudo tailscale up
```

Then install **Tailscale** on the phone from the Play Store and sign in
with the same account.

### 3) Install this APK

Download the latest APK from
[**Releases**](https://github.com/Johannes1979I/astroarch-interface-app/releases/latest)
and install it on the phone (Android 8.0+).

### 4) Pair the app

Open the app → **SCAN QR FROM DASHBOARD** and frame the QR shown by
the desktop dashboard widget on the Pi. Alternatively, **Enter
manually**:

- **Host**: Pi's Tailscale IP (e.g. `100.x.y.z`, from `tailscale ip -4`)
- **Port**: `8765`
- **Token**: printed by the bridge install script

---

## Building from source

```bash
flutter pub get
flutter build apk --release

# Build web (per servirla dal bridge con ASTROARCH_WEB_DIR):
flutter build web --release --no-web-resources-cdn
```

`--no-web-resources-cdn` non e' facoltativo: senza, Flutter scarica
CanvasKit da `gstatic.com` al primo avvio. In postazione, dove la rete e'
l'hotspot del Raspberry e internet non c'e', la app resterebbe una pagina
bianca — cioe' esattamente lo scenario per cui esiste la build web. Con il
flag, CanvasKit finisce dentro la build.


The APK is produced in `build/app/outputs/flutter-apk/app-release.apk`.

Version bumping: edit **both** `lib/app_version.dart` (`kAppVersion`)
**and** `pubspec.yaml` (`version:`) so the Dashboard badge stays
aligned with the installed APK.

### Tech stack

| | |
|---|---|
| Framework | Flutter 3.32 / Dart 3.5 |
| State management | Provider |
| HTTP | http / web_socket_channel |
| Charts | fl_chart |
| QR scanner | mobile_scanner |
| i18n | local table + StringTr extension (`lib/i18n/strings.dart`) |
| Theme | custom dark astro theme + Night Mode |

### Project structure

```
lib/
├── api/             — REST / WebSocket clients
├── i18n/strings.dart — IT/EN translation table
├── screens/         — 14 module screens
│   ├── align/         (plate_solve_tab, polar_align_tab)
│   ├── capture/       (job_form, sequence_runner, cooler_panel)
│   └── ...
├── state/           — AppState (Provider), capture jobs persistence
├── theme/           — colour tokens
└── widgets/         — reusable widgets (ekos_master_toggle, common, …)
```

---

## Documentation

- 📄 [**User Manual PDF**](AstroarchInterface_Manual.pdf) — full printable guide
- 🎨 [mockups.html](mockups.html) — UI preview (open in a browser)

---

## License

[MIT](LICENSE) — feel free to use, modify, distribute. Please keep
attribution to Zarletti-Osservatorio Jupiter.

---

## Team & contributors

This project is built and improved by a small community of astrophotographers.

| | Role | Contributions |
|---|---|---|
| **Gianpaolo Zarletti** (Zarletti-Osservatorio Jupiter) | Creator, lead developer & maintainer | Concept, architecture, app + bridge development |
| **Mattia Procopio** ([MattBlack85](https://github.com/MattBlack85)) | Co-maintainer · packaging & distribution | `uv` migration, Makefile, pacman packaging, PKGBUILD & CI |
| **Stéphane Carlin** ([sc74](https://github.com/sc74)) | Contributor | Multi-user PKGBUILD, broadcast-stream fix, desktop dashboard i18n (FR/ES/DE) |
| **Benoit "Tucniak"** ([BenoitBotton](https://github.com/BenoitBotton)) | Contributor | French app localization, QA & testing on multiple hardware |

Want to help? PRs and ideas are very welcome.

## Credits (third-party)

- **AstroArch** — [github.com/devDucks/astroarch](https://github.com/devDucks/astroarch)
- **KStars / Ekos** — [edu.kde.org/kstars](https://edu.kde.org/kstars/)
- **PHD2** — [openphdguiding.org](https://openphdguiding.org/)
- **astrometry.net** — [astrometry.net](https://astrometry.net/)

🌙 **Clear skies!** — Zarletti-Osservatorio Jupiter & contributors

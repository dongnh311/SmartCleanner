# SmartCleanner — macOS

> macOS side of the dual-platform `SmartCleanner` repo. The Windows port lives in [`../Windows/`](../Windows/). The Xcode scheme and bundle name stay `MacCleaner` so existing code signatures and TCC grants keep working — no re-sign, no re-prompt.

A personal macOS cleaner + system monitor — scans junk, manages malware
persistence, uninstalls apps with leftovers, and surfaces real-time
metrics on par with [exelban/Stats](https://github.com/exelban/Stats).
Built with SwiftUI + Swift 6 strict concurrency, targeting macOS 13+.

Not for distribution. Single-user, ad-hoc signed.

![Main window](docs/screenshots/hero.png)

## Highlights

- **Cleanup** that refuses to wipe caches of running dev tools (Android
  Studio, Xcode, iOS Simulator, JetBrains, qemu / gradle daemon) so it
  never kills your live emulator.
- **System monitor** — SMC sensors (temperatures, fans, power),
  GPU utilization, per-core CPU history, network history with VPN
  detection, Bluetooth devices, disk I/O.
- **Realtime protection** (opt-in) — a userspace layer on the menu-bar
  agent that watches LaunchAgents/Daemons, hashes new downloads against a
  local SHA-256 blocklist, and guards your documents with ransomware
  canaries + a write-burst detector. Two extra engines for downloaded
  files (Settings › Protection): **VirusTotal** reputation lookup (you
  paste a free API key — only the file's hash leaves the machine), and an
  **updatable blocklist feed** (point it at any SHA-256 list / abuse.ch
  export). DANGER hits auto-quarantine (reversible); reviews and ransomware
  signals alert only. No kernel hooks (Endpoint Security needs an
  entitlement this ad-hoc build can't carry), so detection is reactive,
  not block-before-exec. Toggle on the Malware Removal page.
- **Quarantine with restore** — anything cleaned moves to a 7-day
  quarantine before being permanently deleted; one-click restore.
- **Smart Care** orchestrator runs Cleanup / Protection / Speed in
  parallel and surfaces a single Clean button — Protection also lists
  hidden background apps so menu-bar / daemon processes you don't
  recognise are one click away from a quit.
- **Usage Trends** — 60s sampler logs every running app into a 90-day
  hourly history, then surfaces which apps you actually use, which
  background runners are quietly racking up hours, and which installed
  apps you haven't opened in months.
- **Menu bar agent** that survives Cmd+Q. Configurable metric strip
  (CPU, RAM, GPU, network) + popover with tiles + alerts.
- **Built-in Paint** — multi-layer raster + vector editor for quick
  markup so you don't need to install Paint S or open Preview.
- **Localized** in English + Tiếng Việt.
- **Design system** — every module pulls its accent from
  `SidebarItem.section.accentColor`, cards from `cardStyle()`, percent /
  battery / temperature tints from `Color.percentTint(_:)` &
  `temperatureTint(_:)` & `batteryTint(_:)` in
  `Core/UI/DesignTokens.swift`. Smart Care pillar gradients live in
  `PillarGradient.{cleanup,protection,speed}`. Full spec under
  `design_handoff_maccleaner/`.
- **Detail popups** — list rows that hide more than the row chrome
  expose an `i` button → `DetailSheet` with full path, size, rule
  provenance + Copy / Reveal in Finder. Wired on Quick Clean groups,
  every `CleanupItemRow`, and Malware threats.

---

## Requirements

- macOS 13 (Ventura) or newer
- Xcode 15+ — `xcodebuild` is the build driver
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — generates the
  `.xcodeproj` from `project.yml`

## Setup

```bash
sudo xcodebuild -license accept
brew install xcodegen
git clone https://github.com/dongnh311/SmartCleanner.git
cd SmartCleanner/macOS
xcodegen generate
open MacCleaner.xcodeproj
# — or —
xcodebuild -scheme MacCleaner -destination 'platform=macOS' build
```

GRDB Swift Package resolves on first build.

### Permissions

Several modules need Full Disk Access (caches under `~/Library/Caches`,
Mail attachments, TCC entries, etc.). The onboarding wizard asks on
first launch; otherwise add `MacCleaner.app` manually under
**System Settings → Privacy & Security → Full Disk Access**.

Accessibility access is optional, only used by Process Monitor's
window-level inspection.

---

## Features

### Smart Care

One scan that fans out three pillars in parallel:

- **Cleanup** — mirrors Quick Clean (safe-only system junk + trash)
- **Protection** — persistence threats (suspicious LaunchAgents, quarantined binaries) **plus running background apps**: anything in
  `NSWorkspace.runningApplications` with a non-`.regular` activation policy is surfaced so menu-bar utilities and hidden daemons get
  one-click visibility / quit
- **Speed** — apps holding ≥ 500 MB RAM (SIGTERM via Process Monitor)

The result is one report card; **Clean** quarantines selected threats,
removes selected junk, and quits selected processes in one parallel
pass. A CMM-style log sheet shows the per-file outcome — removed,
skipped-for-safety, errored.

![Smart Care](docs/screenshots/smart-care.png)

### Dashboard

Realtime hero with disk usage, CPU sparkline (60-sample history),
memory pressure, battery + health, network speed and top processes —
all updating once a second.

![Dashboard](docs/screenshots/dashboard.png)

### Quick Clean

One-click safe purge of caches, logs and trash. Caches under
`~/Library/Caches/*` are direct-deleted; trash items move to
quarantine. Live banner warns if Android Studio / Xcode / iOS
Simulator are running and skips their caches automatically.

![Quick Clean](docs/screenshots/quick-clean.png)

### System Junk

Curated rule pack (`Resources/CleanupRules/system_junk.json`) covering
~30 paths: per-app caches, system caches, logs, Xcode DerivedData,
iOS Simulator devices, npm/yarn/Cocoapods/SPM/Gradle/Maven caches,
saved application states, and more. Each rule declares whether items
direct-delete or quarantine.

![System Junk](docs/screenshots/system-junk.png)

### Mail Attachments

Walks `~/Library/Mail/V*/...` and the sandboxed mail container,
finding `Attachments` directories you can purge. Mail re-downloads
on demand so it's safe.

![Mail Attachments](docs/screenshots/mail-attachments.png)

### Photo Junk

Scans `~/Pictures/*.photoslibrary` for derivative caches, mutations,
streaming previews and internal scratch — nothing user content,
strictly cache surface.

![Photo Junk](docs/screenshots/photo-junk.png)

### Trash Bins

User trash + every external volume's `.Trashes`. Per-item size
breakdown, one click to empty.

![Trash Bins](docs/screenshots/trash-bins.png)

---

### Malware Removal

Persistence inspector — enumerates every LaunchAgent /
LaunchDaemon and apps with `com.apple.quarantine` xattr. Tags each
with risk signals (runs from `/tmp`, unsigned, downloads via curl,
etc.) and a severity score.

![Malware Removal](docs/screenshots/malware.png)

### Privacy

Browser cache / cookies / history surface across Safari, Chrome,
Firefox, Edge, Brave plus macOS recents. Refuses to clean a browser
that's currently running.

![Privacy](docs/screenshots/privacy.png)

### App Permissions

Reads the TCC database to show which apps have Camera, Microphone,
Screen Recording, Full Disk Access, etc. Read-only inspector.

![App Permissions](docs/screenshots/app-permissions.png)

---

### Maintenance

DNS flush, Spotlight reindex, font cache reset, Safari history
purge — single-shot commands wrapped behind buttons.

![Maintenance](docs/screenshots/maintenance.png)

### Login Items

LaunchAgents/Daemons + System Settings login items in one list, with
toggle (enable/disable via launchctl) and delete (move to quarantine).

![Login Items](docs/screenshots/login-items.png)

### Process Monitor

`ps` snapshot every 2s, sortable by CPU/RAM. SIGTERM (graceful) or
SIGKILL buttons per row.

![Process Monitor](docs/screenshots/process-monitor.png)

### Usage Trends

A 60s sampler walks `NSWorkspace.runningApplications` and writes the
hourly aggregate (`bundle_id`, `minutes_seen`, `avg_memory_bytes`,
`is_background`) to a SQLite table. Aggregates persist for 90 days
then auto-purge.

Four cards (7 / 30 / 90 day picker):

- **Most-used apps** — top by total minutes seen across the window
- **Background runners** — hidden / menu-bar apps by uptime, the place
  to spot a daemon that's been quietly running 6 hours a day
- **Memory hogs (avg)** — apps with the highest mean RAM while running
  (filtered to ≥ 30 minutes of samples so brief spikes don't dominate)
- **Unused apps** — installed apps the sampler hasn't seen in this
  window, sorted by how long they've been stale; "never" means never
  opened while MacCleaner was running

Data only counts time MacCleaner was up. First samples land within
~60s of launch; the view auto-refreshes every 60s.

![Usage Trends](docs/screenshots/usage-trends.png)

### Memory

`host_statistics64` breakdown (free / active / inactive / wired /
compressed / app memory) plus a *Free Up* action that calls
`memory_pressure` to trigger compression.

![Memory](docs/screenshots/memory.png)

### Battery

IOKit AppleSmartBattery: percent, charging state, time-to-empty /
full, cycle count, max capacity, condition. Plus *System Activity*
card (uptime since boot via `kern.boottime`, sleep events from
`pmset -g log`).

![Battery](docs/screenshots/battery.png)

### Sensors

SMC reader — pure-Swift IOKit bridge. Lists every available
temperature, fan, power and voltage sensor, refreshing every 3s,
each with a 60-sample rolling sparkline. Color-coded thresholds
(green &lt;60°C, orange &lt;80°C, red ≥80°C).

![Sensors](docs/screenshots/sensors.png)

### Network

60-second download / upload sparkline, optional public IP fetch
(opt-in toggle, hits api.ipify.org), VPN badge when a `utun*` tunnel
is alive, per-interface byte counters.

![Network](docs/screenshots/network.png)

### Bluetooth

Lists every paired Bluetooth device with connection status and
battery (single battery for most peripherals; left/right/case for
AirPods family). Refreshes every 5s.

![Bluetooth](docs/screenshots/bluetooth.png)

### Disk Monitor

Per-volume free/used progress bars + live read/write rates pulled
from `IOBlockStorageDriver Statistics`, with sparkline history.
Distinguishes physical disks vs network volumes.

![Disk Monitor](docs/screenshots/disk-monitor.png)

---

### Uninstaller

Lists installed apps from `/Applications`, `~/Applications`, and
App Store. Selecting an app finds its leftover files (Application
Support, Caches, Containers, LaunchAgents, Preferences). One Quarantine
button moves the bundle + leftovers in one transaction.

![Uninstaller](docs/screenshots/uninstaller.png)

### Updater

Combines macOS App Store updates, Sparkle-based apps and Homebrew
casks/formulae into one list. Click to update.

![Updater](docs/screenshots/updater.png)

---

### Space Lens

Disk usage hierarchy — pick a folder, drill into the largest
children. Tree view + size column.

![Space Lens](docs/screenshots/space-lens.png)

### Large & Old

Filter by minimum size + age threshold. Useful for finding ancient
disk hogs in Downloads / Documents.

![Large & Old](docs/screenshots/large-old.png)

### Duplicate Finder

SHA-256 hash everything in a folder, group identical files. Pick a
keeper per group (or auto-pick newest), the rest move to quarantine.

![Duplicate Finder](docs/screenshots/duplicates.png)

### Similar Photos

Vision feature-print clustering — finds visually similar photos
without needing exact byte equality. Pick a keeper per cluster.

![Similar Photos](docs/screenshots/similar-photos.png)

---

### Shredder

Multi-pass overwrite + delete. Honest about SSD limitations
(TRIM-managed flash makes overwrites less meaningful).

![Shredder](docs/screenshots/shredder.png)

### Quarantine

Lists every quarantine session in `~/.MacCleanerQuarantine/`.
Restore individual items, delete sessions, or empty everything.
Auto-purge after 7 days.

![Quarantine](docs/screenshots/quarantine.png)

### Clock

Multi-timezone clock with current time per zone, 12/24h toggle,
add/remove via search picker covering the full TZ database.

![Clock](docs/screenshots/clock.png)

### My Tools

Bookmarks for arbitrary apps, scripts and shortcuts. Per-tool icon
grid.

![My Tools](docs/screenshots/my-tools.png)

### Paint

Built-in raster + vector editor for quick sketches and image markup
— skips the need for Paint S or Preview. Multi-layer document with
per-layer visibility/delete, transparent canvas with a checker
backdrop, zoom 10–800% (⌘+scroll / pinch), and 8 tools (Select,
Pencil, Brush, Eraser, Fill, Eyedropper, Text, Arrow, Line, Rect,
Ellipse). Text/Arrow/Shapes persist as vector objects you can
select, move, resize, rotate, restyle or delete. New Document sheet
takes custom width/height with HD/4K/A4 presets and transparent or
solid-colour background. Save (⌘S) overwrites the current file
atomically; Save As… (⇧⌘S) flattens visible layers to PNG/JPG.
Right panel toggles Layers + History tabs — History lists every
labelled action (Pencil / Add Text / Resize / …) with click-to-
revert.

![Paint](docs/screenshots/paint.png)

---

## Menu bar

The status bar item shows a configurable metric strip
(`C 27% | R 78% | G 9% | S 71% | ↑   0K | ↓   2K  ✦`), and clicking
opens a popover with a Mac Overview + tiles for disk / memory /
battery / CPU / GPU / sensors / network. Top-5 processes by CPU and
RAM. Footer with *Run Smart Care* + Settings + Quit.

![Menu bar popover](docs/screenshots/menubar.png)

Rendering notes:
- Label is rasterised to an `NSImage` (SF Pro 14pt + monospaced-digit
  feature, figure-space padding) because `MenuBarExtra` strips the
  font + per-glyph colour from a raw `Text`. The image is cached by
  content key so a stable strip costs ~0 between ticks.
- Percent metrics colour-code by threshold (green < 60, orange < 85,
  red ≥ 85). Battery flips: low = bad.

Settings → Menu bar exposes:
- **Visibility** — Info + Icon (default) / Info only / Icon only /
  Hidden (removes the status item entirely).
- **Separator** — Pipe (` | `) or Space.
- **Label style** — Short (`C` / `R` / `G` / `S`) or Full (`CPU` /
  `RAM` / `GPU` / `SSD`).
- **Metrics** — CPU / RAM / GPU / SSD / battery / CPU temp / fan
  RPM / net in / net out, toggle + reorder.

Quitting the main window keeps the menu bar agent alive (transitions
to `.accessory` activation policy). Click the power icon in the
popover for a confirmation dialog that fully terminates.

## Alerts

Six builtin rules ship enabled by default — CPU sustained &gt;90%
for 30s, CPU temp &gt;95°C, fan stuck at 0 RPM, battery &lt;10%,
disk &lt;5GB free, single process &gt;4GB resident. Per-rule cooldown
prevents spam. UNUserNotificationCenter delivery; the master toggle
in **Settings → Alerts** asks for notification permission on first
enable.

![Alerts settings](docs/screenshots/alerts.png)

## Settings

- **General** — appearance (light / dark / system), language picker
  (English / Tiếng Việt / system), run Smart Care at launch.
- **Menu Bar** — toggle each metric on the strip, reorder.
- **Alerts** — master switch + per-rule toggles.
- **Quarantine** — folder reveal, list current sessions.
- **About** — version, license.

![Settings](docs/screenshots/settings.png)

---

## Dropping in screenshots

Place PNGs at `docs/screenshots/<name>.png` matching the filenames
referenced above. Suggested capture sizes: ~1600×1000 for full
window views, ~340-wide for menu bar popover. Use light or dark
mode consistently.

To record a clip of the menu bar strip:
`screencapture -i menubar.png` then crop.

## Quarantine internals

Anything moved by a cleaner / uninstaller / login-items delete
lands in `~/.MacCleanerQuarantine/<timestamp>/` with a
`manifest.json` recording the original path. Sessions auto-purge
after 7 days. **Tools → Quarantine** lists every session and
restores items in one click. Direct delete is reserved for cache
items the OS regenerates anyway (Quick Clean's safe-delete path).

## Live dev-tool protection

When a known IDE / emulator / build tool is running, MacCleaner
refuses to delete its caches even if a rule technically targets
them. Detected via `NSWorkspace.runningApplications` plus a `ps`
sweep for non-bundled processes (qemu, gradle daemon, emulator).
The Quick Clean banner lists detected tools so you can see the
guard is active before clicking Clean Now.

| Detected tool | Protected paths |
|---|---|
| Android Studio | `~/.gradle`, `~/.android`, `~/Library/Caches/Google/AndroidStudio*`, `~/Library/Logs/Google/AndroidStudio*` |
| Xcode | `~/Library/Developer/Xcode/DerivedData`, `~/Library/Developer/CoreSimulator/Devices`, `~/Library/Caches/com.apple.dt.Xcode` |
| iOS Simulator | `~/Library/Developer/CoreSimulator/Devices` |
| JetBrains family | `~/.gradle`, `~/.m2` |
| qemu / emulator (non-bundled) | `~/.android/avd`, `~/.android/cache` |

Plus blanket protection for `~/.android/avd`, `~/.android/cache`,
`~/Library/Android` (the SDK install) regardless of running state.

---

## Headless smoke test

```bash
MACCLEANER_SMOKE_TEST=1 \
  /path/to/build/Debug/MacCleaner.app/Contents/MacOS/MacCleaner
```

Each line: `[smoke] PASS|FAIL <Module> <duration> — <summary>`. A
clean run ends with `[smoke] OK — all checks passed`. Run before
every push.

Coverage: RuleEngine, PermissionsService, FileSizeCalculator,
SystemJunkScanner, TrashBinScanner, HierarchicalScanner,
LargeFilesScanner, AppScanner, LeftoverDetector, HomebrewUpdater,
ProcessMonitor, LoginItemsService, MemoryService, BatteryService,
MalwareScanner, PrivacyCleaner, MailAttachmentsScanner,
PhotoJunkScanner, PermissionsReader, SystemMetrics,
SmartCareOrchestrator.

## Project structure

```
App/                         SwiftUI scenes — RootView, SidebarView, MenuBarExtra,
                             AppLifecycle (window/quit policy)
Core/
  Alerts/                    AlertEngine + builtin rules
  Cleanup/                   CleanableItem, RuleEngine, QuarantineService,
                             WhitelistGuard, LiveDevTools, CleanProgress
  Database/                  GRDB-backed scan_history + exclusion tables
  DI/                        AppContainer (DI root)
  FileSystem/                Bytes formatting, size calculator
  Performance/               Memory, Battery, ProcessMonitor, NetworkSpeed,
                             LoginItem, GPUStats, BluetoothService,
                             ClockService, DiskIOService, PublicIPService,
                             SystemActivity
    SMC/                     Pure-Swift IOKit bridge, sensor catalog
  Protection/                MalwareScanner, PrivacyCleaner
  UI/                        Design tokens, ModuleHeader, EmptyStateView,
                             SparklineView, UnifiedBackground

Features/
  Cleanup/                   Quick Clean, System Junk, Mail, Photo Junk, Trash
  Applications/              Uninstaller, Updater
  Performance/               Maintenance, Login Items, Process Monitor,
                             Memory, Battery, Sensors, Network, Bluetooth,
                             DiskMonitor
  Protection/                Malware, Privacy, AppPermissions
  Files/                     Space Lens, Large & Old, Duplicates,
                             Similar Photos
  MenuBar/                   MenuBarStatusModel, MenuBarStatusLabel,
                             MenuBarConfig, popover
  SmartCare/                 Orchestrator + 3-pillar scan view
  Quarantine/                Sessions list + restore manager
  Dashboard/                 Realtime hero + sparklines
  Tools/Clock/               Multi-timezone clock
  Shredder/, MyTools/        misc tools

Resources/
  CleanupRules/              system_junk.json — declarative rule packs
  MalwareSignatures/         future-use signature DB
  Localizable.xcstrings      en + vi string catalog
  Assets.xcassets/           AppIcon, AccentColor

Tools/
  generate_icon.swift        regenerates the AppIcon PNGs

docs/
  ROADMAP-monitor-parity.md  Stats-parity sprint log
  SPEC.md, UI_SPEC.md        original design specs
  screenshots/               README screenshots
```

## Regenerating the app icon

```bash
# edit Tools/generate_icon.swift (gradient, glyph, etc.)
swift Tools/generate_icon.swift
xcodegen generate
xcodebuild -scheme MacCleaner build
```

Force LaunchServices to refresh after changing icon bytes:

```bash
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
  -kill -r -domain local -domain system -domain user
killall Dock Finder
```

# MacCleaner — Windows

Windows port. Plan + Mac→Win API mapping in [`WINDOWS_PORT_PLAN.md`](../WINDOWS_PORT_PLAN.md).

## Status

Phases 0 – 7 scaffolded. Every navigation tag routes to a real page
backed by a real Core service; no `StubPage` callsites remain.

| Phase | Modules | Status |
|---|---|---|
| 0 — Bootstrap | sln, App, Core, Tests, CI | ✅ |
| 1 — Core services | SystemMetrics, Process, Battery, Drive, Registry, Sqlite, Toast, NotifyIcon | ✅ |
| 2 — Performance pages | Dashboard, Process Monitor, Memory, Battery, Network, Disk Monitor, Bluetooth, Sensors, Login Items | ✅ |
| 3 — Applications | Uninstaller, Updater (winget) | ✅ |
| 4 — Files | Space Lens, Large & Old, Duplicates, Similar Photos | ✅ |
| 5 — Cleanup | Quick Clean, Recycle Bin | ✅ |
| 6 — Tools | Shredder, Quarantine, My Tools, Clock, Scroll Denoiser, Paint | ✅ |
| 7 — Settings | About + data-folder shortcuts | ✅ |

Runtime validation on a real Windows box is the next step — CI confirms
it compiles and the xunit tests pass on `windows-latest`, but no human
has clicked through the UI yet.

## Build

Requires Visual Studio 2022 17.8+ or .NET 8 SDK on Windows. The
`Microsoft.WindowsAppSDK` nuget brings the WinUI 3 build tools — no
extra workload install needed.

```pwsh
cd Windows/MacCleaner.Win
dotnet restore /p:Platform=x64
dotnet build /p:Platform=x64
dotnet run --project App/App.csproj
```

CI lives at `.github/workflows/windows-ci.yml`: builds on every push
touching `Windows/**`, runs xunit, publishes a self-contained `win-x64`
artifact named `MacCleaner-win-x64` on each green main build.

## Solution layout

```
Windows/MacCleaner.Win/
├── MacCleaner.Win.sln
├── global.json                # pins .NET 8 SDK
├── Directory.Build.props      # LangVersion latest, Nullable enable
├── App/                       # WinUI 3 entry, MainWindow, Views, Hosts
│   ├── App.xaml(.cs)
│   ├── MainWindow.xaml(.cs)
│   ├── AppServices.cs         # App-layer DI extensions
│   ├── app.manifest           # asInvoker, PerMonitorV2 DPI, UTF-8 ACP
│   ├── Controls/ModuleHeader.xaml(.cs)
│   ├── Hosts/NotifyIconHost.cs
│   ├── Resources/             # DesignTokens.xaml + Styles.xaml
│   ├── Services/ToastService.cs
│   └── Views/                 # 24 feature pages + StubPage + SettingsPage
├── Core/                      # OS-facing services (class library)
│   ├── Alerts/
│   ├── Applications/          # WingetService
│   ├── Cleanup/               # CleanupService, RecycleBinService, targets
│   ├── DI/AppContainer.cs
│   ├── Files/                 # SpaceLens, LargeOld, Duplicates, SimilarPhotos
│   ├── FileSystem/            # Bytes, DriveService
│   ├── Performance/           # SystemMetrics, Process, Battery, Network,
│   │                          # DiskMonitor, Bluetooth, Sensors
│   ├── Storage/               # Registry, Sqlite
│   ├── Tools/                 # Shredder, Quarantine, MyTools, ScrollDenoiser
│   └── NativeMethods.txt      # CsWin32 input
└── Tests/                     # xunit — Bytes, Drive, Registry, Sqlite
```

## Module ↔ service map

| Page | Tag | Backing service |
|---|---|---|
| Dashboard | `dashboard` | `ISystemMetricsService` + `IDriveService` |
| Process Monitor | `processes` | `IProcessService` |
| Memory | `memory` | `ISystemMetricsService` |
| Battery | `battery` | `IBatteryService` (GetSystemPowerStatus) |
| Network | `network` | `INetworkService` (delta-based throughput) |
| Disk Monitor | `diskmon` | `IDiskMonitorService` (PhysicalDisk perf counters) |
| Bluetooth | `bluetooth` | `IBluetoothService` (WinRT DeviceInformation) |
| Sensors | `sensors` | `ISensorsService` (LibreHardwareMonitorLib) |
| Login Items | `loginitems` | `IRegistryService` |
| Uninstaller | `uninstaller` | `IRegistryService` |
| Updater | `updater` | `IWingetService` (winget CLI wrap) |
| Quick Clean | `quickclean` | `ICleanupService` + `CleanupTargets` |
| Recycle Bin | `recyclebin` | `IRecycleBinService` (SHQueryRecycleBin) |
| Space Lens | `spacelens` | `ISpaceLensService` |
| Large & Old | `largeold` | `ILargeOldFilesService` |
| Duplicates | `duplicates` | `IDuplicateFinderService` (SHA256) |
| Similar Photos | `similar` | `ISimilarPhotosService` (avg-hash pHash) |
| Shredder | `shredder` | `IShredderService` |
| Quarantine | `quarantine` | `IQuarantineService` |
| My Tools | `mytools` | `IMyToolsService` |
| Clock | `clock` | `TimeZoneInfo` (no service) |
| Paint | `paint` | `InkCanvas` (no service) |
| Scroll Denoiser | `scroll` | `IScrollDenoiserService` (WH_MOUSE_LL) |
| Settings | (NavView built-in) | `ISqliteService`, `IQuarantineService` |

## Tech stack

- WinUI 3 + .NET 8 (C#)
- `Microsoft.Extensions.DependencyInjection` for DI
- `Microsoft.Data.Sqlite` for usage-trend DB
- `CommunityToolkit.Mvvm` for `INotifyPropertyChanged` boilerplate
- `H.NotifyIcon.WinUI` for the system tray
- `LibreHardwareMonitorLib` for sensors (admin-required for most readings)
- `System.Drawing.Common` for image hashing in Similar Photos
- `CsWin32` source-generated P/Invoke (file `Core/NativeMethods.txt`)

## What's dropped from the macOS app

Per `WINDOWS_PORT_PLAN.md` section 2.2: Smart Care, Maintenance, System
Junk, Mail Attachments, Photo Junk, Malware Removal, Privacy, App
Permissions — all dropped for the reasons in that section.

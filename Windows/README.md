# MacCleaner — Windows

Windows port. Plan + Mac→Win API mapping in [`WINDOWS_PORT_PLAN.md`](../WINDOWS_PORT_PLAN.md).

## Status

Phase 0 (Bootstrap) done. WinUI 3 skeleton scaffolded — 24 stub pages wired
into the navigation shell, no feature logic yet.

## Solution layout

```
Windows/MacCleaner.Win/
├── MacCleaner.Win.sln
├── global.json                # pins .NET 8 SDK
├── Directory.Build.props      # shared LangVersion + nullable
├── App/                       # WinUI 3 entry point + Views
│   ├── App.xaml / App.xaml.cs
│   ├── MainWindow.xaml        # NavigationView with 24 stub items
│   ├── Program.cs             # explicit STAThread entry
│   ├── app.manifest           # asInvoker, PerMonitorV2 DPI, UTF-8
│   ├── Controls/ModuleHeader.xaml(.cs)
│   ├── Resources/DesignTokens.xaml    # ported from macOS DesignTokens.swift
│   ├── Resources/Styles.xaml
│   └── Views/Modules.cs + StubPage.xaml(.cs)
├── Core/                      # OS-facing services (class library)
│   ├── DI/AppContainer.cs
│   ├── FileSystem/Bytes.cs    # mirrors macOS byte/rate formatters
│   └── NativeMethods.txt      # CsWin32 source-generator input
└── Tests/                     # xunit
    └── BytesTests.cs
```

## Build

Requires Visual Studio 2022 17.8+ or .NET 8 SDK with the Windows App SDK
workload:

```pwsh
cd Windows/MacCleaner.Win
dotnet workload install windowsappsdk
dotnet restore
dotnet build /p:Platform=x64
dotnet run --project App/App.csproj
```

CI lives at `.github/workflows/windows-ci.yml` and runs build + test on
`windows-latest` for every push touching `Windows/**`.

## Tech stack

- WinUI 3 + .NET 8 (C#)
- `Microsoft.Extensions.DependencyInjection` for DI
- `Microsoft.Data.Sqlite` for usage-trend DB (Phase 3)
- `CommunityToolkit.Mvvm` for `INotifyPropertyChanged` boilerplate
- `H.NotifyIcon.WinUI` for system tray (Phase 1)
- `LibreHardwareMonitorLib` for sensors (Phase 2)
- `CsWin32` source-generated P/Invoke

## Scope

24 modules ported from macOS — see port plan section 2.1 for the full list
and Mac→Win API mapping. Smart Care, Maintenance, System Junk, Mail
Attachments, Photo Junk, Malware Removal, Privacy and App Permissions are
explicitly dropped (rationale in section 2.2).

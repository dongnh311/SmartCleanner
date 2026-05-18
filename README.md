# SmartCleanner

Cross-platform cleaner and system monitor for macOS and Windows.

![Main window](macOS/docs/screenshots/hero.png)

## Repo layout

| Path | Description |
|---|---|
| [`macOS/`](macOS/) | Original build — SwiftUI + Swift 6, targets macOS 13+. App scheme `MacCleaner`. See [`macOS/README.md`](macOS/README.md). |
| [`Windows/`](Windows/) | WinUI 3 + .NET 8 (C#) port. Feature-complete scaffold. See [`Windows/README.md`](Windows/README.md). |
| [`WINDOWS_PORT_PLAN.md`](WINDOWS_PORT_PLAN.md) | Port plan: feature inventory (24 modules kept, 8 Mac-specific dropped), Mac→Win API mapping, 7-phase roadmap. |

## Status

- **macOS** — in production use. 31 modules, single-user, ad-hoc signed.
- **Windows** — phases 0 – 7 scaffolded. Every navigation tag routes to a real page backed by a real Core service. Runtime validation on a Windows machine pending.

The two builds live in the same repo so the design system and shared
algorithms (`DirectionLockFilter`, duplicate hash logic, perceptual
photo hashing, etc.) stay easy to cross-reference.

## Quick start

### macOS

```bash
git clone https://github.com/dongnh311/SmartCleanner.git
cd SmartCleanner/macOS
xcodegen generate
xcodebuild -scheme MacCleaner -destination 'platform=macOS' build
```

Details: [`macOS/README.md`](macOS/README.md).

### Windows

```pwsh
git clone https://github.com/dongnh311/SmartCleanner.git
cd SmartCleanner/Windows/MacCleaner.Win
dotnet restore /p:Platform=x64
dotnet build /p:Platform=x64
dotnet run --project App/App.csproj
```

Or grab the self-contained `MacCleaner-win-x64` / `MacCleaner-win-arm64`
artifact from the latest green run on the
[Windows CI workflow](../../actions/workflows/windows-ci.yml).
Details: [`Windows/README.md`](Windows/README.md).

## License

Personal, not for distribution.

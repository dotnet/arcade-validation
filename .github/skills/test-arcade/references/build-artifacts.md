# Build Artifacts

Understanding the Arcade build artifact layout is essential for troubleshooting feed configuration and package resolution issues.

## Arcade Build Output

After building Arcade with `--pack`, artifacts are produced under `artifacts/`:

```
arcade/artifacts/
├── bin/                              # Compiled binaries by project/configuration
│   ├── Microsoft.DotNet.Arcade.Sdk/
│   ├── Microsoft.DotNet.Helix.Sdk/
│   ├── Microsoft.DotNet.SignTool/
│   └── ...
├── packages/                         # NuGet packages
│   └── Release/                      # (or Debug/)
│       ├── NonShipping/              # ← Primary source for local feed
│       │   ├── Microsoft.DotNet.Arcade.Sdk.{version}.nupkg
│       │   ├── Microsoft.DotNet.Helix.Sdk.{version}.nupkg
│       │   ├── Microsoft.DotNet.Build.Tasks.Feed.{version}.nupkg
│       │   ├── Microsoft.DotNet.SignTool.{version}.nupkg
│       │   └── ...
│       └── Shipping/                 # Packages intended for public feeds
│           └── ...
├── log/                              # Build logs
│   └── Release/
│       ├── Build.binlog              # MSBuild binary log (use for diagnostics)
│       └── ...
├── TestResults/                      # Test output (if tests were run)
├── tmp/                              # Temporary build artifacts
└── toolset/                          # Downloaded build tools
```

## Key Packages

These are the primary packages consumed by repos using Arcade:

| Package | Purpose |
|---------|---------|
| `Microsoft.DotNet.Arcade.Sdk` | Core MSBuild SDK — the main package that controls the build |
| `Microsoft.DotNet.Helix.Sdk` | Helix distributed testing SDK |
| `Microsoft.DotNet.Build.Tasks.Feed` | NuGet feed publishing tasks |
| `Microsoft.DotNet.Build.Tasks.Packaging` | Package creation and validation |
| `Microsoft.DotNet.Build.Tasks.Installers` | MSI/PKG installer generation |
| `Microsoft.DotNet.SignTool` | Code signing tasks |
| `Microsoft.DotNet.XUnitExtensions` | Enhanced XUnit test capabilities |
| `Microsoft.DotNet.RemoteExecutor` | Cross-platform process execution for tests |

## Version Format

The Arcade SDK version is determined by the `OfficialBuildId` property:

```
{major}.{minor}.{patch}-beta.{OfficialBuildId}
```

For example, with `OfficialBuildId=20291001.1`:
```
10.0.0-beta.25291001.1
```

The version is embedded in the `.nupkg` filename:
```
Microsoft.DotNet.Arcade.Sdk.10.0.0-beta.25291001.1.nupkg
```

## Local Feed Structure

The script copies packages into a flat directory used as a local NuGet feed source:

```
/tmp/arcade-local-feed/
├── Microsoft.DotNet.Arcade.Sdk.10.0.0-beta.25291001.1.nupkg
├── Microsoft.DotNet.Helix.Sdk.10.0.0-beta.25291001.1.nupkg
├── Microsoft.DotNet.Build.Tasks.Feed.10.0.0-beta.25291001.1.nupkg
└── ...
```

This directory is registered as a NuGet source named `local-arcade-feed` in the test repo's `NuGet.config`.

## global.json Updates

The script updates the test repo's `global.json` to reference the locally-built version:

**Before:**
```json
{
  "tools": {
    "dotnet": "10.0.100"
  },
  "msbuild-sdks": {
    "Microsoft.DotNet.Arcade.Sdk": "10.0.0-beta.25100.1",
    "Microsoft.DotNet.Helix.Sdk": "10.0.0-beta.25100.1"
  }
}
```

**After:**
```json
{
  "tools": {
    "dotnet": "10.0.100"
  },
  "msbuild-sdks": {
    "Microsoft.DotNet.Arcade.Sdk": "10.0.0-beta.25291001.1",
    "Microsoft.DotNet.Helix.Sdk": "10.0.0-beta.25291001.1"
  }
}
```

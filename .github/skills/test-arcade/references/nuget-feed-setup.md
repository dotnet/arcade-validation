# Local NuGet Feed Configuration

How the script sets up a local NuGet feed from Arcade build artifacts and configures a test repo to consume from it.

## Overview

After Arcade is built with `--pack`, NuGet packages are output to `artifacts/packages/Release/NonShipping/`. The script uses `dotnet nuget push` to populate a hierarchical local feed from these packages, then registers the feed as a NuGet source for the test repo.

## Feed Initialization with `dotnet nuget push`

The `dotnet nuget push` command, when targeting a local folder source, copies each package into a hierarchical feed layout:

```bash
for nupkg in "$ARCADE_PACKAGES_PATH"/*.nupkg; do
    dotnet nuget push "$nupkg" --source "$FEED_PATH" --skip-duplicate
done
```

**Flat input** (what Arcade produces):
```
artifacts/packages/Release/NonShipping/
├── Microsoft.DotNet.Arcade.Sdk.10.0.0-beta.25291001.1.nupkg
├── Microsoft.DotNet.Helix.Sdk.10.0.0-beta.25291001.1.nupkg
├── Microsoft.DotNet.SignTool.10.0.0-beta.25291001.1.nupkg
└── ...
```

**Hierarchical output** (what `dotnet nuget push` creates):
```
/tmp/arcade-local-feed/
├── microsoft.dotnet.arcade.sdk/
│   └── 10.0.0-beta.25291001.1/
│       ├── microsoft.dotnet.arcade.sdk.10.0.0-beta.25291001.1.nupkg
│       └── microsoft.dotnet.arcade.sdk.10.0.0-beta.25291001.1.nupkg.sha512
├── microsoft.dotnet.helix.sdk/
│   └── 10.0.0-beta.25291001.1/
│       ├── ...
└── ...
```

The hierarchical layout is a [local NuGet feed format](https://learn.microsoft.com/en-us/nuget/hosting-packages/local-feeds) that NuGet can restore from directly.

The `--skip-duplicate` flag prevents errors when a package already exists in the feed (e.g., when re-running without `--clean-feed`).

## Registering the Feed

After creating the feed, the script registers it as a NuGet source:

```bash
# Run from the test repo directory so it modifies the repo's NuGet.config
cd /path/to/test-repo
dotnet nuget add source /tmp/arcade-local-feed
```

This adds a `<packageSource>` entry to the test repo's `NuGet.config`. The local feed takes priority alongside other configured sources (e.g., Azure DevOps feeds, nuget.org).

## Clearing NuGet Caches

Before adding the source, the script clears all NuGet caches:

```bash
dotnet nuget locals all --clear
```

This is **critical** because NuGet aggressively caches resolved packages. Without clearing:
- A previously-cached official Arcade SDK version may be used instead of the locally-built one
- Version resolution may silently pick the wrong package
- Symptoms: test repo builds successfully but uses the old Arcade, not your changes

### Cache Locations

`dotnet nuget locals all --list` shows:
- **http-cache**: HTTP response cache
- **global-packages**: `~/.nuget/packages/` — extracted packages
- **temp**: temporary extraction directory
- **plugins-cache**: credential plugin cache

All are cleared by `--clear all`.

## Feed Precedence

NuGet resolves packages by checking sources in the order listed in `NuGet.config`. When the local feed is added:
1. NuGet checks the local feed first (if listed first)
2. Falls back to Azure DevOps feeds and nuget.org for packages not in the local feed

The locally-built Arcade packages will be found because:
- The exact version (e.g., `10.0.0-beta.25291001.1`) only exists in the local feed
- `global.json` is updated to request this exact version
- NuGet caches are cleared, so no stale cached version can interfere

## Manual Feed Setup

If you need to configure the feed manually (e.g., the script failed partway through):

```bash
# 1. Create feed from packages
for nupkg in /path/to/arcade/artifacts/packages/Release/NonShipping/*.nupkg; do
    dotnet nuget push "$nupkg" --source /tmp/arcade-local-feed --skip-duplicate
done

# 2. Clear caches
dotnet nuget locals all --clear

# 3. Add source (from test repo directory)
cd /path/to/test-repo
dotnet nuget add source /tmp/arcade-local-feed

# 4. Verify
dotnet nuget list source
```

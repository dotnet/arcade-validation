# global.json Version Pinning

How the script updates the test repo's `global.json` to consume locally-built Arcade packages.

## What global.json Controls

In .NET repos that use Arcade, `global.json` has an `msbuild-sdks` section that pins the versions of MSBuild SDK packages:

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

When the repo builds, MSBuild resolves these SDK packages from configured NuGet sources at the pinned version.

## What the Script Does

The script replaces wildcard version pins (`"*"`) with the exact version of the locally-built Arcade SDK:

```bash
# Before (wildcard pin — used in some repos)
"Microsoft.DotNet.Arcade.Sdk": "*"

# After
"Microsoft.DotNet.Arcade.Sdk": "10.0.0-beta.25291001.1"
```

Both `Microsoft.DotNet.Arcade.Sdk` and `Microsoft.DotNet.Helix.Sdk` are updated to the same version, since they are always released together from the same Arcade build.

### Version Extraction

The version is extracted from the package filename:

```
Microsoft.DotNet.Arcade.Sdk.10.0.0-beta.25291001.1.nupkg
                             └──────────────────────┘
                                    version
```

Using:
```bash
basename "$pkg" | sed -n 's/Microsoft\.DotNet\.Arcade\.Sdk\.\(.*\)\.nupkg/\1/p'
```

## Repos with Exact Version Pins

Some repos pin to an exact version rather than `"*"`:

```json
"Microsoft.DotNet.Arcade.Sdk": "10.0.0-beta.25100.1"
```

The script's current `sed` replacement targets the wildcard `*` pattern. For repos with exact version pins, you'll need to manually update `global.json` or adjust the sed pattern:

```bash
# Replace any existing version (not just wildcard)
sed -i 's/"Microsoft.DotNet.Arcade.Sdk": "[^"]*"/"Microsoft.DotNet.Arcade.Sdk": "NEW_VERSION"/' global.json
```

## Which SDKs to Update

The two primary SDKs from Arcade referenced in `global.json`:

| SDK | Purpose |
|-----|---------|
| `Microsoft.DotNet.Arcade.Sdk` | Core build infrastructure — targets, props, tasks |
| `Microsoft.DotNet.Helix.Sdk` | Helix distributed testing — only needed if the test repo runs Helix tests |

Some repos also reference additional Arcade SDKs:
- `Microsoft.DotNet.SharedFramework.Sdk` — shared framework packaging
- `Microsoft.DotNet.CMake.Sdk` — CMake integration

If the test repo uses these, they should also be updated to the locally-built version.

## Verifying the Update

After the script runs, confirm the update:

```bash
cat /path/to/test-repo/global.json | grep -A1 "msbuild-sdks"
```

Expected output should show the locally-built version (matching the OfficialBuildId used):
```json
"msbuild-sdks": {
    "Microsoft.DotNet.Arcade.Sdk": "10.0.0-beta.25291001.1",
    "Microsoft.DotNet.Helix.Sdk": "10.0.0-beta.25291001.1"
}
```

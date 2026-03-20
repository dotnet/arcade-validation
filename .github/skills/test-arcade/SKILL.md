---
name: test-arcade
description: >
  Build the Arcade SDK from source, configure a local NuGet feed with the artifacts,
  and validate the build by running a test repository against the locally-built packages.
  Use when testing local Arcade changes against a consuming repo, validating Arcade SDK
  changes before merging, or verifying that a repo can build with a new Arcade version.
  Use when asked "test arcade", "build and test arcade", "validate arcade changes",
  "try arcade locally", "test arcade SDK", "build arcade packages", or
  "run a repo against local arcade".
  DO NOT USE FOR: CI analysis, Helix test investigation, codeflow/dependency-flow issues,
  or production Arcade SDK publishing.
---

# Build and Test Arcade SDK Locally

Build the Arcade SDK from a local checkout, publish the artifacts to a local NuGet feed, and validate by building a test repository against those packages.

**Workflow**: Gather paths (Step 0) → run the script (Step 1) → interpret results (Step 2) → present summary (Step 3). The script handles repo resets, building, feed configuration, `global.json` updates, and test repo builds end-to-end.

## When to Use This Skill

- Testing local Arcade SDK changes against a consuming repository
- Validating that a repo builds with a modified Arcade version before submitting a PR
- Reproducing build issues with specific Arcade changes
- Questions like "does my arcade change break runtime?", "test arcade locally", "validate arcade SDK"

**Not for**: CI/CD pipeline analysis, Helix test failures, publishing Arcade packages to official feeds, or dependency flow troubleshooting.

## Prerequisites

- **Git**: repos must be cloned locally
- **Network access**: Azure DevOps package feeds (dev.azure.com/dnceng) must be reachable for NuGet restore

## Quick Start

```bash
# Full build-and-test (uses ~/repos/arcade and ~/repos/arcade-validation)
./scripts/test-arcade.sh

# Clean the local feed before running (e.g., after switching arcade branches)
./scripts/test-arcade.sh --clean-feed

# Build and run Signing Validation (SignCheck) on test repo output
./scripts/test-arcade.sh --signcheck

# Run SignCheck against a custom directory
./scripts/test-arcade.sh --signcheck --signcheck-dir /path/to/files
```

## Step 0: Verify Repos Are Cloned

The script finds `arcade` and `arcade-validation` as sibling directories of the `helpers` repo root. For example, if `helpers` is at `~/repos/helpers`, the script expects:

- `~/repos/arcade` — the `dotnet/arcade` repo with the changes to test
- `~/repos/arcade-validation` — the `dotnet/arcade-validation` repo used as the test target

The local NuGet feed is stored at `.arcade-local-feed/` inside the skill directory (hidden). It is **not cleaned up** between runs — use `--clean-feed` to explicitly clear it when needed (e.g., after switching branches or testing a different Arcade change).

## Step 1: Run the Script

Run `scripts/test-arcade.sh`. The script performs these phases in order:

1. **Validate** — confirms `~/repos/arcade` and `~/repos/arcade-validation` directories exist
2. **Reset repos** — deletes `.packages` and `artifacts` directories in both repos to ensure a clean state
3. **Create feed** — creates the feed directory if it doesn't exist (only cleans it when `--clean-feed` is passed)
4. **Build Arcade** — runs `./build.sh --configuration Release --pack` with an auto-generated future-dated `OfficialBuildId` in the arcade repo
5. **Configure local NuGet feed** — uses `dotnet nuget push` to populate a hierarchical local feed from `artifacts/packages/Release/NonShipping`, clears all NuGet caches, and adds the feed as a source for arcade-validation
6. **Update global.json** — finds the built `Microsoft.DotNet.Arcade.Sdk` package, extracts its version, and updates arcade-validation's `global.json` to replace wildcard (`*`) version pins for both `Microsoft.DotNet.Arcade.Sdk` and `Microsoft.DotNet.Helix.Sdk` with the exact built version
7. **Build arcade-validation** — runs `./build.sh` in arcade-validation
8. **Signing Validation** *(optional, `--signcheck`)* — runs `eng/common/sdk-task.sh --task SigningValidation` against the test repo's output packages. Defaults to `artifacts/packages/<config>/NonShipping`; override with `--signcheck-dir`

### Script Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `--clean-feed` | ❌ | Delete and recreate the local feed directory before running. Use when switching branches or testing a different Arcade change |
| `--signcheck` | ❌ | Run Signing Validation (SignCheck) after building the test repo. Checks files in `artifacts/packages/<config>/NonShipping` by default |
| `--signcheck-dir <path>` | ❌ | Directory to validate with SignCheck. Implies `--signcheck`. Use to check a custom directory instead of the default |

## Step 2: Interpret Results

The script streams build output to stdout/stderr in real time. It exits on the first failure (`set -e`). Check the exit code and output to determine success or failure.

### Common Failure Scenarios

| Failure | Likely Cause | Remediation |
|---------|-------------|-------------|
| Arcade build fails | Code error in Arcade changes | Check `artifacts/log/` for `.binlog` files; fix the code |
| `Arcade package not found` | Build didn't produce expected packages | Verify build completed with `--pack`; check `artifacts/packages/Release/NonShipping/` |
| `Could not extract Arcade version` | Package filename doesn't match expected pattern | Check `.nupkg` filenames in NonShipping directory |
| Test repo restore fails | NuGet feed not configured correctly or cache is stale | Run `dotnet nuget locals all --clear`; verify feed path contains `.nupkg` files |
| Test repo build fails | Arcade changes broke compatibility | Compare with a build against official Arcade; check for breaking API changes |
| SignCheck: no packages directory | Test repo didn't produce packages | Build with `--pack`, or specify `--signcheck-dir` pointing to existing files |
| SignCheck: signing validation fails | Unsigned or incorrectly signed files found | Review SignCheck log in `artifacts/log/`; update `eng/Signing.props` or exclusions as needed |
| Network errors during restore | Azure DevOps feeds unreachable | Check network/VPN; verify feed URLs in NuGet.config |

## Step 3: Present Results

Lead with a 1-2 sentence verdict, then a summary.

Example output format:

```
## Arcade Test Results

**Verdict**: All phases passed. The test repo builds successfully against local Arcade changes.

| # | Phase | Result |
|---|-------|--------|
| 1 | Reset repos | ✅ |
| 2 | Build Arcade | ✅ |
| 3 | Configure feed | ✅ |
| 4 | Update global.json | ✅ |
| 5 | Build test repo | ✅ |
| 6 | Signing Validation | ✅ *(if --signcheck)* |

Arcade SDK version: 10.0.0-beta.<future-date>.1
Packages published to: /tmp/arcade-local-feed
```

When `--signcheck` is used, also include the SignCheck results. Read the per-file outcomes from `artifacts/log/Debug/signcheck.xml` and the summary from `signcheck.log`:

```
**SignCheck results** (from `signcheck.xml`):

| File | Outcome | Details |
|------|---------|---------|
| `dotnet-sdk-source-10.0.104.tar.gz` | Signed | Timestamp: 02/23/26 17:13:46 (RSA) |
| `release.json` | Skipped | — |
| `dotnet-sdk-source-10.0.104.tar.gz.sig` | Skipped | — |

Summary: 3 files total — 1 signed, 0 unsigned, 2 skipped, 1 not unpacked. No signing issues found.
```

Possible `Outcome` values in the XML: `Signed`, `Unsigned` (error), `Skipped`, `Excluded`, `SkippedAndExcluded`. Any `Unsigned` file is an error — include it prominently in the results.

If any phase fails, include the error details and remediation guidance from the table above.

## Anti-Patterns

> ❌ **Don't reuse a stale feed directory.** The script resets the feed on each run, but if you're running steps manually, always clear the feed and NuGet caches before re-testing with new Arcade changes.

> ❌ **Don't assume build failures are Arcade's fault.** The test repo may have its own issues. Compare with a build against the official Arcade SDK to isolate the cause.

> ❌ **Don't manually modify NuGet.config or global.json** when the script handles it. Manual edits risk inconsistency and are harder to reproduce.

> ❌ **Don't test against a dirty repo.** Ensure both the Arcade and test repos have committed or stashed changes before running. Uncommitted changes in build infrastructure files can cause misleading results.

> ❌ **Don't install a .NET SDK manually.** The build process installs its own SDK via `eng/common/dotnet.sh`. Manual SDK installations can cause version conflicts.

## References

- **Signing Validation (SignCheck)**: [references/signing-validation.md](references/signing-validation.md)
- **Building Arcade**: [references/building-arcade.md](references/building-arcade.md)
- **NuGet feed setup**: [references/nuget-feed-setup.md](references/nuget-feed-setup.md)
- **global.json version pinning**: [references/global-json-pinning.md](references/global-json-pinning.md)
- **Build artifacts**: [references/build-artifacts.md](references/build-artifacts.md)
- **Troubleshooting**: [references/troubleshooting.md](references/troubleshooting.md)
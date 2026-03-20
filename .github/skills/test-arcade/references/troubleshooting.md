# Troubleshooting

Common issues when building and testing Arcade locally, with diagnosis steps and fixes.

## Build Failures

### Arcade build fails: "Unable to load service index"

**Symptom**: NuGet restore fails with feed connectivity errors.

**Cause**: Network access to Azure DevOps package feeds is blocked.

**Fix**:
- Verify VPN/network connectivity to `dev.azure.com/dnceng`
- Check that `NuGet.config` in the arcade repo has the correct feed URLs
- Try restoring with `--verbosity diagnostic` to see which feed is failing:
  ```bash
  cd /path/to/arcade && ./build.sh --restore --verbosity diagnostic 2>&1 | grep -i "unable to load"
  ```

### Arcade build fails: wrong .NET SDK

**Symptom**: Build errors related to SDK version mismatch.

**Cause**: The global .NET SDK doesn't match what Arcade expects.

**Fix**:
- Arcade's `build.sh` should auto-install the correct SDK via `eng/common/dotnet.sh`
- **NEVER** manually install an SDK — the build installs its own
- If the auto-install fails, check `global.json` in the Arcade repo for the expected version

### Arcade build: no packages produced

**Symptom**: Build succeeds but `artifacts/packages/` is empty or missing.

**Cause**: Build ran without the `--pack` flag.

**Fix**: Ensure the build command includes `--pack`:
```bash
./build.sh --configuration Release --pack /p:OfficialBuildId=$(date -d '+5 years' +%Y%m%d).1
```

## Feed Configuration Failures

### "Failed to add local NuGet feed source"

**Symptom**: `dotnet nuget add source` command fails.

**Cause**: Usually a duplicate source name or invalid NuGet.config.

**Fix**:
- Remove existing source first: `dotnet nuget remove source local-arcade-feed --configfile /path/to/NuGet.config`
- Verify NuGet.config is valid XML
- Check file permissions on NuGet.config

### Test repo restore: "Unable to find package Microsoft.DotNet.Arcade.Sdk"

**Symptom**: Test repo can't find the Arcade SDK package during restore.

**Cause**: Feed path doesn't contain the expected package, or NuGet cache is stale.

**Fix**:
1. Verify the package exists in the feed: `ls /tmp/arcade-local-feed/Microsoft.DotNet.Arcade.Sdk.*.nupkg`
2. Clear NuGet caches: `dotnet nuget locals all --clear`
3. Verify the source is registered: `dotnet nuget list source --configfile /path/to/NuGet.config`
4. Check that `global.json` version matches the package version exactly

### Version mismatch between global.json and packages

**Symptom**: Restore fails even though packages exist in the feed.

**Cause**: The version in `global.json` doesn't exactly match the `.nupkg` filename.

**Fix**:
- Check the exact version: `ls /tmp/arcade-local-feed/Microsoft.DotNet.Arcade.Sdk.*.nupkg`
- Compare with `global.json`: `cat /path/to/test-repo/global.json | grep Arcade`
- The script handles this automatically, but manual runs may have mismatches

## Test Repo Build Failures

### Test repo build fails with Arcade-specific errors

**Symptom**: Build errors in MSBuild targets or tasks from Arcade packages.

**Diagnosis**:
1. Check if the same error occurs with the official Arcade SDK (revert `global.json` and `NuGet.config` changes)
2. Compare the `.binlog` files between local and official Arcade builds
3. Look for breaking API changes in your Arcade modifications

### Test repo build fails with unrelated errors

**Symptom**: Errors that don't reference Arcade packages (e.g., source code compilation errors).

**Cause**: The test repo itself has issues independent of Arcade.

**Fix**:
- Build the test repo without Arcade changes first to establish a baseline
- Check the test repo's issue tracker for known build issues
- Ensure the test repo branch is compatible with the Arcade version being tested

## Performance Issues

### Disk space issues

**Symptom**: Build fails with "No space left on device".

**Fix**:
- Clean previous artifacts: `rm -rf /path/to/arcade/artifacts /path/to/test-repo/artifacts`
- Clean NuGet caches: `dotnet nuget locals all --clear`
- Remove old feed directories


## Investigating Build Logs

For detailed build diagnostics, use the MSBuild binary log (`.binlog`):

```bash
# Find binlog files
find /path/to/repo/artifacts/log -name "*.binlog"

# View structured log (requires MSBuild Structured Log Viewer)
# https://msbuildlog.com/
```

Key locations:
- Arcade build log: `arcade/artifacts/log/{Configuration}/Build.binlog`
- Test repo build log: `test-repo/artifacts/log/{Configuration}/Build.binlog`

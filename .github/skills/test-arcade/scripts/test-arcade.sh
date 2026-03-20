#!/usr/bin/env bash
# test-arcade.sh
#
# Replaces the BuildAndTestArcade .NET CLI tool.
# Builds the Arcade SDK from ~/repos/arcade, configures a local NuGet feed
# with the build artifacts, and builds arcade-validation against them.
# Optionally runs Signing Validation (SignCheck) on the test repo output.
#
# Prerequisites:
#   - dotnet CLI (for building and configuring the local NuGet feed)
#   - Network access to Azure DevOps package feeds
#
# Usage:
#   ./test-arcade.sh
#   ./test-arcade.sh --clean-feed
#   ./test-arcade.sh --signcheck
#   ./test-arcade.sh --signcheck --signcheck-dir path/to/files
#   ./test-arcade.sh --skip-arcade-build --signcheck   # reuse previous Arcade build

set -euo pipefail

CLEAN_FEED=false
SIGNCHECK=false
SIGNCHECK_DIR=""
SKIP_ARCADE_BUILD=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
ARCADE_PATH="$REPO_ROOT/../arcade"
TEST_PATH="$REPO_ROOT/../arcade-validation"
FEED_PATH="$SKILL_DIR/.arcade-local-feed"

# ─── Parse arguments ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case $1 in
        --clean-feed) CLEAN_FEED=true;  shift   ;;
        --signcheck)  SIGNCHECK=true;   shift   ;;
        --skip-arcade-build) SKIP_ARCADE_BUILD=true; shift ;;
        --signcheck-dir)
            SIGNCHECK=true
            SIGNCHECK_DIR="$2"
            shift 2
            ;;
        -h|--help)
            sed -n '2,19p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Resolve to absolute paths
ARCADE_PATH="$(cd "$ARCADE_PATH" 2>/dev/null && pwd)" || ARCADE_PATH=""
TEST_PATH="$(cd "$TEST_PATH" 2>/dev/null && pwd)" || TEST_PATH=""

# ─── Validate paths ─────────────────────────────────────────────────────────
if [[ -z "$ARCADE_PATH" || ! -d "$ARCADE_PATH" ]]; then
    echo "Error: 'arcade' directory not found next to the helpers repo"
    echo "Expected at: $REPO_ROOT/../arcade"
    exit 1
fi
if [[ -z "$TEST_PATH" || ! -d "$TEST_PATH" ]]; then
    echo "Error: 'arcade-validation' directory not found next to the helpers repo"
    echo "Expected at: $REPO_ROOT/../arcade-validation"
    exit 1
fi

echo "Building and testing Arcade with the following parameters:"
echo "Arcade Repo Path:       $ARCADE_PATH"
echo "Test Repo Path:         $TEST_PATH (arcade-validation)"
echo "Package Feed Path:      $FEED_PATH"
if $SIGNCHECK; then
    echo "Signing Validation:     enabled${SIGNCHECK_DIR:+ (dir: $SIGNCHECK_DIR)}"
fi

# ─── Reset repos ────────────────────────────────────────────────────────────
reset_repo() {
    local repo_path="$1"
    for dir in .packages artifacts; do
        local target="$repo_path/$dir"
        if [[ -d "$target" ]]; then
            rm -rf "$target"
        fi
    done
}

if $SKIP_ARCADE_BUILD; then
    echo "Skipping Arcade build (--skip-arcade-build)..."
    # Only reset the test repo, leave Arcade artifacts and feed intact.
    reset_repo "$TEST_PATH"
else
    reset_repo "$ARCADE_PATH"
    reset_repo "$TEST_PATH"

    # ─── Reset feed (only if --clean-feed) ──────────────────────────────────
    if $CLEAN_FEED; then
        echo "Cleaning feed directory..."
        if [[ -d "$FEED_PATH" ]]; then
            rm -rf "$FEED_PATH"
        fi
    fi
    mkdir -p "$FEED_PATH"

    # ─── Build Arcade ───────────────────────────────────────────────────────
    # Generate a future-dated OfficialBuildId to avoid conflicts with real builds.
    # Format: YYYYMMDD.N — we use a date 5 years in the future.
    OFFICIAL_BUILD_ID="$(date -d '+5 years' +%Y%m%d).1"
    echo "Building Arcade (OfficialBuildId=$OFFICIAL_BUILD_ID)..."
    (cd "$ARCADE_PATH" && ./build.sh --configuration Release --pack /p:OfficialBuildId="$OFFICIAL_BUILD_ID")

    # ─── Configure local NuGet feed ─────────────────────────────────────────
    echo "Configuring local NuGet feed..."
    ARCADE_PACKAGES_PATH="$ARCADE_PATH/artifacts/packages/Release/NonShipping"

    for nupkg in "$ARCADE_PACKAGES_PATH"/*.nupkg; do
        dotnet nuget push "$nupkg" --source "$FEED_PATH" --skip-duplicate
    done
    dotnet nuget locals all --clear
    (cd "$TEST_PATH" && dotnet nuget add source "$FEED_PATH" 2>/dev/null) || echo "Local feed source already registered — continuing."

    # ─── Update global.json ─────────────────────────────────────────────────
    echo "Updating global.json..."
    ARCADE_SDK_PKG="$(find "$ARCADE_PACKAGES_PATH" -name 'Microsoft.DotNet.Arcade.Sdk.*.nupkg' -print -quit)"

    if [[ -z "$ARCADE_SDK_PKG" ]]; then
        echo "Error: Arcade package not found in $ARCADE_PACKAGES_PATH"
        exit 1
    fi

    ARCADE_VERSION="$(basename "$ARCADE_SDK_PKG" | sed -n 's/Microsoft\.DotNet\.Arcade\.Sdk\.\(.*\)\.nupkg/\1/p')"

    if [[ -z "$ARCADE_VERSION" ]]; then
        echo "Error: Could not extract Arcade version from $(basename "$ARCADE_SDK_PKG")"
        exit 1
    fi

    GLOBAL_JSON_PATH="$TEST_PATH/global.json"
    sed -i 's|"Microsoft.DotNet.Arcade.Sdk": "[^"]*"|"Microsoft.DotNet.Arcade.Sdk": "'"$ARCADE_VERSION"'"|' "$GLOBAL_JSON_PATH"
    sed -i 's|"Microsoft.DotNet.Helix.Sdk": "[^"]*"|"Microsoft.DotNet.Helix.Sdk": "'"$ARCADE_VERSION"'"|' "$GLOBAL_JSON_PATH"
    echo "Pinned Arcade SDK version: $ARCADE_VERSION"
fi

# ─── Build Test Repo ─────────────────────────────────────────────────────────
echo "Building arcade-validation..."
(cd "$TEST_PATH" && ./build.sh)

# ─── Run Signing Validation ──────────────────────────────────────────────────
if $SIGNCHECK; then
    if [[ -z "$SIGNCHECK_DIR" ]]; then
        # Default to the test repo's NonShipping packages matching the build config.
        # build.sh defaults to Debug; look for whatever config directory exists.
        for cfg in Debug Release; do
            candidate="$TEST_PATH/artifacts/packages/$cfg/NonShipping"
            if [[ -d "$candidate" ]]; then
                SIGNCHECK_DIR="$candidate"
                break
            fi
        done
        if [[ -z "$SIGNCHECK_DIR" ]]; then
            echo "Error: No artifacts/packages/<config>/NonShipping directory found."
            echo "Build the test repo with --pack or specify --signcheck-dir."
            exit 1
        fi
    fi

    if [[ ! -d "$SIGNCHECK_DIR" ]]; then
        echo "Error: SignCheck directory does not exist: $SIGNCHECK_DIR"
        exit 1
    fi

    echo "Running Signing Validation on: $SIGNCHECK_DIR"
    SIGNCHECK_EXCLUSIONS="$TEST_PATH/eng/SignCheckExclusionsFile.txt"
    SIGNCHECK_EXTRA_ARGS=()
    if [[ -f "$SIGNCHECK_EXCLUSIONS" ]]; then
        echo "Using exclusions file:    $SIGNCHECK_EXCLUSIONS"
        SIGNCHECK_EXTRA_ARGS+=("/p:SignCheckExclusionsFile=$SIGNCHECK_EXCLUSIONS")
    fi
    # The SigningValidation.proj restore runs from the NuGet package cache, not
    # from the repo root, so it won't see the repo's NuGet.config. Pass the
    # local feed explicitly so the SignCheckTask package can be resolved.
    SIGNCHECK_EXTRA_ARGS+=("/p:RestoreAdditionalProjectSources=$FEED_PATH")
    (cd "$TEST_PATH" && ./eng/common/sdk-task.sh --task SigningValidation --restore \
        /p:PackageBasePath="$SIGNCHECK_DIR" "${SIGNCHECK_EXTRA_ARGS[@]}")
fi
